import SwiftUI
import UniformTypeIdentifiers

struct TransactionsView: View {
    @EnvironmentObject var store: FinanceStore
    @State private var showAddFlow = false
    @State private var showImportSheet = false
    
    // Suche & Filter
    @State private var searchText: String = ""
    @State private var isSearchPresented: Bool = false
    @State private var showFilterSheet: Bool = false
    @State private var filters = TransactionFilterOptions()
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedDays, id: \.self) { day in
                    daySection(for: day)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Buchungen")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isSearchPresented = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    Button {
                        showFilterSheet = true
                    } label: {
                        Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    // Export: use store.exportAll() which returns a URL
                    ShareLink(item: store.exportAll(),
                              preview: SharePreview("FinanceOverview-Backup.json")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    
                    Button {
                        showImportSheet = true
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                    }
                    Button {
                        showAddFlow = true
                    } label: { Image(systemName: "plus") }
                }
            }
            .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buchungen durchsuchen")
            .sheet(isPresented: $showAddFlow) {
                AddTransactionFlowView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showImportSheet) {
                ImportCSVView(isPresented: $showImportSheet)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showFilterSheet) {
                NavigationStack {
                    TransactionFilterView(filters: $filters)
                        .environmentObject(store)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
    
    private var filteredTransactions: [FinanceTransaction] {
        var txs = store.transactions
        
        if !filters.kinds.isEmpty {
            txs = txs.filter { filters.kinds.contains($0.kind) }
        }
        if !filters.accountIDs.isEmpty {
            txs = txs.filter { t in
                switch t.kind {
                case .income, .expense:
                    if let id = t.accountID { return filters.accountIDs.contains(id) }
                    return false
                case .transfer:
                    return (t.fromAccountID.map { filters.accountIDs.contains($0) } ?? false)
                        || (t.toAccountID.map { filters.accountIDs.contains($0) } ?? false)
                }
            }
        }
        if let from = filters.dateFrom {
            txs = txs.filter { $0.date >= Calendar.current.startOfDay(for: from) }
        }
        if let to = filters.dateTo {
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to))!
            txs = txs.filter { $0.date < end }
        }
        if let minA = filters.minAmount {
            txs = txs.filter { abs($0.amount) >= minA }
        }
        if let maxA = filters.maxAmount {
            txs = txs.filter { abs($0.amount) <= maxA }
        }
        if filters.onlyWithNotes {
            txs = txs.filter { !($0.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            txs = txs.filter { t in
                let hay = "\(t.name) \(t.note ?? "")".localizedCaseInsensitiveContains(q)
                if hay { return true }
                switch t.kind {
                case .income, .expense:
                    if let id = t.accountID,
                       let name = store.accounts.first(where: { $0.id == id })?.name,
                       name.localizedCaseInsensitiveContains(q) { return true }
                case .transfer:
                    let from = store.accounts.first(where: { $0.id == t.fromAccountID })?.name ?? ""
                    let to = store.accounts.first(where: { $0.id == t.toAccountID })?.name ?? ""
                    if from.localizedCaseInsensitiveContains(q) || to.localizedCaseInsensitiveContains(q) { return true }
                }
                // Kategorie-Name durchsuchen
                if let cat = store.category(by: t.categoryID),
                   cat.name.localizedCaseInsensitiveContains(q) { return true }
                return false
            }
        }
        return txs
    }
    
    private var groupedByDay: [Date: [FinanceTransaction]] {
        Dictionary(grouping: filteredTransactions) { t in
            Calendar.current.startOfDay(for: t.date)
        }
    }
    
    private var sortedDays: [Date] {
        groupedByDay.keys.sorted(by: >)
    }
    
    @ViewBuilder
    private func daySection(for day: Date) -> some View {
        let txs: [FinanceTransaction] = groupedByDay[day] ?? []
        Section(dateFormatterShort.string(from: day)) {
            ForEach(txs) { t in
                NavigationLink {
                    TransactionDetailView(transaction: t)
                } label: {
                    TransactionRow(transaction: t)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        store.removeTransaction(t)
                    } label: { Label("Löschen", systemImage: "trash") }
                }
                .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            }
        }
    }
}

struct TransactionRow: View {
    @EnvironmentObject var store: FinanceStore
    let transaction: FinanceTransaction
    
