import CommonCrypto
import CryptoKit
import Foundation

// Backup files, byte-compatible with the web app:
//   { app, format, encrypted: false, data, exportedAt }
//   { app, format, encrypted: true, salt, iterations, iv, ct, exportedAt }
// Encryption: PBKDF2-SHA-256 → AES-256-GCM; `ct` is ciphertext || 16-byte tag, as in Web Crypto.

public enum BackupError: Error, Equatable {
    case notABackup
    case needsPassword
    case wrongPassword
    case invalid
}

public enum Backup {
    public static let defaultIterations = 600_000

    public static func export(_ data: AppData, password: String? = nil, iterations: Int = defaultIterations) throws -> Data {
        let exportedAt = ISO8601DateFormatter().string(from: Date())
        let enc = JSONEncoder()
        var obj: [String: Any] = ["app": "spending-app", "format": 1, "exportedAt": exportedAt]
        if let password, !password.isEmpty {
            var salt = Data(count: 16)
            salt.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
            let key = try deriveKey(password: password, salt: salt, iterations: iterations)
            let sealed = try AES.GCM.seal(try enc.encode(data), using: key)
            obj["encrypted"] = true
            obj["salt"] = salt.base64EncodedString()
            obj["iterations"] = iterations
            obj["iv"] = Data(sealed.nonce).base64EncodedString()
            obj["ct"] = (sealed.ciphertext + sealed.tag).base64EncodedString()
        } else {
            obj["encrypted"] = false
            obj["data"] = try JSONSerialization.jsonObject(with: try enc.encode(data))
        }
        return try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }

    public static func isEncrypted(_ file: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: file) as? [String: Any])?["encrypted"] as? Bool == true
    }

    public static func load(_ file: Data, password: String? = nil) throws -> AppData {
        guard let obj = try? JSONSerialization.jsonObject(with: file) as? [String: Any],
              obj["app"] as? String == "spending-app" else { throw BackupError.notABackup }
        let json: Data
        if obj["encrypted"] as? Bool == true {
            guard let password, !password.isEmpty else { throw BackupError.needsPassword }
            guard let salt = (obj["salt"] as? String).flatMap({ Data(base64Encoded: $0) }),
                  let iv = (obj["iv"] as? String).flatMap({ Data(base64Encoded: $0) }),
                  let ct = (obj["ct"] as? String).flatMap({ Data(base64Encoded: $0) }), ct.count >= 16
            else { throw BackupError.invalid }
            let iterations = min(max(obj["iterations"] as? Int ?? defaultIterations, 100_000), 10_000_000)
            let key = try deriveKey(password: password, salt: salt, iterations: iterations)
            do {
                let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ct.dropLast(16), tag: ct.suffix(16))
                json = try AES.GCM.open(box, using: key)
            } catch {
                throw BackupError.wrongPassword
            }
        } else {
            guard let d = obj["data"], let encoded = try? JSONSerialization.data(withJSONObject: d) else { throw BackupError.invalid }
            json = encoded
        }
        guard let data = try? JSONDecoder().decode(AppData.self, from: json) else { throw BackupError.invalid }
        return data.sanitized()
    }

    static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        SymmetricKey(data: try pbkdf2(password: password, salt: salt, iterations: iterations, length: 32))
    }

    static func pbkdf2(password: String, salt: Data, iterations: Int, length: Int) throws -> [UInt8] {
        let pw = Array(password.utf8)
        var out = [UInt8](repeating: 0, count: length)
        let status = salt.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                                 s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &out, out.count)
        }
        guard status == kCCSuccess else { throw BackupError.invalid }
        return out
    }
}
