import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var store: FinanceStore
    
    enum TimeRange: String, CaseIterable, Identifiable {
        case sixM = "6M", oneY = "12M", twoY = "24M", all = "Alle"
        var id: String { rawValue }
        var months: Int? {
            switch self {
            case .sixM: return 6
            case .oneY: return 12
            case .twoY: return 24
            case .all: return nil
            }
        }
    }
    
    @State private var range: TimeRange = .oneY
    
    // MARK: - Derived series (robust gegen leere Zeiträume)
    private var monthAxis: [Date] {
        // Erzeuge konsistente Monatsachse (aufwärts sortiert)
        let cal = Calendar.current
        let end = cal.date(from: cal.dateComponents([.year, .month], from: Date()))! // Start des aktuellen Monats
        let count: Int = {
            if let m = range.months { return max(m, 1) }
            // "Alle": nutze Spannweite der Daten, mindestens 6 Monate
            let months = spanInMonths()
            return max(months, 6)
        }()
        return monthsArray(endingAt: end, count: count)
    }
    private var incomeByMonth: [Date: Double] {
        sumByMonth(kind: .income)
    }
    private var expenseByMonth: [Date: Double] {
        sumByMonth(kind: .expense) // bereits positiv summiert
    }
    private var incomeSeries: [MonthlyPoint] {
        monthAxis.map { MonthlyPoint(month: $0, value: incomeByMonth[$0] ?? 0) }
    }
    private var expenseSeries: [MonthlyPoint] {
        monthAxis.map { MonthlyPoint(month: $0, value: expenseByMonth[$0] ?? 0) }
    }
    private var cashflowSeries: [MonthlyPoint] {
        zip(incomeSeries, expenseSeries).map { MonthlyPoint(month: $0.month, value: $0.value - $1.value) }
    }
    
    // KPIs
    private var kpis: (net: Double, avgExp: Double, avgInc: Double, savingsRate: Double) {
        let ex = expenseSeries.map(\.value)
        let inc = incomeSeries.map(\.value)
        let avgExp = ex.isEmpty ? 0 : ex.reduce(0,+) / Double(ex.count)
        let avgInc = inc.isEmpty ? 0 : inc.reduce(0,+) / Double(inc.count)
        let net = inc.reduce(0,+) - ex.reduce(0,+)
        let totalInc = inc.reduce(0,+)
        let savingsRate = totalInc > 0 ? net / totalInc : 0
        return (net, avgExp, avgInc, savingsRate)
    }
    
    // Top Orte (Ausgaben)
    private var topExpensePlaces: [TopPlace] {
        let txs = filteredTransactions().filter { $0.kind == .expense }
        let grouped = Dictionary(grouping: txs, by: { $0.name })
        let sums = grouped.map { (name, txs) -> TopPlace in
            let total = txs.map { -$0.amount }.reduce(0, +)
            return TopPlace(name: name, value: total)
        }
        return Array(sums.sorted { $0.value > $1.value }.prefix(6))
    }
    
    // Ausgaben nach Kontokategorie
    private var expenseByAccountCategory: [(AccountCategory, Double)] {
        let txs = filteredTransactions().filter { $0.kind == .expense }
        var dict: [AccountCategory: Double] = [:]
        for t in txs {
            if let id = t.accountID,
               let cat = store.accounts.first(where: { $0.id == id })?.category {
                dict[cat, default: 0] += -t.amount
            }
        }
        return AccountCategory.allCases
            .map { ($0, dict[$0] ?? 0) }
            .filter { $0.1 > 0 }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Filter
                    Picker("Zeitraum", selection: $range) {
                        ForEach(TimeRange.allCases) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    // KPIs
                    HStack(spacing: 12) {
                        card(title: "Netto", value: formatCurrency(kpis.net), color: .accentColor)
                        card(title: "Ø Ausgaben", value: formatCurrency(kpis.avgExp), color: .red)
                        card(title: "Ø Einnahmen", value: formatCurrency(kpis.avgInc), color: .green)
                    }
                    card(title: "Sparquote", value: percentString(kpis.savingsRate), color: .blue)
                    
                    // Chart: Ausgaben & Einnahmen
                    cardContainer(title: "Monatliche Ausgaben & Einnahmen") {
                        if incomeSeries.allSatisfy({ $0.value == 0 }) && expenseSeries.allSatisfy({ $0.value == 0 }) {
                            placeholder("Keine Daten im ausgewählten Zeitraum")
                        } else {
                            Chart {
                                ForEach(expenseSeries) { p in
                                    AreaMark(
                                        x: .value("Monat", p.month, unit: .month),
                                        y: .value("Ausgaben", p.value)
                                    )
                                    .foregroundStyle(LinearGradient(colors: [.red.opacity(0.5), .clear],
                                                                   startPoint: .top, endPoint: .bottom))
                                    LineMark(
                                        x: .value("Monat", p.month, unit: .month),
                                        y: .value("Ausgaben", p.value)
                                    )
                                    .foregroundStyle(.red)
                                    .interpolationMethod(.monotone)
                                }
                                ForEach(incomeSeries) { p in
                                    AreaMark(
                                        x: .value("Monat", p.month, unit: .month),
                                        y: .value("Einnahmen", p.value)
                                    )
                                    .foregroundStyle(LinearGradient(colors: [.green.opacity(0.45), .clear],
                                                                   startPoint: .top, endPoint: .bottom))
                                    LineMark(
                                        x: .value("Monat", p.month, unit: .month),
                                        y: .value("Einnahmen", p.value)
                                    )
                                    .foregroundStyle(.green)
                                    .interpolationMethod(.monotone)
                                }
                            }
                            .frame(height: 260)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .month)) { _ in
                                    AxisGridLine()
                                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                                }
                            }
                            .chartYAxis {
                                AxisMarks { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let v = value.as(Double.self) {
                                            Text(formatCurrency(v))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Cashflow
                    cardContainer(title: "Cashflow (Einnahmen − Ausgaben)") {
                        if cashflowSeries.allSatisfy({ $0.value == 0 }) {
                            placeholder("Keine Daten im ausgewählten Zeitraum")
                        } else {
                            Chart {
                                ForEach(cashflowSeries) { p in
                                    LineMark(
                                        x: .value("Monat", p.month, unit: .month),
                                        y: .value("Cashflow", p.value)
                                    )
                                    .foregroundStyle(Color.accentColor)
                                    .interpolationMethod(.monotone)
                                    AreaMark(
                                        x: .value("Monat", p.month, unit: .month),
                                        y: .value("Cashflow", p.value)
                                    )
                                    .foregroundStyle(LinearGradient(colors: [.accentColor.opacity(0.35), .clear],
                                                                   startPoint: .top, endPoint: .bottom))
                                }
                            }
                            .frame(height: 220)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .month)) { _ in
                                    AxisGridLine()
                                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                                }
                            }
                            .chartYAxis {
                                AxisMarks { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let v = value.as(Double.self) {
                                            Text(formatCurrency(v))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Top Ausgabenorte
                    cardContainer(title: "Top Ausgabenorte") {
                        if topExpensePlaces.isEmpty {
                            placeholder("Keine Ausgaben im Zeitraum")
                        } else {
                            Chart(topExpensePlaces) { item in
                                BarMark(
                                    x: .value("Betrag", item.value),
                                    y: .value("Ort", item.name)
                                )
                                .foregroundStyle(.blue.gradient)
                            }
                            .frame(height: CGFloat(max(220, topExpensePlaces.count * 36)))
                            .chartXAxis {
                                AxisMarks { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let v = value.as(Double.self) {
                                            Text(formatCurrency(v))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Ausgaben nach Kontokategorie
                    cardContainer(title: "Ausgaben nach Kontokategorie") {
                        if expenseByAccountCategory.isEmpty {
                            placeholder("Keine Ausgaben im Zeitraum")
                        } else {
                            Chart {
                                ForEach(expenseByAccountCategory, id: \.0) { (cat, value) in
                                    BarMark(
                                        x: .value("Betrag", value),
                                        y: .value("Kategorie", cat.rawValue)
                                    )
                                    .foregroundStyle(Color.accentColor.gradient)
                                }
                            }
                            .frame(height: CGFloat(max(200, expenseByAccountCategory.count * 32)))
                            .chartXAxis {
                                AxisMarks { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let v = value.as(Double.self) {
                                            Text(formatCurrency(v))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Statistiken")
        }
    }
    
    // MARK: Datenaufbereitung
    private func filteredTransactions() -> [FinanceTransaction] {
        let cal = Calendar.current
        let endMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        if let m = range.months {
            let start = cal.date(byAdding: .month, value: -m + 1, to: endMonth)!
            return store.transactions.filter { $0.date >= start && $0.date < cal.date(byAdding: .month, value: 1, to: endMonth)! }
        } else {
            return store.transactions
        }
    }
    
    private func sumByMonth(kind: TransactionKind) -> [Date: Double] {
        let cal = Calendar.current
        let txs = filteredTransactions().filter { $0.kind == kind }
        var dict: [Date: Double] = [:]
        for t in txs {
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: t.date))!
            switch kind {
            case .income:
                dict[monthStart, default: 0] += t.amount
            case .expense:
                dict[monthStart, default: 0] += -t.amount // positiv summieren
            case .transfer:
                break
            }
        }
        return dict
    }
    
    private func monthsArray(endingAt end: Date, count: Int) -> [Date] {
        let cal = Calendar.current
        var months: [Date] = []
        for i in stride(from: count - 1, through: 0, by: -1) {
            if let d = cal.date(byAdding: .month, value: -i, to: end) {
                months.append(d)
            }
        }
        return months
    }
    
    private func spanInMonths() -> Int {
        let cal = Calendar.current
        let dates = store.transactions.map { cal.date(from: cal.dateComponents([.year, .month], from: $0.date))! }
        guard let minD = dates.min(), let maxD = dates.max() else { return 6 }
        let comps = cal.dateComponents([.month], from: minD, to: maxD)
        return (comps.month ?? 0) + 1
    }
    
    // MARK: UI Hilfen
    private func card(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.weight(.semibold)).foregroundStyle(color)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
    
    private func cardContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
    
    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemBackground))
            )
    }
    
    private func percentString(_ value: Double) -> String {
        let pct = max(min(value, 1), -1)
        let nf = NumberFormatter()
        nf.numberStyle = .percent
        nf.maximumFractionDigits = 0
        return nf.string(from: NSNumber(value: pct)) ?? "0%"
    }
}

struct MonthlyPoint: Identifiable, Hashable {
    var id: Date { month }
    let month: Date
    let value: Double
}

struct TopPlace: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let value: Double
}
