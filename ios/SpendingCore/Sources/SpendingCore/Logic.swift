import Foundation

// Port of js/logic.js. Dates are "yyyy-MM-dd" day keys in the local time zone.

public enum Days {
    private static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    public static func key(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public static func parts(_ k: String) -> (y: Int, m: Int, d: Int) {
        let p = k.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? (p[0], p[1], p[2]) : (1970, 1, 1)
    }

    /// Noon of that day, which avoids DST edge cases.
    public static func date(_ k: String) -> Date {
        let p = parts(k)
        return cal.date(from: DateComponents(year: p.y, month: p.m, day: p.d, hour: 12))!
    }

    public static func make(_ y: Int, _ m: Int, _ d: Int) -> String {
        key(cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!)
    }

    public static func today() -> String { key(Date()) }

    public static func add(_ k: String, _ n: Int) -> String {
        n == 0 ? k : key(cal.date(byAdding: .day, value: n, to: date(k))!)
    }

    /// b - a in whole days
    public static func between(_ a: String, _ b: String) -> Int {
        cal.dateComponents([.day], from: date(a), to: date(b)).day!
    }

    /// 0 = Sunday … 6 = Saturday (like JavaScript)
    public static func weekday(_ k: String) -> Int { cal.component(.weekday, from: date(k)) - 1 }

    public static func isValid(_ k: String) -> Bool {
        guard k.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let p = parts(k)
        return (1...12).contains(p.m) && (1...31).contains(p.d) && make(p.y, p.m, p.d) == k
    }

    public static let months = ["Ιανουάριος", "Φεβρουάριος", "Μάρτιος", "Απρίλιος", "Μάιος", "Ιούνιος",
                                "Ιούλιος", "Αύγουστος", "Σεπτέμβριος", "Οκτώβριος", "Νοέμβριος", "Δεκέμβριος"]
    public static let monthsShort = ["Ιαν", "Φεβ", "Μαρ", "Απρ", "Μαΐ", "Ιουν", "Ιουλ", "Αυγ", "Σεπ", "Οκτ", "Νοε", "Δεκ"]
    public static let weekdays = ["Κυρ", "Δευ", "Τρί", "Τετ", "Πέμ", "Παρ", "Σάβ"]

    public static func short(_ k: String, withYear: Bool = false) -> String {
        let p = parts(k)
        let base = "\(weekdays[weekday(k)]) \(p.d) \(monthsShort[p.m - 1])"
        return withYear ? "\(base) \(p.y)" : base
    }

    public static func label(_ k: String, today t: String = today()) -> String {
        switch between(k, t) {
        case 0: "Σήμερα"
        case 1: "Χθες"
        case -1: "Αύριο"
        default: short(k, withYear: k.prefix(4) != t.prefix(4))
        }
    }
}

public enum Money {
    /// "12,50", "12.50", "€ 1.234,56", "1,234.56", "EUR 3.2" → cents. nil if invalid.
    public static func toCents(_ input: String) -> Int? {
        var s = String(input.unicodeScalars.filter { CharacterSet(charactersIn: "0123456789,.-").contains($0) })
        guard s.contains(where: \.isNumber) else { return nil }
        let lastComma = s.lastIndex(of: ",")
        let lastDot = s.lastIndex(of: ".")
        if let c = lastComma, lastDot == nil || c > lastDot! {
            s = s.replacingOccurrences(of: ".", with: "")
            if let i = s.firstIndex(of: ",") { s.replaceSubrange(i...i, with: ".") }
            s = s.replacingOccurrences(of: ",", with: "")
        } else {
            s = s.replacingOccurrences(of: ",", with: "")
        }
        guard let v = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var cents = v * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &cents, 0, .plain)
        let n = NSDecimalNumber(decimal: rounded)
        guard n != .notANumber, abs(n.doubleValue) < 1e13 else { return nil }
        return n.intValue
    }

    public static func inputText(_ cents: Int?) -> String {
        guard let c = cents else { return "" }
        return String(format: "%d,%02d", c / 100, abs(c % 100))
    }
}

