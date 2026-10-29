import Foundation
import Observation
import Security
import SpendingCore

enum SyncConfig {
    /// Address of the sync server (server/). Empty = account features hidden.
    static let url = URL(string: "https://sync.62-238-96-63.sslip.io")
}

/// Account keys live in the Keychain, readable only while this iPhone is unlocked and never
/// included in backups or other devices.
enum Keychain {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.andrewfilipp.oikonomika.sync",
        kSecAttrAccount as String: "account",
    ]

    static func save(_ keys: AccountKeys) -> Bool {
        guard let data = try? JSONEncoder().encode(keys) else { return false }
        delete()
        var q = base
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> AccountKeys? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(AccountKeys.self, from: data)
    }

    static func delete() {
        SecItemDelete(base as CFDictionary)
    }
}

@MainActor @Observable
final class SyncManager {
    static let shared = SyncManager()

    private(set) var username: String?
    private(set) var busy = false
    private(set) var lastSync: Date?
    private(set) var error: SyncError?

    private var keys: AccountKeys?
    private let client = SyncConfig.url.map { SyncClient(baseURL: $0) }
    private var debounce: Task<Void, Never>?
    private var running: Task<Void, Never>?
    private var again = false

    var enabled: Bool { client != nil }

    func loadAccount() {
        guard enabled, keys == nil, let k = Keychain.load() else { return }
        keys = k
        username = k.username
        lastSync = UserDefaults.standard.object(forKey: "lastSync") as? Date
    }

    /// Sync shortly after local changes (several quick edits → one upload).
    func schedule() {
        guard keys != nil else { return }
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { await syncNow() }
        }
    }

    func syncNow() async {
        guard let keys, let client else { return }
        if let running {
            again = true
            await running.value
            return
        }
        busy = true
        let task = Task { @MainActor in
            do {
                repeat {
                    again = false
                    try await syncOnce(keys, client)
                } while again && self.keys == keys
                error = nil
                lastSync = Date()
                UserDefaults.standard.set(lastSync, forKey: "lastSync")
            } catch let e as SyncError {
                error = e
            } catch {
                self.error = .server(0)
            }
            busy = false
        }
        running = task
        await task.value
        running = nil
    }

    private func syncOnce(_ keys: AccountKeys, _ client: SyncClient) async throws {
        let store = Store.shared
        store.loadIfNeeded()
        guard store.loaded else { return }
        let started = store.changes
        let local = store.data
        let now = Date().timeIntervalSince1970 * 1000
        let (result, _) = try await client.syncRound(keys) { remote in
            guard let remote else { return (local, true) }
            let r = remote.sanitized()
            let merged = SyncMerge.merge(local: local, remote: r, now: now).sanitized()
            return (merged, merged != r)
        }
        guard self.keys == keys else { return }
        if store.changes != started {
            again = true // edited while syncing: merge again with the newer local data
        } else if result != store.data {
            store.applySynced(result)
        }
    }

    // MARK: account

    func signIn(username raw: String, password: String, create: Bool) async throws {
        guard let client else { return }
        let username = AccountKeys.normalize(raw)
        let k = try await Task.detached(priority: .userInitiated) {
            try AccountKeys.derive(username: username, password: password)
        }.value
        if create { try await client.register(k) }
        try await client.verify(k)
        _ = Keychain.save(k)
        keys = k
        self.username = username
        error = nil
        await syncNow()
    }

    func signOut() {
        debounce?.cancel()
        Keychain.delete()
        keys = nil
        username = nil
        lastSync = nil
        error = nil
        UserDefaults.standard.removeObject(forKey: "lastSync")
    }

    var signedIn: Bool { keys != nil }

    /// Calorie estimate for a photo, through the sync server (which holds the AI service key).
    func estimate(jpeg: Data, note: String) async throws -> FoodEstimate {
        guard let keys, let client else { throw SyncError.unauthorized }
        return try await client.estimate(keys, jpeg: jpeg, note: note)
    }

    func deleteAccount() async throws {
        guard let keys, let client else { return }
        try await client.deleteAccount(keys)
        signOut()
    }

    static func message(_ e: SyncError) -> String {
        switch e {
        case .offline: "Χωρίς σύνδεση — θα συγχρονιστεί αργότερα."
        case .unauthorized: "Λάθος όνομα χρήστη ή κωδικός."
        case .locked: "Πολλές αποτυχημένες προσπάθειες. Δοκίμασε σε 15 λεπτά."
        case .taken: "Το όνομα χρήστη υπάρχει ήδη."
        case .rateLimited: "Πάρα πολλές εγγραφές από αυτό το δίκτυο. Δοκίμασε αύριο."
        case .decrypt: "Τα δεδομένα του λογαριασμού δεν ανοίγουν με αυτόν τον κωδικό."
        case .conflict: "Ταυτόχρονες αλλαγές — δοκίμασε ξανά."
        case .badRequest, .server: "Ο συγχρονισμός απέτυχε."
        }
    }
}
