//
//  SearchView.swift
//  Shukatsu
//
//  Created by rob on 9/2/25.
//

import SwiftUI
import CoreData

// Identify which entity a hit refers to
enum SearchKind { case opportunity, contact }

// One search result row
struct SearchResult: Identifiable, Hashable {
    let id: NSManagedObjectID
    let title: String
    let kind: SearchKind
}

struct SearchView: View {
    @Environment(\.managedObjectContext) private var moc

    var query: String
    var onSelect: (SearchResult) -> Void

    @State private var opps: [SearchResult] = []
    @State private var contacts: [SearchResult] = []

    var body: some View {
        List {
            if !opps.isEmpty {
                Section("Opportunities") {
                    ForEach(opps) { hit in
                        Button(hit.title) { onSelect(hit) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if !contacts.isEmpty {
                Section("Contacts") {
                    ForEach(contacts) { hit in
                        Button(hit.title) { onSelect(hit) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if opps.isEmpty && contacts.isEmpty && !query.isEmpty {
                Text("No results for \"\(query)\"")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
        .onAppear { runSearch() }
        .onChange(of: query) { _, _ in runSearch() }
    }

    private func runSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { opps.removeAll(); contacts.removeAll(); return }

        let needle = text.lowercased()

        // Opportunities: fetch a small batch, filter in memory (safer for optional strings)
        do {
            let r = NSFetchRequest<Opportunity>(entityName: "Opportunity")
            r.fetchLimit = 200
            let items = try moc.fetch(r)
            let filtered = items.filter { opp in
                (opp.title?.localizedCaseInsensitiveContains(needle) ?? false) ||
                (opp.company?.localizedCaseInsensitiveContains(needle) ?? false)
            }
            opps = filtered.map { .init(id: $0.objectID, title: ($0.title ?? "Untitled"), kind: .opportunity) }
        } catch { opps.removeAll() }

        // Contacts: fetch a small batch, filter in memory (handles nils safely)
        do {
            let r = NSFetchRequest<Contact>(entityName: "Contact")
            r.fetchLimit = 200
            let items = try moc.fetch(r)
            let filtered = items.filter { c in
                let first = c.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let last  = c.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let company = c.company?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return first.localizedCaseInsensitiveContains(needle) ||
                       last.localizedCaseInsensitiveContains(needle) ||
                       company.localizedCaseInsensitiveContains(needle)
            }
            contacts = filtered.map { c in
                let name = [c.first, c.last]
                    .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                return .init(id: c.objectID, title: name.isEmpty ? "Unnamed Contact" : name, kind: .contact)
            }
        } catch { contacts.removeAll() }
    }
}

#Preview {
    // Preview with an empty context so the view compiles; results will be empty here.
    SearchView(query: "Test") { _ in }
}
