import SwiftUI

struct DebtFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: FinanceStore
    
    let original: Debt?
    
    @State private var title: String
    @State private var amount: Double
    @State private var direction: DebtDirection
    @State private var dueDate: Date?
    @State private var hasDueDate: Bool
    @State private var account: Account?
    @State private var note: String
    
    init(original: Debt?) {
        self.original = original
        if let d = original {
            _title = State(initialValue: d.title)
            _amount = State(initialValue: d.amount)
            _direction = State(initialValue: d.direction)
            _dueDate = State(initialValue: d.dueDate)
            _hasDueDate = State(initialValue: d.dueDate != nil)
            _account = State(initialValue: nil) // resolve onAppear
            _note = State(initialValue: d.note ?? "")
        } else {
            _title = State(initialValue: "")
            _amount = State(initialValue: 0)
            _direction = State(initialValue: .iOwe)
            _dueDate = State(initialValue: nil)
            _hasDueDate = State(initialValue: false)
            _account = State(initialValue: nil)
            _note = State(initialValue: "")
        }
    }
    
    var body: some View {
        Form {
            Section("Schuld") {
                TextField("Titel", text: $title)
                HStack {
                    Text("Betrag")
                    Spacer()
                    TextField("0", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                }
                Picker("Richtung", selection: $direction) {
                    ForEach(DebtDirection.allCases) { dir in
                        Text(dir.rawValue).tag(dir)
                    }
                }
                Toggle("Fälligkeitsdatum", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Fällig am", selection: Binding(get: {
                        dueDate ?? Date()
                    }, set: { new in
                        dueDate = new
                    }), displayedComponents: .date)
                }
                Picker("Konto (optional)", selection: Binding(
                    get: { account },
                    set: { account = $0 }
                )) {
                    Text("Keines").tag(Optional<Account>.none)
                    ForEach(store.accounts) { acc in
                        Text(acc.name).tag(Optional(acc) as Account?)
                    }
                }
                .pickerStyle(.navigationLink)
                TextField("Notiz", text: $note, axis: .vertical)
            }
        }
        .navigationTitle(original == nil ? "Schuld hinzufügen" : "Schuld bearbeiten")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amount <= 0)
            }
        }
        .onAppear {
            if let d = original, let aid = d.accountID {
                account = store.accounts.first(where: { $0.id == aid })
            }
        }
    }
    
    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalDue = hasDueDate ? dueDate : nil
        if var d = original {
            d.title = trimmed
            d.amount = amount
            d.direction = direction
            d.dueDate = finalDue
            d.accountID = account?.id
            d.note = note.isEmpty ? nil : note
            store.updateDebt(d)
        } else {
            let new = Debt(title: trimmed,
                           amount: amount,
                           direction: direction,
                           dueDate: finalDue,
                           accountID: account?.id,
                           note: note.isEmpty ? nil : note,
                           isSettled: false)
            store.addDebt(new)
        }
        dismiss()
    }
}
