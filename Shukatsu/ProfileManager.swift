//
//  ProfileManager.swift
//  Shukatsu
//
//  Created by rob on 8/12/25.
//

import Foundation
import SwiftUI      // ObservableObject / @Published
import CoreData     // NSPersistentContainer
import AppKit
import Security    // Keychain

extension Notification.Name {
    static let ProfileWillDelete = Notification.Name("ProfileWillDelete")
}

// MARK: - Keychain helper
private enum Keychain {
    static let service = "com.shukatsu.app"

    static func set(_ data: Data, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary) // replace if exists
        var add = query
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func get(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        return status == errSecSuccess ? (out as? Data) : nil
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class ProfileManager: ObservableObject {
    static let shared = ProfileManager()
    private let lastProfileIDKey = "LastProfileID"

    @Published var current: ProfileInfo
    @Published var profiles: [ProfileInfo] = []
    // Notifies views to drop selections/rebuild when the profile/store changes.
    @Published var profileSwitchToken = UUID()

    struct ProfileInfo: Identifiable, Codable, Equatable {
        var id: String
        var displayName: String
    }
    
    // MARK: - Metadata stored inside each profile folder (profile.json)
    private struct ProfileMeta: Codable {
        var id: String
        var displayName: String
        var createdAt: Date
    }

    // MARK: - Secret namespaces
    private func passwordAccount(for profile: ProfileInfo) -> String { "profile-password-\(profile.id)" }

    // MARK: - Per-profile UserDefaults namespacing (lightweight helper)
    func namespacedKey(_ raw: String, for profile: ProfileInfo? = nil) -> String {
        let p = profile ?? current
        return "profile:\(p.id):\(raw)"
    }

    private func metaURL(for folder: URL) -> URL {
        folder.appendingPathComponent("profile.json")
    }

    private func loadMeta(at folder: URL) -> ProfileMeta? {
        let url = metaURL(for: folder)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProfileMeta.self, from: data)
    }

    private func saveMeta(for profile: ProfileInfo) {
        let folder = baseURL(for: profile)
        let meta = ProfileMeta(id: profile.id, displayName: profile.displayName, createdAt: Date())
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(meta)
            try data.write(to: metaURL(for: folder), options: .atomic)
        } catch {
            NSLog("Failed to write profile meta: \(error.localizedDescription)")
        }
    }

    init() {
        current = .init(id: "player-one", displayName: "Player One")
        loadProfiles()
        try? ensureProfileFolders()
    }
    
    var hasProfiles: Bool {
        !profiles.isEmpty
    }

    // MARK: Paths (for specific profile)
    private func baseURL(for profile: ProfileInfo) -> URL {
        let documents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        return documents.appendingPathComponent("Shukatsu/Profiles/\(profile.id)", isDirectory: true)
    }
    private func storeURL(for profile: ProfileInfo) -> URL { baseURL(for: profile).appendingPathComponent("Shukatsu.sqlite") }
    private func opportunitiesURL(for profile: ProfileInfo) -> URL { baseURL(for: profile).appendingPathComponent("Opportunities", isDirectory: true) }

    private var archivedProfilesBaseURL: URL {
        let documents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        return documents.appendingPathComponent("Shukatsu/ArchivedProfiles", isDirectory: true)
    }

    private func slug(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let allowed = lowered.compactMap { ch -> Character? in
            if ch.isLetter || ch.isNumber { return ch }
            if ch == " " || ch == "-" || ch == "_" { return "-" }
            return nil
        }
        var s = String(allowed)
        while s.contains("--") { s = s.replacingOccurrences(of: "--", with: "-") }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func timestampForArchive() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f.string(from: Date())
    }

    // MARK: Paths
    private var baseURL: URL {
        let documents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        return documents.appendingPathComponent("Shukatsu/Profiles/\(current.id)", isDirectory: true)
    }
    var storeURL: URL { baseURL.appendingPathComponent("Shukatsu.sqlite") }
    var opportunitiesURL: URL { baseURL.appendingPathComponent("Opportunities", isDirectory: true) }

