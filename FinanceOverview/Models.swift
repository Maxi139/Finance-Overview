import Foundation
import SwiftUI

enum AccountCategory: String, CaseIterable, Identifiable, Codable {
    case giro = "Giro"
    case tagesgeld = "Tagesgeld"
    case festgeld = "Festgeld"
    case andereAnlagen = "Andere Anlagen"
    
    var id: String { rawValue }
}

struct Account: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var category: AccountCategory
    var initialBalance: Double
    var isAvailable: Bool
    var isPrimary: Bool
    var parentAccountID: UUID? // für Unterkonten
    
    init(id: UUID = UUID(),
         name: String,
         category: AccountCategory,
         initialBalance: Double,
         isAvailable: Bool = true,
         isPrimary: Bool = false,
         parentAccountID: UUID? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.initialBalance = initialBalance
        self.isAvailable = isAvailable
        self.isPrimary = isPrimary
        self.parentAccountID = parentAccountID
    }
    
    var isSubaccount: Bool { parentAccountID != nil }
}

enum TransactionKind: String, CaseIterable, Identifiable, Codable {
    case expense = "Ausgabe"
    case income  = "Einnahme"
    case transfer = "Umbuchung"
    var id: String { rawValue }
}

struct FinanceTransaction: Identifiable, Hashable, Codable {
    let id: UUID
    var date: Date
    var name: String
    var amount: Double
    var kind: TransactionKind
    var accountID: UUID?        // für Einnahmen/Ausgaben
    var fromAccountID: UUID?    // für Umbuchungen
    var toAccountID: UUID?      // für Umbuchungen
    var note: String?
    
    init(id: UUID = UUID(),
         date: Date,
         name: String,
         amount: Double,
         kind: TransactionKind,
         accountID: UUID? = nil,
         fromAccountID: UUID? = nil,
         toAccountID: UUID? = nil,
         note: String? = nil) {
        self.id = id
        self.date = date
        self.name = name
        self.amount = amount
        self.kind = kind
        self.accountID = accountID
        self.fromAccountID = fromAccountID
        self.toAccountID = toAccountID
        self.note = note
    }
}

struct Investment: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var value: Double
    init(id: UUID = UUID(), name: String, value: Double) {
        self.id = id
        self.name = name
        self.value = value
    }
}

/// App-weit gespeichertes Erscheinungsbild
enum AppearanceMode: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .light: return "Hell"
        case .dark: return "Dunkel"
        case .system: return "System"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

// MARK: - Schulden

enum DebtDirection: String, CaseIterable, Identifiable, Codable {
    case iOwe = "Ich schulde"
    case owedToMe = "Mir wird geschuldet"
    var id: String { rawValue }
}

struct Debt: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var amount: Double // positiv
    var direction: DebtDirection
    var dueDate: Date?
    var accountID: UUID?
    var note: String?
    var isSettled: Bool
    
    init(id: UUID = UUID(),
         title: String,
         amount: Double,
         direction: DebtDirection,
         dueDate: Date? = nil,
         accountID: UUID? = nil,
         note: String? = nil,
         isSettled: Bool = false) {
        self.id = id
        self.title = title
        self.amount = amount
        self.direction = direction
        self.dueDate = dueDate
        self.accountID = accountID
        self.note = note
        self.isSettled = isSettled
    }
}

// MARK: - Globales Erfolgs-Overlay

struct SaveSuccessOverlay: Identifiable {
    let id = UUID()
    let kind: TransactionKind
    let name: String
    let amount: Double
}
