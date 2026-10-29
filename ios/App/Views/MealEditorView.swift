import SpendingCore
import SwiftUI

/// Values per serving of the picked food, so changing the quantity rescales them.
private struct Base: Equatable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

struct MealEditorView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let original: Meal?
    private let from: (purchase: Purchase, item: Item)?
    @State private var date: Date
    @State private var kind: MealKind
    @State private var name: String
    @State private var qty: Double
    @State private var kcal: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var foodId: String?
    @State private var base: Base?
    @State private var saveToLibrary = false
    @State private var serving = ""
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    init(target: MealTarget) {
        let m = target.meal
        original = m
        from = target.from
        _date = State(initialValue: Days.date(m?.date ?? target.date))
        _kind = State(initialValue: m?.meal ?? MealKind.at(hour: Calendar.current.component(.hour, from: Date())))
        _name = State(initialValue: m?.name ?? target.from?.item.name ?? "")
        _qty = State(initialValue: m?.qty ?? 1)
        _kcal = State(initialValue: m.map { "\($0.kcal)" } ?? "")
        _protein = State(initialValue: m.map { Self.text($0.protein) } ?? "")
        _carbs = State(initialValue: m.map { Self.text($0.carbs) } ?? "")
        _fat = State(initialValue: m.map { Self.text($0.fat) } ?? "")
        _foodId = State(initialValue: m?.foodId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Τι έφαγες; (π.χ. Σουβλάκι πίτα)", text: $name)
                        .focused($nameFocused)
                        .textInputAutocapitalization(.sentences)
                    if nameFocused || original == nil && name.isEmpty {
                        ForEach(suggestions) { f in
                            Button { pick(f) } label: {
                                HStack {
                                    Text(f.name).foregroundStyle(.primary)
                                    if !f.serving.isEmpty { Text(f.serving).font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    Text("\(Fmt.kcal(f.kcal)) kcal").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                    }
                    Picker("Γεύμα", selection: $kind) {
                        ForEach(MealKind.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("Ημερομηνία", selection: $date, in: ...Date(), displayedComponents: .date)
                }

                Section {
                    if base != nil {
                        Stepper(value: $qty, in: 0.25...20, step: 0.25) {
                            Text("Ποσότητα: \(Self.text(qty))×\(serving.isEmpty ? "" : " \(serving)")")
                        }
                    }
                    NumberRow(title: "Θερμίδες", unit: "kcal", text: $kcal)
                    NumberRow(title: "Πρωτεΐνη", unit: "g", text: $protein)
                    NumberRow(title: "Υδατάνθρακες", unit: "g", text: $carbs)
                    NumberRow(title: "Λιπαρά", unit: "g", text: $fat)
                } footer: {
                    Text("Αν δεν ξέρεις τα macros, άφησέ τα κενά: μετράνε μόνο οι θερμίδες.")
                }

                if original == nil && foodId == nil {
                    Section {
                        Toggle("Αποθήκευση στη βιβλιοθήκη", isOn: $saveToLibrary)
                        if saveToLibrary { TextField("Μερίδα (π.χ. 1 τεμάχιο, 200 g)", text: $serving) }
                    } footer: {
                        Text("Την επόμενη φορά το βρίσκεις έτοιμο με τις τιμές του.")
                    }
                }

                if let from {
                    Section("Αγορά") {
                        LabeledContent(from.purchase.store.isEmpty ? from.item.name : from.purchase.store, value: Fmt.money(from.item.cents))
                    }
                }

                if original != nil {
                    Section {
                        Button("Διαγραφή γεύματος", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(original == nil ? "Νέο γεύμα" : "Γεύμα")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Άκυρο") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Αποθήκευση") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Self.number(kcal) == nil)
                }
            }
            .onChange(of: qty) { _, q in
                guard let b = base else { return }
                kcal = "\(Int((b.kcal * q).rounded()))"
                protein = Self.text(b.protein * q)
                carbs = Self.text(b.carbs * q)
                fat = Self.text(b.fat * q)
            }
            .confirmationDialog("Διαγραφή γεύματος;", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Διαγραφή", role: .destructive) {
                    if let original { store.deleteMeal(original.id) }
                    dismiss()
                }
            }
            .onAppear { if original == nil && from == nil { nameFocused = true } }
        }
    }

    private var suggestions: [RecentFood] {
        let recent = NutritionLogic.recent(store.data.meals, foods: store.data.foods, limit: 200)
        let q = ItemHistory.key(name)
        return Array(recent.filter { q.isEmpty || $0.key.contains(q) }.prefix(6))
    }

    private func pick(_ f: RecentFood) {
        name = f.name
        foodId = f.foodId
        serving = f.serving
        qty = 1
        base = Base(kcal: Double(f.kcal), protein: f.protein, carbs: f.carbs, fat: f.fat)
        kcal = "\(f.kcal)"
        protein = Self.text(f.protein)
        carbs = Self.text(f.carbs)
        fat = Self.text(f.fat)
        nameFocused = false
    }

    private func save() {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !trimmed.isEmpty, let k = Self.number(kcal) else { return }
        var m = original ?? Meal(date: Days.key(date), meal: kind, name: trimmed, kcal: 0)
        m.date = Days.key(date)
        m.meal = kind
        m.name = trimmed
        m.qty = base == nil ? (original?.qty ?? 1) : qty
        m.kcal = Int(k.rounded())
        m.protein = Self.number(protein) ?? 0
        m.carbs = Self.number(carbs) ?? 0
        m.fat = Self.number(fat) ?? 0
        m.foodId = foodId
        if original == nil {
            m.source = from != nil ? "purchase" : foodId != nil ? "food" : "manual"
            m.purchaseId = from?.purchase.id
            m.itemId = from?.item.id
        }
        if saveToLibrary {
            // The library keeps one serving: divide back by the quantity eaten.
            let q = max(m.qty, 0.01)
            store.saveFood(Food(name: trimmed, serving: serving.trimmingCharacters(in: .whitespaces), kcal: Int((Double(m.kcal) / q).rounded()),
                                protein: m.protein / q, carbs: m.carbs / q, fat: m.fat / q))
            m.foodId = store.data.foods.first { ItemHistory.key($0.name) == ItemHistory.key(trimmed) }?.id
        }
        store.upsertMeal(m)
        dismiss()
    }

    static func number(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), v >= 0, v.isFinite else { return nil }
        return v
    }

    static func text(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return (r == r.rounded() ? String(Int(r)) : String(r)).replacingOccurrences(of: ".", with: ",")
    }
}

private struct NumberRow: View {
    let title: String
    let unit: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }
}
