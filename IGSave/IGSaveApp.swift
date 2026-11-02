import SwiftUI

@main
struct IGSaveApp: App {
    init() {
        #if DEBUG
        UITestSupport.configureIfNeeded()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            HomeView().tint(.termIce).preferredColorScheme(.dark)
        }
    }
}
