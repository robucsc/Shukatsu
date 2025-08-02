//
//  ContactView.swift
//  Shukatsu
//
//  Created by rob on 8/3/25.
//

import SwiftUI
import CoreData

private struct InspectorRow: View {
    let label: String
    let value: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(label):")
                .font(.callout.weight(.semibold))
                .frame(width: 64, alignment: .leading)
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            Text(trimmed.isEmpty ? "—" : trimmed)
                .font(.callout)
                .foregroundStyle(trimmed.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 22)
    }
}

struct ContactView: View {
    // Edit a real Core Data contact
    @ObservedObject var contact: Contact
    @Environment(\.managedObjectContext) private var context

    @State private var saveWorkItem: DispatchWorkItem?

    private func saveDebounced() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { try? context.save() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func saveNow() { try? context.save() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GroupBox("Contact Details") {
                    Grid(alignment: .leading, horizontalSpacing: 9, verticalSpacing: 10) {
                        GridRow { field("First", text: $contact.first.stringOrEmpty); field("Last", text: $contact.last.stringOrEmpty) }
                        GridRow { field("Company", text: $contact.company.stringOrEmpty); field("Position", text: $contact.position.stringOrEmpty) }
                        GridRow { field("Phone", text: $contact.phone.stringOrEmpty); field("Email", text: $contact.email.stringOrEmpty) }
                        GridRow {  field("LinkedIn", text: $contact.linkedin.stringOrEmpty) }

                        // Connected (from LinkedIn export)
                        GridRow {
                            DatePicker("Connected", selection: $contact.connected.dateOrToday, displayedComponents: [.date])
                                .datePickerStyle(.field)
                                .onChange(of: contact.connected ?? Date()) { _, _ in saveDebounced() }
                            
                            DatePicker("Last Contacted", selection: $contact.contact.dateOrToday, displayedComponents: [.date])
                                                            .datePickerStyle(.field)
                                                            .onChange(of: contact.contact ?? Date()) { _, _ in saveDebounced() }
                        }

                        // Notes
                        GridRow {
                            TextEditor(text: $contact.notes.stringOrEmpty)
                                .frame(minHeight: 120)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 1))
                                .gridCellColumns(2)
                                .onChange(of: contact.notes ?? "") { _, _ in saveDebounced() }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(displayName)
        .onDisappear { saveNow() }
    }

    private var displayName: String {
        let first = contact.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last  = contact.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let full  = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "Contact" : full
    }

    // MARK: - Row helpers
    @ViewBuilder
    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(prompt))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 260)
            .onChange(of: text.wrappedValue) { _, _ in saveDebounced() }
    }
}

// MARK: - Optional binding helpers
extension Binding where Value == String? {
    var stringOrEmpty: Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? "" },
            set: { self.wrappedValue = $0 }
        )
    }
}

extension Binding where Value == Date? {
    /// Provides a non-optional Date binding (defaults to today). When set, writes back to the optional.
    var dateOrToday: Binding<Date> {
        Binding<Date>(
            get: { self.wrappedValue ?? Date() },
            set: { self.wrappedValue = $0 }
        )
    }
}

// MARK: - Domain-local creation API (keeps creation in the Contact feature)
extension Contact {
    @discardableResult
    static func create(in context: NSManagedObjectContext,
                       first: String = "",
                       last: String = "",
                       linkedin: String = "",
                       company: String = "",
                       position: String = "",
                       phone: String = "",
                       email: String = "",
                       notes: String = "",
                       connected: Date? = nil,
                       contact: Date? = nil) throws -> Contact {
        let c = Contact(context: context)
        c.first = first
        c.last = last
        c.linkedin = linkedin
        c.company = company
        c.position = position
        c.phone = phone
        c.email = email
        c.notes = notes
        c.connected = connected ?? .now
        c.contact  = contact  ?? .now
        try context.save()
        return c
    }
}

 struct ContactsDetail: View {
    @Binding var selectedContact: Contact?
    @Environment(\.managedObjectContext) private var context

    private func ensureSelected() {
        guard selectedContact == nil else { return }
        let req: NSFetchRequest<Contact> = Contact.fetchRequest()
        req.sortDescriptors = [
            NSSortDescriptor(key: "contact",   ascending: false),
            NSSortDescriptor(key: "connected", ascending: false),
            NSSortDescriptor(key: "last",      ascending: true)
        ]
        req.fetchLimit = 1
        if let newest = try? context.fetch(req).first {
            selectedContact = newest
        } else if let created = try? Contact.create(in: context) {
            selectedContact = created
        }
    }

    var body: some View {
        let _ = ensureSelected()
        return Group {
            if let c = selectedContact, c.managedObjectContext === context {
                ContactView(contact: c)
                    .preference(
                        key: InspectorContentKey.self,
                        value: InspectorBox(view: AnyView(ContactInspectorPane(selected: $selectedContact)))
                    )
            } else {
                EmptyView()
            }
        }
    }
}

struct ContactInspectorPane: View {
    @Binding var selected: Contact?
    @Environment(\.managedObjectContext) private var context

    private enum SortKey { case first, last, connected }
    @State private var sortKey: SortKey = .first
    @State private var ascending: Bool = true

