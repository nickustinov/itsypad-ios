import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // CKSyncEngine listens for CloudKit silent pushes itself, but the app
        // must register with APNs or no pushes are delivered at all.
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone && SettingsStore.shared.lockRotation {
            return .portrait
        }
        return .allButUpsideDown
    }
}
