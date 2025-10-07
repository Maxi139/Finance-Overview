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
                    // CSV-Export als ShareLink (URL zur temporären CSV-Datei)
                    ShareLink(item: store.exportCSV(),
                              preview: SharePreview("Buchungen.csv")) {
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
                    .environmentObject(store) // gleicher Store -> sofortige Aktualisierung
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
        
        // Art
        if !filters.kinds.isEmpty {
            txs = txs.filter { filters.kinds.contains($0.kind) }
        }
        // Konto(s)
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
        // Zeitraum
        if let from = filters.dateFrom {
            txs = txs.filter { $0.date >= Calendar.current.startOfDay(for: from) }
        }
        if let to = filters.dateTo {
            // bis einschließlich Endtag
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to))!
            txs = txs.filter { $0.date < end }
        }
        // Betrag (absolut)
        if let minA = filters.minAmount {
            txs = txs.filter { abs($0.amount) >= minA }
        }
        if let maxA = filters.maxAmount {
            txs = txs.filter { abs($0.amount) <= maxA }
        }
        // Notiz
        if filters.onlyWithNotes {
            txs = txs.filter { !($0.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        // Suche
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            txs = txs.filter { t in
                let hay = "\(t.name) \(t.note ?? "")".localizedCaseInsensitiveContains(q)
                if hay { return true }
                // optional: Konto-Namen durchsuchen
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
            let from = store.accounts.first(where: {$0.id == transaction.fromAccountID})?.name ?? "—"
            let to   = store.accounts.first(where: {$0.id == transaction.toAccountID})?.name ?? "—"
            return "\(from) → \(to)"
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.name).font(.body.weight(.medium))
                Text(accountNameText).font(.caption).foregroundStyle(.secondary)
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
    @State private var showFileImporter = false
    @State private var lastImportInfo: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Zielkonto") {
                    accountPicker(selection: $selectedAccount)
                }
                
                Section("CSV-Datei") {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("CSV auswählen", systemImage: "doc.badge.plus")
                    }
                    .disabled(selectedAccount == nil)
                    
                    if let info = lastImportInfo {
                        Text(info)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section {
                    Text("Format pro Zeile: Name,Datum,Betrag")
                    Text("Komma-getrennt (CSV), Felder können in Anführungszeichen stehen.")
                    Text("Datum: dd.MM.yy (z. B. 15.09.25)")
                    Text("Betrag: negativ für Ausgaben, positiv für Einnahmen")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("CSV importieren")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { isPresented = false }
                }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [
                            .commaSeparatedText, .text, .plainText, .utf8PlainText, .data
                          ],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first, let account = selectedAccount else { return }
                    let imported = store.importCSV(from: url, to: account)
                    lastImportInfo = "\(imported) Buchungen importiert."
                case .failure(let error):
                    lastImportInfo = "Import fehlgeschlagen: \(error.localizedDescription)"
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // Gruppierter Konto-Picker (wie im Add-Flow)
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
                            .tag(Optional(acc))
                        }
                    }
                }
            }
        }
        .pickerStyle(.navigationLink)
    }
}

// MARK: - Filter

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

private struct TransactionFilterView: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    
    @Binding var filters: TransactionFilterOptions
    
    // Strings für Betrag (optional)
    @State private var minAmountText: String = ""
    @State private var maxAmountText: String = ""
    
    var body: some View {
        Form {
            Section("Art") {
                ForEach(TransactionKind.allCases) { kind in
                    Toggle(kind.rawValue, isOn: Binding(
                        get: { filters.kinds.contains(kind) },
                        set: { new in
                            if new { filters.kinds.insert(kind) } else { filters.kinds.remove(kind) }
                        }
                    ))
                }
            }
            Section("Konten") {
                if store.accounts.isEmpty {
                    Text("Keine Konten vorhanden").foregroundStyle(.secondary)
                } else {
                    ForEach(store.accounts) { acc in
                        HStack {
                            Text(acc.name)
                            Spacer()
                            if filters.accountIDs.contains(acc.id) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if filters.accountIDs.contains(acc.id) {
                                filters.accountIDs.remove(acc.id)
                            } else {
                                filters.accountIDs.insert(acc.id)
                            }
                        }
                    }
                }
            }
            Section("Zeitraum") {
                Toggle("Von", isOn: Binding(
                    get: { filters.dateFrom != nil },
                    set: { new in filters.dateFrom = new ? Date() : nil }
                ))
                if let from = filters.dateFrom {
                    DatePicker("Start", selection: Binding(get: { from }, set: { filters.dateFrom = $0 }), displayedComponents: .date)
                }
                Toggle("Bis", isOn: Binding(
                    get: { filters.dateTo != nil },
                    set: { new in filters.dateTo = new ? Date() : nil }
                ))
                if let to = filters.dateTo {
                    DatePicker("Ende", selection: Binding(get: { to }, set: { filters.dateTo = $0 }), displayedComponents: .date)
                }
            }
            Section("Betrag (absolut)") {
                HStack {
                    Text("Minimum")
                    Spacer()
                    TextField("z. B. 10", text: $minAmountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
                HStack {
                    Text("Maximum")
                    Spacer()
                    TextField("z. B. 500", text: $maxAmountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
            }
            Section("Weitere") {
                Toggle("Nur mit Notiz", isOn: $filters.onlyWithNotes)
            }
        }
        .navigationTitle("Filter")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Zurücksetzen") {
                    filters.reset()
                    minAmountText = ""
                    maxAmountText = ""
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") {
                    applyAmounts()
                    dismiss()
                }
            }
        }
        .onAppear {
            if let minA = filters.minAmount { minAmountText = NumberFormatter.localizedString(from: NSNumber(value: minA), number: .decimal) }
            if let maxA = filters.maxAmount { maxAmountText = NumberFormatter.localizedString(from: NSNumber(value: maxA), number: .decimal) }
        }
    }
    
    private func applyAmounts() {
        func parse(_ s: String) -> Double? {
            var s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            s = s.replacingOccurrences(of: "€", with: "")
                 .replacingOccurrences(of: " ", with: "")
                 .replacingOccurrences(of: ".", with: "")
                 .replacingOccurrences(of: ",", with: ".")
            return Double(s)
        }
        filters.minAmount = parse(minAmountText)
        filters.maxAmount = parse(maxAmountText)
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
    
    init(transaction: FinanceTransaction) {
        self.transaction = transaction
        _name = State(initialValue: transaction.name)
        _amount = State(initialValue: abs(transaction.amount))
        _date = State(initialValue: transaction.date)
        _note = State(initialValue: transaction.note ?? "")
        _selectedAccount = State(initialValue: nil)
        _fromAccount = State(initialValue: nil)
        _toAccount = State(initialValue: nil)
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
                // Auflösen der Konten erst hier (Store verfügbar)
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
        case .income:
            updated.amount = abs(amount)
            updated.accountID = selectedAccount?.id
            updated.fromAccountID = nil
            updated.toAccountID = nil
        case .transfer:
            updated.amount = abs(amount)
            updated.accountID = nil
            updated.fromAccountID = fromAccount?.id
            updated.toAccountID = toAccount?.id
        }
        
        store.updateTransaction(updated)
        dismiss()
    }
    
    // Gemeinsame Konto-Optionen (gruppiert)
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
