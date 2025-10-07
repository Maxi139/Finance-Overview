import SwiftUI

struct AccountsView: View {
    @EnvironmentObject var store: FinanceStore
    @State private var showAddAccount = false
    @State private var showAddInvestment = false
    @State private var showAddDebt = false
    
    // Datenverwaltung (ohne Tutorial)
    @State private var confirmReset = false
    
    // Konto bearbeiten
    @State private var editingAccount: Account?
    // Schuld bearbeiten
    @State private var editingDebt: Debt?
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(AccountCategory.allCases, id: \.id) { cat in
                    Section(cat.rawValue) {
                        ForEach(topLevelAccounts(for: cat), id: \.id) { acc in
                            accountCell(acc)
                            // Unterkonten
                            ForEach(subaccounts(of: acc), id: \.id) { sub in
                                accountCell(sub, isSub: true)
                            }
                        }
                    }
                }
                
                if !store.investments.isEmpty {
                    Section("Geldanlagen") {
                        ForEach(store.investments, id: \.id) { inv in
                            HStack {
                                Text(inv.name)
                                Spacer()
                                Text(formatCurrency(inv.value))
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.removeInvestment(inv)
                                } label: { Label("Entfernen", systemImage: "trash") }
                            }
                        }
                    }
                }
                
                // Schulden
                Section {
                    if openDebts.isEmpty {
                        Button {
                            showAddDebt = true
                        } label: {
                            Label("Neue Schuld hinzufügen", systemImage: "text.badge.plus")
                        }
                    } else {
                        ForEach(openDebtsSorted, id: \.id) { debt in
                            debtRow(debt)
                        }
                        Button {
                            showAddDebt = true
                        } label: {
                            Label("Neue Schuld", systemImage: "text.badge.plus")
                        }
                    }
                } header: {
                    Text("Schulden")
                } footer: {
                    if !openDebts.isEmpty {
                        HStack {
                            Text("Summe ich schulde:")
                            Spacer()
                            Text(formatCurrency(sumIOwe)).foregroundStyle(.red)
                        }
                        HStack {
                            Text("Summe mir wird geschuldet:")
                            Spacer()
                            Text(formatCurrency(sumOwedToMe)).foregroundStyle(.green)
                        }
                    }
                }
            }
            .navigationTitle("Konten")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Datenverwaltung (ohne Tutorial)
                    Menu {
                        Button {
                            store.loadDemoData()
                        } label: {
                            Label("Demo-Daten laden", systemImage: "tray.and.arrow.down")
                        }
                        Button(role: .destructive) {
                            confirmReset = true
                        } label: {
                            Label("Alle Daten löschen", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    
                    Button {
                        showAddInvestment = true
                    } label: { Image(systemName: "banknote") }
                    
                    Button {
                        showAddAccount = true
                    } label: { Image(systemName: "plus") }
                }
            }
            // Konto hinzufügen
            .sheet(isPresented: $showAddAccount) {
                NavigationStack {
                    AccountFormView(original: nil)
                        .environmentObject(store)
                }
                .presentationDetents([.large])
            }
            // Geldanlage hinzufügen
            .sheet(isPresented: $showAddInvestment) {
                NavigationStack {
                    InvestmentFormView()
                        .environmentObject(store)
                }
                .presentationDetents([.medium, .large])
            }
            // Konto bearbeiten
            .sheet(item: $editingAccount) { acc in
                NavigationStack {
                    AccountFormView(original: acc)
                        .environmentObject(store)
                }
                .presentationDetents([.large])
            }
            // Schuld hinzufügen
            .sheet(isPresented: $showAddDebt) {
                NavigationStack {
                    DebtFormView(original: nil)
                        .environmentObject(store)
                }
                .presentationDetents([.medium, .large])
            }
            // Schuld bearbeiten
            .sheet(item: $editingDebt) { d in
                NavigationStack {
                    DebtFormView(original: d)
                        .environmentObject(store)
                }
                .presentationDetents([.medium, .large])
            }
            .alert("Wirklich alle Daten löschen?", isPresented: $confirmReset) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) {
                    store.resetToEmpty()
                }
            } message: {
                Text("Diese Aktion kann nicht rückgängig gemacht werden.")
            }
        }
    }
    
    private var openDebts: [Debt] {
        store.debts.filter { !$0.isSettled }
    }
    private var openDebtsSorted: [Debt] {
        openDebts.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?):
                if l != r { return l < r }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case (nil, nil):
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case (nil, _?): return false
            case (_?, nil): return true
            }
        }
    }
    private var sumIOwe: Double {
        openDebts.filter { $0.direction == .iOwe }.map(\.amount).reduce(0, +)
    }
    private var sumOwedToMe: Double {
        openDebts.filter { $0.direction == .owedToMe }.map(\.amount).reduce(0, +)
    }
    
    private func topLevelAccounts(for category: AccountCategory) -> [Account] {
        store.accounts.filter { $0.category == category && $0.parentAccountID == nil }
    }
    
    private func subaccounts(of account: Account) -> [Account] {
        store.accounts.filter { $0.parentAccountID == account.id }
    }
    
    private func accountCell(_ acc: Account, isSub: Bool = false) -> some View {
        NavigationLink {
            AccountDetailView(account: acc)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if acc.isPrimary { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                        Text(acc.name)
                    }
                    HStack(spacing: 8) {
                        if isSub { Text("Unterkonto").font(.caption2).padding(4).background(.secondary.opacity(0.15), in: Capsule()) }
                        if acc.isAvailable { Text("verfügbar").font(.caption2).padding(4).background(.green.opacity(0.15), in: Capsule()) }
                    }
                }
                Spacer()
                Text(formatCurrency(store.balance(for: acc))).font(.callout.weight(.semibold))
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                store.removeAccount(acc)
            } label: { Label("Löschen", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button {
                store.setPrimary(acc)
            } label: { Label("Hauptkonto", systemImage: "star") }
            Button {
                // Unterkonto erstellen
                let sub = Account(name: "\(acc.name) – Unterkonto", category: acc.category, initialBalance: 0, isAvailable: acc.isAvailable, parentAccountID: acc.id)
                store.addAccount(sub)
            } label: { Label("Unterkonto", systemImage: "arrow.branch") }
        }
        .contextMenu {
            Button("Bearbeiten") { editingAccount = acc }
            Button(acc.isAvailable ? "Als nicht verfügbar markieren" : "Als verfügbar markieren") {
                var copy = acc
                copy.isAvailable.toggle()
                store.updateAccount(copy)
            }
        }
    }
    
    private func debtRow(_ debt: Debt) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(debt.title)
                HStack(spacing: 6) {
                    Text(debt.direction.rawValue)
                        .font(.caption2)
                        .padding(4)
                        .background(debt.direction == .iOwe ? Color.red.opacity(0.15) : Color.green.opacity(0.15), in: Capsule())
                    if let due = debt.dueDate {
                        Text("fällig: \(dateFormatterShort.string(from: due))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let id = debt.accountID, let acc = store.accounts.first(where: { $0.id == id }) {
                        Text(acc.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(formatCurrency(debt.amount))
                .font(.callout.weight(.semibold))
                .foregroundStyle(debt.direction == .iOwe ? .red : .green)
        }
        .contentShape(Rectangle())
        .onTapGesture { editingDebt = debt }
        .swipeActions(edge: .leading) {
            Button {
                store.toggleSettled(debt)
            } label: {
                Label("Erledigt", systemImage: "checkmark.circle")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.removeDebt(debt)
            } label: { Label("Löschen", systemImage: "trash") }
        }
    }
}

// MARK: - Formulare im selben File

struct AccountFormView: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    
    let original: Account?
    
    @State private var name: String
    @State private var category: AccountCategory
    @State private var initialBalance: Double
    @State private var isAvailable: Bool
    
    init(original: Account?) {
        self.original = original
        if let acc = original {
            _name = State(initialValue: acc.name)
            _category = State(initialValue: acc.category)
            _initialBalance = State(initialValue: acc.initialBalance)
            _isAvailable = State(initialValue: acc.isAvailable)
        } else {
            _name = State(initialValue: "")
            _category = State(initialValue: .giro)
            _initialBalance = State(initialValue: 0)
            _isAvailable = State(initialValue: true)
        }
    }
    
    var body: some View {
        Form {
            Section("Allgemein") {
                TextField("Name", text: $name)
                Picker("Kategorie", selection: $category) {
                    ForEach(AccountCategory.allCases) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                Toggle("Verfügbar", isOn: $isAvailable)
            }
            Section("Startsaldo") {
                HStack {
                    Text("Anfangsbestand")
                    Spacer()
                    TextField("0", value: $initialBalance, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 120)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle(original == nil ? "Konto hinzufügen" : "Konto bearbeiten")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    
    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if var acc = original {
            acc.name = trimmedName
            acc.category = category
            acc.initialBalance = initialBalance
            acc.isAvailable = isAvailable
            store.updateAccount(acc)
        } else {
            let new = Account(name: trimmedName, category: category, initialBalance: initialBalance, isAvailable: isAvailable)
            store.addAccount(new)
        }
        dismiss()
    }
}

private struct InvestmentFormView: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var value: Double = 0
    
    var body: some View {
        Form {
            Section("Geldanlage") {
                TextField("Name", text: $name)
                HStack {
                    Text("Wert")
                    Spacer()
                    TextField("0", value: $value, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 120)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Geldanlage hinzufügen")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Hinzufügen") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.addInvestment(Investment(name: trimmed, value: value))
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

// MARK: - Debt Formular

private struct DebtFormView: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    
    let original: Debt?
    
    @State private var title: String
    @State private var amount: Double
    @State private var direction: DebtDirection
    @State private var account: Account?
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var note: String
    @State private var isSettled: Bool
    
    init(original: Debt?) {
        self.original = original
        if let d = original {
            _title = State(initialValue: d.title)
            _amount = State(initialValue: d.amount)
            _direction = State(initialValue: d.direction)
            _hasDueDate = State(initialValue: d.dueDate != nil)
            _dueDate = State(initialValue: d.dueDate ?? Date())
            _note = State(initialValue: d.note ?? "")
            _isSettled = State(initialValue: d.isSettled)
            // account wird im body via onAppear aufgelöst
            _account = State(initialValue: nil)
        } else {
            _title = State(initialValue: "")
            _amount = State(initialValue: 0)
            _direction = State(initialValue: .iOwe)
            _hasDueDate = State(initialValue: false)
            _dueDate = State(initialValue: Date())
            _note = State(initialValue: "")
            _isSettled = State(initialValue: false)
            _account = State(initialValue: nil)
        }
    }
    
    var body: some View {
        Form {
            Section("Schuld") {
                Picker("Richtung", selection: $direction) {
                    ForEach(DebtDirection.allCases) { d in
                        Text(d.rawValue).tag(d)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Titel", text: $title)
                HStack {
                    Text("Betrag")
                    Spacer()
                    TextField("0", value: $amount, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 120)
                }
            }
            Section("Zuordnung & Fälligkeit") {
                accountPicker(selection: $account)
                Toggle("Fälligkeitsdatum", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Fällig am", selection: $dueDate, displayedComponents: .date)
                }
            }
            Section("Notiz") {
                TextField("optional", text: $note, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
            }
            if original != nil {
                Section {
                    Toggle("Erledigt", isOn: $isSettled)
                }
            }
        }
        .navigationTitle(original == nil ? "Schuld hinzufügen" : "Schuld bearbeiten")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amount <= 0)
            }
        }
        .onAppear {
            if let d = original, let id = d.accountID {
                account = store.accounts.first(where: { $0.id == id })
            }
        }
    }
    
    private func save() {
        let accID = account?.id
        let finalDue = hasDueDate ? dueDate : nil
        if var d = original {
            d.title = title
            d.amount = amount
            d.direction = direction
            d.accountID = accID
            d.dueDate = finalDue
            d.note = note.isEmpty ? nil : note
            d.isSettled = isSettled
            store.updateDebt(d)
        } else {
            let d = Debt(title: title, amount: amount, direction: direction, dueDate: finalDue, accountID: accID, note: note.isEmpty ? nil : note, isSettled: false)
            store.addDebt(d)
        }
        dismiss()
    }
    
    private func accountPicker(selection: Binding<Account?>) -> some View {
        Picker("Konto", selection: selection) {
            Text("Keines").tag(Optional<Account>.none)
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
                            Text(acc.name).tag(Optional(acc))
                        }
                    }
                }
            }
        }
        .pickerStyle(.navigationLink)
    }
}

