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
    let money = { (c: Int) in "\(c)" }
    let a = Alerts.pending(data, today: "2026-10-10", money: money)
    #expect(a.map(\.key) == ["month-2026-10-01-80"])
    data.settings.alertsSent = a.map(\.key)
    #expect(Alerts.pending(data, today: "2026-10-10", money: money).isEmpty)
    data.purchases.append(Purchase(date: "2026-10-06", items: [Item(name: "y", cents: 2000, cat: "other")]))
    #expect(Alerts.pending(data, today: "2026-10-10", money: money).map(\.key) == ["month-2026-10-01-100"])
}

@Test func merchantHints() {
    let data = AppData()
    #expect(MerchantHints.category(for: "LIDL HELLAS", in: data) == "groceries")
    #expect(MerchantHints.category(for: "Shell Κηφισίας", in: data) == "transport")
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
