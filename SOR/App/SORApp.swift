import SwiftUI
import UserNotifications
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
import GoogleSignIn

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Without GoogleService-Info.plist (see README, "One-time setup") the app explains what's missing instead of crashing.
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            // Offline cache: the shop Wi-Fi is never great.
            let settings = FirestoreSettings()
            settings.cacheSettings = PersistentCacheSettings()
            Firestore.firestore().settings = settings
            Messaging.messaging().delegate = self
        }
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("push: couldn't register:", error.localizedDescription) // Personal Team test installs can't get push
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            if let model = AppModel.shared { model.savePushToken(fcmToken) }
        }
    }

    /// Show notifications while the app is open too (a new task while you're looking at Home, say).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Tapping one opens what it's about (the bot puts the website path in `path`).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let path = response.notification.request.content.userInfo["path"] as? String else { return }
        await MainActor.run { AppModel.shared?.open(path: path) }
    }
}

@main
struct SORApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "system" ? nil : .dark)
                .onOpenURL { url in
                    // Google sign-in comes back through its own scheme; team.systemoverload.org links open their page.
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    model.open(url: url)
                }
                .task {
                    AppModel.shared = model
                    model.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.watchArrivals()
                        model.refreshCalendar(force: true)
                        UNUserNotificationCenter.current().setBadgeCount(0)
                    }
                }
        }
    }
}