    private let lastColWidth: CGFloat = 64
    private let connectedColWidth: CGFloat = 72

    private let connectedFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .none
        return df
    }()

    private func descriptors() -> [NSSortDescriptor] {
        switch sortKey {
        case .first:
            return [
                NSSortDescriptor(keyPath: \Contact.first, ascending: ascending),
                NSSortDescriptor(keyPath: \Contact.last, ascending: true)
            ]
        case .last:
            return [
                NSSortDescriptor(keyPath: \Contact.last, ascending: ascending),
                NSSortDescriptor(keyPath: \Contact.first, ascending: true)
            ]
        case .connected:
            return [
                NSSortDescriptor(key: "connected", ascending: ascending),
                NSSortDescriptor(keyPath: \Contact.last, ascending: true),
                NSSortDescriptor(keyPath: \Contact.first, ascending: true)
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let c = selected, c.managedObjectContext === context {
                Text("Inspector").font(.headline)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    InspectorRow(label: "Name",    value: displayName(c))
                    InspectorRow(label: "Company", value: c.company)
                    InspectorRow(label: "Email",   value: c.email)
                    InspectorRow(label: "Phone",   value: c.phone)
                }
                Divider().padding(.vertical, 4)
            } else {
                Text("No selection")
                    .foregroundStyle(.secondary)
            }

            // Contacts list
            Text("Contacts").font(.headline)

            // Sort header (Opps-style pills)
            HStack(spacing: 4) {
                SortHeaderButton(title: "First", isActive: sortKey == .first, ascending: ascending && sortKey == .first, width: nil) {
                    if sortKey == .first { ascending.toggle() } else { sortKey = .first; ascending = true }
                }
                SortHeaderButton(title: "Last", isActive: sortKey == .last, ascending: ascending && sortKey == .last, width: lastColWidth) {
                    if sortKey == .last { ascending.toggle() } else { sortKey = .last; ascending = true }
                }
                SortHeaderButton(title: "Connected", isActive: sortKey == .connected, ascending: ascending && sortKey == .connected, width: connectedColWidth) {
                    if sortKey == .connected { ascending.toggle() } else { sortKey = .connected; ascending = false }
                }
                Spacer(minLength: 0)
            }
            .font(.footnote)
            .padding(.vertical, 0)
            Divider()

            ContactInspectorList(
                selected: $selected,
                descriptors: descriptors(),
                lastColWidth: lastColWidth,
                connectedColWidth: connectedColWidth,
                connectedFormatter: connectedFormatter
            )
            .frame(maxHeight: 220)
        }
        .padding(.horizontal, 8)
        .padding(.top, 0)
        .padding(.bottom, 8)
    }

    private func displayName(_ c: Contact) -> String {
        let first = c.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last  = c.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let full  = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "Contact" : full
    }

    private struct SortHeaderButton: View {
        let title: String
        let isActive: Bool
        let ascending: Bool
        let width: CGFloat? // nil means flexible (fill)
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(title)
                    if isActive { Image(systemName: ascending ? "chevron.up" : "chevron.down") }
                }
                .frame(
                    width: width,
                    alignment: .leading
                )
                .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
                .padding(.horizontal, isActive ? 6 : 0)
                .padding(.vertical, isActive ? 3 : 0)
                .background(isActive ? Color.secondary.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
    }

    private struct ContactInspectorList: View {
        @Binding var selected: Contact?
        @FetchRequest private var contacts: FetchedResults<Contact>
        let lastColWidth: CGFloat
        let connectedColWidth: CGFloat
        let connectedFormatter: DateFormatter

        init(selected: Binding<Contact?>, descriptors: [NSSortDescriptor], lastColWidth: CGFloat, connectedColWidth: CGFloat, connectedFormatter: DateFormatter) {
            self._selected = selected
            self._contacts = FetchRequest<Contact>(
                entity: Contact.entity(),
                sortDescriptors: descriptors,
                animation: .default
            )
            self.lastColWidth = lastColWidth
            self.connectedColWidth = connectedColWidth
            self.connectedFormatter = connectedFormatter
        }
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(contacts) { contact in
                        Button(action: { selected = contact }) {
                            let first = (contact.first ?? "").trimmingCharacters(in: .whitespaces)
                            let last  = (contact.last  ?? "").trimmingCharacters(in: .whitespaces)
                            let nameFirst = first.isEmpty ? "—" : first
                            let nameLast  = last.isEmpty ? "—" : last
                            let connected = contact.connected.map { connectedFormatter.string(from: $0) } ?? "—"

                            HStack(spacing: 2) {
                                Text(nameFirst)
                                    .foregroundStyle(first.isEmpty ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(nameLast)
                                    .foregroundStyle(last.isEmpty ? .secondary : .primary)
                                    .frame(width: lastColWidth, alignment: .leading)
                                Text(connected)
                                    .foregroundStyle(.secondary)
                                    .frame(width: connectedColWidth, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                        .background(
                            (selected?.objectID == contact.objectID
                             ? Color.accentColor.opacity(0.22)
                             : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        )
                    }
                }
            }
            .frame(minWidth: 260)
            .toolbar { InspectorToggleToolbarItems() }
        }
    }
}
