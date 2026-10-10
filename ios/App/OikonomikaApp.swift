import SpendingCore
import SwiftUI
import UserNotifications

@main
struct OikonomikaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = Store.shared
    @State private var router = Router()
    @State private var lock = LockManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(lock)
                .tint(.brand)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        return true
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(LockManager.self) private var lock
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack {
            if store.loaded {
                MainTabs()
            } else if let message = store.errorMessage {
                ContentUnavailableView {
                    Label("Κάτι πήγε στραβά", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Δοκίμασε ξανά") { store.load() }
                }
            } else {
                ProgressView()
            }

            if lock.isLocked {
                LockView().transition(.opacity)
            } else if phase != .active && store.data.settings.lockEnabled {
                PrivacyCover() // hides amounts in the app switcher
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lock.isLocked)
        .task {
            store.loadIfNeeded()
            lock.lockOnLaunch(enabled: store.data.settings.lockEnabled)
            Notifier.shared.dataChanged(store)
        }
        .onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .background:
                lock.wentToBackground()
            case .active:
                store.loadIfNeeded()
                store.mergeInbox()
                lock.becameActive(settings: store.data.settings)
                Notifier.shared.dataChanged(store)
            default:
                break
            }
        }
    }
}

struct MainTabs: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            HomeView()
                .tabItem { Label("Αρχική", systemImage: "house.fill") }
                .tag(Router.Tab.home)
            HistoryView()
                .tabItem { Label("Ιστορικό", systemImage: "list.bullet") }
                .tag(Router.Tab.history)
            StatsView()
                .tabItem { Label("Στατιστικά", systemImage: "chart.bar.fill") }
                .tag(Router.Tab.stats)
            SettingsView()
                .tabItem { Label("Ρυθμίσεις", systemImage: "gearshape.fill") }
                .tag(Router.Tab.settings)
        }
        .sheet(item: $router.editor) { target in
            EditorView(target: target)
        }
    }
}
