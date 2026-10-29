import PhotosUI
import SpendingCore
import SwiftUI
import UIKit

/// Photo of a meal → estimated calories per food, adjusted by the user and saved as meals.
struct PhotoEstimateView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var note = ""
    @State private var loading = false
    @State private var error: String?
    @State private var estimate: FoodEstimate?
    /// Portion per estimated item (1 = as estimated, 0 = leave out).
    @State private var portions: [Double] = []
    @State private var kind = MealKind.at(hour: Calendar.current.component(.hour, from: Date()))
    @State private var linkedItem: String?

    var body: some View {
        NavigationStack {
            Group {
                if !store.data.nutrition.aiPhotos || !SyncManager.shared.signedIn {
                    setup
                } else {
                    Form { content }
                }
            }
            .navigationTitle("Εκτίμηση")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Άκυρο") { dismiss() } }
                if estimate != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Αποθήκευση") { save() }.fontWeight(.semibold).disabled(total == 0)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { picked in
                    if let picked { use(picked) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { use(img) }
                    libraryItem = nil
                }
            }
            .onAppear {
                if image == nil && store.data.nutrition.aiPhotos && SyncManager.shared.signedIn && UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showCamera = true
                }
            }
        }
    }

    private var setup: some View {
        ContentUnavailableView {
            Label("Εκτίμηση από φωτογραφία", systemImage: "camera.viewfinder")
        } description: {
            Text(SyncManager.shared.signedIn
                ? "Ενεργοποίησέ την στις Ρυθμίσεις → Διατροφή. Η φωτογραφία στέλνεται μέσω του server σου σε AI (Claude ή Gemini) για ανάλυση."
                : "Χρειάζεται λογαριασμός συγχρονισμού (Ρυθμίσεις → Λογαριασμός), γιατί η φωτογραφία περνά από τον server σου.")
        } actions: {
            Button("Άνοιγμα Ρυθμίσεων") {
                dismiss()
                router.tab = .settings
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder private var content: some View {
        Section {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 220).clipped()
                    .listRowInsets(EdgeInsets())
            }
            HStack {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: { Label("Κάμερα", systemImage: "camera") }
                        .buttonStyle(.bordered)
                }
                PhotosPicker(selection: $libraryItem, matching: .images) { Label("Βιβλιοθήκη", systemImage: "photo") }
                    .buttonStyle(.bordered)
            }
            TextField("Σημείωση (προαιρετικά, π.χ. μισή μερίδα, χωρίς λάδι)", text: $note)
            if image != nil && estimate == nil && !loading {
                Button("Εκτίμηση") { Task { await run() } }
            }
        }

        if loading {
            Section { HStack { ProgressView(); Text("Ανάλυση φωτογραφίας…").foregroundStyle(.secondary) } }
        }
        if let error {
            Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
        }

        if let estimate {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Σύνολο (εκτίμηση)").font(.caption).foregroundStyle(.secondary)
                        Text("~\(Fmt.kcal(total)) kcal").font(.title.bold()).monospacedDigit()
                    }
                    Spacer()
                    Text(confidenceText(estimate.confidence)).font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
                if !estimate.note.isEmpty { Text(estimate.note).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Φαγητά") {
                if estimate.items.isEmpty { Text("Δεν αναγνωρίστηκε φαγητό.").foregroundStyle(.secondary) }
                ForEach(Array(estimate.items.enumerated()), id: \.offset) { i, item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.name).font(.headline)
                            Spacer()
                            Text("\(Fmt.kcal(Int((Double(item.kcal) * portions[i]).rounded()))) kcal").monospacedDigit()
                        }
                        Stepper(value: $portions[i], in: 0...4, step: 0.25) {
                            Text(portions[i] == 0 ? "Εκτός" : "\(MealEditorView.text(portions[i]))× · ~\(Int((Double(item.grams) * portions[i]).rounded())) g")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Picker("Γεύμα", selection: $kind) { ForEach(MealKind.allCases) { Text($0.title).tag($0) } }
                let bought = todayFood
                if !bought.isEmpty {
                    Picker("Σύνδεση με αγορά", selection: $linkedItem) {
                        Text("Καμία").tag(String?.none)
                        ForEach(bought, id: \.item.id) { e in
                            Text("\(e.purchase.store.isEmpty ? e.item.name : e.purchase.store) · \(Fmt.money(e.item.cents))").tag(Optional(e.item.id))
                        }
                    }
                }
            } footer: {
                Text("Οι τιμές είναι κατά προσέγγιση. Διόρθωσε τις μερίδες αν χρειάζεται, ή άλλαξε κάθε γεύμα αργότερα.")
            }
        }
    }

    private var total: Int {
        guard let estimate else { return 0 }
        return zip(estimate.items, portions).reduce(0) { $0 + Int((Double($1.0.kcal) * $1.1).rounded()) }
    }

    private var todayFood: [(purchase: Purchase, item: Item)] {
        store.data.purchases.filter { $0.date == store.today }
            .flatMap { p in p.items.map { (purchase: p, item: $0) } }
            .filter { ["food", "coffee", "groceries"].contains($0.item.cat) }
    }

    private func confidenceText(_ c: String) -> String {
        switch c {
        case "high": "Υψηλή βεβαιότητα"
        case "medium": "Μέτρια βεβαιότητα"
        default: "Χαμηλή βεβαιότητα"
        }
    }

    private func use(_ img: UIImage) {
        image = img
        estimate = nil
        error = nil
        Task { await run() }
    }

    private func run() async {
        guard let image, let jpeg = Self.jpeg(image) else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let e = try await SyncManager.shared.estimate(jpeg: jpeg, note: note)
            estimate = e
            portions = e.items.map { _ in 1 }
        } catch let e as SyncError {
            error = switch e {
            case .offline: "Χωρίς σύνδεση. Δοκίμασε ξανά όταν έχεις internet."
            case .rateLimited: "Έφτασες το όριο εκτιμήσεων για σήμερα."
            case .server(503): "Ο server δεν έχει ρυθμιστεί για εκτιμήσεις (λείπει το API key του AI)."
            case .server(422): "Η φωτογραφία δεν μπόρεσε να αναλυθεί. Δοκίμασε άλλη."
            default: "Η εκτίμηση απέτυχε. Δοκίμασε ξανά."
            }
        } catch {
            self.error = "Η εκτίμηση απέτυχε. Δοκίμασε ξανά."
        }
    }

    private func save() {
        guard let estimate else { return }
        let link = todayFood.first { $0.item.id == linkedItem }
        var linked = false
        for (item, portion) in zip(estimate.items, portions) where portion > 0 {
            // The purchase is linked to the first food only, so its cost counts once.
            let m = Meal(estimate: item, portion: portion, date: store.today, meal: kind,
                         purchaseId: linked ? nil : link?.purchase.id, itemId: linked ? nil : link?.item.id)
            linked = linked || link != nil
            store.upsertMeal(m)
        }
        dismiss()
    }

    /// Longest side 1024 px: enough to recognise food, small to send (~150 KB).
    static func jpeg(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1024
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.7)
    }
}

/// The system camera (PhotosPicker cannot take photos).
private struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.done(info[.originalImage] as? UIImage)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.done(nil)
            parent.dismiss()
        }
    }
}
