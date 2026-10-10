import LocalAuthentication
import Observation
import SpendingCore
import SwiftUI

/// App lock with Face ID / Touch ID, falling back to the device passcode.
@MainActor @Observable
final class LockManager {
    var isLocked = false
    var message: String?
    private var backgroundAt: Date?
    private var authenticating = false

    func lockOnLaunch(enabled: Bool) {
        isLocked = enabled
    }

    func wentToBackground() {
        backgroundAt = Date()
    }

    func becameActive(settings: Settings) {
        defer { backgroundAt = nil }
        guard settings.lockEnabled, let since = backgroundAt else { return }
        if Date().timeIntervalSince(since) >= Double(settings.autoLockSec) { isLocked = true }
    }

    func unlock() async {
        if await authenticate(reason: "Ξεκλείδωμα των οικονομικών σου") { isLocked = false }
    }

    /// Returns true on success. Also used to confirm turning the lock on or off.
    func authenticate(reason: String) async -> Bool {
        guard !authenticating else { return false }
        authenticating = true
        defer { authenticating = false }
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = "Όρισε κωδικό στο iPhone (Ρυθμίσεις → Face ID & κωδικός) για να χρησιμοποιήσεις το κλείδωμα."
            return false
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            message = nil
            return ok
        } catch {
            message = nil
            return false
        }
    }

    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "κωδικό"
        }
    }
}

struct LockView: View {
    @Environment(LockManager.self) private var lock

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 52))
                .foregroundStyle(.brand)
            Text("Τα Οικονομικά μου").font(.title2.bold())
            Text("Κλειδωμένο").foregroundStyle(.secondary)
            if let m = lock.message {
                Text(m).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
            }
            Spacer()
            Button {
                Task { await lock.unlock() }
            } label: {
                Label("Ξεκλείδωμα με \(LockManager.biometryName)", systemImage: "faceid")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task { await lock.unlock() }
    }
}

struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
    }
}
