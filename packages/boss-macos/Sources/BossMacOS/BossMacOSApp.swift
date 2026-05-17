import AppKit
import SwiftUI

@main
struct BossApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = BossMacOSViewModel()
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    var body: some Scene {
        Window("Boss", id: "main") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 760, minHeight: 560)
        }
        .windowStyle(.titleBar)

        MenuBarExtra {
            BossMenuBarView(viewModel: viewModel)
        } label: {
            MenuBarHeadphonesIcon()
        }

        Settings {
            BossSettingsView(launchAtLogin: launchAtLogin)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Open Boss") {
                    AppDelegate.openMainWindow()
                }

                Button("Choose Device") {
                    viewModel.returnToDeviceSelection()
                }

                Button("Reconnect") {
                    viewModel.refresh()
                }

                Divider()

                Menu("Scan Timeout") {
                    ForEach([5, 10, 15, 20, 30, 45, 60], id: \.self) { seconds in
                        Button {
                            viewModel.scanTimeoutSeconds = seconds
                        } label: {
                            if viewModel.scanTimeoutSeconds == seconds {
                                Label("\(seconds) seconds", systemImage: "checkmark")
                            } else {
                                Text("\(seconds) seconds")
                            }
                        }
                    }
                }
            }
            CommandGroup(replacing: .newItem) {}
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchedAtLogin = Self.detectLoginItemLaunch()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        Self.applyAppIcon()
        if launchedAtLogin {
            DispatchQueue.main.async {
                Self.transitionToMenuBarOnly()
            }
        } else {
            NSApplication.shared.setActivationPolicy(.regular)
            Self.activateApp()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    static func activateApp() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.delegate = NSApp.delegate as? AppDelegate
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func openMainWindow() {
        NSApplication.shared.unhide(nil)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            if let window = NSApp.windows.first {
                window.delegate = NSApp.delegate as? AppDelegate
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    static func applyAppIcon() {
        guard let image = BossImageResource.bossLogo.nsImage() else {
            return
        }
        NSApplication.shared.applicationIconImage = image
    }

    static func transitionToMenuBarOnly() {
        NSApp.windows.forEach { $0.orderOut(nil) }
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.hide(nil)
    }

    private static func detectLoginItemLaunch() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let launchedAtLogin = event.paramDescriptor(forKeyword: LoginItemLaunchKeyword.value) else {
            return false
        }
        return launchedAtLogin.booleanValue
    }

    @objc
    private func handleWindowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        window.delegate = self
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender.title == "Boss" {
            AppDelegate.transitionToMenuBarOnly()
            return false
        }
        return true
    }
}

private enum LoginItemLaunchKeyword {
    static let value: AEKeyword = 0x6C676974
}

private struct MenuBarHeadphonesIcon: View {
    var body: some View {
        if let image = menuBarImage {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "headphones")
        }
    }

    private var menuBarImage: NSImage? {
        guard let image = BossImageResource.headphonesMenuBar.nsImage() else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
