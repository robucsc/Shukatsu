//
//  ContentView.swift
//  Shukatsu
//
//  Created by rob on 8/2/25.
//

import SwiftUI
import CoreData
import Combine

private struct SidebarWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 280
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct InspectorBox: Equatable {
    let id = UUID()
    let view: AnyView
    static func == (lhs: InspectorBox, rhs: InspectorBox) -> Bool { lhs.id == rhs.id }
}

struct InspectorContentKey: PreferenceKey {
    static var defaultValue: InspectorBox = InspectorBox(view: AnyView(EmptyView()))
    static func reduce(value: inout InspectorBox, nextValue: () -> InspectorBox) { value = nextValue() }
}

enum SidebarItem: Hashable {
    case opportunities
    case contacts
    case reports
    case settings
}

struct ContentView: View {
    @State private var sidebarSelection: SidebarItem? = .opportunities
    @State private var selectedOpportunity: Opportunity?
    @State private var selectedContact: Contact?
    @State private var searchText: String = ""
    @State private var inspectorPresented = true
    @State private var inspectorSortKey: OpportunityInspectorList.SortKey = .title
    @State private var inspectorAscending: Bool = true
    @State private var inspectorContent: AnyView = AnyView(EmptyView())
    @State private var showingSearch = false
    @State private var sidebarWidth: CGFloat = 280
    
    
    @Environment(\.managedObjectContext) var managedObjectContext
    @EnvironmentObject var profileManager: ProfileManager
    


    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection, searchText: $searchText)
        } detail: {
            DetailView(selectedItem: sidebarSelection, selectedOpportunity: $selectedOpportunity, selectedContact: $selectedContact)
                .id(profileManager.profileSwitchToken)
                .onPreferenceChange(InspectorContentKey.self) { box in inspectorContent = box.view }
        }
        .onAppear { diagAI() }
        .onPreferenceChange(SidebarWidthKey.self) { w in
            sidebarWidth = w
        }
        .id(profileManager.profileSwitchToken)
        .inspector(isPresented: $inspectorPresented) {
            VStack { inspectorContent }
                .id(profileManager.profileSwitchToken)
        }
        .onReceive(NotificationCenter.default.publisher(for: InspectorBus.hide)) { _ in
            inspectorPresented = false
        }
        .onReceive(NotificationCenter.default.publisher(for: InspectorBus.show)) { _ in
            inspectorPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: InspectorBus.toggle)) { _ in
            inspectorPresented.toggle()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Add Opportunity") {
                        self.addOpportunity()
                    }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                    Divider()
                    Button("Delete Selected Opportunity", role: .destructive) {
                        deleteSelectedOpportunity()
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(selectedOpportunity == nil)
                } label: {
                    Label("Opportunities", systemImage: "briefcase")
                }

                Menu {
                    Button("Add Contact") {
                        self.addContact()
                    }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                    Divider()
                    Button("Delete Selected Contact", role: .destructive) {
                        deleteSelectedContact()
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(selectedContact == nil)
                } label: {
                    Label("Contacts", systemImage: "person.crop.circle")
                }

                Button {
                    sidebarSelection = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
//        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
        .onChange(of: searchText) { _, t in
            showingSearch = !t.isEmpty
        }
        .overlay {
            if showingSearch {
                GeometryReader { g in
                    ZStack(alignment: .topLeading) {
                        // Full-screen tap catcher to dismiss when clicking outside the panel
                        Color.clear
                            .contentShape(Rectangle())
                            .ignoresSafeArea()
                            .onTapGesture {
                                showingSearch = false
                                searchText = ""
                            }
                            .zIndex(5)

                        // Spotlight-like panel anchored near the sidebar/search area
                        SearchView(query: searchText) { (hit: SearchResult) in
                            switch hit.kind {
                            case .opportunity:
                                if let obj = try? managedObjectContext.existingObject(with: hit.id) as? Opportunity {
                                    selectedOpportunity = obj
                                    sidebarSelection = .opportunities
                                }
                            case .contact:
                                if let obj = try? managedObjectContext.existingObject(with: hit.id) as? Contact {
                                    selectedContact = obj
                                    sidebarSelection = .contacts
                                }
                            }
                            // Keep panel open while browsing; clear text or click outside to close.
                        }
                        .frame(width: max(196, sidebarWidth - 32), height: 420)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(radius: 12, y: 6)
                        .padding(.top, g.safeAreaInsets.top - 72)
                        .padding(.leading, 8)
                        .zIndex(10)
                    }
                }
            }
        }
        .animation(.default, value: inspectorPresented)
        .onExitCommand {
            searchText = ""
            showingSearch = false
        }
        .onChange(of: profileManager.profileSwitchToken) { _, _ in
            searchText = ""
            selectedOpportunity = nil
            selectedContact = nil
            inspectorContent = AnyView(EmptyView())
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ProfileWillSwitch"))) { _ in
            selectedOpportunity = nil
            selectedContact = nil
            inspectorContent = AnyView(EmptyView())
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenSettings"))) { _ in
            sidebarSelection = .settings
            inspectorContent = AnyView(EmptyView())
        }
    }
    
    private func addContact() {
        let c = Contact(context: managedObjectContext)
        c.first = ""
        c.last = ""
        c.company = ""
        c.position = ""
        c.linkedin = ""
        c.phone = ""
        c.email = ""
        c.notes = ""
        c.connected = .now
        c.contact = .now
        do {
            try managedObjectContext.save()
            selectedContact = c
            sidebarSelection = .contacts
        } catch { print("Save failed: \(error)") }
    }
    
    private func addOpportunity() {
        let o = Opportunity(context: managedObjectContext)
        do {
            try managedObjectContext.save()
            selectedOpportunity = o
            sidebarSelection = .opportunities
        } catch { print("Save failed: \(error)") }
    }

    private func deleteSelectedOpportunity() {
        guard let sel = selectedOpportunity else { return }
        let id = sel.objectID
        selectedOpportunity = nil
        managedObjectContext.performAndWait {
            let obj = managedObjectContext.object(with: id)
            managedObjectContext.delete(obj)
            try? managedObjectContext.save()
        }
    }

    private func deleteSelectedContact() {
        guard let sel = selectedContact else { return }
        let id = sel.objectID
        selectedContact = nil
        managedObjectContext.performAndWait {
            let obj = managedObjectContext.object(with: id)
            managedObjectContext.delete(obj)
            try? managedObjectContext.save()
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Binding var searchText: String

    var body: some View {
        List(selection: $selection) {
            Divider()
            NavigationLink("Opportunities", value: SidebarItem.opportunities)
            NavigationLink("Contacts", value: SidebarItem.contacts)
            NavigationLink("Reports", value: SidebarItem.reports)
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: SidebarWidthKey.self, value: geo.size.width)
            }
        )
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
        .listStyle(.sidebar)
        .navigationTitle("Shukatsu")
        .overlay(alignment: .bottomLeading) { ProfileMenuButton() }
    }
}

