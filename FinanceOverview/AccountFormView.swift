import SwiftUI

struct AccountFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: FinanceStore

    let original: Account?

    @State private var name: String
    @State private var category: AccountCategory
    @State private var initialBalance: Double
    @State private var isAvailable: Bool
    @State private var isPrimary: Bool
    @State private var parentAccount: Account?

    init(original: Account?) {
        self.original = original
        if let acc = original {
            _name = State(initialValue: acc.name)
            _category = State(initialValue: acc.category)
            _initialBalance = State(initialValue: acc.initialBalance)
            _isAvailable = State(initialValue: acc.isAvailable)
            _isPrimary = State(initialValue: acc.isPrimary)
            // Parent wird in onAppear aufgelöst, falls Unterkonto
            _parentAccount = State(initialValue: nil)
        } else {
            _name = State(initialValue: "")
            _category = State(initialValue: .giro)
            _initialBalance = State(initialValue: 0)
            _isAvailable = State(initialValue: true)
            _isPrimary = State(initialValue: false)
            _parentAccount = State(initialValue: nil)
        }
    }

    var body: some View {
        Form {
            Section("Konto") {
                TextField("Name", text: $name)
                Picker("Kategorie", selection: $category) {
                    ForEach(AccountCategory.allCases) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                HStack {
                    Text("Anfangssaldo")
                    Spacer()
                    TextField("0", value: $initialBalance, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                }
                Toggle("Verfügbar", isOn: $isAvailable)
                Toggle("Als Hauptkonto markieren", isOn: $isPrimary)
            }

            Section("Unterkonto (optional)") {
                Picker("Übergeordnetes Konto", selection: Binding(
                    get: { parentAccount },
                    set: { parentAccount = $0 }
                )) {
                    Text("Keines").tag(Optional<Account>.none)
                    ForEach(store.accounts) { acc in
                        Text(acc.name).tag(Optional(acc) as Account?)
                    }
                }
                .pickerStyle(.navigationLink)
                .disabled(original?.id == parentAccount?.id)
            }

            if original != nil {
                Section {
                    Text("Bearbeitung eines bestehenden Kontos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(original == nil ? "Konto erstellen" : "Konto bearbeiten")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") { save() }
                    .disabled(!canSave)
            }
        }
        .onAppear {
            // Parent-Account auflösen, falls Original ein Unterkonto ist
            if let acc = original, let parentID = acc.parentAccountID {
                parentAccount = store.accounts.first(where: { $0.id == parentID })
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if var acc = original {
            acc.name = trimmed
            acc.category = category
            acc.initialBalance = initialBalance
            acc.isAvailable = isAvailable
            acc.isPrimary = isPrimary
            acc.parentAccountID = parentAccount?.id
            store.updateAccount(acc)
            if isPrimary { store.setPrimary(acc) }
        } else {
            let new = Account(name: trimmed,
                              category: category,
                              initialBalance: initialBalance,
                              isAvailable: isAvailable,
                              isPrimary: isPrimary,
                              parentAccountID: parentAccount?.id)
            store.addAccount(new)
            if isPrimary {
                store.setPrimary(new)
            }
        }
        Haptics.success()
        dismiss()
    }
}
