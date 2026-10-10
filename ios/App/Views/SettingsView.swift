import SpendingCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(LockManager.self) private var lock
    @Environment(\.openURL) private var openURL

    @State private var showExportChoice = false
    @State private var passwordRequest: PasswordRequest?
    @State private var exportFile: JSONFile?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingImport: AppData?
    @State private var confirmWipe = false
    @State private var notice: String?
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                budgetSection
                categoryBudgetSection
                categoriesSection
                notificationsSection
                securitySection
                applePaySection
                backupSection
                aboutSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Ρυθμίσεις")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Τέλος") { hideKeyboard() }
                }
            }
            .sheet(item: $passwordRequest) { req in PasswordSheet(request: req) }
            .fileExporter(isPresented: $showExporter, document: exportFile, contentType: .json,
                          defaultFilename: "spending-backup-\(Days.today())") { result in
                if case .success = result { notice = "Το αντίγραφο αποθηκεύτηκε." }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                if case let .success(url) = result { readBackup(url) }
            }
            .confirmationDialog("Τύπος αντιγράφου", isPresented: $showExportChoice, titleVisibility: .visible) {
                Button("Κρυπτογραφημένο με κωδικό (προτείνεται)") {
                    passwordRequest = PasswordRequest(title: "Κωδικός αντιγράφου", confirm: true) { pw in export(password: pw) }
                }
                Button("Χωρίς κρυπτογράφηση") { export(password: nil) }
            } message: {
                Text("Το κρυπτογραφημένο αντίγραφο ανοίγει μόνο με τον κωδικό σου. Ανοίγει και στην web έκδοση.")
            }
            .alert("Επαναφορά δεδομένων;", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
                Button("Αντικατάσταση", role: .destructive) {
                    if let d = pendingImport { store.replaceAll(with: d); notice = "Η επαναφορά ολοκληρώθηκε." }
                    pendingImport = nil
                }
                Button("Άκυρο", role: .cancel) { pendingImport = nil }
            } message: {
                Text("Το αντίγραφο έχει \(pendingImport?.purchases.count ?? 0) αγορές και θα αντικαταστήσει τα τρέχοντα δεδομένα.")
            }
            .confirmationDialog("Διαγραφή όλων των δεδομένων;", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Οριστική διαγραφή", role: .destructive) { store.reset() }
            } message: {
                Text("Αγορές, κατηγορίες και ρυθμίσεις θα διαγραφούν από αυτό το iPhone. Δεν αναιρείται.")
            }
            .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .alert("Οι ειδοποιήσεις είναι απενεργοποιημένες", isPresented: $notificationsDenied) {
                Button("Άνοιγμα Ρυθμίσεων") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                Button("Άκυρο", role: .cancel) {}
            } message: {
                Text("Επίτρεψε τις ειδοποιήσεις για την εφαρμογή από τις Ρυθμίσεις του iPhone.")
            }
        }
    }

    // MARK: sections

    private var budgetSection: some View {
        Section {
            ForEach(PeriodKind.allCases) { BudgetField(kind: $0) }
            Picker("Η εβδομάδα ξεκινά", selection: binding(\.weekStart)) {
                Text("Δευτέρα").tag(1)
                Text("Κυριακή").tag(0)
            }
        } header: {
            Text("Budget")
        } footer: {
            Text("Άφησε κενό ό,τι δεν χρειάζεσαι. Το «Διαθέσιμα σήμερα» βγαίνει από το πιο αυστηρό budget.")
        }
    }

    private var categoryBudgetSection: some View {
        Section {
            ForEach(store.data.categories) { c in
                NavigationLink { CategoryBudgetView(categoryID: c.id) } label: {
                    HStack {
                        CategoryIcon(category: c, size: 30)
                        Text(c.name).lineLimit(1)
                        Spacer()
                        if let b = c.budget {
                            Text("\(Fmt.money(b))/\(c.budgetPeriod == .week ? "εβδ." : "μήνα")")
                                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                        if c.budgetChanges > 0 {
                            BudgetChangesBadge(count: c.budgetChanges)
                        }
                    }
                }
            }
        } header: {
            Text("Budget ανά κατηγορία")
        } footer: {
            Text("Όρισε ξεχωριστό όριο ανά εβδομάδα ή μήνα για κάθε κατηγορία, π.χ. Καύσιμα 60 €/εβδομάδα. Το ✎ δείχνει πόσες φορές το άλλαξες.")
        }
    }

    private var categoriesSection: some View {
        Section("Κατηγορίες") {
            ForEach(store.data.categories) { c in
                NavigationLink { CategoryEditorView(category: c) } label: {
                    HStack {
                        CategoryIcon(category: c, size: 30)
                        Text(c.name)
                    }
                }
            }
            NavigationLink { CategoryEditorView(category: nil) } label: {
                Label("Νέα κατηγορία", systemImage: "plus")
            }
        }
    }

    private var notificationsSection: some View {
        Section {
            Toggle("Καθημερινή υπενθύμιση", isOn: Binding(
                get: { store.data.settings.dailyReminder },
                set: { on in
                    if on {
                        Task {
                            if await Notifier.shared.requestPermission() {
                                store.update { $0.settings.dailyReminder = true }
                            } else {
                                notificationsDenied = true
                            }
                        }
                    } else {
                        store.update { $0.settings.dailyReminder = false }
                    }
                }))
            if store.data.settings.dailyReminder {
                DatePicker("Ώρα", selection: Binding(
                    get: {
                        let m = store.data.settings.reminderMinutes
                        return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
                    },
                    set: { d in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                        store.update { $0.settings.reminderMinutes = c.hour! * 60 + c.minute! }
                    }), displayedComponents: .hourAndMinute)
            }
            Toggle("Ειδοποιήσεις budget", isOn: Binding(
                get: { store.data.settings.budgetAlerts },
                set: { on in
                    store.update { $0.settings.budgetAlerts = on }
                    if on { Task { if !(await Notifier.shared.requestPermission()) { notificationsDenied = true } } }
                }))
        } header: {
            Text("Ειδοποιήσεις")
        } footer: {
            Text("Η υπενθύμιση δεν έρχεται αν έχεις ήδη καταγράψει κάτι εκείνη τη μέρα. Οι ειδοποιήσεις budget έρχονται όταν φτάσεις στο 80% και στο 100% ενός budget, ή όταν ξεπεράσεις το σημερινό όριο.")
        }
    }

    private var securitySection: some View {
        Section {
            Toggle("Κλείδωμα με \(LockManager.biometryName)", isOn: Binding(
                get: { store.data.settings.lockEnabled },
                set: { on in
                    Task {
                        let reason = on ? "Ενεργοποίηση κλειδώματος" : "Απενεργοποίηση κλειδώματος"
                        if await lock.authenticate(reason: reason) {
                            store.update { $0.settings.lockEnabled = on }
                        } else if let m = lock.message {
                            notice = m
                        }
                    }
                }))
            if store.data.settings.lockEnabled {
                Picker("Αυτόματο κλείδωμα", selection: binding(\.autoLockSec)) {
                    Text("Αμέσως").tag(0)
                    Text("Μετά από 1 λεπτό").tag(60)
                    Text("Μετά από 5 λεπτά").tag(300)
                    Text("Μετά από 15 λεπτά").tag(900)
                }
            }
        } header: {
            Text("Ασφάλεια & ιδιωτικότητα")
        } footer: {
            Text("""
            • Τα δεδομένα αποθηκεύονται μόνο σε αυτό το iPhone, κρυπτογραφημένα από το iOS όσο η συσκευή είναι κλειδωμένη.
            • Η εφαρμογή δεν συνδέεται ποτέ στο internet: δεν έχει server, λογαριασμό, διαφημίσεις ή analytics.
            • Με το κλείδωμα ενεργό, τα ποσά κρύβονται και στην εναλλαγή εφαρμογών.
            • Τα δεδομένα περιλαμβάνονται στο κρυπτογραφημένο backup του iPhone, για να μη χαθούν αν αλλάξεις κινητό.
            """)
        }
    }

    private var applePaySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Κάθε πληρωμή με Apple Pay καταγράφεται αυτόματα:").fontWeight(.semibold)
                step(1, "Άνοιξε τις **Συντομεύσεις** → **Αυτοματισμός** → **+** → **Συναλλαγή**.")
                step(2, "Διάλεξε τις κάρτες σου και **Εκτέλεση αμέσως**.")
                step(3, "Πρόσθεσε την ενέργεια **Καταχώρηση πληρωμής** (Οικονομικά).")
                step(4, "Στο **Ποσό** βάλε τη μεταβλητή *Ποσό* και στο **Έμπορος** τη μεταβλητή *Έμπορος*.")
                Text("Οι πληρωμές εμφανίζονται στην Αρχική «προς έλεγχο», για να τις χωρίσεις σε προϊόντα αν θέλεις.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            Button("Άνοιγμα Συντομεύσεων") { openURL(URL(string: "shortcuts://")!) }
        } header: {
            Label("Apple Pay", systemImage: "apple.logo")
        }
    }

    private var backupSection: some View {
        Section {
            Button { showExportChoice = true } label: { Label("Εξαγωγή αντιγράφου", systemImage: "square.and.arrow.up") }
            Button { showImporter = true } label: { Label("Επαναφορά από αντίγραφο", systemImage: "square.and.arrow.down") }
        } header: {
            Text("Αντίγραφα ασφαλείας")
        } footer: {
            Text("Συμβατά με την web έκδοση: μπορείς να μεταφέρεις τα δεδομένα από και προς τον browser.")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Έκδοση")
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–").foregroundStyle(.secondary)
            }
            Button("Διαγραφή όλων των δεδομένων", role: .destructive) { confirmWipe = true }
        }
    }

    // MARK: helpers

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Color.brand, in: Circle())
            Text(text).font(.subheadline)
        }
    }

    private func binding<T>(_ path: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { store.data.settings[keyPath: path] }, set: { v in store.update { $0.settings[keyPath: path] = v } })
    }

    private func export(password: String?) {
        do {
            exportFile = JSONFile(data: try Backup.export(store.data, password: password))
            showExporter = true
        } catch {
            notice = "Η εξαγωγή απέτυχε."
        }
    }

    private func readBackup(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let file = try? Data(contentsOf: url), file.count < 50_000_000 else {
            notice = "Δεν ήταν δυνατή η ανάγνωση του αρχείου."
            return
        }
        if Backup.isEncrypted(file) {
            passwordRequest = PasswordRequest(title: "Κωδικός αντιγράφου", confirm: false) { pw in load(file, password: pw) }
        } else {
            load(file, password: nil)
        }
    }

    private func load(_ file: Data, password: String?) {
        do {
            pendingImport = try Backup.load(file, password: password)
        } catch BackupError.wrongPassword {
            notice = "Λάθος κωδικός."
        } catch {
            notice = "Το αρχείο δεν είναι έγκυρο αντίγραφο αυτής της εφαρμογής."
        }
    }
}

