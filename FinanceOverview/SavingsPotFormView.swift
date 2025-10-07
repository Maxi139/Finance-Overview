import SwiftUI

struct SavingsPotFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: FinanceStore
    
    let original: SavingsPot?
    let account: Account
    var onSave: (SavingsPot) -> Void
    
    @State private var name: String
    @State private var goal: Double
    @State private var note: String
    
    init(original: SavingsPot?, account: Account, onSave: @escaping (SavingsPot) -> Void) {
        self.original = original
        self.account = account
        self.onSave = onSave
        if let pot = original {
            _name = State(initialValue: pot.name)
            _goal = State(initialValue: pot.goal)
            _note = State(initialValue: pot.note ?? "")
        } else {
            _name = State(initialValue: "")
            _goal = State(initialValue: 0)
            _note = State(initialValue: "")
        }
    }
    
    var body: some View {
        Form {
            Section("Spartopf") {
                TextField("Name", text: $name)
                HStack {
                    Text("Ziel")
                    Spacer()
                    TextField("0", value: $goal, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                }
                TextField("Beschreibung (optional)", text: $note, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
            }
            Section {
                HStack {
                    Text("Verfügbarkeit")
                    Spacer()
                    Text(account.isAvailable ? "verfügbar" : "nicht verfügbar")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(original == nil ? "Spartopf erstellen" : "Spartopf bearbeiten")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    Haptics.lightTap()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if var pot = original {
                        pot.name = trimmed
                        pot.goal = goal
                        pot.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
                        onSave(pot)
                    } else {
                        let pot = SavingsPot(accountID: account.id, name: trimmed, goal: goal, note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note)
                        onSave(pot)
                    }
                    Haptics.success()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || goal <= 0)
            }
        }
    }
}

