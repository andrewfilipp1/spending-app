import Foundation

// Nutrition (schema 3): meals eaten, a library of foods and goals. Same JSON and rules as js/logic.js.

public enum MealKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .breakfast: "Πρωινό"
        case .lunch: "Μεσημεριανό"
        case .dinner: "Βραδινό"
        case .snack: "Σνακ"
        }
    }

    /// The meal of the day for an hour, for a new entry.
    public static func at(hour: Int) -> MealKind {
        switch hour {
        case 5..<11: .breakfast
        case 12..<16: .lunch
        case 19..<23: .dinner
        default: .snack
        }
    }
}

public struct Nutrition: Codable, Equatable, Sendable {
    public var kcalGoal: Int?
    public var proteinGoal: Int?
    public var carbsGoal: Int?
    public var fatGoal: Int?
    /// The goal follows the watch: resting energy plus active energy (from Health), plus `kcalAdjust`.
    public var useHealth = false
    public var kcalAdjust = 0
    /// Photos of food may be sent (through the sync server) for an estimate.
    public var aiPhotos = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kcalGoal = (try? c.decodeIfPresent(Int.self, forKey: .kcalGoal)) ?? nil
        proteinGoal = (try? c.decodeIfPresent(Int.self, forKey: .proteinGoal)) ?? nil
        carbsGoal = (try? c.decodeIfPresent(Int.self, forKey: .carbsGoal)) ?? nil
        fatGoal = (try? c.decodeIfPresent(Int.self, forKey: .fatGoal)) ?? nil
        useHealth = (try? c.decodeIfPresent(Bool.self, forKey: .useHealth)) ?? false
        kcalAdjust = (try? c.decodeIfPresent(Int.self, forKey: .kcalAdjust)) ?? 0
        aiPhotos = (try? c.decodeIfPresent(Bool.self, forKey: .aiPhotos)) ?? false
    }

    func sanitized() -> Nutrition {
        var n = self
        if let v = kcalGoal, !(500...10000).contains(v) { n.kcalGoal = nil }
        if let v = proteinGoal, !(0...1000).contains(v) { n.proteinGoal = nil }
        if let v = carbsGoal, !(0...1000).contains(v) { n.carbsGoal = nil }
        if let v = fatGoal, !(0...1000).contains(v) { n.fatGoal = nil }
        if !(-2000...2000).contains(kcalAdjust) { n.kcalAdjust = 0 }
        return n
    }
}

/// A library food; values per serving.
public struct Food: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var serving: String
    public var kcal: Int
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var createdAt: Double
    public var updatedAt: Double

    public init(id: String = UUID().uuidString, name: String, serving: String = "1 μερίδα", kcal: Int, protein: Double = 0, carbs: Double = 0,
                fat: Double = 0, createdAt: Double = Date().timeIntervalSince1970 * 1000, updatedAt: Double = 0) {
        self.id = id
        self.name = name
        self.serving = serving
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = try c.decode(String.self, forKey: .name)
        serving = (try? c.decodeIfPresent(String.self, forKey: .serving)) ?? ""
        kcal = Int(((try? c.decodeIfPresent(Double.self, forKey: .kcal)) ?? 0).rounded())
        protein = (try? c.decodeIfPresent(Double.self, forKey: .protein)) ?? 0
        carbs = (try? c.decodeIfPresent(Double.self, forKey: .carbs)) ?? 0
        fat = (try? c.decodeIfPresent(Double.self, forKey: .fat)) ?? 0
        createdAt = (try? c.decodeIfPresent(Double.self, forKey: .createdAt)) ?? 0
        updatedAt = (try? c.decodeIfPresent(Double.self, forKey: .updatedAt)) ?? 0
    }
}

