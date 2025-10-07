import SwiftUI

struct AccountDetailView: View {
    @EnvironmentObject var store: FinanceStore
    let account: Account
    
    @State private var showEdit = false
    
    private var balance: Double {
        store.balance(for: account)
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
                    Text("Saldo")
                    Spacer()
                    Text(formatCurrency(balance))
                        .font(.callout.weight(.semibold))
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
    }
}
