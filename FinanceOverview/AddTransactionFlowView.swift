import SwiftUI
import UIKit

private enum AddStep: Int, CaseIterable {
    case kind, name, accounts, amount, date, note
    var title: String {
        switch self {
        case .kind: return "Art der Buchung"
        case .name: return "Wie heißt die Buchung?"
        case .accounts: return "Wähle Konto"
        case .amount: return "Welcher Betrag?"
        case .date: return "Datum"
        case .note: return "Notiz"
        }
    }
}

// Moderner, gut sichtbarer TextField-Style (Dark/Light kompatibel)
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
    
    // State
    @State private var step: AddStep = .kind
    @State private var kind: TransactionKind = .expense
    @State private var name: String = ""
    @State private var selectedAccount: Account?
    @State private var fromAccount: Account?
    @State private var toAccount: Account?
    @State private var amount: Double = 0
    @State private var date: Date = Date()
    @State private var note: String = ""
    
    // NavigationLink-States für Kontoauswahl (damit "Weiter" nur geht, wenn Picker geschlossen ist)
    @State private var isSinglePickerActive: Bool = false
    @State private var isFromPickerActive: Bool = false
    @State private var isToPickerActive: Bool = false
    
    // Fokussteuerung für Textfelder
    private enum Field: Hashable { case name, amount }
    @FocusState private var focusedField: Field?
    
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(step.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") { dismiss() }
                    }
                }
                .background(Color(uiColor: .systemBackground))
                .onAppear {
                    if kind != .transfer, selectedAccount == nil {
                        selectedAccount = store.primaryAccount
                    }
                }
                .onChange(of: step) { _, newStep in
                    if newStep == .accounts, kind != .transfer, selectedAccount == nil {
                        selectedAccount = store.primaryAccount
                    }
                    switch newStep {
                    case .name:
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedField = .name }
                    case .amount:
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedField = .amount }
                    default:
                        focusedField = nil
                    }
                }
                .onChange(of: kind) { _, newKind in
                    if newKind != .transfer, selectedAccount == nil {
                        selectedAccount = store.primaryAccount
                    }
                }
        }
        .interactiveDismissDisabled() // bewusster Flow
        .safeAreaInset(edge: .bottom) { bottomBar } // überdeckt keine Felder
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
                                accountLink(selection: $fromAccount,
                                            placeholder: "Konto wählen",
                                            isActive: $isFromPickerActive)
                                    .modernField()
                            }
                            LabeledContent("Nach") {
                                accountLink(selection: $toAccount,
                                            placeholder: "Konto wählen",
                                            isActive: $isToPickerActive)
                                    .modernField()
                            }
                        }
                    } else {
                        Text("Welches Konto ist betroffen?")
                            .font(.title3).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        LabeledContent("Konto") {
                            accountLink(selection: $selectedAccount,
                                        placeholder: "Konto wählen",
                                        isActive: $isSinglePickerActive)
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
                Button("Zurück") { previous() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if step == .date {
                Button("Fertig") {
                    // Notizen überspringen -> direkt speichern
                    save()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button(step == .note ? "Speichern" : "Weiter") {
                if step == .note { save() } else { next() }
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
        guard let i = AddStep.allCases.firstIndex(of: step),
              i + 1 < AddStep.allCases.count else { return }
        step = AddStep.allCases[i + 1]
    }
    private func previous() {
        guard let i = AddStep.allCases.firstIndex(of: step),
              i - 1 >= 0 else { return }
        step = AddStep.allCases[i - 1]
    }
    
    private func isStepValid(_ step: AddStep) -> Bool {
        switch step {
        case .kind: return true
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
            tx = FinanceTransaction(date: date, name: finalName, amount: finalAmount, kind: .expense, accountID: selectedAccount?.id, note: finalNote)
        case .income:
            finalAmount = abs(amount)
            tx = FinanceTransaction(date: date, name: finalName, amount: finalAmount, kind: .income, accountID: selectedAccount?.id, note: finalNote)
        case .transfer:
            finalAmount = abs(amount)
            tx = FinanceTransaction(date: date, name: finalName.isEmpty ? "Umbuchung" : finalName, amount: finalAmount, kind: .transfer, fromAccountID: fromAccount?.id, toAccountID: toAccount?.id, note: finalNote)
        }
        store.addTransaction(tx)
        
        // Sheet zuerst schließen, dann Overlay global anzeigen (5s, Tipp schließt sofort)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        Task { @MainActor in
            dismiss()
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s, damit das Sheet sicher zu ist
            store.successOverlay = SaveSuccessOverlay(kind: kind, name: finalName.isEmpty ? kind.rawValue : finalName, amount: finalAmount)
        }
    }
    
    private func kindButton(_ k: TransactionKind, title: String, icon: String, color: Color) -> some View {
        Button {
            kind = k
            next()
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
    
    // Kontoauswahl mit explizitem isActive-Binding, damit wir wissen, ob die Auswahl gerade offen ist.
    private func accountLink(selection: Binding<Account?>, placeholder: String, isActive: Binding<Bool>) -> some View {
        NavigationLink(isActive: isActive) {
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
                                    if selection.wrappedValue?.id == acc.id {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selection.wrappedValue = acc
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Konto wählen")
        } label: {
            HStack {
                Text(selection.wrappedValue?.name ?? placeholder)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }
    }
}
