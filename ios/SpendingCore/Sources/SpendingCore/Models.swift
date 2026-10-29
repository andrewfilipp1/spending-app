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
    /// Unspent (or overspent) daily budget moves to the next day, within the month.
    public var carryOver = true
    /// Monthly fund for unexpected expenses (cents), separate from the regular budgets.
    public var unexpectedBudget: Int?
    /// Day the daily budget was first set; earlier days do not count as savings.
    public var daySince: String?

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
        carryOver = (try? c.decodeIfPresent(Bool.self, forKey: .carryOver)) ?? true
        unexpectedBudget = (try? c.decodeIfPresent(Int.self, forKey: .unexpectedBudget)) ?? nil
        daySince = (try? c.decodeIfPresent(String.self, forKey: .daySince)) ?? nil
    }
}

/// One entry per budget change of a category (kept so the app can show how often it was changed).
public struct BudgetChange: Codable, Hashable, Sendable {
    public var at: Double // ms since 1970
    public var from: Int?
    public var fromPeriod: PeriodKind?
    public var to: Int?
    public var period: PeriodKind

    public init(at: Double, from: Int?, fromPeriod: PeriodKind?, to: Int?, period: PeriodKind) {
        self.at = at
        self.from = from
        self.fromPeriod = fromPeriod
        self.to = to
        self.period = period
    }
}

