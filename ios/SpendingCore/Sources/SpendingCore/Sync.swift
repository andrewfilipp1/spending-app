import CryptoKit
import Foundation

// Account + end-to-end encrypted sync. Same protocol and formats as js/sync.js and js/logic.js.
//
// From the account password the device derives (PBKDF2-SHA-256, 600k rounds) 64 bytes:
// the first 32 are the AES-256-GCM key for the data (never leaves the device), the last 32 are
// the login key sent to the server, which stores only its SHA-256.

public struct AccountKeys: Codable, Equatable, Sendable {
    public let username: String
    public let encKey: Data
    public let auth: Data

    public static let usernamePattern = #"^[a-z0-9._-]{3,32}$"#

    public static func normalize(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func isValid(username: String) -> Bool {
        username.range(of: usernamePattern, options: .regularExpression) != nil
    }

    /// Slow on purpose (~0.5 s); call off the main thread.
    public static func derive(username: String, password: String, iterations: Int = 600_000) throws -> AccountKeys {
        let bytes = try Backup.pbkdf2(password: password, salt: Data("spending-app/sync/v1/\(username)".utf8),
                                      iterations: iterations, length: 64)
        return AccountKeys(username: username, encKey: Data(bytes[0..<32]), auth: Data(bytes[32..<64]))
    }

    var key: SymmetricKey { SymmetricKey(data: encKey) }
}

public struct SyncBlob: Codable, Equatable, Sendable {
    public let iv: String
    public let ct: String // ciphertext || 16-byte tag, base64 (Web Crypto layout)

    static func seal(_ data: AppData, key: SymmetricKey) throws -> SyncBlob {
        let box = try AES.GCM.seal(try JSONEncoder().encode(data), using: key)
        return SyncBlob(iv: Data(box.nonce).base64EncodedString(), ct: (box.ciphertext + box.tag).base64EncodedString())
    }

    func open(key: SymmetricKey) throws -> AppData {
        guard let iv = Data(base64Encoded: iv), let ct = Data(base64Encoded: ct), ct.count >= 16 else { throw SyncError.decrypt }
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ct.dropLast(16), tag: ct.suffix(16))
            return try JSONDecoder().decode(AppData.self, from: try AES.GCM.open(box, using: key))
        } catch {
            throw SyncError.decrypt
        }
    }
}

public enum SyncError: Error, Equatable, Sendable {
    case offline, unauthorized, locked, taken, rateLimited, decrypt, conflict, badRequest
    case server(Int)
}

// MARK: - stamping & merging

/// A list entry that syncs on its own (newest edit wins). Ids are unique across lists, so they share `deleted`.
protocol SyncRecord: Equatable {
    var id: String { get }
    var createdAt: Double { get }
    var updatedAt: Double { get set }
}

extension Purchase: SyncRecord {}
extension Meal: SyncRecord {}
extension Food: SyncRecord {}

public enum SyncMerge {
    static func stamp(_ p: some SyncRecord) -> Double { max(p.updatedAt, p.createdAt) }

    private static func stampRecords<R: SyncRecord>(prev: [R], next: inout [R], deleted: inout [String: Double], now: Double) {
        var before = Dictionary(prev.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for i in next.indices {
            let p = next[i]
            var q = before.removeValue(forKey: p.id)
            q?.updatedAt = p.updatedAt
            if q != p { next[i].updatedAt = now }
        }
        for id in before.keys { deleted[id] = now }
    }

    private static func mergeRecords<R: SyncRecord>(local: [R], remote: [R], deleted: [String: Double]) -> [R] {
        var byId: [String: R] = [:]
        var order: [String] = []
        for p in remote where byId[p.id] == nil {
            byId[p.id] = p
            order.append(p.id)
        }
        for p in local {
            if let r = byId[p.id] {
                if stamp(p) > stamp(r) { byId[p.id] = p }
            } else {
                byId[p.id] = p
                order.append(p.id)
            }
        }
        return order.compactMap { byId[$0] }.filter { (deleted[$0.id] ?? 0) < stamp($0) }
    }

    /// Marks what changed since the last save so other devices can tell which copy is newer.
    public static func stampChanges(prev: AppData?, next: inout AppData, now: Double) {
        guard let prev else { return }
        if prev.settings != next.settings { next.settingsUpdatedAt = now }
        if prev.categories != next.categories { next.categoriesUpdatedAt = now }
        if prev.nutrition != next.nutrition { next.nutritionUpdatedAt = now }
        stampRecords(prev: prev.purchases, next: &next.purchases, deleted: &next.deleted, now: now)
        stampRecords(prev: prev.meals, next: &next.meals, deleted: &next.deleted, now: now)
        stampRecords(prev: prev.foods, next: &next.foods, deleted: &next.deleted, now: now)
    }

    /// Purchases, meals and foods merge one by one (newest edit wins, deletions win over older edits);
    /// settings, categories and nutrition take the most recently changed copy; ties go to the server copy.
    public static func merge(local: AppData, remote: AppData, now: Double) -> AppData {
        var deleted = remote.deleted
        for (id, t) in local.deleted { deleted[id] = max(deleted[id] ?? 0, t) }

        let purchases = mergeRecords(local: local.purchases, remote: remote.purchases, deleted: deleted)

        let localCats = local.categoriesUpdatedAt > remote.categoriesUpdatedAt
        var categories = localCats ? local.categories : remote.categories
        let used = Set(purchases.flatMap { $0.items.map(\.cat) })
        for c in (localCats ? remote.categories : local.categories) where used.contains(c.id) && !categories.contains(where: { $0.id == c.id }) {
            categories.insert(c, at: max(0, categories.count - 1))
        }

        var out = AppData(schema: max(local.schema, remote.schema),
                          settings: local.settingsUpdatedAt > remote.settingsUpdatedAt ? local.settings : remote.settings,
                          categories: categories, purchases: purchases)
        out.settingsUpdatedAt = max(local.settingsUpdatedAt, remote.settingsUpdatedAt)
        out.categoriesUpdatedAt = max(local.categoriesUpdatedAt, remote.categoriesUpdatedAt)
        out.meals = mergeRecords(local: local.meals, remote: remote.meals, deleted: deleted)
        out.foods = mergeRecords(local: local.foods, remote: remote.foods, deleted: deleted)
        out.nutrition = local.nutritionUpdatedAt > remote.nutritionUpdatedAt ? local.nutrition : remote.nutrition
        out.nutritionUpdatedAt = max(local.nutritionUpdatedAt, remote.nutritionUpdatedAt)
        let yearAgo = now - 365 * 86_400_000
        out.deleted = deleted.filter { $0.value > yearAgo }
        return out
    }
}

// MARK: - client

public struct SyncClient: Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral // no cache, no cookies
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    private struct Remote: Decodable {
        let version: Int
        let blob: SyncBlob?
    }

