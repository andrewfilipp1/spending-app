#if DEBUG
import Foundation
import SpendingCore

/// Sample data for simulator screenshots: launch with `-demo-data` (and optionally `-tab stats`).
enum Demo {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-demo-data") }

    static var tab: Router.Tab? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return nil }
        return ["home": .home, "nutrition": .nutrition, "history": .history, "stats": .stats, "settings": .settings][args[i + 1]]
    }

    static func data() -> AppData {
        var d = AppData()
        d.settings.budgets.month = 40000
        d.settings.budgets.week = 10000
        d.settings.budgetAlerts = false
        let today = Days.today()
        if let i = d.categories.firstIndex(where: { $0.id == "fuel" }) {
            d.categories[i].setBudget(5000, period: .week, at: 1_759_000_000_000)
            d.categories[i].setBudget(7000, period: .week, at: 1_759_500_000_000)
            d.categories[i].setBudget(6000, period: .week, at: 1_760_000_000_000)
        }
        if let i = d.categories.firstIndex(where: { $0.id == "groceries" }) {
            d.categories[i].setBudget(25000, period: .month, at: 1_759_000_000_000)
        }
        let shops: [(String, String, [(String, Int, Int)])] = [
            ("Σκλαβενίτης", "groceries", [("Ψωμί", 120, 2), ("Φέτα", 650, 4), ("Ντομάτες", 310, 3), ("Γιαούρτι", 220, 1)]),
            ("Coffee Island", "coffee", [("Freddo espresso", 250, 1)]),
            ("Shell", "fuel", [("Βενζίνη", 4000, 7)]),
            ("efood", "food", [("Σουβλάκια", 1150, 1)]),
            ("Φαρμακείο", "health", [("Depon", 350, 1)]),
        ]
        for back in stride(from: 35, through: 0, by: -1) {
            let s = shops[(back * 7 + 3) % shops.count]
            let items = s.2.prefix(1 + back % s.2.count).map { Item(name: $0.0, cents: $0.1, cat: s.1, days: $0.2) }
            d.purchases.append(Purchase(date: Days.add(today, -back), store: s.0, createdAt: Double(back), items: Array(items)))
        }
        d.purchases.append(Purchase(date: today, store: "Lidl", source: "applepay", review: true,
                                    items: [Item(name: "Lidl", cents: 2340, cat: "groceries")]))
        d.nutrition.kcalGoal = 2200
        d.nutrition.proteinGoal = 140
        let meals: [(MealKind, String, Int, Double, Double, Double)] = [
            (.breakfast, "Γιαούρτι με μέλι", 300, 18, 30, 12), (.breakfast, "Freddo espresso", 120, 4, 18, 3),
            (.lunch, "Σουβλάκι πίτα ×2", 760, 44, 80, 28), (.snack, "Μπανάνα", 105, 1, 27, 0),
            (.dinner, "Χωριάτικη σαλάτα", 330, 9, 12, 27), (.dinner, "Ψωμί", 160, 5, 30, 2),
        ]
        for back in 0...6 {
            for (i, m) in meals.enumerated() where back > 0 || m.0 != .dinner {
                let k = Int(Double(m.2) * (1 + Double((back * 3 + i) % 5 - 2) / 10))
                d.meals.append(Meal(date: Days.add(today, -back), meal: m.0, name: m.1, kcal: k, protein: m.3, carbs: m.4, fat: m.5,
                                    createdAt: Double(i)))
            }
        }
        return d
    }
}
#endif