public struct Category: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    public var color: String // #rrggbb
    public var budget: Int? // cents per budgetPeriod
    public var budgetPeriod: PeriodKind // .week or .month
    public var budgetHistory: [BudgetChange]
    /// Own fund (e.g. weekly groceries): kept out of the general budgets, counts only against `budget`.
    public var ownFund: Bool
    /// General payments (e.g. subscriptions): count in the week/month/year budgets, not in the daily limit.
    public var offDaily: Bool

    public init(id: String = UUID().uuidString, name: String, emoji: String, color: String, budget: Int? = nil,
                budgetPeriod: PeriodKind = .month, budgetHistory: [BudgetChange] = [], ownFund: Bool = false, offDaily: Bool = false) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.color = color
        self.budget = budget
        self.budgetPeriod = budgetPeriod
        self.budgetHistory = budgetHistory
        self.ownFund = ownFund
        self.offDaily = offDaily
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        emoji = (try? c.decodeIfPresent(String.self, forKey: .emoji)) ?? ""
        color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? ""
        budget = (try? c.decodeIfPresent(Int.self, forKey: .budget)) ?? nil
        budgetPeriod = (try? c.decodeIfPresent(PeriodKind.self, forKey: .budgetPeriod)) ?? .month
        budgetHistory = (try? c.decodeIfPresent([BudgetChange].self, forKey: .budgetHistory)) ?? []
        ownFund = (try? c.decodeIfPresent(Bool.self, forKey: .ownFund)) ?? false
        offDaily = (try? c.decodeIfPresent(Bool.self, forKey: .offDaily)) ?? false
    }

    /// How many times an existing budget was changed or removed (setting it the first time is not a change).
    public var budgetChanges: Int { budgetHistory.filter { $0.from != nil }.count }

    /// Records the change in the history. Returns false if nothing changed.
    @discardableResult
    public mutating func setBudget(_ cents: Int?, period: PeriodKind, at: Double = Date().timeIntervalSince1970 * 1000) -> Bool {
        let period: PeriodKind = period == .week ? .week : .month
        guard cents != budget || (cents != nil && period != budgetPeriod) else { return false }
        budgetHistory.append(BudgetChange(at: at, from: budget, fromPeriod: budget == nil ? nil : budgetPeriod, to: cents, period: period))
        budgetHistory = Array(budgetHistory.suffix(200))
        budget = cents
        budgetPeriod = period
        return true
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
    /// Comes out of the unexpected-expenses fund instead of the regular budgets.
    public var unexpected: Bool
    /// General payment (e.g. a subscription): counts in the week/month/year budgets, not in the daily limit.
    public var offDaily: Bool
    public var items: [Item]

    public init(id: String = UUID().uuidString, date: String, store: String = "", note: String = "", source: String = "manual",
                createdAt: Double = Date().timeIntervalSince1970 * 1000, updatedAt: Double = 0, review: Bool = false, unexpected: Bool = false, offDaily: Bool = false, items: [Item]) {
        self.id = id
        self.date = date
        self.store = store
        self.note = note
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.review = review
        self.unexpected = unexpected
        self.offDaily = offDaily
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
        unexpected = (try? c.decodeIfPresent(Bool.self, forKey: .unexpected)) ?? false
        offDaily = (try? c.decodeIfPresent(Bool.self, forKey: .offDaily)) ?? false
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

private struct LenientMeal: Decodable {
    let value: Meal?
    init(from decoder: Decoder) throws {
        value = try? Meal(from: decoder)
    }
}

private struct LenientFood: Decodable {
    let value: Food?
    init(from decoder: Decoder) throws {
        value = try? Food(from: decoder)
    }
}

public struct AppData: Codable, Equatable, Sendable {
    public static let schemaVersion = 3

    public var schema: Int
    public var settings: Settings
    public var categories: [Category]
    public var purchases: [Purchase]
    // Schema 3: nutrition.
    public var meals: [Meal] = []
    public var foods: [Food] = []
    public var nutrition = Nutrition()
    // Sync bookkeeping (see SyncMerge): when settings/categories/nutrition last changed, and deleted record ids.
    public var settingsUpdatedAt: Double = 0
    public var categoriesUpdatedAt: Double = 0
    public var nutritionUpdatedAt: Double = 0
    public var deleted: [String: Double] = [:]

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
        meals = (try? c.decodeIfPresent([LenientMeal].self, forKey: .meals))?.compactMap(\.value) ?? []
        foods = (try? c.decodeIfPresent([LenientFood].self, forKey: .foods))?.compactMap(\.value) ?? []
        nutrition = (try? c.decodeIfPresent(Nutrition.self, forKey: .nutrition)) ?? Nutrition()
        settingsUpdatedAt = (try? c.decodeIfPresent(Double.self, forKey: .settingsUpdatedAt)) ?? 0
        categoriesUpdatedAt = (try? c.decodeIfPresent(Double.self, forKey: .categoriesUpdatedAt)) ?? 0
        nutritionUpdatedAt = (try? c.decodeIfPresent(Double.self, forKey: .nutritionUpdatedAt)) ?? 0
        deleted = (try? c.decodeIfPresent([String: Double].self, forKey: .deleted)) ?? [:]
    }

    public static let defaultCategories: [Category] = [
        Category(id: "groceries", name: "Σούπερ μάρκετ", emoji: "🛒", color: "#16a34a"),
        Category(id: "food", name: "Φαγητό έξω", emoji: "🍔", color: "#ea580c"),
        Category(id: "coffee", name: "Καφές", emoji: "☕", color: "#a16207"),
        Category(id: "transport", name: "Μετακινήσεις", emoji: "🚗", color: "#2563eb"),
        Category(id: "fuel", name: "Καύσιμα", emoji: "⛽", color: "#0891b2"),
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
        if d.deleted.count > 5000 {
            d.deleted = Dictionary(uniqueKeysWithValues: d.deleted.sorted { $0.value > $1.value }.prefix(5000).map { ($0.key, $0.value) })
        }
        let s = settings
        d.settings.weekStart = s.weekStart == 0 ? 0 : 1
        d.settings.currency = s.currency.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil ? s.currency : "EUR"
        d.settings.autoLockSec = [0, 60, 300, 900].contains(s.autoLockSec) ? s.autoLockSec : 60
        d.settings.reminderMinutes = min(max(s.reminderMinutes, 0), 24 * 60 - 1)
        d.settings.alertsSent = Array(s.alertsSent.suffix(60))
        if let since = s.daySince, since.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil { d.settings.daySince = nil }
        if let v = s.unexpectedBudget, v < 0 || v >= 100_000_000_000 { d.settings.unexpectedBudget = nil }
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
            if let b = c.budget, b < 0 || b >= 100_000_000_000 { c.budget = nil }
            if c.budgetPeriod != .week { c.budgetPeriod = .month }
            c.budgetHistory = c.budgetHistory.suffix(200).map { h in
                var h = h
                if let f = h.from, f < 0 { h.from = nil }
                if let t = h.to, t < 0 { h.to = nil }
                if h.period != .week { h.period = .month }
                if let fp = h.fromPeriod, fp != .week { h.fromPeriod = .month }
                return h
            }
            return c
        }
        if d.categories.isEmpty { d.categories = AppData.defaultCategories }
        // Schema 2 added the "Καύσιμα" category.
        if schema < 2, !d.categories.contains(where: { $0.id == "fuel" }), let fuel = AppData.defaultCategories.first(where: { $0.id == "fuel" }) {
            let at = (d.categories.firstIndex { $0.id == "transport" }).map { $0 + 1 } ?? max(0, d.categories.count - 1)
            d.categories.insert(fuel, at: at)
        }
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
        var mealIds = Set<String>(), foodIds = Set<String>()
        d.meals = meals.compactMap { $0.sanitized() }.filter { mealIds.insert($0.id).inserted }
        d.foods = foods.compactMap { $0.sanitized() }.filter { foodIds.insert($0.id).inserted }
        d.nutrition = nutrition.sanitized()
        return d
    }
}
