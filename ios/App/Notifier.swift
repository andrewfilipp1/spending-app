import Foundation
import SpendingCore
import UserNotifications

/// Local notifications only — scheduled on the device, no server, nothing leaves the phone.
@MainActor
final class Notifier {
    static let shared = Notifier()
    private let center = UNUserNotificationCenter.current()
    private let reminderIDs = (0..<7).map { "reminder-\($0)" }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func dataChanged(_ store: Store) {
        guard store.loaded else { return }
        let data = store.data
        scheduleReminders(data)
        sendBudgetAlerts(store)
        if data.settings.budgetAlerts && data.settings.budgets.any {
            Task {
                if await authorizationStatus() == .notDetermined { _ = await requestPermission() }
            }
        }
    }

    /// One reminder per day for the next week. Today's is skipped once something has been logged.
    private func scheduleReminders(_ data: AppData) {
        center.removePendingNotificationRequests(withIdentifiers: reminderIDs)
        guard data.settings.dailyReminder else { return }
        let today = Days.today()
        let hour = data.settings.reminderMinutes / 60
        let minute = data.settings.reminderMinutes % 60
        let loggedToday = data.purchases.contains { $0.date == today }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let passed = (now.hour! * 60 + now.minute!) >= data.settings.reminderMinutes

        for i in 0..<7 {
            if i == 0 && (loggedToday || passed) { continue }
            let p = Days.parts(Days.add(today, i))
            let content = UNMutableNotificationContent()
            content.title = "Τα Οικονομικά μου"
            content.body = "Κατέγραψες τα σημερινά σου έξοδα;"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(year: p.y, month: p.m, day: p.d, hour: hour, minute: minute), repeats: false)
            center.add(UNNotificationRequest(identifier: reminderIDs[i], content: content, trigger: trigger))
        }
    }

    private func sendBudgetAlerts(_ store: Store) {
        let alerts = Alerts.pending(store.data, today: Days.today())
        guard !alerts.isEmpty else { return }
        for a in alerts {
            let content = UNMutableNotificationContent()
            content.title = a.title
            content.body = a.body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "alert-\(a.key)", content: content, trigger: nil))
        }
        store.markAlertsSent(alerts.map(\.key))
    }
}

/// Shows notifications as banners even while the app is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