    // MARK: Folder setup
    @discardableResult
    func ensureProfileFolders() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL
    }

    @discardableResult
    func ensureProfileFolders(for profile: ProfileInfo) throws -> URL {
        let fm = FileManager.default
        let url = baseURL(for: profile)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeStoreDescription(for url: URL) -> NSPersistentStoreDescription {
        let desc = NSPersistentStoreDescription(url: url)
        // Enable lightweight migration by default
        desc.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        desc.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        return desc
    }

    // MARK: Helpers for store destruction
    private func destroyStore(at url: URL, in container: NSPersistentContainer) throws {
        let psc = container.persistentStoreCoordinator
        // Best-effort: if the store is loaded, remove it before destroying
        for store in psc.persistentStores where store.url == url {
            try psc.remove(store)
        }
        try psc.destroyPersistentStore(at: url, ofType: NSSQLiteStoreType, options: nil)
    }

    // MARK: Switching stores
    func switchTo(_ profile: ProfileInfo, container: NSPersistentContainer) throws {
        // Ensure any active field editors are dismissed before swapping stores to avoid ViewBridge issues.
        NSApp.windows.forEach { $0.endEditing(for: nil) }
        // Tell views to drop selections BEFORE we touch the stores.
        NotificationCenter.default.post(name: Notification.Name("ProfileWillSwitch"), object: nil)

        // Defer the heavy lifting to the next runloop so SwiftUI can release references
        // to objects from the old store before we remove it.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self._performSwitch(to: profile, container: container)
        }
    }

    private func _performSwitch(to profile: ProfileInfo, container: NSPersistentContainer) {
        do {
            self.current = profile
            try self.ensureProfileFolders(for: profile)
            print("Switching to profile \(profile.displayName) → \(self.storeURL(for: profile).path)")

            // Remove any already-loaded stores
            let psc = container.persistentStoreCoordinator
            for store in psc.persistentStores {
                try psc.remove(store)
            }

            // Point the container to the new URL and (re)load
            let desc = makeStoreDescription(for: storeURL(for: profile))
            container.persistentStoreDescriptions = [desc]

            var loadErr: Error?
            container.loadPersistentStores { _, err in loadErr = err }
            if let e = loadErr { throw e }

            // Recommended viewContext config
            container.viewContext.automaticallyMergesChangesFromParent = true
            container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

            // Remember last-used profile for next launch
            UserDefaults.standard.set(profile.id, forKey: lastProfileIDKey)

            // Drop any cached objects from the old store and notify views to reset.
            container.viewContext.reset()
            DispatchQueue.main.async { self.profileSwitchToken = UUID() }
        } catch {
            NSLog("Profile switch failed: \(error.localizedDescription)")
        }
    }

    /// Call this once during app startup after you create the NSPersistentContainer but before UI uses it.
    func bootstrapInitialStore(container: NSPersistentContainer) throws {
        try ensureProfileFolders(for: current)

        // Remove any preloaded stores and load the current profile's store
        let psc = container.persistentStoreCoordinator
        for store in psc.persistentStores { try psc.remove(store) }

        let desc = makeStoreDescription(for: storeURL(for: current))
        container.persistentStoreDescriptions = [desc]

        var loadErr: Error?
        container.loadPersistentStores { _, err in loadErr = err }
        if let e = loadErr { throw e }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Soft-delete (archive) a profile by moving its on-disk store folder to ArchivedProfiles.
    /// Does not remove user documents; reversible by moving the folder back.
    func archiveProfile(_ profile: ProfileInfo, container: NSPersistentContainer) throws {
        NSApp.windows.forEach { $0.endEditing(for: nil) }

        let archivingCurrent = (current.id == profile.id)
        if archivingCurrent {
            NotificationCenter.default.post(name: .ProfileWillDelete, object: nil)
        }

        if archivingCurrent {
            if let next = profiles.first(where: { $0.id != profile.id }) {
                try switchTo(next, container: container)
            } else {
                let psc = container.persistentStoreCoordinator
                for store in psc.persistentStores { try psc.remove(store) }
                let desc = NSPersistentStoreDescription()
                desc.type = NSInMemoryStoreType
                container.persistentStoreDescriptions = [desc]
                var loadErr: Error?
                container.loadPersistentStores { _, err in loadErr = err }
                if let e = loadErr { throw e }
                container.viewContext.reset()
            }
        }

        let fm = FileManager.default
        let srcFolder = baseURL(for: profile)
        try fm.createDirectory(at: archivedProfilesBaseURL, withIntermediateDirectories: true)

        let shortId = String(profile.id.prefix(8))
        let nameSlug = slug(profile.displayName)
        let destName = "\(timestampForArchive())-\(nameSlug.isEmpty ? "profile" : nameSlug)-\(shortId)"
        let dstFolder = archivedProfilesBaseURL.appendingPathComponent(destName, isDirectory: true)

        if fm.fileExists(atPath: srcFolder.path) {
            try fm.moveItem(at: srcFolder, to: dstFolder)
            // Ensure a profile.json exists in the archived folder capturing the friendly name
            let archivedMetaURL = dstFolder.appendingPathComponent("profile.json")
            if !fm.fileExists(atPath: archivedMetaURL.path) {
                let meta = ProfileMeta(id: profile.id, displayName: profile.displayName, createdAt: Date())
                if let data = try? JSONEncoder().encode(meta) {
                    try? data.write(to: archivedMetaURL, options: .atomic)
                }
            }
        }

        profiles.removeAll { $0.id == profile.id }

        if archivingCurrent {
            if let first = profiles.first {
                current = first
                UserDefaults.standard.set(first.id, forKey: lastProfileIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastProfileIDKey)
                current = .init(id: "player-one", displayName: "Player One")
            }
            DispatchQueue.main.async { self.profileSwitchToken = UUID() }
        }
    }
    
    func renameCurrentProfile(to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let i = profiles.firstIndex(where: { $0.id == current.id }) {
            profiles[i].displayName = name
            current.displayName = name
            saveMeta(for: current)               // writes profile.json
            DispatchQueue.main.async { self.profileSwitchToken = UUID() }
        }
    }

    // MARK: - Profile password (Keychain)
    @discardableResult
    func setPassword(_ password: String, for profile: ProfileInfo) -> Bool {
        let data = Data(password.utf8)
        return Keychain.set(data, account: passwordAccount(for: profile))
    }

    func passwordExists(for profile: ProfileInfo) -> Bool {
        Keychain.get(account: passwordAccount(for: profile)) != nil
    }

    func verifyPassword(_ password: String, for profile: ProfileInfo) -> Bool {
        guard let stored = Keychain.get(account: passwordAccount(for: profile)) else { return false }
        return stored == Data(password.utf8)
    }

    func clearPassword(for profile: ProfileInfo) {
        Keychain.delete(account: passwordAccount(for: profile))
    }

    // Current profile convenience
    @discardableResult
    func setPasswordForCurrent(_ password: String) -> Bool { setPassword(password, for: current) }
    func verifyCurrentPassword(_ password: String) -> Bool { verifyPassword(password, for: current) }
    func currentPasswordExists() -> Bool { passwordExists(for: current) }
    func clearCurrentPassword() { clearPassword(for: current) }


    /// Permanently delete a profile and its Core Data store on disk.
    /// If deleting the current profile, we switch to another profile (or an in-memory store if none remain).
    func deleteProfile(_ profile: ProfileInfo, container: NSPersistentContainer) throws {
        // End editing to avoid field editor issues.
        NSApp.windows.forEach { $0.endEditing(for: nil) }

        let deletingCurrent = (current.id == profile.id)

        // If deleting the current profile, switch away first (if possible)
        if deletingCurrent {
            if let next = profiles.first(where: { $0.id != profile.id }) {
                try switchTo(next, container: container)
            } else {
                // No other profiles: load an in-memory store temporarily to keep the context valid
                let psc = container.persistentStoreCoordinator
                for store in psc.persistentStores { try psc.remove(store) }

                let desc = NSPersistentStoreDescription()
                desc.type = NSInMemoryStoreType
                container.persistentStoreDescriptions = [desc]
                var loadErr: Error?
                container.loadPersistentStores { _, err in loadErr = err }
                if let e = loadErr { throw e }
                container.viewContext.reset()
            }
        }

        // Destroy the SQLite store and remove sidecar files/folder.
        let url = storeURL(for: profile)
        do {
            try destroyStore(at: url, in: container)
        } catch {
            // It might not be attached; fall through to best-effort file removal
        }

        let fm = FileManager.default
        let base = baseURL(for: profile)
        let sqlite = url
        let shm = sqlite.deletingPathExtension().appendingPathExtension("sqlite-shm")
        let wal = sqlite.deletingPathExtension().appendingPathExtension("sqlite-wal")
        _ = try? fm.removeItem(at: sqlite)
        _ = try? fm.removeItem(at: shm)
        _ = try? fm.removeItem(at: wal)

        // Attempt to remove the profile folder if now empty
        if let contents = try? fm.contentsOfDirectory(atPath: base.path), contents.isEmpty {
            _ = try? fm.removeItem(at: base)
        }

        // Update in-memory list and current selection
        profiles.removeAll { $0.id == profile.id }

        if deletingCurrent {
            if let first = profiles.first {
                current = first
                // Persist last used profile id
                UserDefaults.standard.set(first.id, forKey: lastProfileIDKey)
                // Notify UI
                DispatchQueue.main.async { self.profileSwitchToken = UUID() }
            } else {
                // No profiles remain; set a default and clear last-used id
                UserDefaults.standard.removeObject(forKey: lastProfileIDKey)
                current = .init(id: "player-one", displayName: "Player One")
                DispatchQueue.main.async { self.profileSwitchToken = UUID() }
            }
        }
    }

    // MARK: Profiles loading and creation
    private func loadProfiles() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let profilesURL = documents.appendingPathComponent("Shukatsu/Profiles", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: profilesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var loaded: [ProfileInfo] = []
        for url in contents where url.hasDirectoryPath {
            if let meta = loadMeta(at: url) {
                loaded.append(ProfileInfo(id: url.lastPathComponent, displayName: meta.displayName))
            } else {
                // Legacy fallback: if the folder name is a UUID, show a neutral name instead of the hash
                let folder = url.lastPathComponent
                if UUID(uuidString: folder) != nil {
                    loaded.append(ProfileInfo(id: folder, displayName: "Profile"))
                } else {
                    loaded.append(ProfileInfo(id: folder, displayName: folder))
                }
            }
        }
        profiles = loaded

        // Choose current
        if let saved = UserDefaults.standard.string(forKey: lastProfileIDKey),
           let match = profiles.first(where: { $0.id == saved }) {
            current = match
        } else if let keep = profiles.first(where: { $0.id == current.id }) {
            current = keep
        } else if let first = profiles.first {
            current = first
        }
    }

    func createProfile(named name: String) throws {
        let newProfile = ProfileInfo(id: UUID().uuidString, displayName: name)
        if profiles.contains(newProfile) { return }

        profiles.append(newProfile)
        _ = try? ensureProfileFolders(for: newProfile)
        saveMeta(for: newProfile)

        // Persist last-used profile id now
        UserDefaults.standard.set(newProfile.id, forKey: lastProfileIDKey)

        // Immediately switch the running Core Data stack to the new profile
        let container = PersistenceController.shared.container
        try? switchTo(newProfile, container: container)

        // Nudge listeners that a switch happened (safety)
        DispatchQueue.main.async { self.profileSwitchToken = UUID() }
    }
}

