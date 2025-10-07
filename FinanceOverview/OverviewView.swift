import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var store: FinanceStore
    @State private var showAddFlow = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCards
                    recentSection
                }
                .padding()
            }
            .navigationTitle("Finance Overview")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddFlow = true
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showAddFlow) {
                AddTransactionFlowView()
                    .environmentObject(store) // gleicher Store -> sofortige Aktualisierung
                    .presentationDetents([.large])
            }
        }
    }
    
    private var headerCards: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                OverviewCard(title: "Hauptkonto",
                             value: formatCurrency(store.balance(for: store.primaryAccount ?? store.accounts.first ?? Account(name: "-", category: .giro, initialBalance: 0))),
                             subtitle: store.primaryAccount?.name ?? "Kein Hauptkonto")
                OverviewCard(title: "Verfügbar",
                             value: formatCurrency(store.availableSum),
                             subtitle: "Summe verfügbarer Konten")
            }
            OverviewCard(title: "Gesamtwert",
                         value: formatCurrency(store.totalValue),
                         subtitle: "Konten + Geldanlagen",
                         fullWidth: true)
        }
    }
    
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Letzte Buchungen")
                    .font(.headline)
                Spacer()
                Button {
                    showAddFlow = true
                } label: {
                    Label("Neu", systemImage: "plus")
                }
            }
            ForEach(store.transactions.prefix(6)) { t in
                TransactionRow(transaction: t)
                    .padding(12) // inneres Padding für Text und Inhalt
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

struct OverviewCard: View {
    var title: String
    var value: String
    var subtitle: String
    var fullWidth: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded))
            Text(subtitle).font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(.background).shadow(color: .black.opacity(0.07), radius: 8, y: 4))
    }
}
