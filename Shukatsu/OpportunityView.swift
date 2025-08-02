//
//  OpportunityView.swift
//  Shukatsu
//
//  Created by rob on 8/2/25.
//



import SwiftUI
import CoreData

@objc enum OpportunityStatus: Int32 {
    case start = 0
    case applied = 1
    case interview = 2
    case closed = 3
}

extension OpportunityStatus {
    var label: String {
        switch self {
        case .start:     return "Start"
        case .applied:   return "Applied"
        case .interview: return "Interview"
        case .closed:    return "Close"
        }
    }
}

struct PreviewOpportunity {
    let id = UUID()
    var company: String
    var title: String
    var location: String
    var salary: String
    var deadline: String
    var description: String
    var notes: String
}

extension Opportunity {
    @discardableResult
    static func create(in context: NSManagedObjectContext,
                       title: String = "Opportunity") throws -> Opportunity {
        let opp = Opportunity(context: context)
        opp.status = OpportunityStatus.start.rawValue
        opp.title = title
        opp.company = ""
        opp.location = ""
        opp.salary = ""
        opp.deadline = ""
        opp.desc = ""
        opp.notes = ""
        try context.save()
        return opp
    }
}


extension Opportunity {
    var wrappedStatus: OpportunityStatus {
        get { OpportunityStatus(rawValue: self.status) ?? .start }
        set { self.status = newValue.rawValue }
    }
}

private struct StatusControl: View {
    @Binding var status: OpportunityStatus

    var body: some View {
        GeometryReader { geo in
            let count: CGFloat = 4
            let segment = geo.size.width / count
            let centerX = segment * (CGFloat(status.rawValue) + 0.5)

            ZStack(alignment: .topLeading) {
                // Track
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 6)
                    .offset(y: 16)

                // Progress up to the middle of the active segment
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, centerX), height: 6)
                    .offset(y: 16)

                // Thumb (centered over the current label)
                Circle()
                    .fill(Color(.windowBackgroundColor))
                    .overlay(Circle().stroke(.separator))
                    .shadow(radius: 4, y: 1)
                    .frame(width: 22, height: 22)
                    .position(x: centerX, y: 16)

                // Tappable labels
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { idx in
                        Text(OpportunityStatus(rawValue: Int32(idx))?.label ?? "")
                            .font(.caption)
                            .frame(width: segment, alignment: .center)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                    status = OpportunityStatus(rawValue: Int32(idx)) ?? .start
                                }
                            }
                    }
                }
                .padding(.top, 28)
            }
        }
        .frame(height: 56)
    }
}

struct OpportunityView: View {
    @ObservedObject var opportunity: Opportunity

    @Environment(\.managedObjectContext) private var ctx

    // Avoid mutating Core Data directly during view updates; perform on the MOC queue instead.
    private func safeBinding(
        _ keyPath: ReferenceWritableKeyPath<Opportunity, String?>,
        default defaultValue: String = ""
    ) -> Binding<String> {
        Binding(
            get: { opportunity[keyPath: keyPath] ?? defaultValue },
            set: { new in
                opportunity.managedObjectContext?.perform {
                    opportunity[keyPath: keyPath] = new
                }
            }
        )
    }

    // Track which editor is active so we can save when focus leaves a field
    @FocusState private var focusedField: EditableField?
    enum EditableField: Hashable { case company, title, location, salary, deadline, desc, notes }

    @State private var saveWorkItem: DispatchWorkItem?

    private func saveDebounced() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func saveNow() {
        // Prefer the object's own context; otherwise fall back to the injected one.
        let moc: NSManagedObjectContext = opportunity.managedObjectContext ?? ctx
        moc.perform {
            guard moc.hasChanges else { return }
            do {
                try moc.save()
            } catch {
                NSLog("Save failed: \(error.localizedDescription)")
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                StatusControl(status: Binding(
                    get: { opportunity.wrappedStatus },
                    set: { new in
                        opportunity.wrappedStatus = new
                        saveNow()
                    }
                ))
                .padding(.bottom)

                GroupBox(label: Text("Opportunity Details")) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            TextField("Company", text: safeBinding(\.company))
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .company)
                                .onSubmit { saveNow() }
                            TextField("Position", text: safeBinding(\.title))
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .title)
                                .onSubmit { saveNow() }
                        }

                        GridRow {
                            TextField("Location", text: safeBinding(\.location))
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .location)
                                .onSubmit { saveNow() }
                            TextField("Salary", text: safeBinding(\.salary))
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .salary)
                                .onSubmit { saveNow() }
                        }

                        GridRow {
                            TextField("Deadline", text: safeBinding(\.deadline))
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .deadline)
                                .onSubmit { saveNow() }
                        }

                        GridRow {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Description")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextEditor(text: safeBinding(\.desc))
                                    .textEditorStyle(.plain)
                                    .onChange(of: opportunity.desc ?? "") { _, _ in saveDebounced() }
                                    .frame(minHeight: 220) // give this room; feels closer to filling the page
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(.separator.opacity(0.6))
                                    )
                            }
                            .gridCellColumns(2)
                            .focused($focusedField, equals: .desc)
                        }

                        GridRow {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Notes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextEditor(text: safeBinding(\.notes))
                                    .textEditorStyle(.plain)
                                    .onChange(of: opportunity.notes ?? "") { _, _ in saveDebounced() }
                                    .frame(minHeight: 200)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(.separator.opacity(0.6))
                                    )
                            }
                            .gridCellColumns(2)
                            .focused($focusedField, equals: .notes)
                        }
                    }
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)
                }
            }
            .padding()
        }
        .navigationTitle(opportunity.title ?? "Opportunity")
        .onChange(of: focusedField) { _, _ in saveNow() }
        .onDisappear { saveNow() }
    }
}

