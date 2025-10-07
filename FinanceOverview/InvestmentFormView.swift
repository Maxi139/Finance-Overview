import SwiftUI

struct InvestmentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: FinanceStore
    
    @State private var name: String = ""
    @State private var value: Double = 0
    
    var body: some View {
        Form {
            Section("Geldanlage") {
                TextField("Name", text: $name)
                HStack {
                    Text("Wert")
                    Spacer()
                    TextField("0", value: $value, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                }
            }
        }
        .navigationTitle("Geldanlage hinzufügen")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    store.addInvestment(Investment(name: trimmed, value: value))
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
