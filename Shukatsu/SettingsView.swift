//
//  SettingsView.swift
//  Shukatsu
//
//  Created by rob on 8/31/25.
//

// SettingsView.swift
import SwiftUI

private let settingsFieldWidth: CGFloat = 320

struct SettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager
    // These @State flags are local-only for now.
    // We’ll bind them to Profile/CoreData + ProfileManager in the next pass.
    @State private var usePassword = false
    @State private var autoLockEnabled = false
    @State private var autoLockMinutes: Int = 10

    @State private var backendURL: String = ""
    @State private var enableFoxit = false
    @State private var enableSalesforce = false
    @State private var enableEvents = false

    // Password flow
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var disablePasswordInput: String = ""
    @State private var passwordError: String? = nil

    // Sheet flags (we’ll replace these with real sheets later)
    @State private var showingSetPassword = false
    @State private var showingConfirmPassword = false
    @State private var showingDeleteProfile = false
    @State private var deleteConfirmText = ""
    @State private var deleteErrorMessage: String? = nil

    @State private var editedProfileName: String = ""
    @State private var editedEmail: String = ""
    @State private var userName: String = ""
    @State private var userRole: String = ""
    @State private var phoneNumber: String = ""
    @State private var saveMessage: String? = nil

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 24) {
                // Left column
                VStack(alignment: .leading, spacing: 24) {
                    // Account (moved unchanged)
                    SettingsCard(title: "Account") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 8) {
                                Text("Profile")
                                Spacer(minLength: 8)
                                TextField("Profile name", text: $editedProfileName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: settingsFieldWidth)
                            }
                            HStack(alignment: .center, spacing: 8) {
                                Text("Name").font(.callout)
                                Spacer(minLength: 8)
                                TextField("User Name", text: $userName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: settingsFieldWidth)
                            }
                            HStack(alignment: .center, spacing: 8) {
                                Text("Role").font(.callout)
                                Spacer(minLength: 8)
                                TextField("e.g., iOS Developer", text: $userRole)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: settingsFieldWidth)
                            }
                            HStack(alignment: .center, spacing: 8) {
                                Text("Phone").font(.callout)
                                Spacer(minLength: 8)
                                TextField("(555) 123-4567", text: $phoneNumber)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: settingsFieldWidth)
                            }
                            HStack(alignment: .center, spacing: 8) {
                                Text("Email").font(.callout)
                                Spacer(minLength: 8)
                                TextField("name@example.com", text: $editedEmail)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: settingsFieldWidth)
                            }
                            HStack {
                                Spacer()
                                if let msg = saveMessage {
                                    Text(msg).foregroundStyle(.secondary)
                                }
                                Button("Save") {
                                    let kName  = profileManager.namespacedKey("UserName")
                                    let kRole  = profileManager.namespacedKey("UserRole")
                                    let kPhone = profileManager.namespacedKey("PhoneNumber")
                                    let kEmail = profileManager.namespacedKey("EmailAddress")
                                    let trimmedProfile = editedProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmedProfile.isEmpty, trimmedProfile != profileManager.current.displayName {
                                        profileManager.renameCurrentProfile(to: trimmedProfile)
                                    }
                                    let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !name.isEmpty { UserDefaults.standard.set(name, forKey: kName) }
                                    let role = userRole.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !role.isEmpty { UserDefaults.standard.set(role, forKey: kRole) }
                                    let phone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !phone.isEmpty { UserDefaults.standard.set(phone, forKey: kPhone) }
                                    let email = editedEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !email.isEmpty { UserDefaults.standard.set(email, forKey: kEmail) }
                                    // Read back to confirm and reflect in UI
                                    userName    = UserDefaults.standard.string(forKey: kName)  ?? userName
                                    userRole    = UserDefaults.standard.string(forKey: kRole)  ?? userRole
                                    phoneNumber = UserDefaults.standard.string(forKey: kPhone) ?? phoneNumber
                                    editedEmail = UserDefaults.standard.string(forKey: kEmail) ?? editedEmail
                                    saveMessage = "Saved"
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saveMessage = nil }
                                }
                                .keyboardShortcut(.defaultAction)
                            }
                            Divider().padding(.top, 2)
                            Divider().padding(.top, 6)
                            HStack {
                                Button(role: .destructive) {
                                    deleteConfirmText = ""
                                    deleteErrorMessage = nil
                                    showingDeleteProfile = true
                                } label: {
                                    Text("Delete Profile…")
                                }
                                Spacer()
                                Button { /* wire later */ } label: {
                                    Text("Export Profile…")
                                }
                                .disabled(true)
                            }
                        }
                    }

                    // Security
                    SettingsCard(title: "Security") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Password")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                if usePassword {
                                    Text("Enabled").foregroundStyle(.secondary)
                                    Button("Change…") { showingSetPassword = true }
                                        .controlSize(.small)
                                    Button("Remove…") { showingConfirmPassword = true }
                                        .controlSize(.small)
                                } else {
                                    Text("Disabled").foregroundStyle(.secondary)
                                    Button("Set Password…") { showingSetPassword = true }
                                        .controlSize(.small)
                                }
                                Spacer(minLength: 8)
                            }
                            Divider().padding(.vertical, 6)
                            Toggle("Require password for this profile", isOn: $usePassword)
                                .onChange(of: usePassword) { _, newVal in
                                    if newVal { showingSetPassword = true }
                                    else { showingConfirmPassword = true }
                                }
                            Toggle("Auto-lock when idle", isOn: $autoLockEnabled)
                            if autoLockEnabled {
                                Stepper(value: $autoLockMinutes, in: 1...120, step: 1) {
                                    Text("Auto-lock after \(autoLockMinutes) min")
                                }
                            }
                        }
                    }

                    // About
                    SettingsCard(title: "About") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Version")
                                Spacer()
                                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("Build")
                                Spacer()
                                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Right column
                VStack(alignment: .leading, spacing: 24) {
                    SettingsCard(title: "Integrations (optional)") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Generate PDFs", isOn: $enableFoxit)
                            Toggle("Sync to CRM", isOn: $enableSalesforce)
                            Toggle("Publish events", isOn: $enableEvents)
                            TextField("Backend URL", text: $backendURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.callout)
                                .placeholder(when: backendURL.isEmpty) {
                                    Text("https://api.example.com").foregroundStyle(.secondary)
                                }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .onAppear {
                editedProfileName = profileManager.current.displayName
                usePassword = profileManager.currentPasswordExists()
                let kName  = profileManager.namespacedKey("UserName")
                let kRole  = profileManager.namespacedKey("UserRole")
                let kPhone = profileManager.namespacedKey("PhoneNumber")
                let kEmail = profileManager.namespacedKey("EmailAddress")
                userName = UserDefaults.standard.string(forKey: kName) ?? ""
                userRole = UserDefaults.standard.string(forKey: kRole) ?? ""
                phoneNumber = UserDefaults.standard.string(forKey: kPhone) ?? ""
                editedEmail = UserDefaults.standard.string(forKey: kEmail) ?? ""
            }
            .onChange(of: profileManager.current.id) { _, _ in
                editedProfileName = profileManager.current.displayName
                usePassword = profileManager.currentPasswordExists()
                let kName  = profileManager.namespacedKey("UserName")
                let kRole  = profileManager.namespacedKey("UserRole")
                let kPhone = profileManager.namespacedKey("PhoneNumber")
                let kEmail = profileManager.namespacedKey("EmailAddress")
                userName = UserDefaults.standard.string(forKey: kName) ?? ""
                userRole = UserDefaults.standard.string(forKey: kRole) ?? ""
                phoneNumber = UserDefaults.standard.string(forKey: kPhone) ?? ""
                editedEmail = UserDefaults.standard.string(forKey: kEmail) ?? ""
            }
            .frame(maxWidth: 980)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        // Temporary placeholder sheets (so this file compiles and runs right now)
        .sheet(isPresented: $showingSetPassword) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Set Password for Profile").font(.headline)
                SecureField("New password", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirm password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                if let err = passwordError { Text(err).foregroundStyle(.red).font(.footnote) }
                HStack {
                    Spacer()
                    Button("Cancel") {
                        newPassword = ""; confirmPassword = ""; passwordError = nil
                        // restore toggle state based on current storage
                        usePassword = profileManager.currentPasswordExists()
                        showingSetPassword = false
                    }
                    Button("Save") {
                        let a = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
                        let b = confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard a.count >= 4 else { passwordError = "Use at least 4 characters"; return }
                        guard a == b else { passwordError = "Passwords don’t match"; return }
                        if profileManager.setPasswordForCurrent(a) {
                            usePassword = true
                            passwordError = nil
                            newPassword = ""; confirmPassword = ""
                            showingSetPassword = false
                        } else {
                            passwordError = "Could not save password"
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(minWidth: 420)
        }
        .sheet(isPresented: $showingConfirmPassword) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Disable Password").font(.headline)
                SecureField("Current password", text: $disablePasswordInput)
                    .textFieldStyle(.roundedBorder)
                if let err = passwordError { Text(err).foregroundStyle(.red).font(.footnote) }
                HStack {
                    Button("Cancel") {
                        // user decided not to disable; revert toggle
                        usePassword = true
                        passwordError = nil
                        disablePasswordInput = ""
                        showingConfirmPassword = false
                    }
                    Spacer()
                    Button("Disable", role: .destructive) {
                        if profileManager.verifyCurrentPassword(disablePasswordInput) {
                            profileManager.clearCurrentPassword()
                            usePassword = false
                            passwordError = nil
                            disablePasswordInput = ""
                            showingConfirmPassword = false
                        } else {
                            passwordError = "Incorrect password"
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(minWidth: 420)
        }
        
        .sheet(isPresented: $showingDeleteProfile) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Delete Profile")
                    .font(.headline)
                Text("This will remove the profile's databases from the active list and move them to the ArchivedProfiles folder. Your documents on disk (cover letters, resumes) will not be deleted.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("Type DELETE to confirm")
                    .font(.callout)
                TextField("DELETE", text: $deleteConfirmText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { /* no-op */ }
                if let err = deleteErrorMessage {
                    Text(err).foregroundStyle(.red).font(.footnote)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { showingDeleteProfile = false }
                    Button("Delete", role: .destructive) {
                        if deleteConfirmText == "DELETE" {
                            do {
                                try profileManager.archiveProfile(profileManager.current, container: PersistenceController.shared.container)
                                showingDeleteProfile = false
                            } catch {
                                deleteErrorMessage = error.localizedDescription
                            }
                        } else {
                            deleteErrorMessage = "Please type DELETE to confirm."
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(deleteConfirmText != "DELETE")
                }
            }
            .padding()
            .frame(minWidth: 460)
        }
    }
}

#Preview {
    SettingsView()
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                    )
            )
        }
    }
}

// Tiny helper so the backend URL field shows a hint
private extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder _ placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            if shouldShow { placeholder() }
            self
        }
    }
}
