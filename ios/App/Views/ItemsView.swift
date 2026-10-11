import SpendingCore
import SwiftUI

/// Every item bought so far: merge likely duplicates and rename items across all purchases.
struct ItemsView: View {
    @Environment(Store.self) private var store
    @State private var query = ""
    @State private var renaming: KnownItem?
    @State private var newName = ""
    @State private var message: String?

    var body: some View {
        let known = ItemHistory.known(store.data.purchases)
        let dups = ItemHistory.duplicates(known)
        let q = ItemHistory.key(query)
        let shown = known.filter { q.isEmpty || $0.key.contains(q) }
        List {
            if !dups.isEmpty && q.isEmpty {
                Section {
                    ForEach(dups) { g in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.name).font(.headline)
                                Text("επίσης γραμμένο: " + g.names.map { "«\($0.trimmingCharacters(in: .whitespaces))»" }.joined(separator: ", "))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Ένωση") { rename(g.names, to: g.name) }
                                .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("Πιθανά διπλά (\(dups.count))")
                }
            }
            Section {
                ForEach(shown) { k in
                    Button {
                        newName = k.name
                        renaming = k
                    } label: {
                        HStack {
                            CategoryIcon(category: store.data.category(k.cat), size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(k.name).foregroundStyle(.primary)
                                Text("\(k.count)× · τελευταία \(Fmt.money(k.cents)) · \(Days.short(k.last))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if shown.isEmpty {
                    Text("Κανένα είδος.").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Πάτα ένα είδος για να αλλάξεις την ονομασία του σε όλες τις αγορές. Αν γράψεις το όνομα άλλου είδους, τα δύο ενώνονται.")
            }
        }
        .searchable(text: $query, prompt: "Αναζήτηση είδους")
        .navigationTitle("Ιστορικό ειδών")
        .alert("Μετονομασία", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Ονομασία", text: $newName)
            Button("Άκυρο", role: .cancel) {}
            Button("Αποθήκευση") {
                if let k = renaming { renameKnown(k, known: known) }
            }
        } message: {
            Text("Αλλάζει σε όλες τις \(renaming?.count ?? 0) καταχωρήσεις.")
        }
        .overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        self.message = nil
                    }
            }
        }
    }

    private func renameKnown(_ k: KnownItem, known: [KnownItem]) {
        let name = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !name.isEmpty else { return }
        // Writing another item's name merges into its spelling.
        let other = known.first { $0.key == ItemHistory.key(name) && $0.key != k.key }
        rename(Array(k.spellings.keys), to: other?.name ?? name, merged: other != nil)
    }

    private func rename(_ from: [String], to: String, merged: Bool = true) {
        var n = 0
        store.update { d in n = ItemHistory.rename(&d.purchases, from: from, to: to) }
        if n > 0 { message = merged ? "Ενώθηκαν \(n) καταχωρήσεις σε «\(to)»" : "Αποθηκεύτηκε" }
    }
}
