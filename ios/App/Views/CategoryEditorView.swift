import SpendingCore
import SwiftUI

struct CategoryEditorView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let original: Cat?
    @State private var name: String
    @State private var emoji: String
    @State private var color: Color
    @State private var confirmDelete = false

    init(category: Cat?) {
        original = category
        _name = State(initialValue: category?.name ?? "")
        _emoji = State(initialValue: category?.emoji ?? "🏷️")
        _color = State(initialValue: Color(hex: category?.color ?? "#0ea5e9"))
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("🏷️", text: $emoji)
                        .font(.title)
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                    TextField("Όνομα", text: $name)
                }
                ColorPicker("Χρώμα", selection: $color, supportsOpacity: false)
            }
            if let original {
                Section {
                    NavigationLink { CategoryBudgetView(categoryID: original.id) } label: {
                        HStack {
                            Text("Budget")
                            Spacer()
                            Text(original.budget.map { "\(Fmt.money($0))/\(original.budgetPeriod == .week ? "εβδ." : "μήνα")" } ?? "—")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let original, original.id != "other" {
                Section {
                    Button("Διαγραφή κατηγορίας", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(original == nil ? "Νέα κατηγορία" : "Κατηγορία")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Αποθήκευση") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .confirmationDialog(deleteMessage, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Διαγραφή", role: .destructive) { delete() }
        }
    }

    private var deleteMessage: String {
        guard let id = original?.id else { return "" }
        let used = store.data.purchases.reduce(0) { $0 + $1.items.filter { $0.cat == id }.count }
        return used > 0 ? "Η κατηγορία χρησιμοποιείται σε \(used) προϊόντα, που θα μεταφερθούν στα «Άλλα»." : "Διαγραφή κατηγορίας;"
    }

    private func save() {
        let symbol = emoji.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? "•"
        var c = original ?? Cat(name: "", emoji: "", color: "")
        c.name = String(name.trimmingCharacters(in: .whitespaces).prefix(60))
        c.emoji = symbol
        c.color = color.hex
        store.update { d in
            if let i = d.categories.firstIndex(where: { $0.id == c.id }) { d.categories[i] = c } else { d.categories.append(c) }
        }
        dismiss()
    }

    private func delete() {
        guard let id = original?.id else { return }
        store.update { d in
            for p in d.purchases.indices {
                for i in d.purchases[p].items.indices where d.purchases[p].items[i].cat == id {
                    d.purchases[p].items[i].cat = "other"
                }
            }
            d.categories.removeAll { $0.id == id }
        }
        dismiss()
    }
}
