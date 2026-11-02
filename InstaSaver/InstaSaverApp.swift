import SwiftUI

@main
struct InstaSaverApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView().tint(.termIce).preferredColorScheme(.dark)
        }
    }
}