struct DetailView: View {
    var selectedItem: SidebarItem?
    @Binding var selectedOpportunity: Opportunity?
    @Binding var selectedContact: Contact?

    @Environment(\.managedObjectContext) var managedObjectContext // << Add this line
    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        switch selectedItem {
        case .opportunities:
            OpportunitiesDetail(selectedOpportunity: $selectedOpportunity)
                .id(profileManager.profileSwitchToken)
        case .contacts:
            ContactsDetail(selectedContact: $selectedContact)
        case .reports:
            ReportView()
        case .settings:
            SettingsView()
                .preference(key: InspectorContentKey.self, value: InspectorBox(view: AnyView(EmptyView())))
        case .none:
            Text("Select an item")
        }
    }
}

struct InspectorView: View {
    var body: some View {
        EmptyView()
    }
}

struct ReportView: View {
    var body: some View {
        Text("Report View Placeholder")
    }
}

func toggleSidebar() {
   NSApp.keyWindow?.firstResponder?.tryToPerform(
       #selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
}

func openSettings() {
    NotificationCenter.default.post(name: Notification.Name("OpenSettings"), object: nil)
}


#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(ProfileManager())
}

struct LoginDialog: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Binding var showing: Bool
    @State private var newProfileName = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Profile")
                .font(.headline)

            TextField("Profile Name", text: $newProfileName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(minWidth: 250)

            HStack {
                Button("Cancel") {
                    showing = false
                }
                Spacer()
                Button("Create") {
                    if !newProfileName.isEmpty {
                        try? profileManager.createProfile(named: newProfileName)
                        showing = false
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

