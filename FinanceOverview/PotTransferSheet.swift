import SwiftUI

struct PotTransferSheet: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    
    let account: Account
    let pot: SavingsPot
    let toPot: Bool // true = Geld in den Topf, false = aus dem Topf
    
    @State private var amount: Double = 0
    @State private var date: Date = Date()
    @State private var note: String = ""
    
    private var savedInPot: Double {
        store.savedAmount(for: pot)
    }
    private var freeBalance: Double {
        store.freeBalance(for: account)
    }
    
    private var maxAllowed: Double {
        if toPot {
            return max(0, freeBalance)
        } else {
            return max(0, savedInPot)
        }
    }
    private var canSave: Bool {
        amount > 0 && amount <= maxAllowed
    }
    
    var body: some View {
        Form {
            Section(toPot ? "Geld in Topf" : "Geld aus Topf") {
                HStack {
                    Text("Betrag")
                    Spacer()
                    TextField("0", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                }
                DatePicker("Datum", selection: $date, displayedComponents: .date)
                TextField("Notiz (optional)", text: $note)
            }
            Section("Hinweise") {
                HStack {
                    Text("Freier Saldo")
                    Spacer()
                    Text(formatCurrency(freeBalance)).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Im Topf")
                    Spacer()
                    Text(formatCurrency(savedInPot)).foregroundStyle(.secondary)
                }
                if toPot && pot.goal > 0 {
                    let newSaved = savedInPot + amount
                    let progress = min(newSaved / pot.goal, 1.0)
                    ProgressView(value: progress)
                    Text("Nach Zuweisung: \(Int(progress * 100))% des Ziels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(toPot ? "Geld zuweisen" : "Geld entnehmen")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    Haptics.lightTap()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Buchen") {
                    let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                    if toPot {
                        store.moveToPot(account: account, pot: pot, amount: amount, date: date, note: trimmedNote.isEmpty ? nil : trimmedNote)
                    } else {
                        store.moveFromPot(account: account, pot: pot, amount: amount, date: date, note: trimmedNote.isEmpty ? nil : trimmedNote)
                    }
                    Haptics.success()
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }
}

