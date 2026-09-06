import SwiftUI

@main
struct PortalOSApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeScreenPrototypeView()
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }
}
