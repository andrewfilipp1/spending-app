import SpendingCore
import SwiftUI
import UIKit

private struct DraftItem: Identifiable, Equatable {
    var id = UUID().uuidString
    var name = ""
    var price = ""
    var cat = "other"
    var days = 1
}

private enum Field: Hashable {
    case store
    case name(String)
    case price(String)
}

private let dayChoices = [1, 2, 3, 4, 5, 6, 7, 10, 14, 30, 60, 90, 180, 365]

struct EditorView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let original: Purchase?
    @State private var date: Date
    @State private var storeName: String
    @State private var note: String
    @State private var items: [DraftItem]
    @State private var expected: Int?
    @State private var source: String
    @State private var error: String?
    @State private var confirmDelete = false
    @FocusState private var focus: Field?

    init(target: EditorTarget) {
        let p = target.purchase
        original = p
        _date = State(initialValue: Days.date(p?.date ?? Days.today()))
        _storeName = State(initialValue: p?.store ?? "")
        _note = State(initialValue: p?.note ?? "")
        _source = State(initialValue: p?.source ?? "manual")
        _items = State(initialValue: p?.items.map {
            DraftItem(id: $0.id, name: $0.name, price: Money.inputText($0.cents), cat: $0.cat, days: $0.days)
        } ?? [DraftItem()])
    }

    var body: some View {
        NavigationStack {
            Form {
                if original == nil {
                    Section {
                        Button { pasteFromClipboard() } label: {
                            Label("Επικόλληση από Apple Pay", systemImage: "apple.logo")
                        }
                    }
                }

                Section {
                    DatePicker("Ημερομηνία", selection: $date, displayedComponents: .date)
                    TextField("Κατάστημα (π.χ. Lidl)", text: $storeName)
                        .focused($focus, equals: .store)
                        .textInputAutocapitalization(.words)
                    if focus == .store {
                        Suggestions(values: storeSuggestions) { storeName = $0; focus = nil }
                    }
                }

                ForEach($items) { $item in
                    Section {
                        itemEditor($item)
                    } header: {
                        if item.id == items.first?.id { Text("Προϊόντα") }
                    }
                }

                Section {
                    Button { addItem() } label: { Label("Προσθήκη προϊόντος", systemImage: "plus.circle.fill") }
                }

                Section {
                    HStack {
                        Text("Σύνολο").font(.headline)
                        Spacer()
                        Text(Fmt.money(total)).font(.title3.bold()).monospacedDigit()
                    }
                    if let expected, expected != total {
                        let diff = expected - total
                        Text("Apple Pay: \(Fmt.money(expected)) · " + (diff > 0 ? "μένουν \(Fmt.money(diff)) για κατανομή" : "υπέρβαση κατά \(Fmt.money(-diff))"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Σημείωση") {
                    TextField("Προαιρετικό", text: $note, axis: .vertical).lineLimit(1...4)
                }

                if original != nil {
                    Section {
                        Button("Διαγραφή αγοράς", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(original == nil ? "Νέα αγορά" : "Επεξεργασία")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Άκυρο") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Αποθήκευση") { save() }.fontWeight(.semibold) }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Τέλος") { focus = nil }
                }
            }
            .onChange(of: focus) { old, _ in
                if old == .store { applyStoreCategory() }
            }
            .confirmationDialog("Διαγραφή αυτής της αγοράς;", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Διαγραφή", role: .destructive) {
                    if let id = original?.id { store.delete(id) }
                    dismiss()
                }
            }
            .alert("Έλεγξε τα στοιχεία", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    // MARK: item row

    @ViewBuilder
    private func itemEditor(_ item: Binding<DraftItem>) -> some View {
        let it = item.wrappedValue
        HStack(spacing: 8) {
            TextField("Προϊόν (π.χ. Γάλα)", text: item.name)
                .focused($focus, equals: .name(it.id))
            TextField("0,00", text: item.price)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 80)
                .focused($focus, equals: .price(it.id))
                .foregroundStyle(isInvalidPrice(it.price) ? .red : .primary)
            Text("€").foregroundStyle(.secondary)
            if items.count > 1 {
                Button {
                    items.removeAll { $0.id == it.id }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Αφαίρεση προϊόντος")
            }
        }
        if focus == .name(it.id) {
            let matches = itemSuggestions(for: it.name)
            if !matches.isEmpty {
                Suggestions(values: matches.map(\.name)) { name in
                    if let m = matches.first(where: { $0.name == name }) { apply(m, to: item) }
                    focus = .price(it.id)
                }
            }
        }
        Picker("Κατηγορία", selection: item.cat) {
            ForEach(store.data.categories) { c in Text("\(c.emoji) \(c.name)").tag(c.id) }
        }
        Picker("Διάρκεια", selection: item.days) {
            ForEach(dayOptions(including: it.days), id: \.self) { n in
                Text(n == 1 ? "Μόνο αυτή τη μέρα" : "Για \(n) ημέρες").tag(n)
            }
        }
        if let cents = Money.toCents(it.price), cents > 0, it.days > 1 {
            let start = Days.key(date)
            Text("≈ \(Fmt.money(cents / it.days)) την ημέρα · \(Days.short(start)) – \(Days.short(Days.add(start, it.days - 1)))")
                .font(.footnote).foregroundStyle(.brand)
        }
    }

    // MARK: helpers

    private var total: Int {
        items.reduce(0) { $0 + max(0, Money.toCents($1.price) ?? 0) }
    }

    private func isInvalidPrice(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && (Money.toCents(t) ?? 0) <= 0
    }

    private func dayOptions(including n: Int) -> [Int] {
        dayChoices.contains(n) ? dayChoices : (dayChoices + [n]).sorted()
    }

    private var storeSuggestions: [String] {
        let q = Logic.norm(storeName)
        var seen = Set<String>()
        return store.data.purchases.sorted(by: Purchase.newestFirst).compactMap { p -> String? in
            let n = Logic.norm(p.store)
            guard !p.store.isEmpty, n != q, q.isEmpty || n.contains(q), seen.insert(n).inserted else { return nil }
            return p.store
        }.prefix(5).map { $0 }
    }

    /// Previously bought items matching what is being typed (latest price and category).
    private func itemSuggestions(for text: String) -> [Item] {
        let q = Logic.norm(text)
        guard q.count >= 1 else { return [] }
        var seen = Set<String>()
        var out: [Item] = []
        for p in store.data.purchases.sorted(by: Purchase.newestFirst) {
            for i in p.items {
                let n = Logic.norm(i.name)
                guard n.contains(q), n != q, seen.insert(n).inserted else { continue }
                out.append(i)
                if out.count == 4 { return out }
            }
        }
        return out
    }

    private func apply(_ known: Item, to item: Binding<DraftItem>) {
        item.wrappedValue.name = known.name
        if store.data.categories.contains(where: { $0.id == known.cat }) { item.wrappedValue.cat = known.cat }
        if item.wrappedValue.price.trimmingCharacters(in: .whitespaces).isEmpty { item.wrappedValue.price = Money.inputText(known.cents) }
        if item.wrappedValue.days == 1 { item.wrappedValue.days = known.days }
    }

    private func addItem() {
        let cat = items.last?.cat ?? MerchantHints.category(for: storeName, in: store.data)
        let new = DraftItem(cat: cat)
        items.append(new)
        focus = .name(new.id)
    }

    private func applyStoreCategory() {
        let cat = MerchantHints.category(for: storeName, in: store.data)
        guard cat != "other" else { return }
        for i in items.indices where items[i].name.isEmpty && items[i].cat == "other" {
            items[i].cat = cat
        }
    }

    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string, let tx = Logic.parseTransaction(text) else {
            error = "Δεν βρέθηκε ποσό στο πρόχειρο."
            return
        }
        if storeName.isEmpty { storeName = tx.merchant }
        expected = tx.cents
        source = "applepay"
        if items.count == 1, Money.toCents(items[0].price) == nil {
            items[0].price = Money.inputText(tx.cents)
        }
        applyStoreCategory()
    }

    private func save() {
        var out: [Item] = []
        for d in items {
            let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let price = d.price.trimmingCharacters(in: .whitespaces)
            if name.isEmpty && price.isEmpty { continue }
            guard let cents = Money.toCents(price), cents > 0 else {
                error = "Η τιμή για «\(name.isEmpty ? "προϊόν χωρίς όνομα" : name)» δεν είναι σωστή."
                return
            }
            let shop = storeName.trimmingCharacters(in: .whitespaces)
            let fallback = shop.isEmpty ? store.data.category(d.cat).name : shop
            out.append(Item(id: d.id, name: String((name.isEmpty ? fallback : name).prefix(120)), cents: cents, cat: d.cat, days: d.days))
        }
        guard !out.isEmpty else {
            error = "Πρόσθεσε τουλάχιστον ένα προϊόν με τιμή."
            return
        }
        var p = original ?? Purchase(date: Days.key(date), items: [])
        p.date = Days.key(date)
        p.store = String(storeName.trimmingCharacters(in: .whitespaces).prefix(120))
        p.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        p.source = source
        p.items = out
        p.review = false
        p.updatedAt = Date().timeIntervalSince1970 * 1000
        store.upsert(p)
        dismiss()
    }
}

private struct Suggestions: View {
    let values: [String]
    let pick: (String) -> Void

    var body: some View {
        if !values.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(values, id: \.self) { v in
                        Button(v) { pick(v) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}
