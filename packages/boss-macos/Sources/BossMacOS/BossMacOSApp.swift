import AppKit
import SwiftUI

@main
struct BossApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = BossMacOSViewModel()

    var body: some Scene {
        WindowGroup("Boss") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 760, minHeight: 560)
                .onAppear {
                    AppDelegate.activateApp()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        Self.activateApp()
    }

    static func activateApp() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}
