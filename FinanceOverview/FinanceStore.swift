import Foundation
import SwiftUI
import Combine

@MainActor
final class FinanceStore: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var transactions: [FinanceTransaction] = []
    @Published var investments: [Investment] = []
    @Published var debts: [Debt] = []
    
    // Globales Erfolgs-Overlay (wird in ContentView angezeigt)
    @Published var successOverlay: SaveSuccessOverlay?
    
    // MARK: - Persistenz
    private var cancellables = Set<AnyCancellable>()
    
    private struct PersistedState: Codable {
        var accounts: [Account]
        var transactions: [FinanceTransaction]
        var investments: [Investment]
        var debts: [Debt] // neu
        
        init(accounts: [Account], transactions: [FinanceTransaction], investments: [Investment], debts: [Debt] = []) {
            self.accounts = accounts
            self.transactions = transactions
            self.investments = investments
            self.debts = debts
        }
        
        // Rückwärtskompatibel laden (debts optional)
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            accounts = try c.decode([Account].self, forKey: .accounts)
            transactions = try c.decode([FinanceTransaction].self, forKey: .transactions)
            investments = try c.decode([Investment].self, forKey: .investments)
            debts = try c.decodeIfPresent([Debt].self, forKey: .debts) ?? []
        }
    }
    
    private static let appFolderName = "FinanceOverview"
    private var stateFileURL: URL {
        let fm = FileManager.default
        let base = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = base.appendingPathComponent(Self.appFolderName, isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent("state.json")
    }
    
    init() {
        // Beim Start aus Persistenz laden (falls vorhanden), sonst leer starten.
        loadFromDisk()
        setupAutosave()
    }
    
    private func setupAutosave() {
        // Speichere bei jeder Änderung (leicht gedrosselt) den gesamten Zustand.
        Publishers.CombineLatest3($accounts, $transactions, $investments)
            .combineLatest($debts)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] combined, debts in
                guard let self else { return }
                let (accs, txs, invs) = combined
                let snapshot = PersistedState(accounts: accs, transactions: txs, investments: invs, debts: debts)
                self.saveToDisk(snapshot)
            }
            .store(in: &cancellables)
    }
    
    private func loadFromDisk() {
        let url = stateFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Keine Datei: leer starten
            accounts = []
            transactions = []
            investments = []
            debts = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
            accounts = decoded.accounts
            transactions = decoded.transactions
            investments = decoded.investments
            debts = decoded.debts
        } catch {
            // Falls etwas schiefgeht, leer starten (und Log ausgeben)
            print("Persistenz laden fehlgeschlagen:", error)
            accounts = []
            transactions = []
            investments = []
            debts = []
        }
    }
    
    private func saveToDisk(_ state: PersistedState) {
        let url = stateFileURL
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("Persistenz speichern fehlgeschlagen:", error)
        }
    }
    
    // MARK: - Mock-Daten
    func loadMockData() {
        // Konten
        let giro = Account(name: "Hauptkonto", category: .giro, initialBalance: 2500, isAvailable: true, isPrimary: true)
        let unterkonto = Account(name: "Haushalt (Unterkonto)", category: .giro, initialBalance: 300, isAvailable: true, isPrimary: false, parentAccountID: giro.id)
        let tagesgeld = Account(name: "Tagesgeld", category: .tagesgeld, initialBalance: 5200, isAvailable: true)
        let festgeld = Account(name: "Festgeld 12M", category: .festgeld, initialBalance: 10000, isAvailable: false)
        let brokerage = Account(name: "Brokerage", category: .andereAnlagen, initialBalance: 0, isAvailable: false)
        accounts = [giro, unterkonto, tagesgeld, festgeld, brokerage]
        
        // Geldanlagen
        investments = [
            Investment(name: "ETF World", value: 7300),
            Investment(name: "Tagesgeld Extra", value: 1200)
        ]
        
        // Buchungen (letzte Monate)
        let cal = Calendar.current
        func d(_ y:Int,_ m:Int,_ d:Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }
        let y = cal.component(.year, from: Date())
        let mNow = cal.component(.month, from: Date())
        
        var sample: [FinanceTransaction] = [
            .init(date: Date(), name: "Bäcker Müller", amount: -8.40, kind: .expense, accountID: accounts[0].id, note: "Frühstück"),
            .init(date: Date(), name: "Gehalt", amount: 3200.0, kind: .income, accountID: accounts[0].id),
            .init(date: Date().addingTimeInterval(-86400*2), name: "Supermarkt EDEKA", amount: -54.90, kind: .expense, accountID: accounts[1].id),
            .init(date: Date().addingTimeInterval(-86400*6), name: "Miete", amount: -980.0, kind: .expense, accountID: accounts[0].id),
            .init(date: Date().addingTimeInterval(-86400*12), name: "Sparen → Tagesgeld", amount: 200.0, kind: .transfer, fromAccountID: accounts[0].id, toAccountID: accounts[2].id, note: "Monatlich"),
        ]
        // ein paar Monatswerte für Statistik:
        for i in 1...8 {
            let month = ((mNow - i - 1 + 12) % 12) + 1
            sample.append(.init(date: d(y, month, 5), name: "Miete", amount: -960, kind: .expense, accountID: accounts[0].id))
            sample.append(.init(date: d(y, month, 12), name: "Supermarkt REWE", amount: Double(-20 * (2 + (i%3))), kind: .expense, accountID: accounts[1].id))
            sample.append(.init(date: d(y, month, 28), name: "Gehalt", amount: 3100 + Double(20*i), kind: .income, accountID: accounts[0].id))
        }
        transactions = sample.sorted { $0.date > $1.date }
        
        // Beispiel-Schulden
        debts = [
            Debt(title: "Leihen für Umzug", amount: 150, direction: .iOwe, dueDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()), accountID: accounts[0].id, note: nil),
            Debt(title: "Peter hat mir Essen bezahlt", amount: 25, direction: .owedToMe, dueDate: nil, accountID: nil, note: "überweisen")
        ]
    }
    
    // MARK: - Berechnungen
    func balance(for account: Account) -> Double {
        var bal = account.initialBalance
        for t in transactions {
            switch t.kind {
            case .expense:
                if t.accountID == account.id { bal += t.amount } // amount ist negativ
            case .income:
                if t.accountID == account.id { bal += t.amount }
            case .transfer:
                if t.fromAccountID == account.id { bal -= t.amount }
                if t.toAccountID == account.id { bal += t.amount }
            }
        }
        return bal
    }
    
    var primaryAccount: Account? {
        accounts.first(where: { $0.isPrimary })
    }
    
    var availableSum: Double {
        accounts.filter { $0.isAvailable }.map { balance(for: $0) }.reduce(0, +)
    }
    
    // Netto-Schulden/Forderungen aus offenen (nicht erledigten) Einträgen:
    // owedToMe -> positiv, iOwe -> negativ
    var netOpenDebts: Double {
        debts.filter { !$0.isSettled }.reduce(0) { acc, d in
            acc + (d.direction == .owedToMe ? d.amount : -d.amount)
        }
    }
    
    var totalValue: Double {
        let accountsSum = accounts.map { balance(for: $0) }.reduce(0, +)
        let investmentsSum = investments.map(\.value).reduce(0, +)
        // Schulden/Forderungen mit einrechnen:
        return accountsSum + investmentsSum + netOpenDebts
    }
    
    // MARK: - Mutationen
    func setPrimary(_ account: Account) {
        accounts = accounts.map { acc in
            var copy = acc
            copy.isPrimary = (acc.id == account.id)
            return copy
        }
    }
    
    func addAccount(_ account: Account) {
        accounts.append(account)
    }
    
    func updateAccount(_ account: Account) {
        if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[idx] = account
        }
    }
    
    func removeAccount(_ account: Account) {
        // Unterkonten mit löschen
        let idsToRemove: Set<UUID> = Set([account.id]) + accounts.filter { $0.parentAccountID == account.id }.map(\.id)
        accounts.removeAll { idsToRemove.contains($0.id) }
        // Transaktionen, die diese Konten betreffen, beibehalten (historisch)
        // Schulden, die an dieses Konto gebunden sind, bleiben bestehen (historisch) – optional könnte man accountID nil setzen.
    }
    
    func addInvestment(_ inv: Investment) { investments.append(inv) }
    func removeInvestment(_ inv: Investment) { investments.removeAll { $0.id == inv.id } }
    
    func addTransaction(_ t: FinanceTransaction) {
        transactions.insert(t, at: 0)
    }
    
    func updateTransaction(_ t: FinanceTransaction) {
        if let idx = transactions.firstIndex(where: { $0.id == t.id }) {
            transactions[idx] = t
            transactions.sort { $0.date > $1.date }
        }
    }
    
    func removeTransaction(_ t: FinanceTransaction) {
        transactions.removeAll { $0.id == t.id }
    }
    
    // MARK: - Schulden
    func addDebt(_ d: Debt) {
        debts.insert(d, at: 0)
    }
    func updateDebt(_ d: Debt) {
        if let idx = debts.firstIndex(where: { $0.id == d.id }) {
            debts[idx] = d
        }
    }
    func removeDebt(_ d: Debt) {
        debts.removeAll { $0.id == d.id }
    }
    func toggleSettled(_ d: Debt) {
        if let idx = debts.firstIndex(where: { $0.id == d.id }) {
            debts[idx].isSettled.toggle()
        }
    }
    
    // MARK: - Datenverwaltung (für Onboarding/Einstellungen)
    func resetToEmpty() {
        accounts.removeAll()
        transactions.removeAll()
        investments.removeAll()
        debts.removeAll()
        // Autosave greift, aber wir speichern zusätzlich direkt:
        let empty = PersistedState(accounts: [], transactions: [], investments: [], debts: [])
        saveToDisk(empty)
    }
    
    func loadDemoData() {
        loadMockData()
        let snapshot = PersistedState(accounts: accounts, transactions: transactions, investments: investments, debts: debts)
        saveToDisk(snapshot)
    }
    
    // MARK: - CSV Import (Komma-getrennt)
    // Erwartetes Format pro Zeile: Name,Datum,Betrag
    // Datum: dd.MM.yy (z. B. 15.09.25)
    // Betrag: negativ = Ausgabe, positiv = Einnahme
    // Felder dürfen in "Anführungszeichen" stehen; eingebettete Kommas werden dann korrekt behandelt.
    func importCSV(from url: URL, to account: Account) -> Int {
        var imported: [FinanceTransaction] = []
        
        let needsSecurity = url.startAccessingSecurityScopedResource()
        defer { if needsSecurity { url.stopAccessingSecurityScopedResource() } }
        
        guard let data = try? Data(contentsOf: url) else { return 0 }
        // Versuche UTF-8, sonst ISO Latin 1
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        
        let lines = text.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yy"
        df.locale = Locale(identifier: "de_DE_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        
        for line in lines {
            let parts = splitCSV(line: line, delimiter: ",")
                .map { unquote($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count >= 3 else { continue }
            
            let name = parts[0]
            let dateStr = parts[1]
            let amountStr = parts[parts.count - 1] // falls es mehr Spalten gibt, nimm die letzte als Betrag
            
            guard let date = df.date(from: dateStr) else { continue }
            guard let amount = parseAmount(amountStr) else { continue }
            
            let kind: TransactionKind = amount < 0 ? .expense : .income
            let tx = FinanceTransaction(date: date,
                                        name: name,
                                        amount: amount, // negativ oder positiv gemäß Datei
                                        kind: kind,
                                        accountID: account.id,
                                        note: nil)
            imported.append(tx)
        }
        
        guard !imported.isEmpty else { return 0 }
        transactions.insert(contentsOf: imported, at: 0)
        transactions.sort { $0.date > $1.date }
        return imported.count
    }
    
    // MARK: - CSV Export (gleiches Format)
    // Pro Zeile: Name,Datum,Betrag ; Datum dd.MM.yy ; Betrag mit Komma als Dezimaltrennzeichen.
    // Umbuchungen werden als zwei Zeilen exportiert (−Betrag und +Betrag) mit identischem Namen.
    func exportCSV() -> URL {
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yy"
        df.locale = Locale(identifier: "de_DE_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "de_DE")
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2
        
        func csvEscape(_ s: String) -> String {
            if s.contains(",") || s.contains("\"") || s.contains("\n") {
                let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            return s
        }
        
        var lines: [String] = []
        // Sortiert nach Datum (aufsteigend oder absteigend ist egal – wir nehmen absteigend wie in der UI)
        for t in transactions.sorted(by: { $0.date > $1.date }) {
            switch t.kind {
            case .income, .expense:
                let name = csvEscape(t.name)
                let dateStr = df.string(from: t.date)
                let amountStr = nf.string(from: NSNumber(value: t.amount)) ?? "\(t.amount)"
                lines.append("\(name),\(dateStr),\(amountStr)")
            case .transfer:
                // Zwei Zeilen erzeugen (von / nach), gleicher Name mit Richtung
                let fromName = accounts.first(where: { $0.id == t.fromAccountID })?.name ?? "—"
                let toName   = accounts.first(where: { $0.id == t.toAccountID })?.name ?? "—"
                let baseName = t.name.isEmpty ? "Umbuchung: \(fromName) → \(toName)" : "\(t.name) (\(fromName) → \(toName))"
                let nameEsc = csvEscape(baseName)
                let dateStr = df.string(from: t.date)
                let minusStr = nf.string(from: NSNumber(value: -abs(t.amount))) ?? "\(-abs(t.amount))"
                let plusStr  = nf.string(from: NSNumber(value:  abs(t.amount))) ?? "\( abs(t.amount))"
                lines.append("\(nameEsc),\(dateStr),\(minusStr)")
                lines.append("\(nameEsc),\(dateStr),\(plusStr)")
            }
        }
        
        let csv = lines.joined(separator: "\n")
        let tmp = FileManager.default.temporaryDirectory
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = tmp.appendingPathComponent("Buchungen-\(ts).csv")
        try? csv.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
    
    // MARK: - CSV Hilfen
    // Spaltet eine CSV-Zeile anhand des Delimiters und beachtet Anführungszeichen und doppelte Quotes.
    private func splitCSV(line: String, delimiter: Character) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        
        while i < line.endIndex {
            let ch = line[i]
            if ch == "\"" {
                // Doppelte Anführungszeichen innerhalb eines quoted Felds -> als ein Quote interpretieren
                let nextIndex = line.index(after: i)
                if inQuotes && nextIndex < line.endIndex && line[nextIndex] == "\"" {
                    current.append("\"")
                    i = nextIndex
                } else {
                    inQuotes.toggle()
                }
            } else if ch == delimiter && !inQuotes {
                result.append(current)
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(ch)
            }
            i = line.index(after: i)
        }
        result.append(current)
        return result
    }
    
    private func unquote(_ s: String) -> String {
        var out = s
        if out.hasPrefix("\"") && out.hasSuffix("\"") && out.count >= 2 {
            out.removeFirst()
            out.removeLast()
        }
        return out
    }
    
    private func parseAmount(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Währungen/Leerzeichen entfernen
        s = s.replacingOccurrences(of: "€", with: "")
             .replacingOccurrences(of: " ", with: "")
        // Tausenderpunkte entfernen, Dezimalkomma in Punkt wandeln
        s = s.replacingOccurrences(of: ".", with: "")
             .replacingOccurrences(of: ",", with: ".")
        // Plus/Minus zulassen
        return Double(s)
    }
    
    // MARK: - Voll-Backup Export/Import (Alles)
    struct FullExport: Codable {
        struct SettingsData: Codable {
            var appearanceMode: String
            var didSeeOnboarding: Bool
        }
        var version: Int
        var createdAt: Date
        var accounts: [Account]
        var transactions: [FinanceTransaction]
        var investments: [Investment]
        var debts: [Debt]
        var settings: SettingsData
    }
    
    func exportAll() -> URL {
        let defaults = UserDefaults.standard
        let appearance = defaults.string(forKey: "appearanceMode") ?? AppearanceMode.system.rawValue
        let seenOnboarding = defaults.bool(forKey: "didSeeOnboarding")
        
        let bundle = FullExport(
            version: 1,
            createdAt: Date(),
            accounts: accounts,
            transactions: transactions,
            investments: investments,
            debts: debts,
            settings: .init(appearanceMode: appearance, didSeeOnboarding: seenOnboarding)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let tmp = FileManager.default.temporaryDirectory
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = tmp.appendingPathComponent("FinanceOverview-Backup-\(ts).json")
        do {
            let data = try encoder.encode(bundle)
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            print("ExportAll fehlgeschlagen:", error)
            // Fallback: leere Datei
            try? Data().write(to: url)
            return url
        }
    }
    
    func importAll(from url: URL) throws {
        let needsSecurity = url.startAccessingSecurityScopedResource()
        defer { if needsSecurity { url.stopAccessingSecurityScopedResource() } }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode(FullExport.self, from: data)
        
        // Zustand ersetzen
        self.accounts = imported.accounts
        self.transactions = imported.transactions.sorted { $0.date > $1.date }
        self.investments = imported.investments
        self.debts = imported.debts
        
        // Einstellungen setzen
        let defaults = UserDefaults.standard
        defaults.set(imported.settings.appearanceMode, forKey: "appearanceMode")
        defaults.set(imported.settings.didSeeOnboarding, forKey: "didSeeOnboarding")
        
        // Persistieren (Autosave greift, aber wir speichern auch sofort)
        let snapshot = PersistedState(accounts: accounts, transactions: transactions, investments: investments, debts: debts)
        saveToDisk(snapshot)
    }
}

// kleines Hilfs-+ für Set
fileprivate func +<T>(lhs: Set<T>, rhs: [T]) -> Set<T> where T: Hashable { lhs.union(rhs) }