/// A meal eaten; values are the totals for the quantity eaten.
public struct Meal: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var date: String // yyyy-MM-dd
    public var meal: MealKind
    public var name: String
    public var qty: Double // servings of the food
    public var kcal: Int
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var source: String // manual | food | photo | purchase
    public var foodId: String?
    public var purchaseId: String?
    public var itemId: String?
    public var createdAt: Double
    public var updatedAt: Double

    public static let sources: Set<String> = ["manual", "food", "photo", "purchase"]

    public init(id: String = UUID().uuidString, date: String, meal: MealKind, name: String, qty: Double = 1, kcal: Int, protein: Double = 0,
                carbs: Double = 0, fat: Double = 0, source: String = "manual", foodId: String? = nil, purchaseId: String? = nil,
                itemId: String? = nil, createdAt: Double = Date().timeIntervalSince1970 * 1000, updatedAt: Double = 0) {
        self.id = id
        self.date = date
        self.meal = meal
        self.name = name
        self.qty = qty
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.source = source
        self.foodId = foodId
        self.purchaseId = purchaseId
        self.itemId = itemId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// `qty` servings of a library food.
    public init(food: Food, qty: Double = 1, date: String, meal: MealKind) {
        self.init(date: date, meal: meal, name: food.name, qty: qty, kcal: Int((Double(food.kcal) * qty).rounded()),
                  protein: round1(food.protein * qty), carbs: round1(food.carbs * qty), fat: round1(food.fat * qty),
                  source: "food", foodId: food.id)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        date = try c.decode(String.self, forKey: .date)
        meal = ((try? c.decodeIfPresent(String.self, forKey: .meal)) ?? nil).flatMap(MealKind.init(rawValue:)) ?? .snack
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        qty = (try? c.decodeIfPresent(Double.self, forKey: .qty)) ?? 1
        kcal = Int(((try? c.decodeIfPresent(Double.self, forKey: .kcal)) ?? 0).rounded())
        protein = (try? c.decodeIfPresent(Double.self, forKey: .protein)) ?? 0
        carbs = (try? c.decodeIfPresent(Double.self, forKey: .carbs)) ?? 0
        fat = (try? c.decodeIfPresent(Double.self, forKey: .fat)) ?? 0
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? "manual"
        foodId = (try? c.decodeIfPresent(String.self, forKey: .foodId)) ?? nil
        purchaseId = (try? c.decodeIfPresent(String.self, forKey: .purchaseId)) ?? nil
        itemId = (try? c.decodeIfPresent(String.self, forKey: .itemId)) ?? nil
        createdAt = (try? c.decodeIfPresent(Double.self, forKey: .createdAt)) ?? 0
        updatedAt = (try? c.decodeIfPresent(Double.self, forKey: .updatedAt)) ?? 0
    }
}

func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }

private func macro(_ v: Double) -> Double { v.isFinite && v >= 0 && v <= 2000 ? round1(v) : 0 }
private func kcalValue(_ v: Int) -> Int { (0...20000).contains(v) ? v : 0 }
private func optId(_ s: String?) -> String? { s.flatMap { $0.isEmpty ? nil : String($0.prefix(64)) } }

extension Food {
    func sanitized() -> Food? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var f = self
        f.name = String(name.prefix(120))
        f.serving = serving.isEmpty ? "1 μερίδα" : String(serving.prefix(60))
        f.kcal = kcalValue(kcal)
        f.protein = macro(protein)
        f.carbs = macro(carbs)
        f.fat = macro(fat)
        return f
    }
}

extension Meal {
    func sanitized() -> Meal? {
        guard Days.isValid(date) else { return nil }
        var m = self
        m.name = name.isEmpty ? "Φαγητό" : String(name.prefix(120))
        m.qty = qty.isFinite && qty >= 0.01 && qty <= 100 ? qty : 1
        m.kcal = kcalValue(kcal)
        m.protein = macro(protein)
        m.carbs = macro(carbs)
        m.fat = macro(fat)
        m.source = Meal.sources.contains(source) ? source : "manual"
        m.foodId = optId(foodId)
        m.purchaseId = optId(purchaseId)
        m.itemId = optId(itemId)
        return m
    }
}

// MARK: - logic

public struct NutritionTotals: Equatable, Sendable {
    public var kcal = 0
    public var protein = 0.0
    public var carbs = 0.0
    public var fat = 0.0

    public init(kcal: Int = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}

/// From Health: a typical day's resting energy and what was burned moving today.
public struct HealthEnergy: Equatable, Sendable {
    public var restingKcal: Double
    public var activeKcal: Double

    public init(restingKcal: Double, activeKcal: Double) {
        self.restingKcal = restingKcal
        self.activeKcal = activeKcal
    }
}

public struct RecentFood: Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public var name: String
    public var foodId: String?
    public var serving: String
    public var kcal: Int
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var count: Int
    public var last: String
}