    var amountColor: Color {
        switch transaction.kind {
        case .income: return .green
        case .expense: return .red
        case .transfer: return .blue
        }
    }
    var accountNameText: String {
        switch transaction.kind {
        case .income, .expense:
            if let id = transaction.accountID,
               let acc = store.accounts.first(where: {$0.id == id}) {
                return acc.name
            }
            return "-"
        case .transfer:
            let from = store.accounts.first(where: {$0.id == transaction.fromAccountID })?.name ?? "—"
            let to   = store.accounts.first(where: {$0.id == transaction.toAccountID })?.name ?? "—"
            return "\(from) → \(to)"
        }
    }
    var categoryTag: some View {
        Group {
            if let cat = store.category(by: transaction.categoryID) {
                HStack(spacing: 6) {
                    Circle().fill(cat.swiftUIColor).frame(width: 8, height: 8)
                    Text(cat.name).font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(cat.swiftUIColor.opacity(0.15), in: Capsule())
            }
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.name).font(.body.weight(.medium))
                HStack(spacing: 8) {
                    Text(accountNameText).font(.caption).foregroundStyle(.secondary)
                    categoryTag
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency(transaction.amount))
                    .foregroundStyle(amountColor)
                    .font(.callout.weight(.semibold))
                Text(dateFormatterShort.string(from: transaction.date))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Detailansicht für eine Buchung

struct TransactionDetailView: View {
    @EnvironmentObject var store: FinanceStore
    let transaction: FinanceTransaction
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    
    private var accountText: String {
        switch transaction.kind {
        case .income, .expense:
            if let id = transaction.accountID,
               let acc = store.accounts.first(where: { $0.id == id }) {
                return acc.name
            }
            return "-"
        case .transfer:
            let from = store.accounts.first(where: { $0.id == transaction.fromAccountID })?.name ?? "—"
            let to   = store.accounts.first(where: { $0.id == transaction.toAccountID })?.name ?? "—"
            return "\(from) → \(to)"
        }
    }
    
    var body: some View {
        Form {
            Section("Details") {
                HStack { Text("Name"); Spacer(); Text(transaction.name).foregroundStyle(.secondary) }
                HStack { Text("Art"); Spacer(); Text(transaction.kind.rawValue).foregroundStyle(.secondary) }
                HStack { Text("Betrag"); Spacer(); Text(formatCurrency(transaction.amount)).foregroundStyle(.secondary) }
                HStack { Text("Datum"); Spacer(); Text(dateFormatterShort.string(from: transaction.date)).foregroundStyle(.secondary) }
                HStack { Text(transaction.kind == .transfer ? "Von/Nach" : "Konto"); Spacer(); Text(accountText).foregroundStyle(.secondary) }
                if let cat = store.category(by: transaction.categoryID) {
                    HStack {
                        Text("Kategorie")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(cat.swiftUIColor).frame(width: 10, height: 10)
                            Text(cat.name)
                        }
                        .foregroundStyle(cat.swiftUIColor)
                    }
                }
            }
            if let note = transaction.note, !note.isEmpty {
                Section("Notiz") {
                    Text(note)
                }
            }
        }
        .navigationTitle("Buchung")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Bearbeiten") { showEdit = true }
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog("Buchung löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                store.removeTransaction(transaction)
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .sheet(isPresented: $showEdit) {
            EditTransactionView(transaction: transaction)
                .environmentObject(store)
        }
    }
}

// MARK: - CSV-Import Sheet

private struct ImportCSVView: View {
    @EnvironmentObject var store: FinanceStore
    @Binding var isPresented: Bool
    
    @State private var selectedAccount: Account?
    @State private var pickedURL: URL?
    @State private var importSummary: String?
    @State private var showDocumentPicker = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Konto") {
                    accountPicker(selection: $selectedAccount)
                }
                Section("CSV-Datei") {
                    if let url = pickedURL {
                        Text(url.lastPathComponent).font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text("Keine Datei gewählt").foregroundStyle(.secondary)
                    }
                    Button {
                        showDocumentPicker = true
                    } label: {
                        Label("Datei wählen", systemImage: "doc")
                    }
                }
                if let summary = importSummary {
                    Section("Ergebnis") {
                        Text(summary)
                    }
                }
            }
            .navigationTitle("CSV importieren")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importieren") { runImport() }
                        .disabled(selectedAccount == nil || pickedURL == nil)
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker(url: $pickedURL)
            }
        }
    }
    
    private func runImport() {
        guard let acc = selectedAccount, let url = pickedURL else { return }
        let count = store.importCSV(from: url, to: acc)
        importSummary = count > 0 ? "\(count) Buchungen importiert." : "Keine Buchungen importiert."
    }
    
    private func accountPicker(selection: Binding<Account?>) -> some View {
        Picker("Konto", selection: selection) {
            ForEach(AccountCategory.allCases) { cat in
                let accountsInCat = store.accounts
                    .filter { $0.category == cat }
                    .sorted { lhs, rhs in
                        if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary && !rhs.isPrimary }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                if !accountsInCat.isEmpty {
                    Section(cat.rawValue) {
                        ForEach(accountsInCat) { acc in
                            Text(acc.name).tag(Optional(acc) as Account?)
                        }
                    }
                }
            }
        }
        .pickerStyle(.navigationLink)
    }
}

private struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var url: URL?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.url = urls.first
        }
    }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.commaSeparatedText, UTType.text, UTType.data], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

// MARK: - Filter Optionen

private struct TransactionFilterOptions {
    var kinds: Set<TransactionKind> = []
    var accountIDs: Set<UUID> = []
    var dateFrom: Date?
    var dateTo: Date?
    var minAmount: Double?
    var maxAmount: Double?
    var onlyWithNotes: Bool = false
    
    mutating func reset() {
        kinds.removeAll()
        accountIDs.removeAll()
        dateFrom = nil
        dateTo = nil
        minAmount = nil
        maxAmount = nil
        onlyWithNotes = false
    }
    var isActive: Bool {
        !kinds.isEmpty || !accountIDs.isEmpty || dateFrom != nil || dateTo != nil || minAmount != nil || maxAmount != nil || onlyWithNotes
    }
}

// MARK: - Filter View

private struct TransactionFilterView: View {
    @EnvironmentObject var store: FinanceStore
    @Binding var filters: TransactionFilterOptions
    
    var body: some View {
        Form {
            Section("Art") {
                ForEach(TransactionKind.allCases) { k in
                    Toggle(k.rawValue, isOn: Binding(
                        get: { filters.kinds.contains(k) },
                        set: { newVal in
                            if newVal { filters.kinds.insert(k) } else { filters.kinds.remove(k) }
                        }
                    ))
                }
            }
            Section("Konten") {
                ForEach(AccountCategory.allCases) { cat in
                    let accountsInCat = store.accounts
                        .filter { $0.category == cat }
                        .sorted { lhs, rhs in
                            if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary && !rhs.isPrimary }
                            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                        }
                    if !accountsInCat.isEmpty {
                        Section(cat.rawValue) {
                            ForEach(accountsInCat) { acc in
                                Toggle(isOn: Binding(
                                    get: { filters.accountIDs.contains(acc.id) },
                                    set: { newVal in
                                        if newVal { filters.accountIDs.insert(acc.id) } else { filters.accountIDs.remove(acc.id) }
                                    }
                                )) {
                                    HStack {
                                        if acc.isPrimary { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                                        Text(acc.name)
                                        if acc.isSubaccount {
                                            Text("Unterkonto")
                                                .font(.caption2)
                                                .padding(4)
                                                .background(.secondary.opacity(0.15), in: Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Section("Zeitraum") {
                DatePicker("Von", selection: Binding(
                    get: { filters.dateFrom ?? Date() },
                    set: { filters.dateFrom = $0 }
                ), displayedComponents: .date)
                .environment(\.locale, Locale(identifier: "de_DE"))
                .opacity(filters.dateFrom == nil ? 0.6 : 1)
                Toggle("Von aktiv", isOn: Binding(
                    get: { filters.dateFrom != nil },
                    set: { isOn in filters.dateFrom = isOn ? Calendar.current.startOfDay(for: Date()) : nil }
                ))
                
                DatePicker("Bis", selection: Binding(
                    get: { filters.dateTo ?? Date() },
                    set: { filters.dateTo = $0 }
                ), displayedComponents: .date)
                .environment(\.locale, Locale(identifier: "de_DE"))
                .opacity(filters.dateTo == nil ? 0.6 : 1)
                Toggle("Bis aktiv", isOn: Binding(
                    get: { filters.dateTo != nil },
                    set: { isOn in filters.dateTo = isOn ? Calendar.current.startOfDay(for: Date()) : nil }
                ))
            }
            Section("Betrag") {
                HStack {
                    Text("Min.")
                    Spacer()
                    TextField("0", value: Binding(
                        get: { filters.minAmount ?? 0 },
                        set: { filters.minAmount = $0 > 0 ? $0 : nil }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                }
                HStack {
                    Text("Max.")
                    Spacer()
                    TextField("0", value: Binding(
                        get: { filters.maxAmount ?? 0 },
                        set: { filters.maxAmount = $0 > 0 ? $0 : nil }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                }
            }
            Section {
                Toggle("Nur mit Notizen", isOn: $filters.onlyWithNotes)
            }
            Section {
                Button("Zurücksetzen", role: .destructive) {
                    filters.reset()
                }
            }
        }
        .navigationTitle("Filter")
    }
}

// MARK: - EditTransactionView

struct EditTransactionView: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    
    let transaction: FinanceTransaction
    
    @State private var name: String
    @State private var amount: Double
    @State private var date: Date
    @State private var note: String
    
    @State private var selectedAccount: Account?
    @State private var fromAccount: Account?
    @State private var toAccount: Account?
    
    @State private var selectedCategoryID: UUID?
    @State private var showCreateCategory = false
    
    // Bestätigungsdialog für Bulk-Anwendung
    @State private var showApplyToPastDialog: Bool = false
    @State private var pendingApplyCategoryID: UUID?
    @State private var pendingName: String = ""
    @State private var pendingDate: Date = Date()
    @State private var pendingUpdatedTx: FinanceTransaction?
    @State private var pendingCount: Int = 0
    
    init(transaction: FinanceTransaction) {
        self.transaction = transaction
        _name = State(initialValue: transaction.name)
        _amount = State(initialValue: abs(transaction.amount))
        _date = State(initialValue: transaction.date)
        _note = State(initialValue: transaction.note ?? "")
        _selectedAccount = State(initialValue: nil)
        _fromAccount = State(initialValue: nil)
        _toAccount = State(initialValue: nil)
        _selectedCategoryID = State(initialValue: transaction.categoryID)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Allgemein") {
                    HStack {
                        Text("Art")
                        Spacer()
                        Text(transaction.kind.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    TextField("Name", text: $name)
                }
                
                if transaction.kind == .transfer {
                    Section("Konten") {
                        Picker("Von", selection: Binding(
                            get: { fromAccount },
                            set: { fromAccount = $0 }
                        )) {
                            accountOptions()
                        }
                        .pickerStyle(.navigationLink)
                        
                        Picker("Nach", selection: Binding(
                            get: { toAccount },
                            set: { toAccount = $0 }
                        )) {
                            accountOptions()
                        }
                        .pickerStyle(.navigationLink)
                    }
                } else {
                    Section("Konto") {
                        Picker("Konto", selection: Binding(
                            get: { selectedAccount },
                            set: { selectedAccount = $0 }
                        )) {
                            accountOptions()
                        }
                        .pickerStyle(.navigationLink)
                    }
                    Section("Kategorie") {
                        CategoryPickerInline
                        Button {
                            showCreateCategory = true
                        } label: {
                            Label("Neue Kategorie erstellen", systemImage: "tag.badge.plus")
                        }
                    }
                }
                
                Section("Betrag & Datum") {
                    HStack {
                        Text("Betrag")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                }
                
                Section("Notiz") {
                    TextField("optional", text: $note, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle("Buchung bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                switch transaction.kind {
                case .income, .expense:
                    if let id = transaction.accountID {
                        selectedAccount = store.accounts.first(where: { $0.id == id })
                    }
                case .transfer:
                    if let fid = transaction.fromAccountID {
                        fromAccount = store.accounts.first(where: { $0.id == fid })
                    }
                    if let tid = transaction.toAccountID {
                        toAccount = store.accounts.first(where: { $0.id == tid })
                    }
                }
            }
            .sheet(isPresented: $showCreateCategory) {
                NavigationStack {
                    CreateOrEditCategoryView { new in
                        selectedCategoryID = new.id
                    }
                    .environmentObject(store)
                }
                .presentationDetents([.medium, .large])
            }
        }
        // ConfirmationDialog für Bulk-Anwendung
        .confirmationDialog(
            "Auch vergangene Buchungen kategorisieren?",
            isPresented: $showApplyToPastDialog,
            titleVisibility: .visible
        ) {
            Button("Ja, \(pendingCount) Buchungen aktualisieren", role: .none) {
                if let catID = pendingApplyCategoryID {
                    store.applyCategory(catID, toPastUncategorizedTransactionsMatching: pendingName, before: pendingDate)
                }
                if let updated = pendingUpdatedTx {
                    store.updateTransaction(updated)
                }
                dismiss()
            }
            Button("Nur diese Buchung", role: .cancel) {
                if let updated = pendingUpdatedTx {
                    store.updateTransaction(updated)
                }
                dismiss()
            }
        } message: {
            Text("Es gibt \(pendingCount) vergangene Buchungen ohne Kategorie mit dem gleichen Namen. Sollen diese ebenfalls die Kategorie erhalten?")
        }
    }
    
    private var CategoryPickerInline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                CategoryPickerView(selectedID: $selectedCategoryID)
                    .environmentObject(store)
                if selectedCategoryID != nil {
                    Button {
                        selectedCategoryID = nil
                    } label: {
                        Label("Entfernen", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, amount > 0 else { return false }
        switch transaction.kind {
        case .income, .expense:
            return selectedAccount != nil
        case .transfer:
            return fromAccount != nil && toAccount != nil && fromAccount?.id != toAccount?.id
        }
    }
    
    private func save() {
        var updated = transaction
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.date = date
        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        
        switch transaction.kind {
        case .expense:
            updated.amount = -abs(amount)
            updated.accountID = selectedAccount?.id
            updated.fromAccountID = nil
            updated.toAccountID = nil
            updated.categoryID = selectedCategoryID
        case .income:
            updated.amount = abs(amount)
            updated.accountID = selectedAccount?.id
            updated.fromAccountID = nil
            updated.toAccountID = nil
            updated.categoryID = selectedCategoryID
        case .transfer:
            updated.amount = abs(amount)
            updated.accountID = nil
            updated.fromAccountID = fromAccount?.id
            updated.toAccountID = toAccount?.id
            updated.categoryID = nil
        }
        
        // Nur fragen, wenn income/expense und Kategorie gesetzt ist und (neu gesetzt oder geändert)
        if (updated.kind == .income || updated.kind == .expense),
           let catID = updated.categoryID {
            let wasCategory = transaction.categoryID
            let changedOrSet = wasCategory == nil || wasCategory != catID
            if changedOrSet {
                let count = store.countPastUncategorizedTransactions(matchingName: updated.name, before: updated.date)
                if count > 0 {
                    pendingApplyCategoryID = catID
                    pendingName = updated.name
                    pendingDate = updated.date
                    pendingUpdatedTx = updated
                    pendingCount = count
                    showApplyToPastDialog = true
                    return
                }
            }
        }
        
        // Kein Dialog nötig -> direkt speichern
        store.updateTransaction(updated)
        dismiss()
    }
    
    @ViewBuilder
    private func accountOptions() -> some View {
        ForEach(AccountCategory.allCases) { cat in
            let accountsInCat = store.accounts
                .filter { $0.category == cat }
                .sorted { lhs, rhs in
                    if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary && !rhs.isPrimary }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            if !accountsInCat.isEmpty {
                Section(cat.rawValue) {
                    ForEach(accountsInCat) { acc in
                        HStack {
                            if acc.isPrimary { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                            Text(acc.name)
                            if acc.isSubaccount {
                                Text("Unterkonto")
                                    .font(.caption2)
                                    .padding(4)
                                    .background(.secondary.opacity(0.15), in: Capsule())
                            }
                        }
                        .tag(Optional(acc) as Account?)
                    }
                }
            }
        }
    }
}

// MARK: - Shared Category UI used here (local copies so this file compiles)

struct CategoryPickerView: View {
    @EnvironmentObject var store: FinanceStore
    @Binding var selectedID: UUID?
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 104), spacing: 8)]
    }
    
    var body: some View {
        let cats = store.categories
        if cats.isEmpty {
            Text("Keine Kategorien vorhanden").foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(cats) { cat in
                    CategoryChip(cat: cat, isSelected: selectedID == cat.id) {
                        selectedID = (selectedID == cat.id) ? nil : cat.id
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Kategorien")
        }
    }
}

private struct CategoryChip: View {
    let cat: TransactionCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(cat.swiftUIColor)
                    .frame(width: 10, height: 10)
                Text(cat.name)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? cat.swiftUIColor.opacity(0.15) : Color.secondary.opacity(0.12))
            .foregroundStyle(isSelected ? cat.swiftUIColor : .primary)
            .clipShape(Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// Entfernt: WrapTagsView und SizePreferenceKey (Root-Cause)
struct CreateOrEditCategoryView: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    
    var onCreate: (TransactionCategory) -> Void
    
    @State private var name: String = ""
    @State private var color: Color = .blue
    
    var body: some View {
        Form {
            Section("Kategorie") {
                TextField("Name", text: $name)
                ColorPicker("Farbe", selection: $color, supportsOpacity: false)
            }
        }
        .navigationTitle("Kategorie erstellen")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Hinzufügen") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cat = store.addCategory(name: trimmed, color: color)
                    onCreate(cat)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
