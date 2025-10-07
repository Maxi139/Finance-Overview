import Foundation

let currencyFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = Locale.current.currency?.identifier ?? "EUR"
    f.maximumFractionDigits = 2
    return f
}()

func formatCurrency(_ amount: Double) -> String {
    currencyFormatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
}

let dateFormatterShort: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
}()
