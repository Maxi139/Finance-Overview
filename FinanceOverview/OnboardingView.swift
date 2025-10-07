// OnboardingView.swift
import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: FinanceStore
    @AppStorage("didSeeOnboarding") private var didSeeOnboarding: Bool = false
    
    @State private var step: Int = 0
    @State private var showAddAccount: Bool = false
    @State private var showAddTransaction: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                header
                
                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: addAccountStep
                    default: finishStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                
                Spacer()
                
                footer
            }
            .navigationTitle("Willkommen")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showAddAccount, onDismiss: handleAfterAddAccount) {
            NavigationStack {
                AccountFormView(original: nil)
                    .environmentObject(store)
            }
            .presentationDetents([.large])
        }
    }
    
    private var header: some View {
        VStack(spacing: 8) {
            Text("Schnellstart")
                .font(.title2.weight(.semibold))
            ProgressView(value: Double(step+1), total: 3)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .padding(.horizontal)
        }
        .padding(.top)
    }
    
    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Starte leer oder mit Beispieldaten")
                .font(.headline)
            Text("Du kannst jederzeit Demo-Daten laden oder alles zurücksetzen. Für den Einstieg wähle eine Option:")
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    store.resetToEmpty()
                    step = 1
                } label: {
                    Label("Leer starten", systemImage: "square.dashed")
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    store.loadDemoData()
                    step = 1
                } label: {
                    Label("Demo-Daten laden", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    private var addAccountStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Eigenes Konto hinzufügen")
                .font(.headline)
            Text("Erstelle dein erstes Konto. Du kannst später weitere Konten, Unterkonten und Geldanlagen hinzufügen.")
                .foregroundStyle(.secondary)
            Button {
                showAddAccount = true
            } label: {
                Label("Konto hinzufügen", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            
            if !store.accounts.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Schon vorhanden:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(store.accounts.prefix(3)) { acc in
                            HStack {
                                Text(acc.name)
                                Spacer()
                                Text(formatCurrency(store.balance(for: acc))).foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                    // Force-Refresh der Vorschau, wenn sich die Konten ändern
                    .id(store.accounts.map(\.id))
                }
            }
        }
    }
    
    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fertig!")
                .font(.headline)
            Text("Du kannst jetzt Buchungen erfassen, Konten verwalten und Statistiken ansehen. Das Tutorial findest du später im Konten-Tab über das Zahnrad-Menü.")
                .foregroundStyle(.secondary)
            Button {
                didSeeOnboarding = true
                dismiss()
            } label: {
                Label("Los geht’s", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Zurück") { step -= 1 }
                    .buttonStyle(.bordered)
            }
            Spacer()
            Button(step < 2 ? "Weiter" : "Schließen") {
                if step < 2 {
                    step += 1
                } else {
                    didSeeOnboarding = true
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(step == 1 && store.accounts.isEmpty) // "Weiter" erst wenn mindestens 1 Konto existiert
        }
        .padding()
        .background(.thinMaterial)
    }
    
    private func handleAfterAddAccount() {
        // In Schritt 1 bleiben und Vorschau sicher neu zeichnen
        if step != 1 { step = 1 }
        // Keine weitere Aktion nötig – @Published sorgt für die Aktualisierung.
        // Optionaler Mini-Delay, falls Persistenz gerade schreibt:
        DispatchQueue.main.async { }
    }
}