    private struct ErrorBody: Decodable { let error: String? }

    private func request(_ keys: AccountKeys?, _ method: String, _ path: String, body: Encodable? = nil, timeout: TimeInterval? = nil) async throws -> (Int, Data) {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        if let timeout { req.timeoutInterval = timeout }
        if let keys { req.setValue("Sync \(keys.username):\(keys.auth.base64EncodedString())", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw SyncError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) || status == 409 { return (status, data) }
        switch (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error {
        case "unauthorized": throw SyncError.unauthorized
        case "locked": throw SyncError.locked
        case "taken": throw SyncError.taken
        case "rate_limited": throw SyncError.rateLimited
        case "bad_request": throw SyncError.badRequest
        default: throw SyncError.server(status)
        }
    }

    public func register(_ keys: AccountKeys) async throws {
        struct Body: Encodable { let username: String; let auth: String }
        let (status, _) = try await request(nil, "POST", "v1/register", body: Body(username: keys.username, auth: keys.auth.base64EncodedString()))
        if status == 409 { throw SyncError.taken }
    }

    /// Checks the login and that the stored data opens with these keys.
    public func verify(_ keys: AccountKeys) async throws {
        let (_, data) = try await request(keys, "GET", "v1/data")
        if let blob = try JSONDecoder().decode(Remote.self, from: data).blob { _ = try blob.open(key: keys.key) }
    }

    /// Calorie estimate for a JPEG photo of food. The server answers 503 when estimates are not set up,
    /// 422 when the photo was declined and 502 when the AI service failed (as `.server(status)`).
    public func estimate(_ keys: AccountKeys, jpeg: Data, note: String = "") async throws -> FoodEstimate {
        struct Body: Encodable { let image: String; let note: String }
        let (_, data) = try await request(keys, "POST", "v1/estimate", body: Body(image: jpeg.base64EncodedString(), note: note), timeout: 90)
        return try JSONDecoder().decode(FoodEstimate.self, from: data)
    }

    public func deleteAccount(_ keys: AccountKeys) async throws {
        _ = try await request(keys, "DELETE", "v1/account")
    }

    /// One sync round: `merge(remote)` returns the data that belongs on the server and whether it
    /// differs from the remote copy. Retried on a version conflict.
    public func syncRound(_ keys: AccountKeys, merge: (AppData?) -> (result: AppData, changed: Bool)) async throws -> (AppData, Int) {
        struct Put: Encodable { let version: Int; let blob: SyncBlob }
        struct Version: Decodable { let version: Int }
        for _ in 0..<4 {
            let (_, data) = try await request(keys, "GET", "v1/data")
            let remote = try JSONDecoder().decode(Remote.self, from: data)
            let (result, changed) = merge(try remote.blob?.open(key: keys.key))
            if !changed { return (result, remote.version) }
            let (status, putData) = try await request(keys, "PUT", "v1/data",
                                                      body: Put(version: remote.version, blob: try SyncBlob.seal(result, key: keys.key)))
            if status == 200 { return (result, try JSONDecoder().decode(Version.self, from: putData).version) }
        }
        throw SyncError.conflict
    }
}
