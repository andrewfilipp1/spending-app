import Charts
import SpendingCore
import SwiftUI

struct NutritionView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @State private var section = 0
    @State private var date: String?

    var body: some View {
        let today = store.today
        let day = date ?? today
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Προβολή", selection: $section) {
                        Text("Διατροφή").tag(0)
                        Text("Σώμα").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if section == 0 {
                        DayPicker(date: day, today: today) { date = $0 == today ? nil : $0 }
                        GoalCard(day: day, today: today)
                        MacrosCard(day: day)
                        MealsCard(day: day)
                        if day == today { BoughtTodayCard(today: today) }
                        WeekCard(today: today)
                    } else {
                        BodyView()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Διατροφή")
            .refreshable { await Health.shared.refresh() }
            .task { await Health.shared.refresh() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { router.photo = true } label: { Image(systemName: "camera.fill") }
                        .accessibilityLabel("Φωτογραφία φαγητού")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { router.newMeal(date: day) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .accessibilityLabel("Νέο γεύμα")
                }
            }
        }
    }
}

private struct DayPicker: View {
    let date: String
    let today: String
    let pick: (String) -> Void

    var body: some View {
        HStack {
            Button { pick(Days.add(date, -1)) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Προηγούμενη ημέρα")
            Spacer()
            Text(Days.label(date, today: today)).font(.headline)
            Spacer()
            Button { pick(Days.add(date, 1)) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Επόμενη ημέρα")
                .disabled(date >= today)
        }
        .padding(.horizontal, 8)
    }
}

/// "You can eat X kcal today", like the home screen's "available today".
private struct GoalCard: View {
    @Environment(Store.self) private var store
    let day: String
    let today: String

    var body: some View {
        let n = store.data.nutrition
        let eaten = NutritionLogic.day(store.data.meals, day).kcal
        let energy = day == today ? Health.shared.energy : nil
        let goal = NutritionLogic.kcalGoal(n, health: energy)

        if let goal, goal > 0 {
            let left = goal - eaten
            HStack(spacing: 18) {
                Ring(value: Double(eaten) / Double(goal), label: "\(Fmt.kcal(abs(left)))", caption: left < 0 ? "kcal πάνω" : "kcal ακόμα")
                VStack(alignment: .leading, spacing: 6) {
                    Text(left < 0 ? "Πάνω από τον στόχο" : day == today ? "Μπορείς να φας σήμερα" : "Απέμειναν").font(.headline)
                    Text("Έφαγες \(Fmt.kcal(eaten)) από \(Fmt.kcal(goal)) kcal").font(.subheadline)
                    if n.useHealth, let e = energy {
                        Label("+\(Fmt.kcal(Int(e.activeKcal))) kcal από κίνηση", systemImage: "bolt.fill").font(.footnote)
                        Text("Ηρεμίας \(Fmt.kcal(Int(e.restingKcal)))\(n.kcalAdjust == 0 ? "" : " · προσαρμογή \(n.kcalAdjust > 0 ? "+" : "")\(n.kcalAdjust)")")
                            .font(.footnote).opacity(0.9)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(left < 0 ? Color.orange.gradient : Color.brand.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            Card {
                Text("Έφαγες \(Fmt.kcal(eaten)) kcal").font(.title2.bold())
                Text("Βάλε στόχο θερμίδων στις Ρυθμίσεις → Διατροφή, ή άφησε τον στόχο να ακολουθεί το ρολόι σου.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct Ring: View {
    let value: Double
    let label: String
    let caption: String

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 12)
            Circle().trim(from: 0, to: min(max(value, 0), 1))
                .stroke(.white, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(label).font(.system(size: 24, weight: .heavy, design: .rounded)).monospacedDigit()
                Text(caption).font(.caption2)
            }
        }
        .frame(width: 112, height: 112)
        .animation(.easeOut(duration: 0.3), value: value)
        .accessibilityElement(children: .combine)
    }
}

private struct MacrosCard: View {
    @Environment(Store.self) private var store
    let day: String

    var body: some View {
        let t = NutritionLogic.day(store.data.meals, day)
        let n = store.data.nutrition
        Card {
            HStack(alignment: .top, spacing: 14) {
                Macro(name: "Πρωτεΐνη", value: t.protein, goal: n.proteinGoal, color: .blue)
                Macro(name: "Υδατάνθρακες", value: t.carbs, goal: n.carbsGoal, color: .orange)
                Macro(name: "Λιπαρά", value: t.fat, goal: n.fatGoal, color: .brown)
            }
        }
    }
}

private struct Macro: View {
    let name: String
    let value: Double
    let goal: Int?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(value.rounded()))").font(.headline).monospacedDigit()
                Text(goal.map { "/ \($0) g" } ?? "g").font(.caption).foregroundStyle(.secondary)
            }
            if let goal { ProgressBar(value: goal > 0 ? value / Double(goal) : 0, color: color) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MealsCard: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    let day: String

    var body: some View {
        let meals = store.data.meals.filter { $0.date == day }.sorted { $0.createdAt < $1.createdAt }
        Card {
            if meals.isEmpty {
                Text("Κανένα γεύμα ακόμα. Πάτα + ή την κάμερα για να προσθέσεις.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(MealKind.allCases) { kind in
                let list = meals.filter { $0.meal == kind }
                if !list.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(kind.title.uppercased())
                            Spacer()
                            Text("\(Fmt.kcal(list.reduce(0) { $0 + $1.kcal })) kcal").monospacedDigit()
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(list) { m in
                            Button { router.edit(m) } label: { MealRow(meal: m) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { store.deleteMeal(m.id) } label: { Label("Διαγραφή", systemImage: "trash") }
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct MealRow: View {
    @Environment(Store.self) private var store
    let meal: Meal

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Fmt.kcal(meal.kcal))").monospacedDigit()
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts = ["Π \(Int(meal.protein.rounded())) · Υ \(Int(meal.carbs.rounded())) · Λ \(Int(meal.fat.rounded()))"]
        if meal.source == "photo" { parts.append("εκτίμηση από φωτογραφία") }
        if let id = meal.itemId, let item = store.data.purchases.lazy.flatMap(\.items).first(where: { $0.id == id }) {
            parts.append(Fmt.money(item.cents))
        }
        return parts.joined(separator: " · ")
    }
}

/// Food and drinks bought today that are not logged as eaten yet.
private struct BoughtTodayCard: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    let today: String

    private static let foodCategories: Set<String> = ["food", "coffee"]

    var body: some View {
        let linked = Set(store.data.meals.compactMap(\.itemId))
        let items = store.data.purchases.filter { $0.date == today }
            .flatMap { p in p.items.map { (purchase: p, item: $0) } }
            .filter { Self.foodCategories.contains($0.item.cat) && !linked.contains($0.item.id) }
        if !items.isEmpty {
            Card {
                Label("Από τις σημερινές αγορές", systemImage: "bag").font(.subheadline.weight(.semibold))
                ForEach(items.prefix(4), id: \.item.id) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.item.name)
                            Text("\(e.purchase.store.isEmpty ? store.data.category(e.item.cat).name : e.purchase.store) · \(Fmt.money(e.item.cents))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Το έφαγα") { router.newMeal(date: today, from: e) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
    }
}

/// The last 7 days against the goal, and what eating costs.
private struct WeekCard: View {
    @Environment(Store.self) private var store
    let today: String

    var body: some View {
        let data = store.data
        let days = (0..<7).map { Days.add(today, $0 - 6) }
        let totals = days.map { (day: $0, kcal: NutritionLogic.day(data.meals, $0).kcal) }
        let goal = data.nutrition.kcalGoal
        let logged = totals.filter { $0.kcal > 0 }
        let costs = NutritionLogic.costs(data.meals.filter { $0.date >= days[0] }, purchases: data.purchases)

        if !logged.isEmpty {
            Card {
                HStack {
                    Text("Τελευταίες 7 ημέρες").font(.headline)
                    Spacer()
                    Text("μ.ό. \(Fmt.kcal(logged.reduce(0) { $0 + $1.kcal } / logged.count)) kcal").font(.subheadline).foregroundStyle(.secondary)
                }
                Chart {
                    ForEach(totals, id: \.day) { t in
                        BarMark(x: .value("Ημέρα", Days.short(t.day)), y: .value("kcal", t.kcal))
                            .foregroundStyle(goal.map { t.kcal > $0 } == true ? Color.orange : Color.brand)
                            .cornerRadius(4)
                    }
                    if let goal {
                        RuleMark(y: .value("Στόχος", goal)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 140)
                ForEach(costs) { c in
                    if let per = c.per1000kcal {
                        HStack {
                            Text("\(data.category(c.cat).emoji) \(data.category(c.cat).name)")
                            Spacer()
                            Text("\(Fmt.money(per)) / 1.000 kcal").monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }
}

// MARK: - body (Health)

private struct BodyView: View {
    @Environment(Store.self) private var store
    @State private var asking = false

    var body: some View {
        let health = Health.shared
        if !health.available {
            Card { Text("Η εφαρμογή Υγεία δεν είναι διαθέσιμη σε αυτή τη συσκευή.").foregroundStyle(.secondary) }
        } else if !store.data.nutrition.useHealth {
            Card {
                Label("Σύνδεση με την Υγεία", systemImage: "heart.fill").font(.headline).foregroundStyle(.red)
                Text("Διάβασε βήματα, θερμίδες κίνησης, ύπνο, παλμούς και βάρος από το ρολόι σου (μέσω της εφαρμογής Υγεία), και κράτα τα γεύματα και στην Υγεία. Τα δεδομένα μένουν στο iPhone.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Με Apple Watch δουλεύει αμέσως. Με Garmin, Amazfit, Xiaomi, Withings ή Polar, ενεργοποίησε πρώτα τη σύνδεση με την Υγεία στη δική τους εφαρμογή.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    Task {
                        asking = true
                        if await health.requestAccess() {
                            store.update { $0.nutrition.useHealth = true }
                            await health.refresh()
                        }
                        asking = false
                    }
                } label: {
                    Text("Σύνδεση").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).disabled(asking)
            }
        } else if let s = health.stats {
            BodyStatsView(stats: s)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(40)
        }
    }
}

private struct BodyStatsView: View {
    let stats: BodyStats

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            Tile(name: "Βήματα", value: stats.steps.map { Fmt.kcal(Int($0)) }, unit: "")
            Tile(name: "Ενεργές θερμίδες", value: stats.activeKcal.map { Fmt.kcal(Int($0)) }, unit: "kcal")
            Tile(name: "Ύπνος", value: stats.sleepMinutes.map(Self.hours), unit: "",
                 note: stats.deepSleepMinutes.flatMap { $0 > 0 ? "βαθύς \(Self.hours($0))" : nil })
            Tile(name: "Παλμοί ηρεμίας", value: stats.restingHR.map { "\(Int($0.rounded()))" }, unit: "bpm")
            Tile(name: "HRV", value: stats.hrv.map { "\(Int($0.rounded()))" }, unit: "ms")
            Tile(name: "VO2max", value: stats.vo2max.map { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") }, unit: "")
        }
        if stats.weights.count >= 2, let first = stats.weights.first, let last = stats.weights.last {
            Card {
                HStack {
                    Text("Βάρος · 30 ημέρες").font(.headline)
                    Spacer()
                    let diff = last.kg - first.kg
                    Text("\(diff > 0 ? "+" : "")\(Self.kg(diff)) kg").font(.subheadline.weight(.semibold))
                        .foregroundStyle(diff <= 0 ? Color.brand : .orange)
                }
                Chart(stats.weights) { w in
                    LineMark(x: .value("Ημέρα", w.date), y: .value("kg", w.kg)).foregroundStyle(Color.brand)
                    PointMark(x: .value("Ημέρα", w.date), y: .value("kg", w.kg)).foregroundStyle(Color.brand).symbolSize(16)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 120)
                Text("Τώρα \(Self.kg(last.kg)) kg").font(.footnote).foregroundStyle(.secondary)
            }
        } else if let w = stats.weight {
            Tile(name: "Βάρος", value: Self.kg(w), unit: "kg")
        }
        Text("Από την εφαρμογή Υγεία · \(stats.updated.formatted(date: .omitted, time: .shortened)) · τράβηξε προς τα κάτω για ανανέωση")
            .font(.caption).foregroundStyle(.secondary)
    }

    private static func hours(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return "\(m / 60)ω \(String(format: "%02d", m % 60))λ"
    }

    private static func kg(_ v: Double) -> String {
        String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }
}

private struct Tile: View {
    let name: String
    let value: String?
    let unit: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "—").font(.title3.bold()).monospacedDigit()
                if value != nil && !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
            if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