public struct Alloc: Hashable, Sendable {
    public let date: String
    public let cents: Int
    public let cat: String
    public let name: String
    public let pid: String
    public let unexpected: Bool

    public init(date: String, cents: Int, cat: String, name: String, pid: String, unexpected: Bool = false) {
        self.date = date
        self.cents = cents
        self.cat = cat
        self.name = name
        self.pid = pid
        self.unexpected = unexpected
    }
}

public enum AllocMode: String, CaseIterable, Sendable {
    case spread // item cost spread over item.days
    case paid // full cost on the purchase date
}

public struct Period: Equatable, Sendable {
    public let start: String
    public let end: String
    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }

    public func contains(_ day: String) -> Bool { day >= start && day <= end }
    public var length: Int { Days.between(start, end) + 1 }
}

public enum Logic {
    /// Splits cents over n days; the remainder goes to the first days so the sum is exact.
    public static func split(_ cents: Int, _ n: Int) -> [Int] {
        let n = max(1, n)
        let base = cents / n
        var rem = cents - base * n
        return (0..<n).map { _ in
            defer { if rem > 0 { rem -= 1 } }
            return base + (rem > 0 ? 1 : 0)
        }
    }

    public static func allocations(_ purchases: [Purchase], mode: AllocMode = .spread) -> [Alloc] {
        var out: [Alloc] = []
        for p in purchases {
            for it in p.items {
                let n = mode == .spread ? max(1, it.days) : 1
                for (i, c) in split(it.cents, n).enumerated() {
                    out.append(Alloc(date: Days.add(p.date, i), cents: c, cat: it.cat, name: it.name, pid: p.id, unexpected: p.unexpected))
                }
            }
        }
        return out
    }

    /// Unexpected expenses come out of their own monthly fund, not the regular budgets.
    public static func regular(_ purchases: [Purchase]) -> [Purchase] {
        purchases.filter { !$0.unexpected }
    }

    /// Categories with their own fund (e.g. weekly groceries) are kept out of the general
    /// day/week/month/year budgets; they count only against their category budget.
    public static func general(_ allocs: [Alloc], categories: [Category]) -> [Alloc] {
        let own = Set(categories.filter(\.ownFund).map(\.id))
        return own.isEmpty ? allocs : allocs.filter { !own.contains($0.cat) }
    }

    public static func sum<S: Sequence>(_ a: S) -> Int where S.Element == Alloc {
        a.reduce(0) { $0 + $1.cents }
    }

    public static func period(_ kind: PeriodKind, _ ref: String, weekStart: Int = 1) -> Period {
        let p = Days.parts(ref)
        switch kind {
        case .day:
            return Period(start: ref, end: ref)
        case .week:
            let start = Days.add(ref, -((Days.weekday(ref) - weekStart + 7) % 7))
            return Period(start: start, end: Days.add(start, 6))
        case .month:
            let start = Days.make(p.y, p.m, 1)
            let end = Days.add(Days.make(p.m == 12 ? p.y + 1 : p.y, p.m == 12 ? 1 : p.m + 1, 1), -1)
            return Period(start: start, end: end)
        case .year:
            return Period(start: Days.make(p.y, 1, 1), end: Days.make(p.y, 12, 31))
        }
    }

    public static func shift(_ kind: PeriodKind, _ ref: String, by dir: Int) -> String {
        let p = Days.parts(ref)
        switch kind {
        case .day: return Days.add(ref, dir)
        case .week: return Days.add(ref, 7 * dir)
        case .month:
            let total = p.y * 12 + (p.m - 1) + dir
            return Days.make(total / 12, total % 12 + 1, 1)
        case .year: return Days.make(p.y + dir, 1, 1)
        }
    }

