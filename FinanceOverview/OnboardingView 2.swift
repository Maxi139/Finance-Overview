// OnboardingAccountsSelectionView.swift
import SwiftUI

struct OnboardingAccountsSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: FinanceStore
    @AppStorage("didSeeOnboarding") private var didSeeOnboarding: Bool = false
    
    @State private var step: Int = 0
    @State private var showAddAccount: Bool = false
    
    // Auswahl der Konten in Schritt 1
    @State private var selectedAccountIDs: Set<UUID> = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                header
                
                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: selectAccountsStep
                    default: finishStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                
                Spacer(minLength: 0)
                footer
            }
            .navigationTitle("Willkommen")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showAddAccount, onDismiss: reloadAfterAdd) {
            NavigationStack {
                AccountFormView(original: nil)
                    .environmentObject(store)
            }
            .presentationDetents([.large])
        }
        .onChange(of: showAddAccount) { open in
            // Falls das Sheet geschlossen wurde, Vorauswahl/Refresh sicherstellen
            if !open { reloadAfterAdd() }
        }
        .onChange(of: store.accounts) { _ in
            // Wenn ein Hauptkonto existiert und nichts ausgewählt ist, dieses vorselektieren
            if selectedAccountIDs.isEmpty, let p = store.primaryAccount {
                selectedAccountIDs = [p.id]
            }
        }
        .onAppear {
            // Initiale Vorauswahl beim ersten Anzeigen
            if selectedAccountIDs.isEmpty, let p = store.primaryAccount {
                selectedAccountIDs = [p.id]
            }
        }
    }
    
    private var header: some View {
        VStack(spacing: 8) {
            Text("Schnellstart")
                .font(.title2.weight(.semibold))
            ProgressView(value: Double(step + 1), total: 3)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .padding(.horizontal)
        }
        .padding(.top)
    }
    
    // Schritt 0: leer starten oder Demo-Daten laden
    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Starte leer oder mit Beispieldaten")
                .font(.headline)
            Text("Du kannst jederzeit Demo-Daten laden oder alles zurücksetzen. Wähle eine Option für den Start:")
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    store.resetToEmpty()
                    selectedAccountIDs.removeAll()
                    step = 1
                } label: {
                    Label("Leer starten", systemImage: "square.dashed")
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    store.loadDemoData()
                    // nach Laden: Hauptkonto (falls vorhanden) vorselektieren
                    if let p = store.primaryAccount {
                        selectedAccountIDs = [p.id]
                    } else {
                        selectedAccountIDs.removeAll()
                    }
                    step = 1
                } label: {
                    Label("Demo-Daten laden", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    // Schritt 1: Konten auswählen (mind. 1)
    private var selectAccountsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Konten auswählen")
                .font(.headline)
            if store.accounts.isEmpty {
                Text("Noch keine Konten vorhanden. Füge jetzt eines hinzu.")
                    .foregroundStyle(.secondary)
                Button {
                    showAddAccount = true
                } label: {
                    Label("Konto hinzufügen", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Wähle mindestens ein Konto, das du verwenden möchtest. Du kannst später weitere hinzufügen.")
                    .foregroundStyle(.secondary)
                List {
                    ForEach(store.accounts) { acc in
                        accountRow(acc)
                    }
                }
                // Force-Refresh der List, wenn sich die Konten ändern
                .id(store.accounts.map(\.id))
                .listStyle(.insetGrouped)
                
                Button {
                    showAddAccount = true
                } label: {
                    Label("Weiteres Konto hinzufügen", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    private func accountRow(_ acc: Account) -> some View {
        Button {
            toggleSelection(acc.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if acc.isPrimary { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                        Text(acc.name)
                    }
                    Text(formatCurrency(store.balance(for: acc)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedAccountIDs.contains(acc.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedAccountIDs.contains(id) {
            selectedAccountIDs.remove(id)
        } else {
            selectedAccountIDs.insert(id)
        }
    }
    
    // Schritt 2: Abschluss
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
                if step == 1 {
                    // Falls noch kein Hauptkonto gesetzt ist, eines der ausgewählten setzen
                    if let firstSelected = selectedAccountIDs.first,
                       let acc = store.accounts.first(where: { $0.id == firstSelected }) {
                        if store.primaryAccount?.id != firstSelected {
                            store.setPrimary(acc)
                        }
                    }
                }
                if step < 2 {
                    step += 1
                } else {
                    didSeeOnboarding = true
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isNextDisabled)
        }
        .padding()
        .background(.thinMaterial)
    }
    
    private var isNextDisabled: Bool {
        switch step {
        case 0:
            return false
        case 1:
            // “Weiter” nur, wenn mindestens ein Konto ausgewählt ist
            return selectedAccountIDs.isEmpty || store.accounts.isEmpty
        default:
            return false
        }
    }
    
    // Wird aufgerufen, wenn das "Konto hinzufügen"-Sheet geschlossen wird.
    private func reloadAfterAdd() {
        // Durch @Published wird die Liste automatisch aktualisiert.
        // Hier kümmern wir uns um eine sinnvolle Vorauswahl.
        guard !store.accounts.isEmpty else { return }
        
        if selectedAccountIDs.isEmpty {
            if let p = store.primaryAccount {
                selectedAccountIDs = [p.id]
            } else if let first = store.accounts.first {
                selectedAccountIDs = [first.id]
            }
        } else {
            // Optional: neuestes Konto automatisch mit auswählen
            if let newest = store.accounts.last {
                selectedAccountIDs.insert(newest.id)
            }
        }
    }
}
