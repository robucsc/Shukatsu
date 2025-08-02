//
//  Intel.swift
//  Shukatsu
//
//  Created by rob on 9/3/25.
//

import Foundation
import FoundationModels
import CoreData
import CoreML
#if canImport(Summarization)
import Summarization
#endif

enum Intel {
    @MainActor
    private static func currentUserName() -> String {
        // Mirror SettingsView: read the namespaced key for the active profile
        let pm = ProfileManager()
        let kName = pm.namespacedKey("UserName")
        return (UserDefaults.standard.string(forKey: kName) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct DraftResult {
        let text: String
        let isAI: Bool
    }

    static let session = LanguageModelSession(
        instructions: "Return a short, helpful summary. Prefer 3–5 concise bullets."
    )

    private static func sourceText(from opp: Opportunity) -> String {
        let title = (opp.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let company = (opp.company ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let location = (opp.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = (opp.desc ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var components: [String] = []
        if !title.isEmpty { components.append(title) }
        if !company.isEmpty { components.append("at \(company)") }
        if !location.isEmpty { components.append("(\(location))") }
        if !desc.isEmpty { components.append(desc) }
        return components.joined(separator: " ")
    }

    private static func scrubCoverLetter(_ s: String, userName: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // If the model added a preface, drop everything before the first "Dear"
        if let dearRange = t.range(of: #"(?i)\bdear\b"#, options: .regularExpression) {
            t = String(t[dearRange.lowerBound...])
        }

        // Remove common separators the model sometimes inserts
        t = t.replacingOccurrences(of: "\n---\n", with: "\n")
        t = t.replacingOccurrences(of: "---", with: "")

        // Normalize signature block: ensure we close with the selected user name
        if !userName.isEmpty,
           let sigLine = t.range(of: #"(?im)^\s*Sincerely,\s*$"#, options: .regularExpression) {
            // Keep everything up to and including "Sincerely," on its own line
            let head = String(t[..<sigLine.upperBound])
            // Drop any name lines that immediately follow
            var rest = String(t[sigLine.upperBound...])
            if let nextBreak = rest.range(of: #"\n\s*\n"#, options: .regularExpression) {
                rest = String(rest[nextBreak.lowerBound...])
            } else {
                rest = ""
            }
            t = head + "\n" + userName + (rest.isEmpty ? "" : "\n" + rest)
        }

        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Summarize using Apple Intelligence when present; otherwise fall back locally.
    @MainActor
    static func summarizeOpportunity(_ opp: Opportunity) async -> String {
        let input = sourceText(from: opp)

        // Try Apple Intelligence first (if available)
        if case .available = SystemLanguageModel.default.availability {
            do {
                // Build a minimal prompt from current Opportunity data
                let status = opp.wrappedStatus.label
                let prompt = """
                Summarize this job opportunity for a sidebar card.

                Title/Company/Location/Status:
                \(input) · Status: \(status)

                Requirements:
                - Keep to 3–5 concise bullets.
                - Plain text only.
                """

                let r = try await session.respond(to: prompt)
                return r.content.description.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                // Fall through to local fallback / Summarization
            }
        }

        // Fallback (always works)
        func fallback() -> String {
            func tidy(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

            let title    = tidy(opp.title)
            let company  = tidy(opp.company)
            let location = tidy(opp.location)
            let status   = opp.wrappedStatus.label
            let descRaw  = tidy(opp.desc)

            // 1) Header: **Title at Company — (Location)** · Status: X
            var headerParts: [String] = []
            if !title.isEmpty   { headerParts.append(title) }
            if !company.isEmpty { headerParts.append("at \(company)") }
            let headerPrefix = headerParts.joined(separator: " ")
            let header = location.isEmpty ? headerPrefix : (headerPrefix.isEmpty ? "(\(location))" : "\(headerPrefix) — (\(location))")

            // 2) Build concise bullets from description
            //    - drop common section headings
            //    - split into short thoughts
            //    - de-duplicate
            //    - cap to 4 bullets
            let headingStoplist: Set<String> = [
                "inspiration", "what it does", "how we built it",
                "challenges we ran into", "accomplishments that we're proud of",
                "what we learned", "what's next for shukatsu", "summary"
            ]

            let clipped = String(descRaw.prefix(1400))
            var chunks = clipped
                .components(separatedBy: CharacterSet(charactersIn: "\n•-"))
                .flatMap { $0.components(separatedBy: ". ") }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count > 3 }
                .filter { !headingStoplist.contains($0.lowercased()) }

            var seen = Set<String>()
            chunks = chunks.filter {
                let key = $0.lowercased()
                if seen.contains(key) { return false }
                seen.insert(key); return true
            }

            // prefer slightly longer but still compact lines
            let bullets = chunks
                .prefix(4)
                .map { "• \($0)." }
                .joined(separator: "\n")

            if header.isEmpty && bullets.isEmpty { return "(No details to summarize.)" }

            var out: [String] = []
            if !header.isEmpty { out.append("**\(header)** · Status: \(status)") }
            if !bullets.isEmpty { out.append(bullets) }
            return out.joined(separator: "\n\n")
        }

        #if canImport(Summarization)
        if #available(macOS 15.0, *) {
            do {
                var config = Summarization.Configuration()
                config.format = .paragraph
                let session = try SummarizationSession(configuration: config)
                let result = try await session.summarize(input)
                return result.outputText
            } catch {
                return fallback()
            }
        } else {
            return fallback()
        }
        #else
        return fallback()
        #endif
    }
    
    /// Draft a brief cover letter using Apple Intelligence; fall back to a local template.
    @MainActor
    static func coverLetter(for opp: Opportunity) async -> DraftResult {
        let title = (opp.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let company = (opp.company ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let location = (opp.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = (opp.desc ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let status = opp.wrappedStatus.label
        let userName = await currentUserName()
        let closingRule: String = {
            if userName.isEmpty {
                return "- Close with 'Sincerely,' only."
            } else {
                return "- Close with 'Sincerely,' then '\(userName)'."
            }
        }()
        let pm = ProfileManager()
        let kRole = pm.namespacedKey("UserRole")
        let settingsRole = (UserDefaults.standard.string(forKey: kRole) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let roleForPrompt = title.isEmpty ? (settingsRole.isEmpty ? "the role" : settingsRole) : title
        // Prefer Apple Intelligence if available
        if case .available = SystemLanguageModel.default.availability {
            do {
                let prompt = """
                Write a short, professional cover letter for a macOS app developer.

                Context:
                - Role: \(roleForPrompt)
                - Company: \(company.isEmpty ? "Company" : company)
                - Location: \(location.isEmpty ? "Remote/On-site" : location)
                - Opportunity status: \(status)
                - Notes/description: \(desc.prefix(1200))

                Requirements:
                - Three short paragraphs: intro, fit, close. Keep under 180 words.
                - Plain text only.
                - Start the output with a line beginning with 'Dear ' — no preface like 'Certainly' or meta commentary.
                - Do NOT include sender/recipient address blocks or dates.
                - Do NOT include separators (e.g., '---') or markdown.
                \(closingRule)
                """
                let r = try await session.respond(to: prompt)
                let cleaned = scrubCoverLetter(r.content.description, userName: userName)
                return DraftResult(text: cleaned, isAI: true)
            } catch {
                // fall through to fallback
            }
        }
        // Fallback template
        let role = roleForPrompt
        let co = company.isEmpty ? "your team" : company
        let fallbackText = """
        Dear Hiring Manager,

        I am writing to express interest in \(role) at \(co). My background in Swift, SwiftUI, and macOS app development aligns with your needs. I focus on clean architecture, testing, and shipping product-focused features.

        I would welcome the chance to discuss how I can contribute. Thank you for your time and consideration.

        Sincerely,
        \(userName)
        """
        return DraftResult(text: fallbackText, isAI: false)
    }
    
    /// Draft a brief cover letter using Apple Intelligence; fall back to a local template.
    @MainActor
    static func draftCoverLetter(for opp: Opportunity) async -> String {
        let result = await coverLetter(for: opp)
        return result.text
    }
}



func diagAI() {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    print("OS:", "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    print("proc:", ProcessInfo.processInfo.processName)
    print("bundleID:", Bundle.main.bundleIdentifier ?? "nil")

    // Which SDK/runtime is this target actually using?
    print("SDKROOT:", ProcessInfo.processInfo.environment["SDKROOT"] ?? "unknown")

    // Platform switches
    #if os(macOS)
    print("os(macOS): true")
    #else
    print("os(macOS): false")
    #endif

    #if targetEnvironment(macCatalyst)
    print("targetEnvironment(macCatalyst): true")
    #else
    print("targetEnvironment(macCatalyst): false")
    #endif

    #if os(iOS)
    print("os(iOS): true")
    #else
    print("os(iOS): false")
    #endif

    #if arch(arm64)
    print("arch: arm64")
    #elseif arch(x86_64)
    print("arch: x86_64")
    #else
    print("arch: other")
    #endif

    let avail = SystemLanguageModel.default.availability
    print("Availability:", String(describing: avail))
}