    public static func label(_ kind: PeriodKind, _ period: Period) -> String {
        let s = Days.parts(period.start)
        let e = Days.parts(period.end)
        switch kind {
        case .day: return Days.short(period.start, withYear: true)
        case .month: return "\(Days.months[s.m - 1]) \(s.y)"
        case .year: return String(s.y)
        case .week:
            let sm = Days.monthsShort[s.m - 1]
            let em = Days.monthsShort[e.m - 1]
            return sm == em ? "\(s.d)–\(e.d) \(em) \(e.y)" : "\(s.d) \(sm) – \(e.d) \(em) \(e.y)"
        }
    }

    /// How much can be spent today so that a period budget holds: spending before today and amounts
    /// already allocated to later days are subtracted, the rest is shared over the remaining days.
    public static func dailyAllowance(budget: Int, allocs: [Alloc], kind: PeriodKind, today: String, weekStart: Int = 1) -> Int {
        let p = period(kind, today, weekStart: weekStart)
        var before = 0
        var after = 0
        for a in allocs {
            if a.date >= p.start && a.date < today { before += a.cents } else if a.date > today && a.date <= p.end { after += a.cents }
        }
        let daysLeft = Days.between(today, p.end) + 1
        let rest = budget - before - after
        return Int((Double(rest) / Double(daysLeft)).rounded(.down))
    }

    /// Days with a daily budget before this date (the feature's release) are not counted,
    /// so earlier days without a budget do not show up as savings. Same as the web app.
    public static let carryStart = "2026-10-11"

    /// Daily budget minus actual spending, from the start of the month (or `since`) up to yesterday.
    /// Positive = left unspent (carried into today), negative = overspent.
    public static func dayBalance(budget: Int, allocs: [Alloc], today: String, since: String? = nil) -> Int {
        let start = max(max(since ?? carryStart, carryStart), String(today.prefix(8)) + "01")
        let end = Days.add(today, -1)
        guard start <= end else { return 0 }
        let spent = sum(allocs.filter { $0.date >= start && $0.date <= end })
        return budget * (Days.between(start, end) + 1) - spent
    }

    public struct Allowance: Equatable, Sendable {
        public let cents: Int
        public let kind: PeriodKind
    }

    /// The most restrictive of all configured budgets, expressed as "allowed today".
    public static func todayAllowance(_ data: AppData, allocs: [Alloc], today: String) -> Allowance? {
        let s = data.settings
        var opts: [Allowance] = []
        if let d = s.budgets.day {
            let carried = s.carryOver ? dayBalance(budget: d, allocs: allocs, today: today, since: s.daySince) : 0
            opts.append(Allowance(cents: d + carried, kind: .day))
        }
        for k in [PeriodKind.week, .month, .year] {
            if let b = s.budgets[k] {
                opts.append(Allowance(cents: dailyAllowance(budget: b, allocs: allocs, kind: k, today: today, weekStart: s.weekStart), kind: k))
            }
        }
        return opts.min { $0.cents < $1.cents }
    }

