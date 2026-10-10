import SpendingCore
import SwiftUI

struct HistoryView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var category: String?

    var body: some View {
        let groups = grouped()
        NavigationStack {
            List {
                ForEach(groups, id: \.date) { g in
                    Section {
                        ForEach(g.purchases) { p in
                            Button { router.edit(p) } label: {
                                PurchaseRow(purchase: p, category: store.data.category(p.items.first?.cat ?? "other"))
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) { store.delete(p.id) } label: { Label("Διαγραφή", systemImage: "trash") }
                            }
                        }
                    } header: {
                        HStack {
                            Text(Days.label(g.date))
                            Spacer()
                            Text(Fmt.money(g.total)).monospacedDigit()
                        }
                    }
                }
            }
            .overlay {
                if groups.isEmpty {
                    if store.data.purchases.isEmpty {
                        ContentUnavailableView("Καμία αγορά ακόμα", systemImage: "cart", description: Text("Πάτα + για να προσθέσεις την πρώτη."))
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .searchable(text: $query, prompt: "Προϊόν ή κατάστημα")
            .navigationTitle("Ιστορικό")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Κατηγορία", selection: $category) {
                            Text("Όλες οι κατηγορίες").tag(String?.none)
                            ForEach(store.data.categories) { c in Text("\(c.emoji) \(c.name)").tag(Optional(c.id)) }
                        }
                    } label: {
                        Image(systemName: category == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Φίλτρο κατηγορίας")
                }
                ToolbarItem(placement: .primaryAction) { AddButton() }
            }
        }
    }

    private func grouped() -> [(date: String, purchases: [Purchase], total: Int)] {
        let q = Logic.norm(query)
        let list = store.data.purchases.sorted(by: Purchase.newestFirst).filter { p in
            (category == nil || p.items.contains { $0.cat == category })
                && (q.isEmpty || Logic.norm(p.store).contains(q) || Logic.norm(p.note).contains(q)
                    || p.items.contains { Logic.norm($0.name).contains(q) })
        }
        var order: [String] = []
        var byDate: [String: [Purchase]] = [:]
        for p in list {
            if byDate[p.date] == nil { order.append(p.date) }
            byDate[p.date, default: []].append(p)
        }
        return order.map { d in
            let ps = byDate[d]!
            let total = ps.reduce(0) { sum, p in
                sum + (category == nil ? p.total : p.items.filter { $0.cat == category }.reduce(0) { $0 + $1.cents })
            }
            return (d, ps, total)
        }
    }
}