struct ProfileMenuButton: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var showLoginDialog = false

    var body: some View {
        Menu {
            // Header (disabled)
            Text(profileManager.current.displayName.isEmpty
                 ? "Select a profile"
                 : profileManager.current.displayName)
                .font(.headline)
                .foregroundStyle(.secondary)
                .disabled(true)

            Divider()

            // Settings
            Button("Settings…") { openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            
            Divider()

            if !profileManager.profiles.isEmpty {
                // Switch Profile submenu
                Menu("Switch Profile") {
                    ForEach(profileManager.profiles, id: \.id) { p in
                        if isCurrent(p) {
                            // Checked/disabled current item
                            Label(p.displayName, systemImage: "checkmark")
                                .disabled(true)
                        } else {
                            Button(p.displayName) { switchTo(p) }
                        }
                    }
                    Divider()
                    Button("Add New Profile…") { createNewProfile() }
                }

                // Log out
                Divider()
                
                Button("Log Out", role: .destructive) { logout() }
            } else {
                // No profiles yet
                Button("Sign In…") { signInExisting() }
                Button("Create New Profile…") { createNewProfile() }
            }
        } label: {
            // 🔒 Your existing visual stays the same
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(initials(from: profileManager.current.displayName))
                            .font(.caption)
                            .foregroundColor(.white)
                    )
                Text(profileManager.current.displayName.isEmpty
                     ? "No Profile"
                     : profileManager.current.displayName)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showLoginDialog) {
            LoginDialog(showing: $showLoginDialog)
                .environmentObject(profileManager)
        }
    }

    // MARK: - Helpers

    private func isCurrent(_ p: ProfileManager.ProfileInfo) -> Bool {
        profileManager.current.id == p.id
    }

    private func initials(from name: String) -> String {
        let s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "??" }
        let parts = s.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let second = parts.dropFirst().first?.prefix(1) ?? ""
        return String((first + second).uppercased())
    }

    // MARK: - Actions (stubs for now; we’ll move these into ProfileManager next)

    private func openSettings() {
        NotificationCenter.default.post(name: Notification.Name("OpenSettings"), object: nil)
    }

    private func switchTo(_ profile: ProfileManager.ProfileInfo) {
        // Example (matches your earlier code style):
        let container = PersistenceController.shared.container
        try? profileManager.switchTo(profile, container: container)
    }

    private func createNewProfile() {
        // For now, reuse the login/create dialog
        showLoginDialog = true
    }

    private func signInExisting() {
        showLoginDialog = true
    }

    private func logout() {
        // Your existing logout logic from earlier snippet
        let container = PersistenceController.shared.container
        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try? container.persistentStoreCoordinator.remove(store)
        }
        if let first = profileManager.profiles.first {
            try? profileManager.switchTo(first, container: container)
        }
    }
}


