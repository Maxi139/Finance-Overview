import SwiftUI
import UIKit

private enum AddStep: Int, CaseIterable {
    case kind, category, name, accounts, amount, date, note
    var title: String {
        switch self {
        case .kind: return "Art der Buchung"
        case .category: return "Kategorie"
        case .name: return "Wie heißt die Buchung?"
        case .accounts: return "Wähle Konto"
        case .amount: return "Welcher Betrag?"
        case .date: return "Datum"
        case .note: return "Notiz"
        }
    }
}

private struct ModernField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
    }
}
private extension View {
    func modernField() -> some View { modifier(ModernField()) }
}

struct AddTransactionFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: FinanceStore
    
    @State private var step: AddStep = .kind
    @State private var kind: TransactionKind = .expense
    @State private var name: String = ""
    @State private var selectedAccount: Account?
    @State private var fromAccount: Account?
    @State private var toAccount: Account?
    @State private var amount: Double = 0
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var selectedCategoryID: UUID?
    @State private var showCreateCategory: Bool = false
    
    @State private var isSinglePickerActive: Bool = false
    @State private var isFromPickerActive: Bool = false
    @State private var isToPickerActive: Bool = false
    
    // Bestätigungsdialog für Bulk-Anwendung
    @State private var showApplyToPastDialog: Bool = false
    @State private var pendingApplyCategoryID: UUID?
    @State private var pendingName: String = ""
    @State private var pendingDate: Date = Date()
    @State private var pendingTxToAdd: FinanceTransaction?
    @State private var pendingCount: Int = 0
    
    private enum Field: Hashable { case name, amount }
    @FocusState private var focusedField: Field?
    
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(step.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") {
                            Haptics.lightTap()
                            dismiss()
                        }
                    }
                }
                .background(Color(uiColor: .systemBackground))
                .onAppear { ensureDefaultAccountIfNeeded() }
                .onChange(of: step) { _, newStep in
                    if newStep == .accounts { ensureDefaultAccountIfNeeded() }
                    switch newStep {
                    case .name:
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedField = .name }
                    case .amount:
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedField = .amount }
                    default:
                        focusedField = nil
                    }
                    if newStep == .category,
                       selectedCategoryID == nil,
                       kind != .transfer,
                       !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        selectedCategoryID = store.suggestedCategoryID(forName: name)
                    }
                }
                .onChange(of: kind) { _, newKind in
                    if newKind != .transfer {
                        ensureDefaultAccountIfNeeded(force: false)
                    } else {
                        selectedCategoryID = nil
                        if step == .category { step = .name }
                    }
                }
                .onChange(of: selectedCategoryID) { _, newValue in
                    if step == .category, kind != .transfer, newValue != nil {
                        Haptics.lightTap()
                        next()
                    }
                }
                .navigationDestination(isPresented: $isSinglePickerActive) {
                    accountPickerList(title: "Konto wählen") { acc in
                        selectedAccount = acc
                        Haptics.lightTap()
                        isSinglePickerActive = false
                    }
                }
                .navigationDestination(isPresented: $isFromPickerActive) {
                    accountPickerList(title: "Von") { acc in
                        fromAccount = acc
                        Haptics.lightTap()
                        isFromPickerActive = false
                    }
                }
                .navigationDestination(isPresented: $isToPickerActive) {
                    accountPickerList(title: "Nach") { acc in
                        toAccount = acc
                        Haptics.lightTap()
                        isToPickerActive = false
                    }
                }
        }
        .interactiveDismissDisabled()
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(isPresented: $showCreateCategory) {
            NavigationStack {
                CreateOrEditCategoryView { new in
                    selectedCategoryID = new.id
                    if step == .category, kind != .transfer {
                        Haptics.lightTap()
                        next()
                    }
                }
                .environmentObject(store)
            }
            .presentationDetents([.medium, .large])
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
                // Jetzt die aktuelle Buchung hinzufügen
                if let tx = pendingTxToAdd {
                    store.addTransaction(tx)
                }
                finalizeAfterSave(kind: txKindForPending(), name: pendingName, amount: pendingTxToAdd?.amount ?? 0)
            }
            Button("Nur diese Buchung", role: .cancel) {
                // Nur aktuelle Buchung hinzufügen
                if let tx = pendingTxToAdd {
                    store.addTransaction(tx)
                }
                finalizeAfterSave(kind: txKindForPending(), name: pendingName, amount: pendingTxToAdd?.amount ?? 0)
            }
        } message: {
            Text("Es gibt \(pendingCount) vergangene Buchungen ohne Kategorie mit dem gleichen Namen. Sollen diese ebenfalls die Kategorie erhalten?")
        }
    }
    
    // MARK: - Inhalt pro Schritt
    @ViewBuilder
    private var content: some View {
        switch step {
        case .kind:
            ScrollView {
                VStack(spacing: 16) {
                    Text("Was möchtest du erfassen?")
                        .font(.title3).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 12) {
                        kindButton(.expense, title: "Ausgabe", icon: "arrow.down.circle.fill", color: .red)
                        kindButton(.income, title: "Einnahme", icon: "arrow.up.circle.fill", color: .green)
                        kindButton(.transfer, title: "Umbuchung", icon: "arrow.left.arrow.right.circle.fill", color: .blue)
                    }
                }
                .padding()
            }
        case .category:
            ScrollView {
                VStack(spacing: 14) {
                    Text("Wähle eine Kategorie")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        if store.categories.isEmpty {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Kategorien werden geladen …")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 220)
                        } else {
                            CategoryPickerView(selectedID: $selectedCategoryID)
                                .environmentObject(store)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 2)
                                .frame(minHeight: 220, alignment: .topLeading)
                        }
                        
                        Button {
                            Haptics.lightTap()
                            showCreateCategory = true
                        } label: {
                            Label("Neue Kategorie erstellen", systemImage: "tag")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 18)
                    .padding(.horizontal, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
        case .name:
            ScrollView {
                VStack(spacing: 16) {
                    Text("Gib der Buchung einen Namen")
                        .font(.title3).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("z. B. Supermarkt, Gehalt …", text: $name)
                        .modernField()
                        .font(.title3)
                        .textInputAutocapitalization(.sentences)
                        .focused($focusedField, equals: .name)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.immediately)
        case .accounts:
            ScrollView {
                VStack(spacing: 16) {
                    if kind == .transfer {
                        Text("Von welchem Konto auf welches?")
                            .font(.title3).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(spacing: 12) {
                            LabeledContent("Von") {
                                accountLink(selectionName: fromAccount?.name, placeholder: "Konto wählen") {
                                    Haptics.lightTap()
                                    isFromPickerActive = true
                                }
                                .modernField()
                            }
                            LabeledContent("Nach") {
                                accountLink(selectionName: toAccount?.name, placeholder: "Konto wählen") {
                                    Haptics.lightTap()
                                    isToPickerActive = true
                                }
                                .modernField()
                            }
                        }
                    } else {
                        Text("Welches Konto ist betroffen?")
                            .font(.title3).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        LabeledContent("Konto") {
                            accountLink(selectionName: selectedAccount?.name, placeholder: "Konto wählen") {
                                Haptics.lightTap()
                                isSinglePickerActive = true
                            }
                            .modernField()
                        }
                    }
                }
                .padding()
            }
        case .amount:
            ScrollView {
                VStack(spacing: 16) {
                    Text("Wie hoch ist der Betrag?")
                        .font(.title3).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 12) {
                        TextField("0,00", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.leading)
                            .modernField()
                            .focused($focusedField, equals: .amount)
                        Text(Locale.current.currency?.identifier ?? "EUR")
                            .font(.headline).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.immediately)
        case .date:
            ScrollView {
                VStack(spacing: 16) {
                    Text("Wann fand die Buchung statt?")
                        .font(.title3).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(.top, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                }
                .padding()
            }
        case .note:
            ScrollView {
                VStack(spacing: 16) {
                    Text("Möchtest du eine Notiz hinzufügen?")
                        .font(.title3).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("optional", text: $note, axis: .vertical)
                        .modernField()
                        .lineLimit(5, reservesSpace: true)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }
    
    // MARK: - Bottom Bar
    private var bottomBar: some View {
        HStack {
            if step != .kind {
                Button("Zurück") {
                    Haptics.lightTap()
                    previous()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            if step == .date {
                Button("Fertig") {
                    Haptics.lightTap()
                    step = .note
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button(step == .note ? "Speichern" : "Weiter") {
                if step == .note {
                    save()
                } else {
                    Haptics.lightTap()
                    next()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isStepValid(step) || isAnyAccountPickerActive)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }
    
    private var isAnyAccountPickerActive: Bool {
        guard step == .accounts else { return false }
        if kind == .transfer {
            return isFromPickerActive || isToPickerActive
        } else {
            return isSinglePickerActive
        }
    }
    
    // MARK: - Helpers
    private func next() {
        var currentIndex = AddStep.allCases.firstIndex(of: step)!
        while true {
            let nextIndex = currentIndex + 1
            guard nextIndex < AddStep.allCases.count else { return }
            let nextStep = AddStep.allCases[nextIndex]
            if kind == .transfer && nextStep == .category {
                currentIndex = nextIndex
                continue
            }
            step = nextStep
            return
        }
    }
    private func previous() {
        var currentIndex = AddStep.allCases.firstIndex(of: step)!
        while true {
            let prevIndex = currentIndex - 1
            guard prevIndex >= 0 else { return }
            let prevStep = AddStep.allCases[prevIndex]
            if kind == .transfer && prevStep == .category {
                currentIndex = prevIndex
                continue
            }
            step = prevStep
            return
        }
    }
    
    private func isStepValid(_ step: AddStep) -> Bool {
        switch step {
        case .kind: return true
        case .category: return true
        case .name: return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .accounts:
            if kind == .transfer { return fromAccount != nil && toAccount != nil && fromAccount?.id != toAccount?.id }
            return selectedAccount != nil
        case .amount: return amount > 0
        case .date: return true
        case .note: return true
        }
    }
    
    private func save() {
        let finalName = name
        let finalNote = note.isEmpty ? nil : note
        let finalAmount: Double
        var tx: FinanceTransaction
        switch kind {
        case .expense:
            finalAmount = -abs(amount)
            tx = FinanceTransaction(date: date, name: finalName, amount: finalAmount, kind: .expense, accountID: selectedAccount?.id, note: finalNote, categoryID: selectedCategoryID)
        case .income:
            finalAmount = abs(amount)
            tx = FinanceTransaction(date: date, name: finalName, amount: finalAmount, kind: .income, accountID: selectedAccount?.id, note: finalNote, categoryID: selectedCategoryID)
        case .transfer:
            finalAmount = abs(amount)
            tx = FinanceTransaction(date: date, name: finalName.isEmpty ? "Umbuchung" : finalName, amount: finalAmount, kind: .transfer, fromAccountID: fromAccount?.id, toAccountID: toAccount?.id, note: finalNote, categoryID: nil)
        }
        
        // Nur für income/expense mit gesetzter Kategorie prüfen und ggf. fragen
        if (tx.kind == .income || tx.kind == .expense),
           let catID = tx.categoryID {
            let count = store.countPastUncategorizedTransactions(matchingName: tx.name, before: tx.date)
            if count > 0 {
                pendingApplyCategoryID = catID
                pendingName = tx.name
                pendingDate = tx.date
                pendingTxToAdd = tx
                pendingCount = count
                showApplyToPastDialog = true
                return
            }
        }
        
        // Kein Dialog nötig -> direkt hinzufügen und abschließen
        store.addTransaction(tx)
        finalizeAfterSave(kind: kind, name: finalName, amount: finalAmount)
    }
    
    private func finalizeAfterSave(kind: TransactionKind, name: String, amount: Double) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        Task { @MainActor in
            dismiss()
            try? await Task.sleep(nanoseconds: 200_000_000)
            store.successOverlay = SaveSuccessOverlay(kind: kind, name: name.isEmpty ? kind.rawValue : name, amount: amount)
        }
    }
    
    private func txKindForPending() -> TransactionKind {
        if let tx = pendingTxToAdd { return tx.kind }
        return kind
    }
    
    private func kindButton(_ k: TransactionKind, title: String, icon: String, color: Color) -> some View {
        Button {
            Haptics.lightTap()
            kind = k
            ensureDefaultAccountIfNeeded()
            if k == .transfer { step = .name } else { step = .category }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
    
    private func accountLink(selectionName: String?, placeholder: String, onTap: @escaping () -> Void) -> some View {
        Button { onTap() } label: {
            HStack {
                Text(selectionName ?? placeholder)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func accountPickerList(title: String, onPick: @escaping (Account) -> Void) -> some View {
        List {
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
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onPick(acc) }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
    }
    
    private func ensureDefaultAccountIfNeeded(force: Bool = false) {
        guard kind != .transfer else { return }
        if force || selectedAccount == nil {
            if let primary = store.primaryAccount {
                selectedAccount = primary
            } else if let first = store.accounts.first {
                selectedAccount = first
            } else {
                selectedAccount = nil
            }
        }
    }
}

// Hinweis: Kategorie-Verwaltung (Bearbeiten/Löschen) wurde aus diesem Flow entfernt.
// Bitte in den Einstellungen separat anbieten.