public struct FoodCost: Identifiable, Sendable {
    public var id: String { cat }
    public let cat: String
    public var cents = 0
    public var kcal = 0
    public var protein = 0.0
    public var per1000kcal: Int? { kcal > 0 ? Int((Double(cents) * 1000 / Double(kcal)).rounded()) : nil }
    public var per10gProtein: Int? { protein > 0 ? Int((Double(cents) * 10 / protein).rounded()) : nil }
}

public enum NutritionLogic {
    public static func day(_ meals: [Meal], _ date: String) -> NutritionTotals {
        var t = NutritionTotals()
        for m in meals where m.date == date {
            t.kcal += m.kcal
            t.protein += m.protein
            t.carbs += m.carbs
            t.fat += m.fat
        }
        t.protein = round1(t.protein)
        t.carbs = round1(t.carbs)
        t.fat = round1(t.fat)
        return t
    }

    /// The day's calorie goal: from the watch when enabled and available, else the fixed goal.
    public static func kcalGoal(_ n: Nutrition, health: HealthEnergy?) -> Int? {
        if n.useHealth, let h = health, h.restingKcal > 0 {
            return max(0, Int((h.restingKcal + h.activeKcal + Double(n.kcalAdjust)).rounded()))
        }
        return n.kcalGoal
    }

    /// Library foods and earlier meals, most used first, for quick entry. Same names count once (newest wins).
    public static func recent(_ meals: [Meal], foods: [Food], limit: Int = 20) -> [RecentFood] {
        var byKey: [String: RecentFood] = [:]
        for f in foods {
            let k = ItemHistory.key(f.name)
            byKey[k] = RecentFood(key: k, name: f.name, foodId: f.id, serving: f.serving, kcal: f.kcal, protein: f.protein,
                                  carbs: f.carbs, fat: f.fat, count: 0, last: "")
        }
        for m in meals.sorted(by: { $0.date < $1.date }) {
            let k = ItemHistory.key(m.name)
            if var e = byKey[k], e.foodId != nil {
                e.count += 1
                e.last = m.date
                byKey[k] = e
            } else {
                byKey[k] = RecentFood(key: k, name: m.name, foodId: nil, serving: "", kcal: m.kcal, protein: m.protein, carbs: m.carbs,
                                      fat: m.fat, count: (byKey[k]?.count ?? 0) + 1, last: m.date)
            }
        }
        return Array(byKey.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.last > $1.last }.prefix(limit))
    }

    /// Per category, the cost of the linked purchase items against the meals eaten from them.
    /// An item eaten over several meals counts once.
    public static func costs(_ meals: [Meal], purchases: [Purchase]) -> [FoodCost] {
        var items: [String: Item] = [:]
        for p in purchases { for i in p.items { items[i.id] = i } }
        var byCat: [String: FoodCost] = [:]
        var order: [String] = []
        var counted = Set<String>()
        for m in meals {
            guard let id = m.itemId, let i = items[id] else { continue }
            if byCat[i.cat] == nil { order.append(i.cat) }
            var c = byCat[i.cat] ?? FoodCost(cat: i.cat)
            if counted.insert(i.id).inserted { c.cents += i.cents }
            c.kcal += m.kcal
            c.protein += m.protein
            byCat[i.cat] = c
        }
        return order.compactMap { byCat[$0] }
    }
}

// MARK: - photo estimate (server/src/estimate.js)

public struct FoodEstimate: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Identifiable, Sendable {
        public var id: String { name + "\(grams)" }
        public var name: String
        public var grams: Int
        public var kcal: Int
        public var protein: Double
        public var carbs: Double
        public var fat: Double
    }

    public var items: [Item]
    public var kcal: Int
    public var confidence: String // low | medium | high
    public var note: String
}

extension Meal {
    /// One estimated item, scaled by `portion` (1 = as estimated).
    public init(estimate i: FoodEstimate.Item, portion: Double, date: String, meal: MealKind, purchaseId: String? = nil, itemId: String? = nil) {
        self.init(date: date, meal: meal, name: i.name, qty: portion, kcal: Int((Double(i.kcal) * portion).rounded()),
                  protein: round1(i.protein * portion), carbs: round1(i.carbs * portion), fat: round1(i.fat * portion),
                  source: "photo", purchaseId: purchaseId, itemId: itemId)
    }
}
