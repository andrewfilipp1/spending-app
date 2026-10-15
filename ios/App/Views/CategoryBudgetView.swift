import SpendingCore
import SwiftUI

/// Budget of one category: amount, period (week/month), progress and the history of changes.
struct CategoryBudgetView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let categoryID: String

    @State private var amount = ""
    @State private var period: PeriodKind = .month
    @State private var ownFund = false
    @State private var loaded = false
    @State private var invalid = false

    private var category: Cat { store.data.category(categoryID) }

    var body: some View {
        let c = category
        Form {
            Section {
                HStack {
                    CategoryIcon(category: c, size: 44)
                    VStack(alignment: .leading) {
                        Text(c.name).font(.headline)
                        Text(c.budgetChanges == 0 ? "Χωρίς αλλαγές μέχρι τώρα" : "Το budget άλλαξε \(c.budgetChanges) \(c.budgetChanges == 1 ? "φορά" : "φορές")")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                HStack {
                    Text("Όριο")
                    Spacer()
                    TextField("—", text: $amount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 120)
                        .foregroundStyle(invalid ? .red : .primary)
                    Text("€").foregroundStyle(.secondary)
                }
                Picker("Ανά", selection: $period) {
                    Text("Εβδομάδα").tag(PeriodKind.week)
                    Text("Μήνα").tag(PeriodKind.month)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Budget κατηγορίας")
            } footer: {
                Text("Άφησε κενό για κανένα όριο. Θα λάβεις ειδοποίηση στο 80% και στο 100%.")
            }

            Section {
                Toggle("🧺 Δικό της ταμείο", isOn: $ownFund)
            } footer: {
                Text("Δεν μετράει στο ημερήσιο ούτε στο γενικό budget, μόνο στο όριο της κατηγορίας. Π.χ. σούπερ μάρκετ για όλη την εβδομάδα.")
            }

            if let status = currentStatus {
                Section(status.category.budgetPeriod == .week ? "Αυτή την εβδομάδα" : "Αυτόν τον μήνα") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(Fmt.money(status.spent)).font(.title3.bold()).monospacedDigit()
                            Text("/ \(Fmt.money(status.budget))").foregroundStyle(.secondary).monospacedDigit()
                            Spacer()
                            Text("\(Int(status.ratio * 100))%").foregroundStyle(levelColor(status.ratio)).monospacedDigit()
                        }
                        ProgressBar(value: status.ratio, color: levelColor(status.ratio))
                        Text(status.spent <= status.budget ? "απομένουν \(Fmt.money(status.budget - status.spent))" : "υπέρβαση \(Fmt.money(status.spent - status.budget))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                if c.budgetHistory.isEmpty {
                    Text("Δεν έχει οριστεί ακόμα budget.").foregroundStyle(.secondary)
                }
                ForEach(Array(c.budgetHistory.enumerated().reversed()), id: \.offset) { _, h in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: icon(h)).foregroundStyle(h.from == nil ? .green : h.to == nil ? .red : .orange)
                        Text(describe(h)).font(.subheadline)
                        Spacer()
                        Text(Self.dateFormatter.string(from: Date(timeIntervalSince1970: h.at / 1000)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Ιστορικό αλλαγών (\(c.budgetChanges))")
            }
        }
        .navigationTitle("Budget κατηγορίας")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Αποθήκευση") { save() }.fontWeight(.semibold) }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Τέλος") { hideKeyboard() }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            amount = Money.inputText(c.budget)
            period = c.budgetPeriod
            ownFund = c.ownFund
        }
        .onChange(of: amount) { invalid = false }
    }

    private var currentStatus: CategoryBudgetStatus? {
        Logic.categoryBudgets(store.data, allocs: Logic.allocations(Logic.regular(store.data.purchases)), today: store.today)
            .first { $0.category.id == categoryID }
    }

    private func save() {
        let t = amount.trimmingCharacters(in: .whitespaces)
        var cents: Int?
        if !t.isEmpty {
            guard let c = Money.toCents(t), c >= 0 else { invalid = true; return }
            cents = c
        }
        store.update { d in
            if let i = d.categories.firstIndex(where: { $0.id == categoryID }) {
                d.categories[i].setBudget(cents, period: period)
                d.categories[i].ownFund = ownFund
            }
        }
        dismiss()
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "el_GR")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private func per(_ p: PeriodKind?) -> String { p == .week ? "/εβδ." : "/μήνα" }

    private func describe(_ h: BudgetChange) -> String {
        switch (h.from, h.to) {
        case (nil, let to?): return "Ορίστηκε \(Fmt.money(to))\(per(h.period))"
        case (let from?, nil): return "Αφαιρέθηκε (ήταν \(Fmt.money(from))\(per(h.fromPeriod)))"
        case (let from?, let to?): return "\(Fmt.money(from))\(per(h.fromPeriod)) → \(Fmt.money(to))\(per(h.period))"
        default: return "—"
        }
    }

    private func icon(_ h: BudgetChange) -> String {
        h.from == nil ? "plus.circle.fill" : h.to == nil ? "minus.circle.fill" : "pencil.circle.fill"
    }
}

/// "✎ 3" — how many times a category budget was changed.
struct BudgetChangesBadge: View {
    let count: Int
    var body: some View {
        Label("\(count)", systemImage: "pencil")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .accessibilityLabel("Άλλαξε \(count) φορές")
    }
}
