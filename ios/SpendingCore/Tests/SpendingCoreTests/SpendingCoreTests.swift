import Foundation
import Testing
@testable import SpendingCore

@Test func parsesMoney() {
    #expect(Money.toCents("12,50") == 1250)
    #expect(Money.toCents("12.5") == 1250)
    #expect(Money.toCents("€ 1.234,56") == 123456)
    #expect(Money.toCents("1,234.56") == 123456)
    #expect(Money.toCents("0,1") == 10)
    #expect(Money.toCents("") == nil)
    #expect(Money.toCents("abc") == nil)
    #expect(Money.inputText(1250) == "12,50")
}

@Test func splitKeepsTotal() {
    #expect(Logic.split(1000, 3) == [334, 333, 333])
    #expect(Logic.split(9999, 7).reduce(0, +) == 9999)
}

@Test func spreadsAcrossDays() {
    let p = Purchase(id: "p", date: "2026-10-30", items: [
        Item(name: "Κοτόπουλο", cents: 900, cat: "groceries", days: 3),
        Item(name: "Καφές", cents: 250, cat: "coffee", days: 1),
    ])
    let spread = Logic.allocations([p])
    #expect(spread.map { "\($0.date):\($0.cents)" } == ["2026-10-30:300", "2026-10-31:300", "2026-11-01:300", "2026-10-30:250"])
    #expect(Logic.sum(Logic.allocations([p], mode: .paid).filter { $0.date == "2026-10-30" }) == 1150)
}

@Test func periods() {
    #expect(Logic.period(.week, "2026-10-10") == Period(start: "2026-10-05", end: "2026-10-11"))
    #expect(Logic.period(.week, "2026-10-11", weekStart: 0) == Period(start: "2026-10-11", end: "2026-10-17"))
    #expect(Logic.period(.month, "2026-02-15") == Period(start: "2026-02-01", end: "2026-02-28"))
    #expect(Logic.period(.month, "2026-12-15") == Period(start: "2026-12-01", end: "2026-12-31"))
    #expect(Logic.shift(.month, "2026-12-31", by: 1) == "2027-01-01")
    #expect(Logic.shift(.month, "2026-01-15", by: -1) == "2025-12-01")
    #expect(Days.add("2026-03-28", 2) == "2026-03-30")
    #expect(Logic.label(.month, Logic.period(.month, "2026-10-10")) == "Οκτώβριος 2026")
    #expect(Days.isValid("2026-02-30") == false)
    #expect(Days.isValid("2026-02-28"))
}

@Test func dailyAllowance() {
    let allocs = [
        Alloc(date: "2026-10-05", cents: 5000, cat: "x", name: "", pid: "a"),
        Alloc(date: "2026-10-12", cents: 1000, cat: "x", name: "", pid: "b"),
        Alloc(date: "2026-10-11", cents: 700, cat: "x", name: "", pid: "c"),
    ]
    #expect(Logic.dailyAllowance(budget: 31000, allocs: allocs, kind: .month, today: "2026-10-11") == (31000 - 5000 - 1000) / 21)
}

@Test func parsesShortcutText() {
    #expect(Logic.parseTransaction("€12,50;Lidl")! == (1250, "Lidl"))
    #expect(Logic.parseTransaction("Σκλαβενίτης\n7,30 €")! == (730, "Σκλαβενίτης"))
    #expect(Logic.parseTransaction("hello") == nil)
}

@Test func alertsFireOnceAt80And100Percent() {
    var data = AppData()
    data.settings.budgets.month = 10000
    data.purchases = [Purchase(date: "2026-10-05", items: [Item(name: "x", cents: 8500, cat: "other")])]
    let a = Alerts.pending(data, today: "2026-10-10")
    #expect(a.map(\.key) == ["month-2026-10-01-80"])
    data.settings.alertsSent = a.map(\.key)
    #expect(Alerts.pending(data, today: "2026-10-10").isEmpty)
    data.purchases.append(Purchase(date: "2026-10-06", items: [Item(name: "y", cents: 2000, cat: "other")]))
    #expect(Alerts.pending(data, today: "2026-10-10").map(\.key) == ["month-2026-10-01-100"])
}

@Test func merchantHints() {
    let data = AppData()
    #expect(MerchantHints.category(for: "LIDL HELLAS", in: data) == "groceries")
    #expect(MerchantHints.category(for: "Shell Κηφισίας", in: data) == "fuel")
    #expect(MerchantHints.category(for: "Uber", in: data) == "transport")
    #expect(MerchantHints.category(for: "Άγνωστο", in: data) == "other")
}

