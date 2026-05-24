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
    private static let mainWindowTitle = "Boss"
    private static var presentationTransitionID = 0
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
        presentationTransitionID &+= 1
        NSApplication.shared.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        restoreMainWindow()
    }

    static func openMainWindow() {
        presentationTransitionID &+= 1
        let transitionID = presentationTransitionID
        NSApplication.shared.unhide(nil)
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            guard transitionID == presentationTransitionID else {
                return
            }
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            restoreMainWindow()
        }
    }

    static func transitionToMenuBarOnly() {
        presentationTransitionID &+= 1
        let transitionID = presentationTransitionID
        NSApp.windows.forEach { window in
            window.orderOut(nil)
        }
        DispatchQueue.main.async {
            guard transitionID == presentationTransitionID else {
                return
            }
            completeMenuBarTransition()
        }
    }

    private static func completeMenuBarTransition() {
        NSApplication.shared.setActivationPolicy(.accessory)
        _ = NSRunningApplication.current.hide()
        NSApplication.shared.hide(nil)
    }

    private static func restoreMainWindow() {
        guard let window = preferredMainWindow() else {
            return
        }

        window.delegate = NSApp.delegate as? AppDelegate
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        if window.canBecomeMain {
            window.makeMain()
        }
    }

    private static func preferredMainWindow() -> NSWindow? {
        NSApp.windows.first(where: isRestorableMainWindow)
            ?? NSApp.windows.first(where: isFocusableTitledWindow)
    }

    private static func isRestorableMainWindow(_ window: NSWindow) -> Bool {
        window.title == mainWindowTitle && isFocusableTitledWindow(window)
    }

    private static func isFocusableTitledWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && window.canBecomeKey && window.canBecomeMain
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
        if sender.title == Self.mainWindowTitle {
            AppDelegate.transitionToMenuBarOnly()
            return false
        }
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else {
            return false
        }
        Self.activateApp()
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
