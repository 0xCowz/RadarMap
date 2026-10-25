import SwiftUI
import UserNotifications

@main
struct RadarMapApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Start background alert monitoring (audio + local notifications + Live Activity)
        BackgroundAlertService.shared.start()
        // Start Live Activity on the Dynamic Island / Lock Screen
        LiveActivityManager.shared.start()
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        if session.role == .carTemplateApplication {
            config.delegateClass = CarPlaySceneDelegate.self
        }
        return config
    }

    func applicationWillTerminate(_ application: UIApplication) {
        LiveActivityManager.shared.stop()
    }
}