@Test func sanitizeRejectsBadValues() {
    var data = AppData()
    data.categories.append(Category(id: "bad", name: "", emoji: "", color: "red"))
    data.purchases = [
        Purchase(date: "not-a-date", items: [Item(name: "a", cents: 100)]),
        Purchase(date: "2026-10-10", items: [Item(name: "", cents: -5), Item(name: "b", cents: 100, cat: "missing", days: 0)]),
    ]
    let s = data.sanitized()
    #expect(s.purchases.count == 1)
    #expect(s.purchases[0].items == [Item(id: s.purchases[0].items[0].id, name: "b", cents: 100, cat: "other", days: 1)])
    #expect(s.categories.last!.color == "#64748b")
}

@Test func backupRoundTrip() throws {
    var data = AppData()
    data.purchases = [Purchase(date: "2026-10-10", store: "Lidl", items: [Item(name: "Γάλα", cents: 149, cat: "groceries")])]
    let plain = try Backup.export(data)
    #expect(try Backup.load(plain).purchases == data.purchases)
    let enc = try Backup.export(data, password: "secret123", iterations: 100_000)
    #expect(Backup.isEncrypted(enc))
    #expect(throws: BackupError.wrongPassword) { try Backup.load(enc, password: "nope") }
    #expect(throws: BackupError.needsPassword) { try Backup.load(enc) }
    #expect(try Backup.load(enc, password: "secret123").purchases == data.purchases)
}

