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
            contentList
                .navigationTitle("Konten")
                .toolbar { topToolbar }
                .sheetsAndAlerts
        }
    }
    
    // MARK: - Split Views
    
    private var contentList: some View {
        List {
            accountsSections
            if !store.investments.isEmpty {
                investmentsSection
            }
            debtsSection
        }
    }
    
    private var accountsSections: some View {
        ForEach(AccountCategory.allCases, id: \.id) { cat in
            Section(cat.rawValue) {
                ForEach(topLevelAccounts(for: cat), id: \.id) { acc in
                    // Hauptkonto-Zeile
                    accountCell(acc)
                    // Spartöpfe des Hauptkontos
                    let potsMain = store.pots(for: acc)
                    if !potsMain.isEmpty {
                        ForEach(potsMain, id: \.id) { pot in
                            potRowCompact(account: acc, pot: pot)
                        }
                    }
                    // Unterkonten + deren Töpfe
                    ForEach(subaccounts(of: acc), id: \.id) { sub in
                        accountCell(sub, isSub: true)
                        let potsSub = store.pots(for: sub)
                        if !potsSub.isEmpty {
                            ForEach(potsSub, id: \.id) { pot in
                                potRowCompact(account: sub, pot: pot, isUnderSubaccount: true)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var investmentsSection: some View {
        Section("Geldanlagen") {
            ForEach(store.investments, id: \.id) { inv in
                HStack {
                    Text(inv.name)
                    Spacer()
                    Text(formatCurrency(inv.value))
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Haptics.error()
                        store.removeInvestment(inv)
                    } label: { Label("Entfernen", systemImage: "trash") }
                }
            }
        }
    }
    
    private var debtsSection: some View {
        Section {
            if openDebts.isEmpty {
                Button {
                    Haptics.lightTap()
                    showAddDebt = true
                } label: {
                    Label("Neue Schuld hinzufügen", systemImage: "text.badge.plus")
                }
            } else {
                ForEach(openDebtsSorted, id: \.id) { debt in
                    debtRow(debt)
                }
                Button {
                    Haptics.lightTap()
                    showAddDebt = true
                } label: {
                    Label("Neue Schuld", systemImage: "text.badge.plus")
                }
            }
        } header: {
            Text("Schulden")
        } footer: {
            if !openDebts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
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
    }
    
    private var topToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button {
                    Haptics.lightTap()
                    store.loadDemoData()
                } label: {
                    Label("Demo-Daten laden", systemImage: "tray.and.arrow.down")
                }
                Button(role: .destructive) {
                    Haptics.warning()
                    confirmReset = true
                } label: {
                    Label("Alle Daten löschen", systemImage: "trash")
                }
            } label: {
                Image(systemName: "gearshape")
            }
            
            // Plus-Menü mit drei Aktionen
            Menu {
                Button {
                    Haptics.lightTap()
                    showAddAccount = true
                } label: {
                    Label("Konto hinzufügen", systemImage: "creditcard.fill")
                }
                Button {
                    Haptics.lightTap()
                    showAddInvestment = true
                } label: {
                    Label("Geldanlage hinzufügen", systemImage: "banknote")
                }
                Button {
                    Haptics.lightTap()
                    showAddDebt = true
                } label: {
                    Label("Schuld hinzufügen", systemImage: "text.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }
    
    // MARK: - Sheets & Alerts
    
    private var sheetsAndAlerts: some View {
        EmptyView()
            .sheet(isPresented: $showAddAccount) {
                // WICHTIG: NavigationStack wieder aktivieren, damit Toolbar sichtbar ist
                NavigationStack {
                    AccountFormView(original: nil)
                        .environmentObject(store)
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showAddInvestment) {
                NavigationStack {
                    InvestmentFormView()
                        .environmentObject(store)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $editingAccount) { acc in
                NavigationStack {
                    AccountFormView(original: acc)
                        .environmentObject(store)
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showAddDebt) {
                NavigationStack {
                    DebtFormView(original: nil)
                        .environmentObject(store)
                }
                .presentationDetents([.medium, .large])
            }
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
                    Haptics.error()
                    store.resetToEmpty()
                }
            } message: {
                Text("Diese Aktion kann nicht rückgängig gemacht werden.")
            }
    }
    
    // MARK: - Derived Data
    
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
    
    // MARK: - Rows
    
    private func accountCell(_ acc: Account, isSub: Bool = false) -> some View {
        let free = store.freeBalance(for: acc)
        let inPots = store.totalSavedInPots(for: acc)
        return NavigationLink {
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
                    Text("In Töpfen: \(formatCurrency(inPots))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(formatCurrency(free)).font(.callout.weight(.semibold))
                    Text("frei").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Haptics.error()
                store.removeAccount(acc)
            } label: { Label("Löschen", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button {
                Haptics.mediumTap()
                store.setPrimary(acc)
            } label: { Label("Hauptkonto", systemImage: "star") }
            Button {
                let sub = Account(name: "\(acc.name) – Unterkonto", category: acc.category, initialBalance: 0, isAvailable: acc.isAvailable, isPrimary: false, parentAccountID: acc.id)
                store.addAccount(sub)
                Haptics.success()
            } label: { Label("Unterkonto", systemImage: "arrow.branch") }
        }
        .contextMenu {
            Button("Bearbeiten") {
                Haptics.lightTap()
                editingAccount = acc
            }
            Button(acc.isAvailable ? "Als nicht verfügbar markieren" : "Als verfügbar markieren") {
                var copy = acc
                copy.isAvailable.toggle()
                store.updateAccount(copy)
                Haptics.lightTap()
            }
        }
    }
    
    private func potRowCompact(account: Account, pot: SavingsPot, isUnderSubaccount: Bool = false) -> some View {
        let saved = store.savedAmount(for: pot)
        let progress = pot.goal > 0 ? min(saved / pot.goal, 1.0) : 0
        // Navigiert zur Konto-Detailseite
        return NavigationLink {
            AccountDetailView(account: account)
        } label: {
            HStack(spacing: 10) {
                // Einrückungsindikator: Punktebene unter Konto
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: isUnderSubaccount ? 28 : 16) // etwas mehr Einzug unter Unterkonto
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "target")
                            .foregroundStyle(.secondary)
                        Text(pot.name)
                            .font(.subheadline)
                        Spacer()
                        Text(percentString(progress))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: progress)
                        .tint(.accentColor)
                    HStack(spacing: 8) {
                        Text("Gespart: \(formatCurrency(saved))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if pot.goal > 0 {
                            Text("Ziel: \(formatCurrency(pot.goal))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden, edges: .top) // optisch enger unter dem Konto
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
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
        .onTapGesture {
            Haptics.lightTap()
            editingDebt = debt
        }
        .swipeActions(edge: .leading) {
            Button {
                store.toggleSettled(debt)
                Haptics.success()
            } label: {
                Label("Erledigt", systemImage: "checkmark.circle")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Haptics.error()
                store.removeDebt(debt)
            } label: { Label("Löschen", systemImage: "trash") }
        }
    }
}

private extension View {
    // Compose all sheets/alerts to keep body simple
    var sheetsAndAlerts: some View { self }
}
