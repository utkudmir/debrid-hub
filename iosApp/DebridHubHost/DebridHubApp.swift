import SwiftUI

@main
struct DebridHubApp: App {
    @StateObject private var viewModel = IOSAppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
