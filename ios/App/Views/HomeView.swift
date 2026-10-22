import SpendingCore
import SwiftUI

struct HomeView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let data = store.data
        let today = store.today
        let allocs = Logic.allocations(Logic.regular(data.purchases))
        let general = Logic.general(allocs, categories: data.categories) // without categories that have their own fund

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if data.purchases.isEmpty && !data.settings.budgets.any {
                        WelcomeCard()
                    } else {
                        HeroCard(data: data, allocs: general, today: today)
                        PeriodsCard(data: data, allocs: general, today: today)
                        UnexpectedCard(data: data, today: today)
                        CategoryBudgetsCard(data: data, allocs: allocs, today: today)
                        let month = Logic.period(.month, today, weekStart: data.settings.weekStart)
                        let monthGeneral = general.filter { month.contains($0.date) }
                        let offDaily = Logic.sum(monthGeneral) - Logic.sum(Logic.daily(monthGeneral, categories: data.categories))
                        if offDaily > 0 {
                            Label("\(Fmt.money(offDaily)) σε γενικές πληρωμές αυτόν τον μήνα (συνδρομές κ.λπ.), εκτός ημερήσιου ορίου.", systemImage: "pin")
                                .font(.footnote).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                        }
                        let committed = Logic.sum(allocs.filter { $0.date > today })
                        if committed > 0 {
                            Label("\(Fmt.money(committed)) έχουν ήδη κατανεμηθεί σε επόμενες ημέρες.", systemImage: "calendar")
                                .font(.footnote).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                        }
                        let review = data.purchases.filter(\.review).sorted(by: Purchase.newestFirst)
                        if !review.isEmpty { ReviewCard(purchases: review) }
                        MonthCategoriesCard(data: data, allocs: allocs, today: today)
                        RecentCard(data: data)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Τα Οικονομικά μου")
            .toolbar { ToolbarItem(placement: .primaryAction) { AddButton() } }
        }
    }
}

private struct HeroCard: View {
    @Environment(Router.self) private var router
    let data: AppData
    let allocs: [Alloc]
    let today: String

    private static let basis: [PeriodKind: String] = [.day: "ημερήσιου", .week: "εβδομαδιαίου", .month: "μηνιαίου", .year: "ετήσιου"]

