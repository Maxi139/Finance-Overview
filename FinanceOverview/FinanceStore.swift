import Foundation
import SwiftUI
import Combine

@MainActor
final class FinanceStore: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var transactions: [FinanceTransaction] = []
    @Published var investments: [Investment] = []
    @Published var debts: [Debt] = []
    // Neu: Spartöpfe
    @Published var pots: [SavingsPot] = []
    
    // Kategorien (frei definierbar)
    @Published var categories: [TransactionCategory] = []
    // Merker: normalisierter Name (lowercased, trimmed) -> CategoryID
    @Published private var categoryMemory: [String: UUID] = [:]
    
    // Globales Erfolgs-Overlay (wird in ContentView angezeigt)
    @Published var successOverlay: SaveSuccessOverlay?
    
    // Neu: Celebration-Overlay für Spartopf-Ziel
    @Published var potCelebration: PotCelebrationOverlay?
    
    // MARK: - Persistenz
    private var cancellables = Set<AnyCancellable>()
    
    private struct PersistedState: Codable {
        var accounts: [Account]
        var transactions: [FinanceTransaction]
        var investments: [Investment]
        var debts: [Debt]
        var categories: [TransactionCategory]
        var categoryMemory: [String: UUID]
        var pots: [SavingsPot] // neu
        
        init(accounts: [Account], transactions: [FinanceTransaction], investments: [Investment], debts: [Debt] = [], categories: [TransactionCategory] = [], categoryMemory: [String: UUID] = [:], pots: [SavingsPot] = []) {
            self.accounts = accounts
            self.transactions = transactions
            self.investments = investments
            self.debts = debts
            self.categories = categories
            self.categoryMemory = categoryMemory
            self.pots = pots
        }
        
        // Rückwärtskompatibel laden
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            accounts = try c.decode([Account].self, forKey: .accounts)
            transactions = try c.decode([FinanceTransaction].self, forKey: .transactions)
            investments = try c.decode([Investment].self, forKey: .investments)
            debts = try c.decodeIfPresent([Debt].self, forKey: .debts) ?? []
            categories = try c.decodeIfPresent([TransactionCategory].self, forKey: .categories) ?? []
            categoryMemory = try c.decodeIfPresent([String: UUID].self, forKey: .categoryMemory) ?? [:]
            pots = try c.decodeIfPresent([SavingsPot].self, forKey: .pots) ?? []
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
        loadFromDisk()
        setupAutosave()
    }
    
    private func setupAutosave() {
        // Speichere bei jeder Änderung (leicht gedrosselt) den gesamten Zustand.
        Publishers.CombineLatest4($accounts, $transactions, $investments, $debts)
            .combineLatest($categories, $categoryMemory, $pots)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] combined, cats, memory, pots in
                guard let self else { return }
                let (accs, txs, invs, debts) = combined
                let snapshot = PersistedState(accounts: accs, transactions: txs, investments: invs, debts: debts, categories: cats, categoryMemory: memory, pots: pots)
                self.saveToDisk(snapshot)
            }
            .store(in: &cancellables)
    }
    
    private func loadFromDisk() {
        let url = stateFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            accounts = []
            transactions = []
            investments = []
            debts = []
            categories = defaultSeedCategories()
            categoryMemory = [:]
            pots = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
            accounts = decoded.accounts
            transactions = decoded.transactions
            investments = decoded.investments
            debts = decoded.debts
            categories = decoded.categories.isEmpty ? defaultSeedCategories() : decoded.categories
            categoryMemory = decoded.categoryMemory
            pots = decoded.pots
            // Sortiere Transaktionen absteigend nach Datum
            transactions.sort { $0.date > $1.date }
        } catch {
            print("Persistenz laden fehlgeschlagen:", error)
            accounts = []
            transactions = []
            investments = []
            debts = []
            categories = defaultSeedCategories()
            categoryMemory = [:]
            pots = []
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
    
    // Seed ein paar sinnvolle Kategorien
    private func defaultSeedCategories() -> [TransactionCategory] {
        [
            TransactionCategory(name: "Lebensmittel", color: .init(r: 0.20, g: 0.70, b: 0.35)),
            TransactionCategory(name: "Gehalt", color: .init(r: 0.10, g: 0.60, b: 0.95)),
            TransactionCategory(name: "Miete", color: .init(r: 0.90, g: 0.30, b: 0.30)),
            TransactionCategory(name: "Transport", color: .init(r: 0.95, g: 0.70, b: 0.10)),
            TransactionCategory(name: "Freizeit", color: .init(r: 0.70, g: 0.40, b: 0.90))
        ]
    }
    
    // MARK: - Mock-Daten
    func loadMockData() {
        let giro = Account(name: "Hauptkonto", category: .giro, initialBalance: 2500, isAvailable: true, isPrimary: true)
        let unterkonto = Account(name: "Haushalt (Unterkonto)", category: .giro, initialBalance: 300, isAvailable: true, isPrimary: false, parentAccountID: giro.id)
        let tagesgeld = Account(name: "Tagesgeld", category: .tagesgeld, initialBalance: 5200, isAvailable: true)
        let festgeld = Account(name: "Festgeld 12M", category: .festgeld, initialBalance: 10000, isAvailable: false)
        let brokerage = Account(name: "Brokerage", category: .andereAnlagen, initialBalance: 0, isAvailable: false)
        accounts = [giro, unterkonto, tagesgeld, festgeld, brokerage]
        
        investments = [
            Investment(name: "ETF World", value: 7300),
            Investment(name: "Tagesgeld Extra", value: 1200)
        ]
        
        if categories.isEmpty {
            categories = defaultSeedCategories()
        }
        
        var sample: [FinanceTransaction] = [
            .init(date: Date(), name: "Bäcker Müller", amount: -8.40, kind: .expense, accountID: accounts[0].id, note: "Frühstück", categoryID: categories.first?.id),
            .init(date: Date(), name: "Gehalt", amount: 3200.0, kind: .income, accountID: accounts[0].id, categoryID: categories.first(where: { $0.name == "Gehalt" })?.id),
            .init(date: Date().addingTimeInterval(-86400*2), name: "Supermarkt EDEKA", amount: -54.90, kind: .expense, accountID: accounts[1].id, categoryID: categories.first(where: { $0.name == "Lebensmittel" })?.id),
            .init(date: Date().addingTimeInterval(-86400*6), name: "Miete", amount: -980.0, kind: .expense, accountID: accounts[0].id, categoryID: categories.first(where: { $0.name == "Miete" })?.id),
            .init(date: Date().addingTimeInterval(-86400*12), name: "Sparen → Tagesgeld", amount: 200.0, kind: .transfer, fromAccountID: accounts[0].id, toAccountID: accounts[2].id, note: "Monatlich")
        ]
        // weitere Monate (wie bisher)
        transactions = sample.sorted { $0.date > $1.date }
        
        debts = [
            Debt(title: "Leihen für Umzug", amount: 150, direction: .iOwe, dueDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()), accountID: accounts[0].id, note: nil),
            Debt(title: "Peter hat mir Essen bezahlt", amount: 25, direction: .owedToMe, dueDate: nil, accountID: nil, note: "überweisen")
        ]
        
        // Beispiel-Spartöpfe
        pots = [
            SavingsPot(accountID: giro.id, name: "Urlaub", goal: 1200, note: "Sommerreise"),
            SavingsPot(accountID: giro.id, name: "Notgroschen", goal: 3000, note: nil)
        ]
        
        learnCategory(forName: "Bäcker Müller", categoryID: categories.first(where: { $0.name == "Lebensmittel" })?.id)
        learnCategory(forName: "Supermarkt EDEKA", categoryID: categories.first(where: { $0.name == "Lebensmittel" })?.id)
        learnCategory(forName: "Supermarkt REWE", categoryID: categories.first(where: { $0.name == "Lebensmittel" })?.id)
        learnCategory(forName: "Miete", categoryID: categories.first(where: { $0.name == "Miete" })?.id)
        learnCategory(forName: "Gehalt", categoryID: categories.first(where: { $0.name == "Gehalt" })?.id)
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
    
    // Summe aktuell im Topf (aus Transaktionen abgeleitet)
    func savedAmount(for pot: SavingsPot) -> Double {
        var sum: Double = 0
        for t in transactions where t.kind == .transfer && t.fromAccountID == pot.accountID && t.toAccountID == pot.accountID {
            if t.toPotID == pot.id { sum += t.amount }
            if t.fromPotID == pot.id { sum -= t.amount }
        }
        return max(0, sum)
    }
    
    // Summe in allen Töpfen eines Kontos
    func totalSavedInPots(for account: Account) -> Double {
        pots.filter { $0.accountID == account.id }.map { savedAmount(for: $0) }.reduce(0, +)
    }
    
    // Freier Saldo = Kontosaldo - in Töpfen gebunden
    func freeBalance(for account: Account) -> Double {
        balance(for: account) - totalSavedInPots(for: account)
    }
    
    var primaryAccount: Account? {
        accounts.first(where: { $0.isPrimary })
    }
    
    var availableSum: Double {
        accounts.filter { $0.isAvailable }.map { balance(for: $0) }.reduce(0, +)
    }
    
    var netOpenDebts: Double {
        debts.filter { !$0.isSettled }.reduce(0) { acc, d in
            acc + (d.direction == .owedToMe ? d.amount : -d.amount)
        }
    }
    
    var totalValue: Double {
        let accountsSum = accounts.map { balance(for: $0) }.reduce(0, +)
        let investmentsSum = investments.map(\.value).reduce(0, +)
        return accountsSum + investmentsSum + netOpenDebts
    }
    
    // MARK: - Mutationen Konten/Transaktionen/… (unverändert + Pots)
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
        let idsToRemove: Set<UUID> = Set([account.id]) + accounts.filter { $0.parentAccountID == account.id }.map(\.id)
        // Entferne zugehörige Töpfe
        pots.removeAll { idsToRemove.contains($0.accountID) }
        accounts.removeAll { idsToRemove.contains($0.id) }
    }
    
    func addInvestment(_ inv: Investment) { investments.append(inv) }
    func removeInvestment(_ inv: Investment) { investments.removeAll { $0.id == inv.id } }
    
    func addTransaction(_ t: FinanceTransaction) {
        // Vorher: Zielprüfung für Töpfe, wir brauchen saved-before/after nur bei toPot-Transfers
        var preSavedByPotID: Double?
        var affectedPot: SavingsPot?
        if t.kind == .transfer, let toPotID = t.toPotID, let pot = pots.first(where: { $0.id == toPotID }) {
            affectedPot = pot
            preSavedByPotID = savedAmount(for: pot)
        }
        
        var tx = t
        if tx.categoryID == nil, t.kind != .transfer, let suggested = suggestedCategoryID(forName: t.name) {
            tx.categoryID = suggested
        }
        transactions.insert(tx, at: 0)
        transactions.sort { $0.date > $1.date }
        if let cat = tx.categoryID, t.kind != .transfer {
            learnCategory(forName: tx.name, categoryID: cat)
        }
        
        // Nachher: prüfen, ob Topf-Ziel überschritten/erreicht wurde
        if let pot = affectedPot, let before = preSavedByPotID {
            let after = savedAmount(for: pot)
            if pot.goal > 0, before < pot.goal, after >= pot.goal {
                // Celebration triggern
                potCelebration = PotCelebrationOverlay(potName: pot.name, goal: pot.goal, saved: after)
            }
        }
    }
    
    func updateTransaction(_ t: FinanceTransaction) {
        if let idx = transactions.firstIndex(where: { $0.id == t.id }) {
            transactions[idx] = t
            transactions.sort { $0.date > $1.date }
            if t.kind != .transfer, let cat = t.categoryID {
                learnCategory(forName: t.name, categoryID: cat)
            }
        }
    }
    
    func removeTransaction(_ t: FinanceTransaction) {
        transactions.removeAll { $0.id == t.id }
    }
    
    // MARK: - Spartöpfe API
    func pots(for account: Account) -> [SavingsPot] {
        pots.filter { $0.accountID == account.id }
    }
    
    func addPot(_ pot: SavingsPot) {
        pots.append(pot)
    }
    
    func updatePot(_ pot: SavingsPot) {
        if let idx = pots.firstIndex(where: { $0.id == pot.id }) {
            pots[idx] = pot
        }
    }
    
    func removePot(_ pot: SavingsPot) {
        // Optional: Transaktionen belassen (Historie) – savedAmount wird dann 0, da keine Moves mehr möglich.
        pots.removeAll { $0.id == pot.id }
    }
    
    // Geld in Topf verschieben (vom Hauptsaldo in Topf)
    func moveToPot(account: Account, pot: SavingsPot, amount: Double, date: Date = Date(), note: String? = nil) {
        guard pot.accountID == account.id, amount > 0 else { return }
        let name = "In Topf: \(pot.name)"
        let tx = FinanceTransaction(
            date: date,
            name: name,
            amount: amount,
            kind: .transfer,
            fromAccountID: account.id,
            toAccountID: account.id,
            fromPotID: nil,
            toPotID: pot.id,
            note: note,
            categoryID: nil
        )
        addTransaction(tx)
    }
    
    // Geld aus Topf zurück zum Hauptsaldo
    func moveFromPot(account: Account, pot: SavingsPot, amount: Double, date: Date = Date(), note: String? = nil) {
        guard pot.accountID == account.id, amount > 0 else { return }
        let name = "Aus Topf: \(pot.name)"
        let tx = FinanceTransaction(
            date: date,
            name: name,
            amount: amount,
            kind: .transfer,
            fromAccountID: account.id,
            toAccountID: account.id,
            fromPotID: pot.id,
            toPotID: nil,
            note: note,
            categoryID: nil
        )
        addTransaction(tx)
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
    
    // MARK: - Kategorien Management (unverändert)
    func addCategory(name: String, color: Color) -> TransactionCategory {
        let new = TransactionCategory(name: name, color: ColorValue(color: color))
        categories.append(new)
        return new
    }
    
    func updateCategory(_ category: TransactionCategory) {
        if let idx = categories.firstIndex(where: { $0.id == category.id }) {
            categories[idx] = category
        }
    }
    
    func removeCategory(_ category: TransactionCategory) {
        categories.removeAll { $0.id == category.id }
        for i in transactions.indices {
            if transactions[i].categoryID == category.id {
                transactions[i].categoryID = nil
            }
        }
        categoryMemory = categoryMemory.filter { $0.value != category.id }
    }
    
    func category(by id: UUID?) -> TransactionCategory? {
        guard let id else { return nil }
        return categories.first(where: { $0.id == id })
    }
    
    // MARK: - Kategorie Memory
    private func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    func learnCategory(forName name: String, categoryID: UUID?) {
        guard let categoryID else { return }
        let key = normalized(name)
        guard !key.isEmpty else { return }
        categoryMemory[key] = categoryID
    }
    func suggestedCategoryID(forName name: String) -> UUID? {
        categoryMemory[normalized(name)]
    }
    
    // MARK: - Datenverwaltung
    func resetToEmpty() {
        accounts.removeAll()
        transactions.removeAll()
        investments.removeAll()
        debts.removeAll()
        pots.removeAll()
        categories = defaultSeedCategories()
        categoryMemory = [:]
        let empty = PersistedState(accounts: [], transactions: [], investments: [], debts: [], categories: categories, categoryMemory: categoryMemory, pots: [])
        saveToDisk(empty)
    }
    
    func loadDemoData() {
        loadMockData()
        let snapshot = PersistedState(accounts: accounts, transactions: transactions, investments: investments, debts: debts, categories: categories, categoryMemory: categoryMemory, pots: pots)
        saveToDisk(snapshot)
    }
    
    // MARK: - CSV Import/Export (unverändert)
    func importCSV(from url: URL, to account: Account) -> Int {
        var imported: [FinanceTransaction] = []
        
        let needsSecurity = url.startAccessingSecurityScopedResource()
        defer { if needsSecurity { url.stopAccessingSecurityScopedResource() } }
        
        guard let data = try? Data(contentsOf: url) else { return 0 }
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
            let amountStr = parts[parts.count - 1]
            
            guard let date = df.date(from: dateStr) else { continue }
            guard let amount = parseAmount(amountStr) else { continue }
            
            let kind: TransactionKind = amount < 0 ? .expense : .income
            var tx = FinanceTransaction(date: date,
                                        name: name,
                                        amount: amount,
                                        kind: kind,
                                        accountID: account.id,
                                        note: nil)
            if kind != .transfer, tx.categoryID == nil, let suggested = suggestedCategoryID(forName: name) {
                tx.categoryID = suggested
            }
            imported.append(tx)
        }
        
        guard !imported.isEmpty else { return 0 }
        transactions.insert(contentsOf: imported, at: 0)
        transactions.sort { $0.date > $1.date }
        return imported.count
    }
    
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
        var categories: [TransactionCategory]
        var categoryMemory: [String: UUID]
        var pots: [SavingsPot] // neu in v3
    }
    
    private struct FullExportV1: Codable {
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
    
    private struct FullExportV2: Codable {
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
        var categories: [TransactionCategory]
        var categoryMemory: [String: UUID]
        // keine pots in v2
    }
    
    func exportAll() -> URL {
        let defaults = UserDefaults.standard
        let appearance = defaults.string(forKey: "appearanceMode") ?? AppearanceMode.system.rawValue
        let seenOnboarding = defaults.bool(forKey: "didSeeOnboarding")
        
        let bundle = FullExport(
            version: 3,
            createdAt: Date(),
            accounts: accounts,
            transactions: transactions,
            investments: investments,
            debts: debts,
            settings: .init(appearanceMode: appearance, didSeeOnboarding: seenOnboarding),
            categories: categories,
            categoryMemory: categoryMemory,
            pots: pots
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
        
        // v3
        if let v3 = try? decoder.decode(FullExport.self, from: data) {
            self.accounts = v3.accounts
            self.transactions = v3.transactions.sorted { $0.date > $1.date }
            self.investments = v3.investments
            self.debts = v3.debts
            self.categories = v3.categories.isEmpty ? defaultSeedCategories() : v3.categories
            self.categoryMemory = v3.categoryMemory
            self.pots = v3.pots
            let defaults = UserDefaults.standard
            defaults.set(v3.settings.appearanceMode, forKey: "appearanceMode")
            defaults.set(v3.settings.didSeeOnboarding, forKey: "didSeeOnboarding")
        } else if let v2 = try? decoder.decode(FullExportV2.self, from: data) {
            // v2 Fallback (ohne pots)
            self.accounts = v2.accounts
            self.transactions = v2.transactions.sorted { $0.date > $1.date }
            self.investments = v2.investments
            self.debts = v2.debts
            self.categories = v2.categories.isEmpty ? defaultSeedCategories() : v2.categories
            self.categoryMemory = v2.categoryMemory
            self.pots = []
            let defaults = UserDefaults.standard
            defaults.set(v2.settings.appearanceMode, forKey: "appearanceMode")
            defaults.set(v2.settings.didSeeOnboarding, forKey: "didSeeOnboarding")
        } else {
            // v1 Fallback
            let v1 = try decoder.decode(FullExportV1.self, from: data)
            self.accounts = v1.accounts
            self.transactions = v1.transactions.sorted { $0.date > $1.date }
            self.investments = v1.investments
            self.debts = v1.debts
            self.categories = defaultSeedCategories()
            self.categoryMemory = [:]
            self.pots = []
            let defaults = UserDefaults.standard
            defaults.set(v1.settings.appearanceMode, forKey: "appearanceMode")
            defaults.set(v1.settings.didSeeOnboarding, forKey: "didSeeOnboarding")
        }
        
        let snapshot = PersistedState(accounts: accounts, transactions: transactions, investments: investments, debts: debts, categories: categories, categoryMemory: categoryMemory, pots: pots)
        saveToDisk(snapshot)
    }
    
    // MARK: - CSV Hilfen
    private func splitCSV(line: String, delimiter: Character) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        
        while i < line.endIndex {
            let ch = line[i]
            if ch == "\"" {
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
        s = s.replacingOccurrences(of: "€", with: "")
             .replacingOccurrences(of: " ", with: "")
        s = s.replacingOccurrences(of: ".", with: "")
             .replacingOccurrences(of: ",", with: ".")
        return Double(s)
    }
}

// kleines Hilfs-+ für Set
fileprivate func +<T>(lhs: Set<T>, rhs: [T]) -> Set<T> where T: Hashable { lhs.union(rhs) }

// MARK: - Bulk-Kategorie-Anwendung (unverändert)
extension FinanceStore {
    func countPastUncategorizedTransactions(matchingName name: String, before: Date) -> Int {
        let key = normalized(name)
        guard !key.isEmpty else { return 0 }
        return transactions.filter { t in
            t.date < before &&
            (t.kind == .income || t.kind == .expense) &&
            t.categoryID == nil &&
            normalized(t.name) == key
        }.count
    }
    
    func applyCategory(_ categoryID: UUID, toPastUncategorizedTransactionsMatching name: String, before: Date) {
        let key = normalized(name)
        guard !key.isEmpty else { return }
        var changed = false
        for i in transactions.indices {
            let t = transactions[i]
            if t.date < before &&
                (t.kind == .income || t.kind == .expense) &&
                t.categoryID == nil &&
                normalized(t.name) == key {
                transactions[i].categoryID = categoryID
                changed = true
            }
        }
        if changed {
            learnCategory(forName: name, categoryID: categoryID)
        }
    }
}

// MARK: - Overlay-Datenmodell für Pot-Ziel
struct PotCelebrationOverlay: Identifiable {
    let id = UUID()
    let potName: String
    let goal: Double
    let saved: Double
}
