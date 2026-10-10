import Foundation

// The JSON shape matches the web app, so backups move freely between the two.
// Decoding is lenient (missing keys get defaults); `sanitized()` then enforces valid values.

public enum PeriodKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case day, week, month, year
    public var id: String { rawValue }
}

public struct Budgets: Codable, Equatable, Sendable {
    public var day: Int?
    public var week: Int?
    public var month: Int?
    public var year: Int?

    public init(day: Int? = nil, week: Int? = nil, month: Int? = nil, year: Int? = nil) {
        self.day = day
        self.week = week
        self.month = month
        self.year = year
    }

    public subscript(kind: PeriodKind) -> Int? {
        get {
            switch kind {
            case .day: day
            case .week: week
            case .month: month
            case .year: year
            }
        }
        set {
            switch kind {
            case .day: day = newValue
            case .week: week = newValue
            case .month: month = newValue
            case .year: year = newValue
            }
        }
    }

    public var any: Bool { PeriodKind.allCases.contains { self[$0] != nil } }
}

public struct Settings: Codable, Equatable, Sendable {
    public var budgets = Budgets()
    public var weekStart = 1 // 1 = Monday, 0 = Sunday
    public var currency = "EUR"
    public var autoLockSec = 60
    // iOS-only settings (ignored by the web app)
    public var lockEnabled = false
    public var dailyReminder = false
    public var reminderMinutes = 21 * 60
    public var budgetAlerts = true
    public var alertsSent: [String] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        budgets = (try? c.decodeIfPresent(Budgets.self, forKey: .budgets)) ?? Budgets()
        weekStart = (try? c.decodeIfPresent(Int.self, forKey: .weekStart)) ?? 1
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "EUR"
        autoLockSec = (try? c.decodeIfPresent(Int.self, forKey: .autoLockSec)) ?? 60
        lockEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .lockEnabled)) ?? false
        dailyReminder = (try? c.decodeIfPresent(Bool.self, forKey: .dailyReminder)) ?? false
        reminderMinutes = (try? c.decodeIfPresent(Int.self, forKey: .reminderMinutes)) ?? 21 * 60
        budgetAlerts = (try? c.decodeIfPresent(Bool.self, forKey: .budgetAlerts)) ?? true
        alertsSent = (try? c.decodeIfPresent([String].self, forKey: .alertsSent)) ?? []
    }
}

public struct Category: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    public var color: String // #rrggbb
    public var budget: Int? // monthly, cents

    public init(id: String = UUID().uuidString, name: String, emoji: String, color: String, budget: Int? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.color = color
        self.budget = budget
    }
}

public struct Item: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var cents: Int
    public var cat: String
    public var days: Int

    public init(id: String = UUID().uuidString, name: String = "", cents: Int = 0, cat: String = "other", days: Int = 1) {
        self.id = id
        self.name = name
        self.cents = cents
        self.cat = cat
        self.days = days
    }
}

public struct Purchase: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var date: String // yyyy-MM-dd
    public var store: String
    public var note: String
    public var source: String // manual | applepay
    public var createdAt: Double
    public var updatedAt: Double
    public var review: Bool // logged automatically, waiting to be checked / split into items
    public var items: [Item]

    public init(id: String = UUID().uuidString, date: String, store: String = "", note: String = "", source: String = "manual",
                createdAt: Double = Date().timeIntervalSince1970 * 1000, updatedAt: Double = 0, review: Bool = false, items: [Item]) {
        self.id = id
        self.date = date
        self.store = store
        self.note = note
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.review = review
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        date = try c.decode(String.self, forKey: .date)
        store = (try? c.decodeIfPresent(String.self, forKey: .store)) ?? ""
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? "manual"
        createdAt = (try? c.decodeIfPresent(Double.self, forKey: .createdAt)) ?? 0
        updatedAt = (try? c.decodeIfPresent(Double.self, forKey: .updatedAt)) ?? 0
        review = (try? c.decodeIfPresent(Bool.self, forKey: .review)) ?? false
        items = (try? c.decodeIfPresent([LenientItem].self, forKey: .items))?.compactMap(\.value) ?? []
    }

    public var total: Int { items.reduce(0) { $0 + $1.cents } }
}

// Skips malformed items instead of failing the whole purchase.
private struct LenientItem: Decodable {
    let value: Item?
    init(from decoder: Decoder) throws {
        value = try? Item(from: decoder)
    }
}

private struct LenientPurchase: Decodable {
    let value: Purchase?
    init(from decoder: Decoder) throws {
        value = try? Purchase(from: decoder)
    }
}