    var body: some View {
        // General payments (subscriptions etc.) stay out of the daily limit.
        let spent = Logic.sum(Logic.daily(allocs, categories: data.categories).filter { $0.date == today })
        let paidToday = Logic.sum(allocs.filter { $0.date == today }) - spent
        let allowance = Logic.todayAllowance(data, allocs: allocs, today: today)
        let allowed = max(0, allowance?.cents ?? 0)
        let left = allowed - spent
        let over = allowance != nil && left < 0

        VStack(alignment: .leading, spacing: 6) {
            if let allowance {
                Text(over ? "Υπέρβαση σήμερα" : "Διαθέσιμα σήμερα").font(.subheadline).opacity(0.9)
                Text(Fmt.money(abs(left))).font(.system(size: 42, weight: .heavy, design: .rounded)).monospacedDigit()
                ProgressBar(value: ratio(spent, allowed), color: .white, track: .white.opacity(0.25)).padding(.vertical, 4)
                Text(allowance.cents <= 0
                    ? "Το \(Self.basis[allowance.kind]!) budget έχει ήδη εξαντληθεί"
                    : "Ξόδεψες \(Fmt.money(spent)) από \(Fmt.money(allowed)) · βάσει \(Self.basis[allowance.kind]!) budget")
                    .font(.footnote).opacity(0.9)
                PaidTodayLine(cents: paidToday)
                if let day = data.settings.budgets.day {
                    DayBalanceLine(balance: Logic.dayBalance(budget: day, allocs: Logic.daily(allocs, categories: data.categories), today: today, since: data.settings.daySince),
                                   carry: data.settings.carryOver)
                }
            } else {
                Text("Ξόδεψες σήμερα").font(.subheadline).opacity(0.9)
                Text(Fmt.money(spent)).font(.system(size: 42, weight: .heavy, design: .rounded)).monospacedDigit()
                PaidTodayLine(cents: paidToday)
                Button("Όρισε budget για να βλέπεις τι σου απομένει →") { router.tab = .settings }
                    .font(.footnote.weight(.semibold)).foregroundStyle(.white)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: over ? [Color(red: 0.73, green: 0.11, blue: 0.11), Color(red: 0.6, green: 0.2, blue: 0.07)]
                : [Color.brand, Color(red: 0.05, green: 0.45, blue: 0.56)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

/// Today's general payments, shown apart since they do not count in the daily limit.
private struct PaidTodayLine: View {
    let cents: Int

    var body: some View {
        if cents > 0 {
            Text("📌 Και \(Fmt.money(cents)) σε γενικές πληρωμές, εκτός ημερήσιου ορίου").font(.footnote).opacity(0.9)
        }
    }
}

/// How far ahead of (or behind) the daily budget this month is, up to yesterday.
private struct DayBalanceLine: View {
    let balance: Int
    let carry: Bool

    var body: some View {
        if balance != 0 {
            let ahead = balance > 0
            let note = carry ? (ahead ? " · προστέθηκαν στο σήμερα" : " · αφαιρέθηκαν από το σήμερα") : ""
            Text("\(ahead ? "🐷 " : "")Αυτόν τον μήνα είσαι **\(ahead ? "+" : "−")\(Fmt.money(abs(balance)))** \(ahead ? "κάτω από" : "πάνω από") το ημερήσιο budget\(note)")
                .font(.footnote)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 6)
        }
    }
}

/// The month's unexpected expenses against their own fund.
private struct UnexpectedCard: View {
    let data: AppData
    let today: String

    var body: some View {
        let p = Logic.period(.month, today, weekStart: data.settings.weekStart)
        let spent = Logic.sum(Logic.allocations(data.purchases.filter(\.unexpected)).filter { p.contains($0.date) })
        let budget = data.settings.unexpectedBudget
        if budget != nil || spent > 0 {
            Card {
                HStack {
                    Text("⚡ Ταμείο απροόπτων").font(.subheadline)
                    Spacer()
                    Text(Fmt.money(spent)).bold().monospacedDigit()
                    if let budget { Text("/ \(Fmt.money(budget))").foregroundStyle(.secondary).monospacedDigit() }
                }
                if let budget {
                    ProgressBar(value: ratio(spent, budget), color: levelColor(ratio(spent, budget)))
                    Text(spent <= budget ? "απομένουν \(Fmt.money(budget - spent)) αυτόν τον μήνα" : "υπέρβαση \(Fmt.money(spent - budget))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Όρισε ποσό για απρόοπτα στις Ρυθμίσεις").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct PeriodsCard: View {
    let data: AppData
    let allocs: [Alloc]
    let today: String

    private static let names: [PeriodKind: String] = [.week: "Αυτή την εβδομάδα", .month: "Αυτόν τον μήνα", .year: "Φέτος"]

    var body: some View {
        let kinds = [PeriodKind.week, .month] + (data.settings.budgets.year != nil ? [.year] : [])
        Card {
            ForEach(kinds) { kind in
                let p = Logic.period(kind, today, weekStart: data.settings.weekStart)
                let spent = Logic.sum(allocs.filter { p.contains($0.date) })
                let budget = data.settings.budgets[kind]
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(Self.names[kind]!)
                        Spacer()
                        Text(Fmt.money(spent)).fontWeight(.semibold).monospacedDigit()
                        if let budget { Text("/ \(Fmt.money(budget))").foregroundStyle(.secondary).monospacedDigit() }
                    }
                    if let budget {
                        ProgressBar(value: ratio(spent, budget), color: levelColor(ratio(spent, budget)))
                        Text(spent <= budget ? "απομένουν \(Fmt.money(budget - spent))" : "υπέρβαση \(Fmt.money(spent - budget))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if kind != kinds.last { Divider().padding(.vertical, 2) }
            }
        }
    }
}

private struct CategoryBudgetsCard: View {
    @Environment(Router.self) private var router
    let data: AppData
    let allocs: [Alloc]
    let today: String

    var body: some View {
        let list = Logic.categoryBudgets(data, allocs: allocs, today: today).sorted { $0.ratio > $1.ratio }
        if !list.isEmpty {
            Card {
                HStack {
                    Text("Όρια κατηγοριών").font(.headline)
                    Spacer()
                    Button("Ρύθμιση") { router.tab = .settings }.font(.subheadline)
                }
                ForEach(list, id: \.category.id) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("\(s.category.emoji) \(s.category.name)").lineLimit(1)
                            Text(s.category.budgetPeriod == .week ? "εβδ." : "μήνας")
                                .font(.caption2).foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                            if s.category.ownFund { Text("🧺").font(.caption2).accessibilityLabel("Δικό της ταμείο") }
                            if s.category.budgetChanges > 0 { BudgetChangesBadge(count: s.category.budgetChanges) }
                            Spacer()
                            Text(Fmt.money(s.spent)).fontWeight(.semibold).monospacedDigit()
                            Text("/ \(Fmt.money(s.budget))").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.subheadline)
                        ProgressBar(value: s.ratio, color: levelColor(s.ratio))
                        Text(s.spent <= s.budget ? "απομένουν \(Fmt.money(s.budget - s.spent))" : "υπέρβαση \(Fmt.money(s.spent - s.budget))")
                            .font(.caption).foregroundStyle(s.spent <= s.budget ? Color.secondary : Color.red)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct ReviewCard: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    let purchases: [Purchase]

    var body: some View {
        Card {
            Label("Πληρωμές Apple Pay προς έλεγχο", systemImage: "apple.logo").font(.headline)
            Text("Πάτα για να διορθώσεις κατηγορία ή να τις χωρίσεις σε προϊόντα. Με ✓ τις κρατάς όπως είναι.")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(purchases) { p in
                HStack {
                    Button { router.edit(p) } label: { PurchaseRow(purchase: p, category: store.data.category(p.items.first?.cat ?? "other")) }
                        .buttonStyle(.plain)
                    Button {
                        var done = p
                        done.review = false
                        store.upsert(done)
                    } label: {
                        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Σωστό")
                }
            }
        }
    }
}

private struct MonthCategoriesCard: View {
    @Environment(Router.self) private var router
    let data: AppData
    let allocs: [Alloc]
    let today: String

    var body: some View {
        let p = Logic.period(.month, today)
        let groups = Dictionary(grouping: allocs.filter { p.contains($0.date) }, by: \.cat)
            .map { (cat: $0.key, cents: Logic.sum($0.value)) }
            .sorted { $0.cents > $1.cents }
        if !groups.isEmpty {
            Card {
                HStack {
                    Text("Κατηγορίες αυτόν τον μήνα").font(.headline)
                    Spacer()
                    Button("Όλα") { router.tab = .stats }.font(.subheadline)
                }
                ForEach(groups.prefix(6), id: \.cat) { g in
                    CategoryBar(category: data.category(g.cat), cents: g.cents, max: groups[0].cents,
                                budget: data.category(g.cat).budgetPeriod == .month ? data.category(g.cat).budget : nil)
                }
            }
        }
    }
}

private struct RecentCard: View {
    @Environment(Router.self) private var router
    let data: AppData

    var body: some View {
        let recent = data.purchases.sorted(by: Purchase.newestFirst).prefix(5)
        Card {
            HStack {
                Text("Πρόσφατες αγορές").font(.headline)
                Spacer()
                if !data.purchases.isEmpty { Button("Όλες") { router.tab = .history }.font(.subheadline) }
            }
            if recent.isEmpty {
                Text("Δεν υπάρχουν ακόμη αγορές. Πάτα + για να προσθέσεις.").foregroundStyle(.secondary).font(.subheadline)
            }
            ForEach(Array(recent)) { p in
                Button { router.edit(p) } label: { PurchaseRow(purchase: p, category: data.category(p.items.first?.cat ?? "other")) }
                    .buttonStyle(.plain)
                if p.id != recent.last?.id { Divider() }
            }
        }
    }
}

private struct WelcomeCard: View {
    @Environment(Router.self) private var router

    var body: some View {
        Card {
            VStack(spacing: 12) {
                Text("👋").font(.system(size: 44))
                Text("Καλώς ήρθες!").font(.title2.bold())
                Text("Κατέγραψε τις αγορές σου προϊόν-προϊόν, όρισε budget ανά ημέρα, εβδομάδα ή μήνα και δες πού πάνε τα χρήματά σου.")
                    .multilineTextAlignment(.center)
                Label("Τα δεδομένα μένουν μόνο σε αυτό το iPhone.", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { router.newPurchase() } label: { Text("Πρόσθεσε την πρώτη αγορά").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button { router.tab = .settings } label: { Text("Όρισε budget").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .padding(.top, 8)
    }
}
