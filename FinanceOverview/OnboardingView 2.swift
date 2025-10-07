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
    
    // Spartopf-Erstellung/Zuweisung
    @State private var potCreationAccount: Account?
    @State private var editingPot: SavingsPot?
    @State private var transferContext: PotTransferContext?
    
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
            // Entfernt den inneren NavigationStack – verhindert Präsentationsprobleme
            AccountFormView(original: nil)
                .environmentObject(store)
            .presentationDetents([.large])
        }
        // Spartopf erstellen/bearbeiten
        .sheet(item: $potCreationAccount) { acc in
            NavigationStack {
                SavingsPotFormView(original: nil, account: acc) { new in
                    store.addPot(new)
                }
                .environmentObject(store)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingPot) { pot in
            NavigationStack {
                // Finde das zugehörige Konto
                let acc = store.accounts.first { $0.id == pot.accountID } ?? store.primaryAccount ?? store.accounts.first!
                SavingsPotFormView(original: pot, account: acc) { updated in
                    store.updatePot(updated)
                }
                .environmentObject(store)
            }
            .presentationDetents([.medium, .large])
        }
        // Geld in/aus Topf verschieben
        .sheet(item: $transferContext) { ctx in
            NavigationStack {
                PotTransferSheet(account: ctx.account, pot: ctx.pot, toPot: ctx.toPot)
                    .environmentObject(store)
            }
            .presentationDetents([.medium, .large])
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
                    Haptics.lightTap()
                    store.resetToEmpty()
                    selectedAccountIDs.removeAll()
                    step = 1
                } label: {
                    Label("Leer starten", systemImage: "square.dashed")
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    Haptics.lightTap()
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
    
    // Schritt 1: Konten auswählen (mind. 1) + Spartöpfe modern integriert
    private var selectAccountsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Konten auswählen")
                    .font(.headline)
                
                if store.accounts.isEmpty {
                    Text("Noch keine Konten vorhanden. Füge jetzt eines hinzu.")
                        .foregroundStyle(.secondary)
                    Button {
                        Haptics.lightTap()
                        showAddAccount = true
                    } label: {
                        Label("Konto hinzufügen", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Wähle mindestens ein Konto. Erstelle optional Spartöpfe (z. B. Notgroschen, Urlaub) wie im Buchungs-Flow. Du kannst später weitere hinzufügen.")
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 12) {
                        ForEach(store.accounts) { acc in
                            accountCard(acc)
                        }
                    }
                    
                    Button {
                        Haptics.lightTap()
                        showAddAccount = true
                    } label: {
                        Label("Weiteres Konto hinzufügen", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // Moderne Konto-Karte mit Auswahl + Spartöpfen
    private func accountCard(_ acc: Account) -> some View {
        let isSelected = selectedAccountIDs.contains(acc.id)
        let free = store.freeBalance(for: acc)
        let inPots = store.totalSavedInPots(for: acc)
        let pots = store.pots(for: acc)
        
        return VStack(alignment: .leading, spacing: 12) {
            // Kopfzeile: Konto + Auswahl
            HStack(spacing: 12) {
                Button {
                    Haptics.lightTap()
                    toggleSelection(acc.id)
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if acc.isPrimary { Image(systemName: "star.fill").foregroundStyle(Color.yellow) }
                        Text(acc.name)
                            .font(.headline)
                        if acc.isSubaccount {
                            Text("Unterkonto")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.15), in: Capsule())
                        }
                        if acc.isAvailable {
                            Text("verfügbar")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15), in: Capsule())
                        }
                    }
                    HStack(spacing: 12) {
                        Label {
                            Text(formatCurrency(inPots))
                        } icon: {
                            Image(systemName: "target").foregroundStyle(Color.secondary)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        
                        Label {
                            Text(formatCurrency(free))
                        } icon: {
                            Image(systemName: "wallet.pass").foregroundStyle(Color.secondary)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                // Schnellaktion: Hauptkonto setzen
                Button {
                    Haptics.mediumTap()
                    store.setPrimary(acc)
                } label: {
                    Image(systemName: acc.isPrimary ? "star.fill" : "star")
                        .foregroundStyle(acc.isPrimary ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Spartopf Vorschläge (nur wenn noch keine Töpfe vorhanden)
            if pots.isEmpty {
                suggestionChips(for: acc)
            }
            
            // Bestehende Töpfe als Chips-Grid mit Mini-Progress und Aktionen
            if !pots.isEmpty {
                PotChipsGrid(
                    account: acc,
                    pots: pots,
                    savedAmount: { store.savedAmount(for: $0) },
                    onAssign: { pot in
                        Haptics.lightTap()
                        transferContext = .init(account: acc, pot: pot, toPot: true)
                    },
                    onWithdraw: { pot in
                        Haptics.lightTap()
                        transferContext = .init(account: acc, pot: pot, toPot: false)
                    },
                    onEdit: { pot in
                        Haptics.lightTap()
                        editingPot = pot
                    }
                )
            }
            
            // Aktionen: neuen Topf erstellen
            HStack(spacing: 8) {
                Button {
                    Haptics.lightTap()
                    potCreationAccount = acc
                } label: {
                    Label("Neuen Spartopf", systemImage: "target")
                }
                .buttonStyle(.bordered)
                
                if !pots.isEmpty {
                    Button {
                        Haptics.lightTap()
                        // Komfort: dem zuletzt erstellten Topf direkt zuweisen
                        if let last = pots.last {
                            transferContext = .init(account: acc, pot: last, toPot: true)
                        } else {
                            potCreationAccount = acc
                        }
                    } label: {
                        Label("Geld zuweisen", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
    
    // Vorschlagschips ähnlich Category-Chips aus dem AddTransaction-Flow
    private func suggestionChips(for account: Account) -> some View {
        let suggestions: [(title: String, goal: Double, icon: String)] = [
            ("Notgroschen", 3000, "shield.lefthalf.filled"),
            ("Urlaub", 1200, "sun.max.fill"),
            ("Technik", 800, "desktopcomputer")
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Spartopf-Vorschläge")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { _, s in
                        Button {
                            let pot = SavingsPot(accountID: account.id, name: s.title, goal: s.goal, note: nil)
                            store.addPot(pot)
                            Haptics.success()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: s.icon)
                                Text(s.title)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
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
            Text("Du kannst jetzt Buchungen erfassen, Konten verwalten, Spartöpfe nutzen und Statistiken ansehen. Das Tutorial findest du später im Konten-Tab über das Zahnrad-Menü.")
                .foregroundStyle(.secondary)
            Button {
                Haptics.success()
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
                Button("Zurück") {
                    Haptics.lightTap()
                    step -= 1
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button(step < 2 ? "Weiter" : "Schließen") {
                Haptics.lightTap()
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

// MARK: - Pot Chips Grid (ähnlich moderner Flow-Optik)

private struct PotChipsGrid: View {
    let account: Account
    let pots: [SavingsPot]
    let savedAmount: (SavingsPot) -> Double
    let onAssign: (SavingsPot) -> Void
    let onWithdraw: (SavingsPot) -> Void
    let onEdit: (SavingsPot) -> Void
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 180), spacing: 8)]
    }
    
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(pots, id: \.id) { pot in
                potChip(pot)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spartöpfe")
    }
    
    private func potChip(_ pot: SavingsPot) -> some View {
        let saved = savedAmount(pot)
        let progress = pot.goal > 0 ? min(saved / pot.goal, 1.0) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pot.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(percentString(progress))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(.accentColor)
            HStack {
                Text(formatCurrency(saved))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if pot.goal > 0 {
                    Text("Ziel: \(formatCurrency(pot.goal))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Button {
                    onAssign(pot)
                } label: {
                    Label("Zuweisen", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.bordered)
                
                Button {
                    onWithdraw(pot)
                } label: {
                    Label("Entnehmen", systemImage: "arrow.up.to.line")
                }
                .buttonStyle(.bordered)
                
                Button {
                    onEdit(pot)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Helper State Wrapper

private struct PotTransferContext: Identifiable {
    let id = UUID()
    let account: Account
    let pot: SavingsPot
    let toPot: Bool
}