private struct BudgetField: View {
    @Environment(Store.self) private var store
    let kind: PeriodKind
    @State private var text = ""
    @FocusState private var focused: Bool

    private var label: String {
        switch kind {
        case .day: "Ημερήσιο"
        case .week: "Εβδομαδιαίο"
        case .month: "Μηνιαίο"
        case .year: "Ετήσιο"
        }
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 110)
                .focused($focused)
            Text("€").foregroundStyle(.secondary)
        }
        .onAppear { text = Money.inputText(store.data.settings.budgets[kind]) }
        // Saved when editing ends, so half-typed amounts never trigger budget alerts.
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespaces)
        let current = store.data.settings.budgets[kind]
        if t.isEmpty {
            if current != nil { store.update { $0.settings.budgets[kind] = nil } }
        } else if let c = Money.toCents(t), c >= 0 {
            if c != current { store.update { $0.settings.budgets[kind] = c } }
            text = Money.inputText(c)
        } else {
            text = Money.inputText(current)
        }
    }
}

struct PasswordRequest: Identifiable {
    let id = UUID()
    let title: String
    let confirm: Bool
    let completion: (String) -> Void
}

private struct PasswordSheet: View {
    let request: PasswordRequest
    @Environment(\.dismiss) private var dismiss
    @State private var p1 = ""
    @State private var p2 = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Κωδικός", text: $p1).textContentType(request.confirm ? .newPassword : .password)
                    if request.confirm { SecureField("Επανάληψη κωδικού", text: $p2).textContentType(.newPassword) }
                } footer: {
                    if request.confirm { Text("Τουλάχιστον 6 χαρακτήρες. Χωρίς αυτόν το αντίγραφο δεν ανοίγει.") }
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Άκυρο") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        if request.confirm {
                            guard p1.count >= 6 else { error = "Τουλάχιστον 6 χαρακτήρες."; return }
                            guard p1 == p2 else { error = "Οι κωδικοί δεν ταιριάζουν."; return }
                        }
                        guard !p1.isEmpty else { return }
                        let pw = p1
                        dismiss()
                        // Let the sheet close before presenting the next one (exporter / alert).
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { request.completion(pw) }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