// Allow binding to optional String Core Data attributes without crashes
extension Binding where Value == String? {
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? "" },
            set: { self.wrappedValue = $0 }
        )
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let newOpportunity = Opportunity(context: context)
    newOpportunity.company = "company"
    newOpportunity.title = "title"
    newOpportunity.location = "location"
    newOpportunity.salary = "salary"
    newOpportunity.deadline = "date"
    newOpportunity.desc = "description"
    newOpportunity.notes = "notes"

    return OpportunityView(opportunity: newOpportunity)
        .environment(\.managedObjectContext, context)
}

struct OpportunitiesDetail: View {
    @Binding var selectedOpportunity: Opportunity?
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var profileManager: ProfileManager

    // Pick a reasonable default when nothing is selected (newest by objectID as a proxy).
    // If none exist, create one.
    private func selectDefaultOpportunityIfNeeded() {
        // If a valid selection is already present for this context, do nothing.
        if let sel = selectedOpportunity, sel.managedObjectContext === context { return }

        let request = NSFetchRequest<Opportunity>(entityName: Opportunity.entity().name ?? "Opportunity")
        request.returnsObjectsAsFaults = false

        do {
            let all = try context.fetch(request)
            if let newest = all.max(by: { lhs, rhs in
                lhs.objectID.uriRepresentation().absoluteString < rhs.objectID.uriRepresentation().absoluteString
            }) {
                // Auto‑select newest existing item
                selectedOpportunity = newest
            } else {
                // No items exist — create one and select it
                if let created = try? Opportunity.create(in: context, title: "Opportunity") {
                    selectedOpportunity = created
                }
            }
        } catch {
            // If fetch fails, try to create a new one so the inspector/detail have content
            if let created = try? Opportunity.create(in: context, title: "Opportunity") {
                selectedOpportunity = created
            }
        }
    }

    var body: some View {
        Group {
            if let opp = selectedOpportunity, opp.managedObjectContext === context {
                OpportunityView(opportunity: opp)
                    .preference(
                        key: InspectorContentKey.self,
                        value: InspectorBox(view: AnyView(OpportunityInspector(selected: $selectedOpportunity)))
                    )
            } else {
                // No selection yet — immediately pick/create one without showing a placeholder UI.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { selectDefaultOpportunityIfNeeded() }
                    .preference(key: InspectorContentKey.self, value: InspectorBox(view: AnyView(EmptyView())))
            }
        }
        .onAppear { selectDefaultOpportunityIfNeeded() }
        .onChange(of: profileManager.profileSwitchToken) { _, _ in
            selectedOpportunity = nil
            selectDefaultOpportunityIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { note in
            guard let deleted = note.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> else { return }
            if let sel = selectedOpportunity, deleted.contains(where: { ($0 as? Opportunity)?.objectID == sel.objectID }) {
                // Selection was deleted -> clear and choose a replacement (or create one if none exist)
                selectedOpportunity = nil
                selectDefaultOpportunityIfNeeded()
            }
        }
        .onChange(of: selectedOpportunity) { _, newValue in
            // If selection becomes a deleted object or loses context, repair it
            if let sel = newValue {
                if sel.isDeleted || sel.managedObjectContext !== context {
                    selectedOpportunity = nil
                    selectDefaultOpportunityIfNeeded()
                }
            }
        }
    }
}

struct OpportunityInspectorList: View {
    enum SortKey { case title, deadline, status }

    @Binding var selected: Opportunity?

    // Local sort state (click the column headers to change)
    @State private var sortKey: SortKey = .title
    @State private var ascending: Bool = true

    // Fetch everything once; we'll sort in-memory so we can switch columns without rebuilding the fetch.
    @FetchRequest(
        entity: Opportunity.entity(),
        sortDescriptors: [],
        predicate: nil,
        animation: .default
    ) private var opps: FetchedResults<Opportunity>

