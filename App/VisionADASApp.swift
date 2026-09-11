import SwiftUI

@main
struct VisionADASApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .landscape
    }
}
