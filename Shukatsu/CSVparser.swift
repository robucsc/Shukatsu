//
//  CSVparser.swift
//  Shukatsu
//
//  Created by rob on 9/3/25.
//


import Foundation
import CoreData     
import Contacts

struct CSVRow: Sendable {
    var first = "", last = "", company = "", position = ""
    var email = "", phone = "", linkedin = "", notes = ""
    var connected: Date? = nil, lastContacted: Date? = nil
}

enum CSVparser {
    // MARK: CSV
    static func parseCSV(_ data: Data) -> [CSVRow] {
        // Minimal CSV: handles commas-in-quotes and double-quote escaping
        guard let s = String(data: data, encoding: .utf8) else { return [] }
        let lines = s.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let header = lines.first.map(String.init) else { return [] }
        let cols = header.splitCSV()
        let idx = { (name: String) in cols.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame } }

        func date(_ str: String) -> Date? {
            let t = str.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return nil }
            let f = DateFormatter()
//            f.calendar = .iso8601; f.locale = .init(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: t)
        }

        return lines.dropFirst().map(String.init).compactMap { line in
            let fields = line.splitCSV()
            func field(_ name: String) -> String {
                guard let i = idx(name), i < fields.count else { return "" }
                return fields[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if fields.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return nil }
            return CSVRow(
                first: field("first"),
                last: field("last"),
                company: field("company"),
                position: field("position"),
                email: field("email"),
                phone: field("phone"),
                linkedin: field("linkedin"),
                notes: field("notes"),
                connected: date(field("connected")),
                lastContacted: date(field("last_contacted"))
            )
        }
    }

    struct ImportResult { var created = 0, updated = 0, skipped = 0 }

    static func importRows(_ rows: [CSVRow], into ctx: NSManagedObjectContext) throws -> ImportResult {
        var result = ImportResult()
        // Preload existing by email / phone for quick matching
        let fetch: NSFetchRequest<Contact> = Contact.fetchRequest()
        let all = try ctx.fetch(fetch)
        var byEmail: [String: Contact] = [:]
        var byPhone: [String: Contact] = [:]
        for c in all {
            if let e = c.email?.lowercased(), !e.isEmpty { byEmail[e] = c }
            if let p = c.phone?.digitsOnly, !p.isEmpty { byPhone[p] = c }
        }

        for r in rows {
            let normEmail = r.email.lowercased()
            let normPhone = r.phone.digitsOnly
            let existing = (!normEmail.isEmpty ? byEmail[normEmail] : nil) ?? (!normPhone.isEmpty ? byPhone[normPhone] : nil)

            let c: Contact
            if let e = existing {
                c = e; result.updated += 1
            } else {
                c = Contact(context: ctx)
                result.created += 1
            }

            // fill if empty
            func set(_ keyPath: ReferenceWritableKeyPath<Contact, String?>, _ v: String) {
                if (c[keyPath: keyPath] ?? "").isEmpty, !v.isEmpty { c[keyPath: keyPath] = v }
            }
            set(\.first, r.first); set(\.last, r.last)
            set(\.company, r.company); set(\.position, r.position)
            set(\.email, normEmail); set(\.phone, normPhone)
            set(\.linkedin, r.linkedin); set(\.notes, r.notes)
            if c.value(forKey: "connected") == nil, let d = r.connected {
                c.setValue(d, forKey: "connected")
            }
            if c.value(forKey: "contact") == nil, let d = r.lastContacted {
                c.setValue(d, forKey: "contact")
            }

            if existing == nil {
                if !normEmail.isEmpty { byEmail[normEmail] = c }
                if !normPhone.isEmpty { byPhone[normPhone] = c }
            }
        }
        try ctx.save()
        return result
    }

    // MARK: Apple Contacts
    @MainActor
    static func importFromAppleContacts(into ctx: NSManagedObjectContext) async throws -> ImportResult {
        let store = CNContactStore()
        try await store.requestAccess(for: .contacts)
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor
        ]
        let req = CNContactFetchRequest(keysToFetch: keys)
        var rows: [CSVRow] = []
        try store.enumerateContacts(with: req) { cn, _ in
            let email = cn.emailAddresses.first?.value as String? ?? ""
            let phone = cn.phoneNumbers.first?.value.stringValue ?? ""
            let url = (cn.urlAddresses.first?.value as String?) ?? ""
            rows.append(CSVRow(
                first: cn.givenName,
                last: cn.familyName,
                company: cn.organizationName,
                position: cn.jobTitle,
                email: email,
                phone: phone,
                linkedin: url,
                notes: ""
            ))
        }
        return try importRows(rows, into: ctx)
    }
}

// --- tiny helpers
private extension String {
    // very small CSV splitter handling quotes and commas
    func splitCSV() -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuotes = false
        var it = self.makeIterator()
        while let ch = it.next() {
            if ch == "\"" {
                if inQuotes, let peek = it.peek(), peek == "\"" {
                    _ = it.next(); cur.append("\"")   // escaped quote
                } else {
                    inQuotes.toggle()
                }
            } else if ch == "," && !inQuotes {
                out.append(cur); cur = ""
            } else {
                cur.append(ch)
            }
        }
        out.append(cur)
        return out
    }
}
private extension String {
    var digitsOnly: String { self.filter { $0.isNumber } }
}
private extension String.Iterator {
    mutating func peek() -> Character? {
        var copy = self
        return copy.next()
    }
}
