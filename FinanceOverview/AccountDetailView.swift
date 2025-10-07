import SwiftUI

struct AccountDetailView: View {
    @EnvironmentObject var store: FinanceStore
    let account: Account
    
    @State private var showEdit = false
    // Sheets für Spartöpfe
    @State private var showCreatePot = false
    @State private var editingPot: SavingsPot?
    @State private var transferPot: SavingsPot?
    @State private var transferDirectionToPot: Bool = true // true = in Topf, false = aus Topf
    
    private var balance: Double {
        store.balance(for: account)
    }
    private var freeBalance: Double {
        store.freeBalance(for: account)
    }
    private var pots: [SavingsPot] {
        store.pots(for: account)
    }
    private var totalSavedInPots: Double {
        store.totalSavedInPots(for: account)
    }
    
    private var relatedTransactions: [FinanceTransaction] {
        store.transactions.filter { t in
            switch t.kind {
            case .income, .expense:
                return t.accountID == account.id
            case .transfer:
                return t.fromAccountID == account.id || t.toAccountID == account.id
            }
        }
        .sorted { $0.date > $1.date }
    }
    
    var body: some View {
        List {
            Section("Konto") {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(account.name).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Kategorie")
                    Spacer()
                    Text(account.category.rawValue).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Status")
                    Spacer()
                    Text(account.isAvailable ? "verfügbar" : "nicht verfügbar")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Saldo (gesamt)")
                    Spacer()
                    Text(formatCurrency(balance))
                        .font(.callout.weight(.semibold))
                }
                HStack {
                    Text("In Töpfen")
                    Spacer()
                    Text(formatCurrency(totalSavedInPots))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Freier Saldo")
                    Spacer()
                    Text(formatCurrency(freeBalance))
                        .font(.callout.weight(.semibold))
                }
            }
            
            Section {
                if pots.isEmpty {
                    Text("Keine Spartöpfe").foregroundStyle(.secondary)
                } else {
                    ForEach(pots, id: \.id) { pot in
                        potRow(pot)
                            .swipeActions {
                                Button {
                                    editingPot = pot
                                } label: {
                                    Label("Bearbeiten", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    store.removePot(pot)
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                    }
                }
                Button {
                    showCreatePot = true
                } label: {
                    Label("Neuen Spartopf erstellen", systemImage: "target")
                }
            } header: {
                Text("Spartöpfe")
            } footer: {
                if !pots.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Summe Ziele")
                            Spacer()
                            let totalGoal = pots.map(\.goal).reduce(0, +)
                            Text(formatCurrency(totalGoal)).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("In Töpfen gesamt")
                            Spacer()
                            Text(formatCurrency(totalSavedInPots)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Section("Buchungen") {
                if relatedTransactions.isEmpty {
                    Text("Keine Buchungen")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(relatedTransactions) { t in
                        TransactionRow(transaction: t)
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    store.setPrimary(account)
                } label: {
                    Image(systemName: account.isPrimary ? "star.fill" : "star")
                }
                
                Button("Bearbeiten") {
                    showEdit = true
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                AccountFormView(original: account)
                    .environmentObject(store)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showCreatePot) {
            NavigationStack {
                SavingsPotFormView(original: nil, account: account) { new in
                    store.addPot(new)
                }
                .environmentObject(store)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingPot) { pot in
            NavigationStack {
                SavingsPotFormView(original: pot, account: account) { updated in
                    store.updatePot(updated)
                }
                .environmentObject(store)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: Binding(
            get: {
                transferPot.map { PotTransferSheet.StateWrapper(pot: $0, toPot: transferDirectionToPot) }
            },
            set: { wrapper in
                if let w = wrapper {
                    transferPot = w.pot
                    transferDirectionToPot = w.toPot
                } else {
                    transferPot = nil
                }
            }
        )) { wrapper in
            NavigationStack {
                PotTransferSheet(account: account, pot: wrapper.pot, toPot: wrapper.toPot)
                    .environmentObject(store)
            }
            .presentationDetents([.medium, .large])
        }
    }
    
    private func potRow(_ pot: SavingsPot) -> some View {
        let saved = store.savedAmount(for: pot)
        let progress = pot.goal > 0 ? min(saved / pot.goal, 1.0) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pot.name).font(.headline)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(.accentColor)
            HStack {
                Text("Ziel: \(formatCurrency(pot.goal))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Gespart: \(formatCurrency(saved))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button {
                    transferPot = pot
                    transferDirectionToPot = true
                } label: {
                    Label("Geld zuweisen", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.bordered)
                
                Button {
                    transferPot = pot
                    transferDirectionToPot = false
                } label: {
                    Label("Geld entnehmen", systemImage: "arrow.up.to.line")
                }
                .buttonStyle(.bordered)
            }
            if let note = pot.note, !note.isEmpty {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private extension PotTransferSheet {
    // Wrapper um .sheet(item:) zu ermöglichen
    struct StateWrapper: Identifiable {
        var id: UUID { pot.id }
        let pot: SavingsPot
        let toPot: Bool
    }
}
