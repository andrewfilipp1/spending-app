import SpendingCore
import SwiftUI

struct NutritionSettingsView: View {
    @Environment(Store.self) private var store
    @State private var asking = false

    var body: some View {
        let n = store.data.nutrition
        Form {
            Section {
                GoalField(title: "Θερμίδες", unit: "kcal", path: \.kcalGoal, range: 500...10000)
                GoalField(title: "Πρωτεΐνη", unit: "g", path: \.proteinGoal, range: 0...1000)
                GoalField(title: "Υδατάνθρακες", unit: "g", path: \.carbsGoal, range: 0...1000)
                GoalField(title: "Λιπαρά", unit: "g", path: \.fatGoal, range: 0...1000)
            } header: {
                Text("Ημερήσιοι στόχοι")
            } footer: {
                Text("Άφησε κενό ό,τι δεν χρειάζεσαι.")
            }

            Section {
                Toggle(isOn: Binding(get: { n.useHealth }, set: { on in
                    if on {
                        Task {
                            asking = true
                            if await Health.shared.requestAccess() {
                                store.update { $0.nutrition.useHealth = true }
                                await Health.shared.refresh()
                            }
                            asking = false
                        }
                    } else {
                        store.update { $0.nutrition.useHealth = false }
                    }
                })) {
                    Text("Σύνδεση με την Υγεία")
                    Text("Βήματα, ύπνος, παλμοί και βάρος από το ρολόι σου, και τα γεύματα γράφονται στην Υγεία")
                }
                .disabled(asking || !Health.shared.available)
                if n.useHealth {
                    Stepper(value: Binding(get: { n.kcalAdjust }, set: { v in store.update { $0.nutrition.kcalAdjust = v } }), in: -1500...1500, step: 50) {
                        Text("Προσαρμογή στόχου")
                        Text(n.kcalAdjust == 0 ? "καμία" : "\(n.kcalAdjust > 0 ? "+" : "")\(n.kcalAdjust) kcal").monospacedDigit()
                    }
                }
            } header: {
                Text("Ρολόι")
            } footer: {
                Text(n.useHealth
                    ? "Ο στόχος θερμίδων γίνεται: θερμίδες ηρεμίας (μ.ό. 7 ημερών) + όσες έκαψες σήμερα + προσαρμογή (π.χ. −400 για απώλεια βάρους). Χωρίς δεδομένα από το ρολόι ισχύει ο σταθερός στόχος."
                    : "Δουλεύει με όποιο ρολόι συγχρονίζεται με την εφαρμογή Υγεία (Apple Watch, Garmin, Amazfit, Withings, Polar κ.ά.). Τα δεδομένα μένουν στο iPhone.")
            }

            Section {
                Toggle(isOn: Binding(get: { n.aiPhotos }, set: { v in store.update { $0.nutrition.aiPhotos = v } })) {
                    Text("Εκτίμηση από φωτογραφία")
                    Text("Βγάζεις φωτογραφία το πιάτο και παίρνεις θερμίδες κατά προσέγγιση")
                }
                .disabled(!SyncManager.shared.signedIn && !n.aiPhotos)
            } header: {
                Text("Φωτογραφίες")
            } footer: {
                Text(SyncManager.shared.signedIn
                    ? "Η φωτογραφία (σε μικρό μέγεθος) στέλνεται μέσω του server σου σε AI για ανάλυση: Claude (Anthropic) ή Gemini (Google), όπως είναι ρυθμισμένος ο server. Με τη δωρεάν έκδοση του Gemini, η Google μπορεί να χρησιμοποιεί τις φωτογραφίες για να βελτιώνει τα προϊόντα της. Στέλνεται μόνο όταν το ζητάς."
                    : "Χρειάζεται λογαριασμός συγχρονισμού, γιατί η φωτογραφία περνά από τον server σου.")
            }

            Section {
                NavigationLink { FoodLibraryView() } label: {
                    LabeledContent("Βιβλιοθήκη τροφίμων", value: "\(store.data.foods.count)")
                }
            }
        }
        .navigationTitle("Διατροφή")
    }
}

private struct GoalField: View {
    @Environment(Store.self) private var store
    let title: String
    let unit: String
    let path: WritableKeyPath<Nutrition, Int?>
    let range: ClosedRange<Int>
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .frame(maxWidth: 110)
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
        .onAppear { text = store.data.nutrition[keyPath: path].map(String.init) ?? "" }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .onSubmit(commit)
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespaces)
        let current = store.data.nutrition[keyPath: path]
        let value: Int? = t.isEmpty ? nil : Int(t).map { min(max($0, range.lowerBound), range.upperBound) }
        if t.isEmpty || value != nil {
            if value != current { store.update { $0.nutrition[keyPath: path] = value } }
        }
        text = store.data.nutrition[keyPath: path].map(String.init) ?? ""
    }
}

private struct FoodLibraryView: View {
    @Environment(Store.self) private var store
    @State private var query = ""

    var body: some View {
        let q = ItemHistory.key(query)
        let foods = store.data.foods.filter { q.isEmpty || ItemHistory.key($0.name).contains(q) }.sorted { $0.name < $1.name }
        List {
            ForEach(foods) { f in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(f.name)
                        Spacer()
                        Text("\(Fmt.kcal(f.kcal)) kcal").monospacedDigit()
                    }
                    Text("\(f.serving) · Π \(Int(f.protein.rounded())) · Υ \(Int(f.carbs.rounded())) · Λ \(Int(f.fat.rounded()))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button(role: .destructive) { store.deleteFood(f.id) } label: { Label("Διαγραφή", systemImage: "trash") }
                }
            }
        }
        .overlay {
            if store.data.foods.isEmpty {
                ContentUnavailableView("Άδεια βιβλιοθήκη", systemImage: "fork.knife",
                                       description: Text("Όταν καταγράφεις ένα γεύμα, άνοιξε «Αποθήκευση στη βιβλιοθήκη» για να το βρίσκεις έτοιμο."))
            } else if foods.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Αναζήτηση")
        .navigationTitle("Βιβλιοθήκη τροφίμων")
    }
}
