import ServiceManagement
import SwiftUI

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var errorMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            errorMessage = nil
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            errorMessage = error.localizedDescription
            refresh()
        }
    }
}

struct BossMenuBarView: View {
    @ObservedObject var viewModel: BossMacOSViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Open Boss") {
                openWindow(id: "main")
                AppDelegate.openMainWindow()
            }

            Divider()

            if !viewModel.deviceName.isEmpty {
                Text(viewModel.deviceName)
                    .font(.headline)
            }

            if !viewModel.selectableAudioModes.isEmpty {
                Menu("Audio Modes") {
                    ForEach(viewModel.selectableAudioModes, id: \.modeIndex) { mode in
                        Button {
                            viewModel.selectAudioMode(mode.modeIndex)
                        } label: {
                            if viewModel.displayedCurrentAudioModeIndex == mode.modeIndex {
                                Label(viewModel.customProfileDisplayName(for: mode), systemImage: "checkmark")
                            } else {
                                Text(viewModel.customProfileDisplayName(for: mode))
                            }
                        }
                    }
                }
            }

            if viewModel.wearDetectionEnabled != nil || viewModel.autoAwareEnabled != nil ||
                viewModel.autoPlayPauseEnabled != nil || viewModel.autoAnswerEnabled != nil {
                Menu("Device Settings") {
                    if viewModel.wearDetectionEnabled != nil {
                        Toggle(
                            "Wear Detection",
                            isOn: Binding(
                                get: { viewModel.wearDetectionEnabled ?? false },
                                set: { viewModel.setWearDetectionEnabled($0) }
                            )
                        )
                    }

                    if viewModel.autoAwareEnabled != nil {
                        Toggle(
                            "Auto-Aware",
                            isOn: Binding(
                                get: { viewModel.autoAwareEnabled ?? false },
                                set: { viewModel.setAutoAwareEnabled($0) }
                            )
                        )
                    }

                    if viewModel.autoPlayPauseEnabled != nil {
                        Toggle(
                            "Auto-Play/Pause",
                            isOn: Binding(
                                get: { viewModel.autoPlayPauseEnabled ?? false },
                                set: { viewModel.setAutoPlayPauseEnabled($0) }
                            )
                        )
                    }

                    if viewModel.autoAnswerEnabled != nil {
                        Toggle(
                            "Auto-Answer",
                            isOn: Binding(
                                get: { viewModel.autoAnswerEnabled ?? false },
                                set: { viewModel.setAutoAnswerEnabled($0) }
                            )
                        )
                    }
                }
            }

            Divider()

            Button("Choose Device") {
                openWindow(id: "main")
                AppDelegate.openMainWindow()
                viewModel.returnToDeviceSelection()
            }

            Button("Reconnect") {
                viewModel.refresh()
            }
            .disabled(viewModel.isBusy)
        }
        .padding(.vertical, 4)
    }
}

struct BossSettingsView: View {
    @ObservedObject var launchAtLogin: LaunchAtLoginController

    var body: some View {
        Form {
            Toggle(
                "Start Boss at login",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )

            Text("When Boss launches at login, it stays in the menu bar and does not automatically open the main window.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if launchAtLogin.requiresApproval {
                Text("macOS requires approval for this login item in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = launchAtLogin.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}