// Encrypted by the web app (js/crypto.js) — proves the formats are compatible.
@Test func readsWebAppBackup() throws {
    let file = Data(#"""
{"app":"spending-app","format":1,"encrypted":true,"salt":"IEZKHnyDdas5l/GffaufrQ==","iterations":100000,"iv":"w3gSxgN0Zna6Cqza","ct":"CJRjVmEsS8qEv5fqAwXpcefqPVIlyWd1BidaqIk8/vc1nwBtXq+euz4qP6BCMAfG2F335P0XGU4nAzmBqESg9qYIZcypSzC5C76vWWXq/6scvEvkNbenFl9qMaYahcRikwsheX8CF8IAnI8KB8Dled3FkTnRnFnKMQUtypdF5RQmNQj/lqjc6YSGKnkg8a6pB23DSh5tyeRP9QLwVrASrcxpe1vxUTbKjV8XIBEKWN7s8ujbSUGz7yAtExxUcSMi8vd1d+iPagrMgJSHeWvp1xJUA8pf5jgqPVBpugRd69fI33qVA3aUYBJS+yz3JkCkEBvnGqR753FBrfkCRRernICs1w7bo6qN0fTUzCoeFFUmAqWLnGfp/NbHdWkDGi7UydL/wdZtPnYR+mP9Vb5WuoanBgT1TBtdCeom0eZF/2/nkkkQAeH3wdec6F/CyvLxHpdCSXs2bWBfJAvGwgUC6BhIVxgW8mmUoxKi8nMCOJ46zDM2iu1YNxFaOJMA5uR5whHw9NfjdvCn48zflxJg4Sj4FVSy3olwA7xMLOHGOYcqxd6x4U6SaPu2eNqfqU4uxdqXznyxQ67rHh7Ve8icfCK0luu5DZPuMFoi5VQzM8pgiF/8L7iEVjz9SGmNwYsHhfVR4z42t7COd65X3KsrPPAiyy+j6UV2rzyZ7wzqgW5Ujzf0zKtUwZ78YvfsBGuzHnnNsbaWN+7+9BLgCHtpdyL9Bf4laqqJ","exportedAt":"x"}
"""#.utf8)
    let data = try Backup.load(file, password: "secret123")
    #expect(data.settings.budgets.month == 40000)
    #expect(data.purchases.first?.items.first?.name == "Κοτόπουλο")
    #expect(data.purchases.first?.items.first?.days == 3)
}

@Test func categoryBudgetHistoryCountsChanges() {
    var c = Cat0()
    let first = c.setBudget(20000, period: .month, at: 1)
    #expect(first)
    #expect(c.budgetChanges == 0) // first time is not a change
    let same = c.setBudget(20000, period: .month, at: 2) // same value: nothing recorded
    #expect(!same)
    c.setBudget(25000, period: .month, at: 3)
    c.setBudget(6000, period: .week, at: 4)
    c.setBudget(nil, period: .week, at: 5)
    #expect(c.budgetChanges == 3)
    #expect(c.budgetHistory.count == 4)
    #expect(c.budgetHistory[2].fromPeriod == .month && c.budgetHistory[2].period == .week)
}

private func Cat0() -> SpendingCore.Category { SpendingCore.Category(id: "fuel", name: "Καύσιμα", emoji: "⛽", color: "#0891b2") }

@Test func categoryBudgetUsesItsOwnPeriod() {
    var data = AppData()
    let i = data.categories.firstIndex { $0.id == "fuel" }!
    data.categories[i].setBudget(5000, period: .week)
    data.purchases = [
        Purchase(date: "2026-10-05", items: [Item(name: "Βενζίνη", cents: 3000, cat: "fuel")]), // Monday, this week
        Purchase(date: "2026-10-01", items: [Item(name: "Βενζίνη", cents: 9000, cat: "fuel")]), // previous week
    ]
    let st = Logic.categoryBudgets(data, allocs: Logic.allocations(data.purchases), today: "2026-10-10")
    #expect(st.count == 1 && st[0].spent == 3000 && st[0].period == Period(start: "2026-10-05", end: "2026-10-11"))
    data.purchases.append(Purchase(date: "2026-10-09", items: [Item(name: "Βενζίνη", cents: 1500, cat: "fuel")]))
    let keys = Alerts.pending(data, today: "2026-10-10").map(\.key)
    #expect(keys == ["cat-fuel-2026-10-05-80"])
}

@Test func migrationAddsFuelOnce() throws {
    let old = ##"{"schema":1,"settings":{},"categories":[{"id":"transport","name":"Μετακινήσεις","emoji":"🚗","color":"#2563eb","budget":null},{"id":"other","name":"Άλλα","emoji":"📦","color":"#64748b","budget":5000}],"purchases":[]}"##
    let d = try JSONDecoder().decode(AppData.self, from: Data(old.utf8)).sanitized()
    #expect(d.categories.map(\.id) == ["transport", "fuel", "other"])
    #expect(d.categories[2].budgetPeriod == .month && d.categories[2].budget == 5000)
    // a user who deleted it later does not get it back
    var again = d
    again.categories.removeAll { $0.id == "fuel" }
    #expect(!again.sanitized().categories.contains { $0.id == "fuel" })
}

// Same password → same keys as the web app (js/sync.js), so both can open the account.
@Test func accountKeysMatchWebApp() throws {
    let k = try AccountKeys.derive(username: "andreas", password: "σωστό άλογο μπαταρία")
    #expect(k.encKey.base64EncodedString() == "UL+KcMHNj5C/nqEffBNWUL25JKbgAkoNvx9hc+G8X5E=")
    #expect(k.auth.base64EncodedString() == "zMlYs3zQSVc6FOqXnJGu+92eRk3F2vj9LPl0yhzIzhE=")
}

private func pur(_ id: String, _ cents: Int, updated: Double = 0) -> Purchase {
    Purchase(id: id, date: "2026-10-10", createdAt: 1, updatedAt: updated, items: [Item(id: "i\(id)", name: id, cents: cents, cat: "other")])
}

@Test func stampChangesMarksEditsAdditionsDeletions() {
    var prev = AppData()
    prev.purchases = [pur("a", 100), pur("b", 200)]
    var next = prev
    next.purchases[0].items[0].cents = 150
    next.purchases.remove(at: 1)
    next.purchases.append(pur("c", 300))
    next.settings.budgets.month = 2000
    SyncMerge.stampChanges(prev: prev, next: &next, now: 50)
    #expect(next.purchases.map { "\($0.id):\(Int($0.updatedAt))" } == ["a:50", "c:50"])
    #expect(next.deleted == ["b": 50])
    #expect(next.settingsUpdatedAt == 50 && next.categoriesUpdatedAt == 0)
}

@Test func mergeKeepsBothSidesAndRespectsDeletions() {
    var remote = AppData()
    remote.purchases = [pur("a", 100, updated: 10), pur("b", 200), pur("d", 1, updated: 40)]
    remote.deleted = ["x": 5]
    remote.settingsUpdatedAt = 30
    remote.settings.budgets.month = 3000
    var local = AppData()
    local.purchases = [pur("a", 999, updated: 20), pur("c", 300, updated: 20), pur("d", 1, updated: 40)]
    local.deleted = ["b": 15, "d": 30]
    local.settingsUpdatedAt = 20
    let m = SyncMerge.merge(local: local, remote: remote, now: 100)
    #expect(m.purchases.map { "\($0.id):\($0.items[0].cents)" }.sorted() == ["a:999", "c:300", "d:1"])
    #expect(m.settings.budgets.month == 3000)
    #expect(m.deleted == ["x": 5, "b": 15, "d": 30])
}

@Test func freshDeviceAdoptsAccountData() {
    var remote = AppData()
    remote.settings.budgets.month = 5000
    let m = SyncMerge.merge(local: AppData(), remote: remote, now: 1)
    #expect(m.settings.budgets.month == 5000)
}

@Test func dayBalanceMatchesWebApp() {
    let a = { (date: String, cents: Int) in Alloc(date: date, cents: cents, cat: "other", name: "x", pid: "p") }
    // 10 € a day; 12-14 Oct: spent 8, 0, 13 → +2 +10 -3 = +9 by the 15th
    let allocs = [a("2026-10-12", 800), a("2026-10-14", 1300), a("2026-10-15", 500), a("2026-10-10", 9999)]
    #expect(Logic.dayBalance(budget: 1000, allocs: allocs, today: "2026-10-15", since: "2026-10-12") == 900)
    #expect(Logic.dayBalance(budget: 1000, allocs: allocs, today: "2026-10-12", since: "2026-10-01") == 1000)
    #expect(Logic.dayBalance(budget: 1000, allocs: allocs, today: "2026-10-12", since: "2026-10-12") == 0)
    #expect(Logic.dayBalance(budget: 1000, allocs: [a("2026-11-01", 400)], today: "2026-11-02", since: "2026-10-12") == 600)

    var data = AppData()
    data.settings.budgets.day = 1000
    data.settings.daySince = "2026-10-12"
    #expect(Logic.todayAllowance(data, allocs: allocs, today: "2026-10-15")?.cents == 1900)
    data.settings.carryOver = false
    #expect(Logic.todayAllowance(data, allocs: allocs, today: "2026-10-15")?.cents == 1000)
}

@Test func unexpectedExpensesStayOutOfBudgets() throws {
    var data = AppData()
    data.settings.budgets.day = 1000
    data.settings.daySince = "2026-10-12"
    data.purchases = [
        Purchase(date: "2026-10-15", items: [Item(name: "Ψωμί", cents: 300, cat: "groceries")]),
        Purchase(date: "2026-10-15", unexpected: true, items: [Item(name: "Συνεργείο", cents: 25000, cat: "transport")]),
    ]
    let allocs = Logic.allocations(Logic.regular(data.purchases))
    #expect(Logic.sum(allocs) == 300)
    #expect(Logic.allocations(data.purchases).filter(\.unexpected).count == 1)
    // Alerts ignore the unexpected expense: 3 € of 10 € is fine
    #expect(Alerts.pending(data, today: "2026-10-15").isEmpty)

    // The flag and the fund survive a round trip through the web app's format
    data.settings.unexpectedBudget = 10000
    let decoded = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data)).sanitized()
    #expect(decoded.purchases.filter(\.unexpected).count == 1)
    #expect(decoded.settings.unexpectedBudget == 10000)
}

@Test func itemHistoryMatchesWebApp() {
    func p(_ id: String, _ date: String, _ items: [(String, Int)]) -> Purchase {
        Purchase(id: id, date: date, items: items.map { Item(name: $0.0, cents: $0.1, cat: "groceries") })
    }
    var ps = [
        p("a", "2026-10-01", [("Γάλα", 150)]),
        p("b", "2026-10-02", [("Γάλα", 160), ("Ψωμί", 90)]),
        p("c", "2026-10-03", [("γαλα", 155), ("Τυρί", 400)]),
        p("d", "2026-10-04", [("Μπανάνες", 200), ("Μπανανες ", 210), ("Μπαννάες", 190)]),
    ]
    #expect(ItemHistory.key("  Γάλα,  φρέσκο ") == "γαλα φρεσκο")
    #expect(ItemHistory.key("Χυμός") == ItemHistory.key("χυμοσ"))
    let known = ItemHistory.known(ps)
    let milk = known.first { $0.key == "γαλα" }!
    #expect(milk.name == "Γάλα")
    #expect(milk.count == 3)
    #expect(milk.cents == 155)

    #expect(ItemHistory.match("ΓΑΛΑ", in: known)?.exact == true)
    #expect(ItemHistory.match("Γλάα", in: known)?.item.name == "Γάλα")
    #expect(ItemHistory.match("Γλάα", in: known)?.exact == false)
    #expect(ItemHistory.match("Γάλλα", in: known)?.item.name == "Γάλα")
    #expect(ItemHistory.match("Τυρι", in: known)?.exact == true)
    #expect(ItemHistory.match("Τυρόπιτα", in: known) == nil)
    #expect(ItemHistory.match("Ρύζι", in: known) == nil)
    #expect(ItemHistory.match("Μπαμιές", in: known) == nil)
    #expect(ItemHistory.match("", in: known) == nil)

    #expect(ItemHistory.typoDistance("abcd", "abdc") == 1)
    #expect(ItemHistory.typoDistance("kitten", "sitting", max: 3) == 3)

    let dups = ItemHistory.duplicates(known)
    #expect(dups.map(\.name) == ["Γάλα", "Μπανάνες"])
    #expect(dups[1].names.sorted() == ["Μπανανες ", "Μπαννάες"].sorted())

    #expect(ItemHistory.rename(&ps, from: dups[1].names, to: "Μπανάνες") == 2)
    #expect(ps[3].items.map(\.name) == ["Μπανάνες", "Μπανάνες", "Μπανάνες"])
}
