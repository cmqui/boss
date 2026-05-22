import BossAppleApp
import SwiftUI

@main
struct BossIOSApp: App {
    @StateObject private var viewModel = BossAppViewModel()

    var body: some Scene {
        WindowGroup {
            BossIOSRootView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
    }
}
