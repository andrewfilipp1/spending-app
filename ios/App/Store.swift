import Foundation
import Observation
import SpendingCore

/// Owns the app data. Everything is stored in one JSON file inside the app sandbox,
/// protected by iOS Data Protection (encrypted with the device passcode while locked).
@MainActor @Observable
final class Store {
    static let shared = Store()

    private(set) var data = AppData()
    private(set) var loaded = false
    var errorMessage: String?

    private let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Data", isDirectory: true)
    private var fileURL: URL { dir.appendingPathComponent("data.json") }
    // Payments logged by Shortcuts while the main file is unavailable (device locked).
    private var inboxURL: URL { dir.appendingPathComponent("inbox.json") }

    func loadIfNeeded() {
        if !loaded { load() }
    }

    func load() {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                // Never overwrite the file if it exists but cannot be read (e.g. device locked).
                data = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: fileURL)).sanitized()
            } else {
                data = AppData()
                try write()
            }
            loaded = true
            errorMessage = nil
            mergeInbox()
        } catch {
            errorMessage = "Δεν ήταν δυνατή η ανάγνωση των δεδομένων. (\(error.localizedDescription))"
        }
    }

    // MARK: changes

    func update(_ change: (inout AppData) -> Void) {
        guard loaded else { return }
        change(&data)
        persist()
    }

    func upsert(_ p: Purchase) {
        update { d in
            if let i = d.purchases.firstIndex(where: { $0.id == p.id }) { d.purchases[i] = p } else { d.purchases.append(p) }
        }
    }

    func delete(_ id: String) {
        update { $0.purchases.removeAll { $0.id == id } }
    }

    func replaceAll(with newData: AppData) {
        guard loaded else { return }
        data = newData.sanitized()
        persist()
    }

    func reset() {
        guard loaded else { return }
        data = AppData()
        try? FileManager.default.removeItem(at: inboxURL)
        persist()
    }

    /// Called by the App Intent (e.g. a Shortcuts automation on every Apple Pay payment).
    func logPayment(cents: Int, merchant: String) {
        loadIfNeeded()
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let cat = MerchantHints.category(for: name, in: loaded ? data : AppData())
        let p = Purchase(date: Days.today(), store: String(name.prefix(120)), source: "applepay", review: true,
                         items: [Item(name: name.isEmpty ? "Πληρωμή Apple Pay" : String(name.prefix(120)), cents: cents, cat: cat)])
        if loaded {
            upsert(p)
        } else {
            appendToInbox(p)
        }
    }

    func markAlertsSent(_ keys: [String]) {
        data.settings.alertsSent = Array((data.settings.alertsSent + keys).suffix(60))
        try? write() // no persist(): avoids re-triggering alert checks
    }

    // MARK: files

    private func persist() {
        do {
            try write()
        } catch {
            errorMessage = "Σφάλμα αποθήκευσης: \(error.localizedDescription)"
        }
        Notifier.shared.dataChanged(self)
    }

    private func write() throws {
        let encoded = try JSONEncoder().encode(data)
        try encoded.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private func appendToInbox(_ p: Purchase) {
        var list = (try? JSONDecoder().decode([Purchase].self, from: Data(contentsOf: inboxURL))) ?? []
        list.append(p)
        if let encoded = try? JSONEncoder().encode(list) {
            try? encoded.write(to: inboxURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func mergeInbox() {
        guard loaded, let raw = try? Data(contentsOf: inboxURL),
              let list = try? JSONDecoder().decode([Purchase].self, from: raw) else { return }
        let existing = Set(data.purchases.map(\.id))
        let new = list.filter { !existing.contains($0.id) }
        try? FileManager.default.removeItem(at: inboxURL)
        if !new.isEmpty {
            data.purchases += new
            data = data.sanitized()
            persist()
        }
    }
}

/// Which sheet/tab is showing.
@MainActor @Observable
final class Router {
    enum Tab: Hashable { case home, history, stats, settings }
    var tab: Tab = .home
    var editor: EditorTarget?

    func newPurchase() { editor = EditorTarget(purchase: nil) }
    func edit(_ p: Purchase) { editor = EditorTarget(purchase: p) }
}

struct EditorTarget: Identifiable {
    let id = UUID()
    var purchase: Purchase?
}