    // Derived sorted list used by the table-like rows below
    private var sortedOpps: [Opportunity] {
        let items = Array(opps)
        return items.sorted { a, b in
            func key(_ o: Opportunity) -> (String, String, String) {
                let name = (o.title ?? "").localizedLowercase
                let date = (o.deadline ?? "")
                let statusNum = String(format: "%02d", Int(o.wrappedStatus.rawValue))
                return (name, date, statusNum)
            }
            let (an, ad, as_) = key(a)
            let (bn, bd, bs) = key(b)
            switch sortKey {
            case .title:
                return ascending ? (an.localizedStandardCompare(bn) == .orderedAscending)
                                  : (an.localizedStandardCompare(bn) == .orderedDescending)
            case .deadline:
                return ascending ? (ad < bd) : (ad > bd)
            case .status:
                return ascending ? (as_ < bs) : (as_ > bs)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Finder‑style column header (click to sort); no pill buttons
            HStack(spacing: 8) {
                header("Name", active: sortKey == .title, toggler: { toggle(.title) })
                    .frame(maxWidth: .infinity, alignment: .leading)
                header("Date", active: sortKey == .deadline, toggler: { toggle(.deadline) })
                    .frame(width: 50, alignment: .leading)
                header("Status", active: sortKey == .status, toggler: { toggle(.status) })
                    .frame(width: 60, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            // Height‑capped scrollable list laid out like a table (3 columns)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedOpps, id: \.objectID) { opp in
                        HStack(spacing: 8) {
                            Text((opp.title?.isEmpty == false ? opp.title! : "Untitled"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(opp.deadline?.isEmpty == false ? opp.deadline! : " ")
                                .frame(width: 50, alignment: .leading)
                            Text(opp.wrappedStatus.label)
                                .frame(width: 60, alignment: .leading)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { selected = opp }
                        .background(
                            (selected?.objectID == opp.objectID ? Color.accentColor.opacity(0.12) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        )
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    // MARK: - Helpers
    private func toggle(_ key: SortKey) {
        if sortKey == key { ascending.toggle() } else { sortKey = key; ascending = true }
    }

    @ViewBuilder
    private func header(_ title: String, active: Bool, toggler: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.footnote)
            if active { Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.footnote) }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(active ? Color.secondary.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .onTapGesture(perform: toggler)
        .accessibilityIdentifier("Column_\(title)")
    }
}

struct OpportunityInspector: View {
    @Binding var selected: Opportunity?

    @State private var showList = true
    @State private var showSummary = true
    @State private var showActions = true
    @State private var showCover = true
    @State private var sortKey: OpportunityInspectorList.SortKey = .title
    @State private var ascending = true

    @State private var isSummarizing = false
    @State private var summaryText: String = ""

    @State private var isDraftingCover = false
    @State private var coverLetterText: String = ""

    @MainActor
    private func summarizeCurrent() async {
        guard let opp = selected else { return }
        isSummarizing = true
        defer { isSummarizing = false }
        summaryText = await Intel.summarizeOpportunity(opp)
    }

    @MainActor
    private func draftCoverLetterCurrent() async {
        guard let opp = selected else { return }
        isDraftingCover = true
        defer { isDraftingCover = false }
        coverLetterText = await Intel.draftCoverLetter(for: opp)
        showSummary = true
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {

                // ACTIONS
                DisclosureGroup(isExpanded: $showActions) {
                    HStack {
                        Button {
                            Task { await draftCoverLetterCurrent() }
                        } label: {
                            if isDraftingCover {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "square.and.pencil")
                            }
                        }
                        .help("Draft Cover Letter")
                        .buttonStyle(.bordered)
                        .disabled(selected == nil || isDraftingCover)

                        Button {
                            InterApp.Pages.open(text: coverLetterText)
                        } label: {
                            Image(systemName: "doc.text")
                        }
                        .help("Open Cover Letter in Pages")
                        .buttonStyle(.bordered)
                        .disabled(coverLetterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.bottom, 6)
                } label: {
                    Label("Actions", systemImage: "bolt.circle")
                }
                
                Divider().padding(.horizontal, 8)

                // SUMMARY
                DisclosureGroup(isExpanded: $showSummary) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button {
                                Task { await summarizeCurrent() }
                            } label: {
                                if isSummarizing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Summarize", systemImage: "sparkles")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(selected == nil || isSummarizing)
                            Spacer()
                        }

                        if !summaryText.isEmpty {
                            Text(.init(summaryText))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .transition(.opacity)
                        } else {
                            Text("No summary yet").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                } label: {
                    Label("Summary", systemImage: "info.circle")
                }

                Divider().padding(.horizontal, 8)

                // COVER LETTER
                DisclosureGroup(isExpanded: $showCover) {
                    VStack(alignment: .leading, spacing: 8) {
                        if coverLetterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("No cover letter yet").foregroundStyle(.secondary)
                        } else {
                            Text(coverLetterText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                } label: {
                    Label("Cover Letter", systemImage: "doc.text")
                }

                Divider().padding(.horizontal, 8)
                
                // LIST SECTION
                DisclosureGroup(isExpanded: $showList) {
                    OpportunityInspectorList(selected: $selected)
                } label: {
                    HStack {
                        Label("Opportunities", systemImage: "list.bullet")
                        Spacer()
                        // Column labels are handled inside the list now
                    }
                }
            }
            .padding(8)
        }
        .frame(minWidth: 260)
        .toolbar { InspectorToggleToolbarItems() }
    }
}
