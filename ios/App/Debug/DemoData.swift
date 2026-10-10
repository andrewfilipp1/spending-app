#if DEBUG
import Foundation
import SpendingCore

/// Sample data for simulator screenshots: launch with `-demo-data` (and optionally `-tab stats`).
enum Demo {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-demo-data") }

    static var tab: Router.Tab? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return nil }
        return ["home": .home, "history": .history, "stats": .stats, "settings": .settings][args[i + 1]]
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
        return d
    }
}
#endif
