import SwiftUI
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Without GoogleService-Info.plist (see README, "One-time setup") the app explains what's missing instead of crashing.
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            // Offline cache: the shop Wi-Fi is never great.
            let settings = FirestoreSettings()
            settings.cacheSettings = PersistentCacheSettings()
            Firestore.firestore().settings = settings
        }
        return true
    }
}

@main
struct SORApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @AppStorage("appearance") private var appearance = "dark"
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "system" ? nil : .dark)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .task { model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.watchArrivals()
                        model.refreshCalendar(force: true)
                    }
                }
        }
    }
}