private struct LenientCategory: Decodable {
    let value: Category?
    init(from decoder: Decoder) throws {
        value = try? Category(from: decoder)
    }
}

public struct AppData: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schema: Int
    public var settings: Settings
    public var categories: [Category]
    public var purchases: [Purchase]

    public init(schema: Int = AppData.schemaVersion, settings: Settings = Settings(), categories: [Category] = AppData.defaultCategories, purchases: [Purchase] = []) {
        self.schema = schema
        self.settings = settings
        self.categories = categories
        self.purchases = purchases
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = (try? c.decodeIfPresent(Int.self, forKey: .schema)) ?? AppData.schemaVersion
        settings = (try? c.decodeIfPresent(Settings.self, forKey: .settings)) ?? Settings()
        categories = (try? c.decodeIfPresent([LenientCategory].self, forKey: .categories))?.compactMap(\.value) ?? AppData.defaultCategories
        purchases = (try? c.decodeIfPresent([LenientPurchase].self, forKey: .purchases))?.compactMap(\.value) ?? []
    }

    public static let defaultCategories: [Category] = [
        Category(id: "groceries", name: "Σούπερ μάρκετ", emoji: "🛒", color: "#16a34a"),
        Category(id: "food", name: "Φαγητό έξω", emoji: "🍔", color: "#ea580c"),
        Category(id: "coffee", name: "Καφές", emoji: "☕", color: "#a16207"),
        Category(id: "transport", name: "Μετακινήσεις", emoji: "🚗", color: "#2563eb"),
        Category(id: "home", name: "Σπίτι & λογαριασμοί", emoji: "🏠", color: "#7c3aed"),
        Category(id: "health", name: "Υγεία", emoji: "💊", color: "#dc2626"),
        Category(id: "fun", name: "Διασκέδαση", emoji: "🎉", color: "#db2777"),
        Category(id: "shopping", name: "Ρούχα & αγορές", emoji: "🛍️", color: "#0d9488"),
        Category(id: "subs", name: "Συνδρομές", emoji: "📱", color: "#4f46e5"),
        Category(id: "other", name: "Άλλα", emoji: "📦", color: "#64748b"),
    ]

    public func category(_ id: String) -> Category {
        categories.first { $0.id == id } ?? categories.first { $0.id == "other" } ?? AppData.defaultCategories.last!
    }

    /// Clamps every field to valid values. Applied to everything loaded or imported.
    public func sanitized() -> AppData {
        var d = self
        d.schema = AppData.schemaVersion
        let s = settings
        d.settings.weekStart = s.weekStart == 0 ? 0 : 1
        d.settings.currency = s.currency.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil ? s.currency : "EUR"
        d.settings.autoLockSec = [0, 60, 300, 900].contains(s.autoLockSec) ? s.autoLockSec : 60
        d.settings.reminderMinutes = min(max(s.reminderMinutes, 0), 24 * 60 - 1)
        d.settings.alertsSent = Array(s.alertsSent.suffix(60))
        for k in PeriodKind.allCases {
            if let v = s.budgets[k], v < 0 || v >= 100_000_000_000 { d.settings.budgets[k] = nil }
        }

        var seen = Set<String>()
        d.categories = categories.compactMap { c in
            guard !c.id.isEmpty, seen.insert(c.id).inserted else { return nil }
            var c = c
            c.name = String(c.name.prefix(60)).isEmpty ? "Κατηγορία" : String(c.name.prefix(60))
            c.emoji = c.emoji.isEmpty ? "•" : String(c.emoji.prefix(1))
            c.color = c.color.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil ? c.color : "#64748b"
            if let b = c.budget, b < 0 { c.budget = nil }
            return c
        }
        if d.categories.isEmpty { d.categories = AppData.defaultCategories }
        if !d.categories.contains(where: { $0.id == "other" }) { d.categories.append(AppData.defaultCategories.last!) }
        let ids = Set(d.categories.map(\.id))

        d.purchases = purchases.compactMap { p in
            guard Days.isValid(p.date) else { return nil }
            var p = p
            p.store = String(p.store.prefix(120))
            p.note = String(p.note.prefix(1000))
            p.source = p.source == "applepay" ? "applepay" : "manual"
            p.items = p.items.compactMap { i in
                guard i.cents > 0, i.cents < 100_000_000_000 else { return nil }
                var i = i
                i.name = String(i.name.prefix(120)).isEmpty ? "Αγορά" : String(i.name.prefix(120))
                i.cat = ids.contains(i.cat) ? i.cat : "other"
                i.days = min(max(i.days, 1), 3660)
                return i
            }
            return p.items.isEmpty ? nil : p
        }
        return d
    }
}
