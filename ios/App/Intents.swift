import AppIntents
import SpendingCore

/// "Log payment" action for the Shortcuts app. Paired with the "Transaction" automation it records
/// every Apple Pay payment automatically, without opening the app.
struct LogPaymentIntent: AppIntent {
    static var title: LocalizedStringResource = "Καταχώρηση πληρωμής"
    static var description = IntentDescription("Καταγράφει μια πληρωμή στα Οικονομικά, π.χ. από τον αυτοματισμό «Συναλλαγή» του Apple Pay.")
    static var openAppWhenRun = false

    @Parameter(title: "Ποσό")
    var amount: String

    @Parameter(title: "Έμπορος", default: "")
    var merchant: String

    static var parameterSummary: some ParameterSummary {
        Summary("Καταχώρηση \(\.$amount) από \(\.$merchant)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let cents = Money.toCents(amount), cents > 0 else {
            return .result(dialog: "Δεν αναγνωρίστηκε ποσό στο «\(amount)».")
        }
        Store.shared.logPayment(cents: cents, merchant: merchant)
        SyncManager.shared.loadAccount()
        await SyncManager.shared.syncNow()
        let text = merchant.isEmpty ? Fmt.money(cents) : "\(Fmt.money(cents)) · \(merchant)"
        return .result(dialog: "Καταχωρήθηκε: \(text)")
    }
}

struct OikonomikaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogPaymentIntent(),
            phrases: ["Καταχώρηση πληρωμής στα \(.applicationName)"],
            shortTitle: "Καταχώρηση πληρωμής",
            systemImageName: "eurosign.circle"
        )
    }
}
