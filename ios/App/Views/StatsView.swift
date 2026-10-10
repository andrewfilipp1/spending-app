import Charts
import SpendingCore
import SwiftUI

private struct Bucket: Identifiable {
    let id: String // day key, or "yyyy-MM" in the year view
    let axis: String
    let full: String
    var cents = 0
    let isNow: Bool
}

struct StatsView: View {
    @Environment(Store.self) private var store
    @State private var kind: PeriodKind = .month
    @State private var ref = Days.today()
    @State private var mode: AllocMode = .spread
    @State private var category: String?
    @State private var selected: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    controls
                    content
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Στατιστικά")
            .toolbar { ToolbarItem(placement: .primaryAction) { AddButton() } }
            .onChange(of: kind) { ref = Days.today(); selected = nil }
            .onChange(of: ref) { selected = nil }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Περίοδος", selection: $kind) {
                Text("Εβδομάδα").tag(PeriodKind.week)
                Text("Μήνας").tag(PeriodKind.month)
                Text("Έτος").tag(PeriodKind.year)
            }
            .pickerStyle(.segmented)

            HStack {
                Button { ref = Logic.shift(kind, ref, by: -1) } label: { Image(systemName: "chevron.left.circle.fill").font(.title) }
                    .accessibilityLabel("Προηγούμενη περίοδος")
                Spacer()
                Text(Logic.label(kind, period)).font(.headline)
                Spacer()
                Button { ref = Logic.shift(kind, ref, by: 1) } label: { Image(systemName: "chevron.right.circle.fill").font(.title) }
                    .accessibilityLabel("Επόμενη περίοδος")
            }
            .symbolRenderingMode(.hierarchical)

            Picker("Τρόπος", selection: $mode) {
                Text("Κατανάλωση").tag(AllocMode.spread)
                Text("Πληρωμές").tag(AllocMode.paid)
            }
            .pickerStyle(.segmented)
            Text(mode == .spread
                ? "Τα προϊόντα που μοίρασες σε πολλές ημέρες μετράνε αναλογικά σε κάθε ημέρα."
                : "Κάθε αγορά μετράει ολόκληρη την ημέρα που πληρώθηκε.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var period: Period { Logic.period(kind, ref, weekStart: store.data.settings.weekStart) }

    @ViewBuilder
    private var content: some View {
        let data = store.data
        let p = period
        let today = Days.today()
        let all = Logic.allocations(data.purchases, mode: mode)
        let inPeriod = all.filter { p.contains($0.date) }
        let filtered = inPeriod.filter { category == nil || $0.cat == category }
        let total = Logic.sum(filtered)
        let prevP = Logic.period(kind, Logic.shift(kind, ref, by: -1), weekStart: data.settings.weekStart)
        let prevTotal = Logic.sum(all.filter { prevP.contains($0.date) && (category == nil || $0.cat == category) })
        let cat = category.map { data.category($0) }
        let budget: Int? = cat != nil ? (kind == cat!.budgetPeriod ? cat!.budget : nil) : data.settings.budgets[kind]

        if let cat {
            HStack {
                Text("\(cat.emoji) \(cat.name)").fontWeight(.semibold)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(hex: cat.color).opacity(0.18), in: Capsule())
                Spacer()
                Button("Όλες οι κατηγορίες") { category = nil }.font(.subheadline)
            }
        }

        tiles(total: total, prevTotal: prevTotal, filtered: filtered, today: today, budget: budget, cat: cat)

        Card {
            let buckets = makeBuckets(filtered, today: today)
            let sel = buckets.first { $0.id == selected }
            Group {
                if let sel {
                    Text("\(sel.full) · ").foregroundStyle(.secondary) + Text(Fmt.money(sel.cents)).bold()
                } else {
                    Text("Άγγιξε το γράφημα για λεπτομέρειες").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            chart(buckets, refLine: referenceLine(cat: cat), color: cat.map { Color(hex: $0.color) } ?? .brand)
        }

        categoriesCard(inPeriod)
        topItemsCard(filtered, cat: cat)
    }

    // MARK: tiles

    private func tiles(total: Int, prevTotal: Int, filtered: [Alloc], today: String, budget: Int?, cat: Cat?) -> some View {
        let p = period
        let elapsedEnd = min(p.end, today)
        let elapsed = p.start > today ? 0 : Days.between(p.start, elapsedEnd) + 1
        let toDate = Logic.sum(filtered.filter { $0.date <= elapsedEnd })
        let delta = prevTotal > 0 ? Int((Double(total - prevTotal) / Double(prevTotal) * 100).rounded()) : nil

        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                Tile(title: "Σύνολο", value: Fmt.money(total)) {
                    if let delta {
                        Text("\(delta > 0 ? "▲" : "▼") \(abs(delta))% από την προηγ.").foregroundStyle(delta > 0 ? .red : .green)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                Tile(title: "Μ.Ο. ανά ημέρα", value: elapsed > 0 ? Fmt.money(toDate / elapsed) : "—") {
                    Text(elapsed > 0 ? "\(elapsed) ημέρες" : "μελλοντική περίοδος").foregroundStyle(.secondary)
                }
            }
            if let budget {
                Card {
                    Text("Budget \(cat?.name ?? kindName)").font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.money(total)).font(.title3.bold()).monospacedDigit()
                        Text("/ \(Fmt.money(budget))").foregroundStyle(.secondary).monospacedDigit()
                    }
                    ProgressBar(value: ratio(total, budget), color: levelColor(ratio(total, budget)))
                    Text(total <= budget ? "απομένουν \(Fmt.money(budget - total))" : "υπέρβαση \(Fmt.money(total - budget))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var kindName: String {
        switch kind {
        case .day: "ημερήσιο"
        case .week: "εβδομαδιαίο"
        case .month: "μηνιαίο"
        case .year: "ετήσιο"
        }
    }

    // MARK: chart

    private func makeBuckets(_ allocs: [Alloc], today: String) -> [Bucket] {
        let p = period
        if kind == .year {
            let y = Days.parts(p.start).y
            var buckets = (1...12).map { m in
                Bucket(id: String(format: "%04d-%02d", y, m), axis: String(Days.monthsShort[m - 1].prefix(1)),
                       full: "\(Days.months[m - 1]) \(y)", isNow: today.hasPrefix(String(format: "%04d-%02d", y, m)))
            }
            for a in allocs { buckets[Days.parts(a.date).m - 1].cents += a.cents }
            return buckets
        }
        var index: [String: Int] = [:]
        var buckets: [Bucket] = (0..<p.length).map { i in
            let d = Days.add(p.start, i)
            index[d] = i
            let axis = kind == .week ? String(Days.weekdays[Days.weekday(d)].prefix(2)) : String(Days.parts(d).d)
            return Bucket(id: d, axis: axis, full: Days.short(d, withYear: true), isNow: d == today)
        }
        for a in allocs { if let i = index[a.date] { buckets[i].cents += a.cents } }
        return buckets
    }

    /// Dashed line: what one bar (a day, or a month in the year view) may cost.
    private func referenceLine(cat: Cat?) -> Double? {
        let s = store.data.settings
        let m = Logic.period(.month, period.start)
        let monthDays = Double(m.length)
        if let cat, let b = cat.budget {
            // a weekly limit is ~52/12 weeks per month
            let perMonth = cat.budgetPeriod == .week ? Double(b) * 52 / 12 : Double(b)
            if kind == .year { return perMonth }
            return cat.budgetPeriod == .week ? Double(b) / 7 : perMonth / monthDays
        }
        if kind == .year {
            if cat != nil { return nil }
            return s.budgets.month.map(Double.init) ?? s.budgets.year.map { Double($0) / 12 }
        }
        if cat != nil { return nil }
        if let d = s.budgets.day { return Double(d) }
        if let w = s.budgets.week { return Double(w) / 7 }
        if let mo = s.budgets.month { return Double(mo) / monthDays }
        return nil
    }

    private func chart(_ buckets: [Bucket], refLine: Double?, color: Color) -> some View {
        let labelIDs: [String] = buckets.enumerated().compactMap { i, b in
            kind != .month || i == 0 || (i + 1) % 5 == 0 ? b.id : nil
        }
        let axis = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0.axis) })
        return Chart {
            ForEach(buckets) { b in
                BarMark(x: .value("Ημέρα", b.id), y: .value("Ποσό", Double(b.cents) / 100))
                    .foregroundStyle(color.opacity(selected == nil || selected == b.id ? (b.isNow ? 1 : 0.8) : 0.3))
                    .cornerRadius(3)
            }
            if let refLine {
                RuleMark(y: .value("Budget", refLine / 100))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("budget").font(.caption2).foregroundStyle(.orange)
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks(values: labelIDs) { v in
                AxisValueLabel {
                    if let id = v.as(String.self) { Text(axis[id] ?? "") }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine()
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text("\(Int(d))€") }
                }
            }
        }
        .frame(height: 210)
    }

    // MARK: lists

    @ViewBuilder
    private func categoriesCard(_ allocs: [Alloc]) -> some View {
        let data = store.data
        let total = Logic.sum(allocs)
        let groups = Dictionary(grouping: allocs, by: \.cat).map { (cat: $0.key, cents: Logic.sum($0.value)) }.sorted { $0.cents > $1.cents }
        Card {
            Text("Ανά κατηγορία").font(.headline)
            if groups.isEmpty {
                Text("Καμία δαπάνη σε αυτή την περίοδο.").foregroundStyle(.secondary).font(.subheadline)
            }
            ForEach(groups, id: \.cat) { g in
                Button {
                    category = category == g.cat ? nil : g.cat
                    selected = nil
                } label: {
                    CategoryBar(category: data.category(g.cat), cents: g.cents, max: groups[0].cents,
                                percent: total > 0 ? g.cents * 100 / total : nil,
                                budget: kind == data.category(g.cat).budgetPeriod ? data.category(g.cat).budget : nil,
                                selected: category == g.cat)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func topItemsCard(_ allocs: [Alloc], cat: Cat?) -> some View {
        let items = topItems(allocs)
        if !items.isEmpty {
            Card {
                Text("Κορυφαία προϊόντα" + (cat.map { " · \($0.name)" } ?? "")).font(.headline)
                ForEach(Array(items.enumerated()), id: \.offset) { i, x in
                    HStack {
                        Text("\(i + 1).").foregroundStyle(.secondary).monospacedDigit()
                        Text(x.name).lineLimit(1)
                        Text("×\(x.count)").foregroundStyle(.secondary).font(.caption)
                        Spacer()
                        Text(Fmt.money(x.cents)).fontWeight(.semibold).monospacedDigit()
                    }
                    .font(.subheadline)
                    if i < items.count - 1 { Divider() }
                }
            }
        }
    }

    private func topItems(_ allocs: [Alloc]) -> [(name: String, cents: Int, count: Int)] {
        var map: [String: (name: String, cents: Int, pids: Set<String>)] = [:]
        for a in allocs {
            let k = Logic.norm(a.name)
            var e = map[k] ?? (a.name, 0, [])
            e.cents += a.cents
            e.pids.insert(a.pid)
            map[k] = e
        }
        let rows: [(name: String, cents: Int, count: Int)] = map.values.map { (name: $0.name, cents: $0.cents, count: $0.pids.count) }
        return Array(rows.sorted { (a: (name: String, cents: Int, count: Int), b: (name: String, cents: Int, count: Int)) in a.cents > b.cents }.prefix(8))
    }
}

private struct Tile<Sub: View>: View {
    let title: String
    let value: String
    @ViewBuilder var sub: Sub

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            sub.font(.caption)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