    /// Accepts text like "€12,50;Lidl", "Lidl\n12,50 €", "12.50 EUR | Shell".
    public static func parseTransaction(_ text: String) -> (cents: Int, merchant: String)? {
        let parts = text.split(whereSeparator: { $0 == ";" || $0 == "\n" || $0 == "|" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var cents: Int?
        var merchant = ""
        for p in parts {
            let stripped = p.replacingOccurrences(of: #"\b[A-Z]{3}\b|[€$£\s ]"#, with: "", options: .regularExpression)
            if cents == nil, stripped.range(of: #"^-?[\d.,]+$"#, options: .regularExpression) != nil, let c = Money.toCents(stripped) {
                cents = abs(c)
            } else if merchant.isEmpty {
                merchant = p
            }
        }
        guard let c = cents else { return nil }
        return (c, merchant)
    }

    /// Lowercased, accent-free text for searching ("Γάλα" matches "γαλα").
    public static func norm(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "el_GR"))
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Category budgets

public struct CategoryBudgetStatus: Sendable {
    public let category: Category
    public let period: Period
    public let budget: Int
    public let spent: Int
    public var ratio: Double { budget > 0 ? Double(spent) / Double(budget) : (spent > 0 ? 1 : 0) }
}

public extension Logic {
    /// Spending of every category that has a budget, in that category's current week or month.
    static func categoryBudgets(_ data: AppData, allocs: [Alloc], today: String) -> [CategoryBudgetStatus] {
        data.categories.compactMap { c in
            guard let b = c.budget else { return nil }
            let p = period(c.budgetPeriod, today, weekStart: data.settings.weekStart)
            let spent = sum(allocs.filter { $0.cat == c.id && p.contains($0.date) })
            return CategoryBudgetStatus(category: c, period: p, budget: b, spent: spent)
        }
    }
}

// MARK: - Budget alerts

public struct BudgetAlert: Equatable, Sendable {
    public let key: String
    public let title: String
    public let body: String
}

/// Notification texts never contain amounts, since they can show on the lock screen.
public enum Alerts {
    private static let periodAdj: [PeriodKind: String] = [.week: "εβδομαδιαίου", .month: "μηνιαίου", .year: "ετήσιου"]

    /// Alerts that should fire now and have not been sent before (deduplicated by key).
    public static func pending(_ data: AppData, today: String) -> [BudgetAlert] {
        let s = data.settings
        guard s.budgetAlerts else { return [] }
        let allocs = Logic.allocations(Logic.regular(data.purchases))
        let general = Logic.general(allocs, categories: data.categories)
        var out: [BudgetAlert] = []

        if let a = Logic.todayAllowance(data, allocs: general, today: today) {
            let spent = Logic.sum(general.filter { $0.date == today })
            if spent > max(0, a.cents) {
                out.append(BudgetAlert(key: "day-\(today)", title: "Ξεπέρασες το σημερινό όριο",
                                       body: "Άνοιξε την εφαρμογή για λεπτομέρειες."))
            }
        }
        for k in [PeriodKind.week, .month, .year] {
            guard let b = s.budgets[k], b > 0 else { continue }
            let p = Logic.period(k, today, weekStart: s.weekStart)
            let spent = Logic.sum(general.filter { p.contains($0.date) })
            let adj = periodAdj[k]!
            if spent >= b {
                out.append(BudgetAlert(key: "\(k.rawValue)-\(p.start)-100", title: "Ξεπεράστηκε το budget",
                                       body: "Ξεπέρασες το όριο του \(adj) budget."))
            } else if spent * 10 >= b * 8 {
                out.append(BudgetAlert(key: "\(k.rawValue)-\(p.start)-80", title: "Πλησιάζεις το όριο",
                                       body: "Έφτασες το \(spent * 100 / b)% του \(adj) budget."))
            }
        }
        for c in Logic.categoryBudgets(data, allocs: allocs, today: today) where c.budget > 0 {
            let adj = periodAdj[c.category.budgetPeriod]!
            let name = c.category.name
            if c.spent >= c.budget {
                out.append(BudgetAlert(key: "cat-\(c.category.id)-\(c.period.start)-100", title: "\(c.category.emoji) \(name): ξεπεράστηκε το όριο",
                                       body: "Ξεπέρασες το \(adj) όριο της κατηγορίας."))
            } else if c.spent * 10 >= c.budget * 8 {
                out.append(BudgetAlert(key: "cat-\(c.category.id)-\(c.period.start)-80", title: "\(c.category.emoji) \(name): πλησιάζεις το όριο",
                                       body: "Έφτασες το \(c.spent * 100 / c.budget)% του \(adj) ορίου της κατηγορίας."))
            }
        }
        let sent = Set(s.alertsSent)
        return out.filter { !sent.contains($0.key) }
    }
}

// MARK: - Category suggestions

public enum MerchantHints {
    private static let rules: [(String, String)] = [
        (#"lidl|σκλαβεν|sklavenitis|masoutis|μασούτ|\bab\b|vasilopoulos|βασιλόπουλ|my ?market|kritikos|κρητικός|galaxias|γαλαξίας|bazaar|market|μάρκετ|φούρν|bakery|φρουτ|κρεοπ|λαϊκή"#, "groceries"),
        (#"coffee|καφ|starbucks|everest|gregory|mikel|γρηγόρ"#, "coffee"),
        (#"efood|wolt|\bbox\b|pizza|πίτσα|souvlaki|σουβλ|ψητοπ|restaurant|εστιατ|ταβέρν|burger|mcdonald|goody"#, "food"),
        (#"shell|\bbp\b|\beko\b|avin|aegean|revoil|elin|καύσιμ|βενζίν|fuel|cyclon|jet oil"#, "fuel"),
        (#"shell|\bbp\b|\beko\b|avin|aegean|revoil|elin|καύσιμ|fuel|oasa|οασα|taxi|ταξί|uber|freenow|parking|στάθμευ|attiki odos|αττική οδός|metro|μετρό"#, "transport"),
        (#"φαρμακ|pharma|clinic|κλινικ|ιατρ|γιατρ|οδοντ"#, "health"),
        (#"netflix|spotify|apple\.com|icloud|disney|youtube|google|prime|vodafone|cosmote|\bnova\b|wind"#, "subs"),
        (#"δεη|\bdei\b|eydap|ευδαπ|ενοίκ|ikea|praktiker|leroy"#, "home"),
        (#"zara|h&m|bershka|pull ?& ?bear|jumbo|public|plaisio|πλαίσιο|kotsovolos|κωτσόβολ|skroutz|shein"#, "shopping"),
        (#"cinema|σινεμ|village|odeon|\bbar\b|club|θέατρ|ticket"#, "fun"),
    ]

    /// The user's own past choice for this store wins; otherwise a keyword guess.
    public static func category(for store: String, in data: AppData) -> String {
        let s = Logic.norm(store)
        guard !s.isEmpty else { return "other" }
        let ids = Set(data.categories.map(\.id))
        if let past = data.purchases.sorted(by: Purchase.newestFirst).first(where: { Logic.norm($0.store) == s }),
           let cat = past.items.first?.cat, ids.contains(cat) {
            return cat
        }
        let raw = store.lowercased()
        for (pattern, cat) in rules where ids.contains(cat) {
            if raw.range(of: pattern, options: .regularExpression) != nil { return cat }
        }
        return "other"
    }
}

public extension Purchase {
    static func newestFirst(_ a: Purchase, _ b: Purchase) -> Bool {
        a.date == b.date ? a.createdAt > b.createdAt : a.date > b.date
    }
}

// MARK: - Item history (same rules as js/logic.js)

public struct KnownItem: Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    /// The most used spelling.
    public var name: String
    public var count: Int
    /// Every spelling used, with how many times.
    public var spellings: [String: Int]
    /// Latest category, price, days and date.
    public let cat: String
    public let cents: Int
    public let days: Int
    public let last: String
}

public struct DuplicateItems: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let names: [String]
    public let count: Int
}

public enum ItemHistory {
    /// Ignores case, accents, final sigma, punctuation and extra spaces: "Γάλα  ", "γαλα" → "γαλα".
    public static func key(_ s: String) -> String {
        let folded = s.decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { !(0x300...0x36F).contains($0.value) }
        let lower = String(String.UnicodeScalarView(folded)).lowercased().replacingOccurrences(of: "ς", with: "σ")
        var out = ""
        var space = false
        for ch in lower {
            if ch.isLetter || ch.isNumber {
                if space && !out.isEmpty { out.append(" ") }
                out.append(ch)
                space = false
            } else {
                space = true
            }
        }
        return out
    }

    public static func known(_ purchases: [Purchase]) -> [KnownItem] {
        var map: [String: KnownItem] = [:]
        var order: [String] = []
        var seen: [String: [String]] = [:] // spellings, newest first
        for p in purchases.sorted(by: Purchase.newestFirst) {
            for i in p.items {
                let k = key(i.name)
                guard !k.isEmpty else { continue }
                if map[k] == nil {
                    map[k] = KnownItem(key: k, name: i.name, count: 0, spellings: [:], cat: i.cat, cents: i.cents, days: i.days, last: p.date)
                    order.append(k)
                }
                map[k]!.count += 1
                if map[k]!.spellings[i.name] == nil { seen[k, default: []].append(i.name) }
                map[k]!.spellings[i.name, default: 0] += 1
            }
        }
        var list: [KnownItem] = []
        for k in order {
            var item = map[k]!
            // most used spelling; ties keep the newest
            let names = seen[k] ?? [item.name]
            item.name = names.reduce(names[0]) { best, s in (item.spellings[s] ?? 0) > (item.spellings[best] ?? 0) ? s : best }
            list.append(item)
        }
        // stable: most used first, then newest
        return list.enumerated().sorted { a, b in
            if a.element.count != b.element.count { return a.element.count > b.element.count }
            if a.element.last != b.element.last { return a.element.last > b.element.last }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Edit distance where swapped neighbours count as one typo (optimal string alignment).
    public static func typoDistance(_ s1: String, _ s2: String, max: Int = 2) -> Int {
        let a = Array(s1), b = Array(s2)
        if abs(a.count - b.count) > max { return max + 1 }
        if a.isEmpty { return b.count }
        var prev2: [Int]? = nil
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i]
            var rowMin = i
            for j in stride(from: 1, through: b.count, by: 1) {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var v = Swift.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if let p2 = prev2, i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { v = Swift.min(v, p2[j - 2] + 1) }
                cur.append(v)
                rowMin = Swift.min(rowMin, v)
            }
            if rowMin > max { return max + 1 }
            prev2 = prev
            prev = cur
        }
        return prev[b.count]
    }

    static func typoLimit(_ n: Int) -> Int { n < 4 ? 0 : n < 8 ? 1 : 2 }

    /// The known item this name means. exact: only the spelling differs; otherwise a likely typo.
    public static func match(_ name: String, in known: [KnownItem]) -> (item: KnownItem, exact: Bool)? {
        let k = key(name)
        guard !k.isEmpty else { return nil }
        if let same = known.first(where: { $0.key == k }) { return (same, true) }
        let limit = typoLimit(k.count)
        var best: KnownItem?
        var bestD = limit + 1
        for o in known where typoLimit(o.key.count) > 0 {
            let d = typoDistance(k, o.key, max: limit)
            if d < bestD || (d == bestD && best != nil && o.count > best!.count) { best = o; bestD = d }
        }
        if let best, bestD <= limit { return (best, false) }
        return nil
    }

    /// Groups of names that are probably the same item, to merge.
    public static func duplicates(_ known: [KnownItem]) -> [DuplicateItems] {
        var groups: [DuplicateItems] = []
        var used = Set<String>()
        for k in known where !used.contains(k.key) {
            let others = k.spellings.keys.filter { $0 != k.name }.sorted()
            let similar = known.filter { o in
                guard o.key != k.key, !used.contains(o.key), typoLimit(o.key.count) > 0 else { return false }
                let lim = Swift.min(typoLimit(k.key.count), typoLimit(o.key.count))
                return typoDistance(k.key, o.key, max: lim) <= lim
            }
            if others.isEmpty && similar.isEmpty { continue }
            used.insert(k.key)
            for o in similar { used.insert(o.key) }
            groups.append(DuplicateItems(name: k.name, names: others + similar.flatMap { $0.spellings.keys.sorted() },
                                         count: k.count + similar.reduce(0) { $0 + $1.count }))
        }
        return groups
    }

    /// Renames every item spelled as one of `from` to `to`; returns how many changed.
    @discardableResult
    public static func rename(_ purchases: inout [Purchase], from: [String], to: String) -> Int {
        let set = Set(from)
        var n = 0
        for p in purchases.indices {
            for i in purchases[p].items.indices where set.contains(purchases[p].items[i].name) && purchases[p].items[i].name != to {
                purchases[p].items[i].name = to
                n += 1
            }
        }
        return n
    }
}
