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

// Formats a fractional value (e.g., 0.25) as a localized percentage string (e.g., "25 %")
func percentString(_ fraction: Double, maximumFractionDigits: Int = 0) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.maximumFractionDigits = maximumFractionDigits
    return formatter.string(from: NSNumber(value: fraction)) ?? String(format: "%.0f%%", fraction * 100)
}
