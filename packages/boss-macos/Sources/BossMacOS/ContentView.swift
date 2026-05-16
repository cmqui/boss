import AppKit
import libboss
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: BossMacOSViewModel

    var body: some View {
        let palette = DevicePalette(variantName: viewModel.deviceVariantName)

        HStack(spacing: 0) {
            sidebar(palette: palette)
                .frame(width: 300)

            Divider()

            detail(palette: palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            viewModel.refreshIfNeeded()
        }
        .sheet(isPresented: $viewModel.isPresentingSaveProfilePrompt) {
            SaveCustomProfileSheet(viewModel: viewModel)
        }
    }

    private func sidebar(palette: DevicePalette) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SidebarDeviceHeader(viewModel: viewModel, palette: palette)

                if hasSupportedDeviceSettings {
                    SidebarCard(title: "Device Settings", systemImage: "switch.2", palette: palette) {
                        VStack(alignment: .leading, spacing: 14) {
                            if viewModel.wearDetectionEnabled != nil {
                                SettingsToggleRow(
                                    title: "Wear Detection",
                                    isOn: Binding(
                                        get: { viewModel.wearDetectionEnabled ?? false },
                                        set: { viewModel.setWearDetectionEnabled($0) }
                                    ),
                                    isEnabled: !viewModel.isBusy,
                                    palette: palette
                                )
                            }

                            if viewModel.autoAwareEnabled != nil {
                                SettingsToggleRow(
                                    title: "Auto-Aware",
                                    isOn: Binding(
                                        get: { viewModel.autoAwareEnabled ?? false },
                                        set: { viewModel.setAutoAwareEnabled($0) }
                                    ),
                                    isEnabled: !viewModel.isBusy,
                                    palette: palette
                                )
                            }

                            if viewModel.autoPlayPauseEnabled != nil {
                                SettingsToggleRow(
                                    title: "Auto-Play/Pause",
                                    isOn: Binding(
                                        get: { viewModel.autoPlayPauseEnabled ?? false },
                                        set: { viewModel.setAutoPlayPauseEnabled($0) }
                                    ),
                                    isEnabled: !viewModel.isBusy,
                                    palette: palette
                                )
                            }

                            if viewModel.autoAnswerEnabled != nil {
                                SettingsToggleRow(
                                    title: "Auto-Answer",
                                    isOn: Binding(
                                        get: { viewModel.autoAnswerEnabled ?? false },
                                        set: { viewModel.setAutoAnswerEnabled($0) }
                                    ),
                                    isEnabled: !viewModel.isBusy,
                                    palette: palette
                                )
                            }

                            if viewModel.volumeControlValue != nil {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Volume Control")
                                        .fontWeight(.medium)

                                    Picker(
                                        "Volume Control",
                                        selection: Binding(
                                            get: { viewModel.volumeControlValue ?? .capTouch },
                                            set: { viewModel.setVolumeControl($0) }
                                        )
                                    ) {
                                        ForEach(BossVolumeControlValue.allCases, id: \.rawValue) { value in
                                            Text(value.displayName).tag(value)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .disabled(viewModel.isBusy)
                                }
                                .foregroundStyle(palette.primaryText)
                            }
                        }
                    }
                }

                SidebarCard(title: "Connection", systemImage: "dot.radiowaves.left.and.right", palette: palette) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Name contains", text: $viewModel.nameFilter)
                            .textFieldStyle(.roundedBorder)

                        Stepper(value: $viewModel.scanTimeoutSeconds, in: 5...60, step: 5) {
                            Text("Scan timeout: \(viewModel.scanTimeoutSeconds)s")
                        }

                        Button {
                            viewModel.refresh()
                        } label: {
                            Label("Reconnect", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isBusy)
                    }
                }
            }
            .padding(20)
        }
        .background(palette.sidebarBackground)
    }

    private func detail(palette: DevicePalette) -> some View {
        return ScrollView {
            ModeSettingsPanel(viewModel: viewModel, palette: palette)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.loadState {
        case .idle:
            Label("Waiting to scan", systemImage: "dot.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
        case .loading(let label):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(label)
            }
            .foregroundStyle(.secondary)
        case .failed:
            Label("Operation failed. Check console output.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case .ready:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private var hasSupportedDeviceSettings: Bool {
        viewModel.wearDetectionEnabled != nil ||
            viewModel.autoAwareEnabled != nil ||
            viewModel.autoPlayPauseEnabled != nil ||
            viewModel.autoAnswerEnabled != nil ||
            viewModel.volumeControlValue != nil
    }
}

private struct ModeSettingsPanel: View {
    @ObservedObject var viewModel: BossMacOSViewModel
    let palette: DevicePalette

    private var selectedMode: BossAudioModeConfig? {
        guard let selectedAudioModeIndex = viewModel.selectedAudioModeIndex else {
            return nil
        }
        return viewModel.selectableAudioModes.first(where: { $0.modeIndex == selectedAudioModeIndex })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mode Workspace")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(viewModel.hasDetachedSettingsDraft ? "Editing unsaved custom changes" : "Select a built-in or saved custom mode.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 12) {
                    Picker("Audio Mode", selection: selectedModeBinding) {
                        ForEach(viewModel.selectableAudioModes, id: \.modeIndex) { mode in
                            Text(viewModel.customProfileDisplayName(for: mode)).tag(mode.modeIndex)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                    .disabled(viewModel.selectableAudioModes.isEmpty || viewModel.isBusy)

                    HStack(spacing: 10) {
                        if let selectedMode {
                            Button {
                                viewModel.setFavorite(!selectedMode.favorite, for: selectedMode)
                            } label: {
                                Label(
                                    selectedMode.favorite ? "Favorited" : "Favorite",
                                    systemImage: selectedMode.favorite ? "star.fill" : "star"
                                )
                            }
                            .disabled(viewModel.isBusy)

                            if viewModel.canDelete(selectedMode) {
                                Button(role: .destructive) {
                                    viewModel.deleteCustomProfile(selectedMode)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .disabled(viewModel.isBusy)
                            }
                        }

                        if viewModel.canSaveCustomProfile {
                            Button {
                                viewModel.beginSavingCustomProfile()
                            } label: {
                                Label("Save as Custom", systemImage: "square.and.arrow.down")
                            }
                        }

                        Button {
                            viewModel.applySettings()
                        } label: {
                            Label("Apply", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                        .disabled(!viewModel.canApplySettings)
                    }
                }
            }

            if let selectedMode {
                HStack(spacing: 10) {
                    Badge(text: selectedMode.userConfigurable ? "Custom" : "Built-In", tint: palette.accent)
                    if selectedMode.favorite {
                        Badge(text: "Favorite", tint: .yellow)
                    }
                    Badge(text: "Prompt: \(selectedMode.prompt.name)", tint: .secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 18) {
                GridRow {
                    Text("CNC")
                        .foregroundStyle(.secondary)
                    HStack {
                        Slider(value: cncBinding, in: 0...10, step: 1)
                        Text("\(viewModel.cncLevel)")
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                }

                GridRow {
                    Text("Spatial Audio")
                        .foregroundStyle(.secondary)
                    Picker("Spatial Audio", selection: spatialAudioBinding) {
                        ForEach(BossSpatialAudioMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                GridRow {
                    Text("Wind Block")
                        .foregroundStyle(.secondary)
                    Toggle("Enabled", isOn: windBlockBinding)
                }

                GridRow {
                    Text("ANC Toggle")
                        .foregroundStyle(.secondary)
                    Toggle("Enabled", isOn: ancBinding)
                }
            }
            .disabled(viewModel.settings == nil || viewModel.isBusy)

            if viewModel.settings == nil {
                ContentUnavailableView(
                    "No Mode Settings Loaded",
                    systemImage: "slider.horizontal.3",
                    description: Text("Reconnect to load the audio-mode controls for this device.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 700, alignment: .topLeading)
    }

    private var selectedModeBinding: Binding<Int> {
        Binding(
            get: {
                viewModel.selectedAudioModeIndex ?? viewModel.selectableAudioModes.first?.modeIndex ?? 0
            },
            set: { viewModel.selectAudioMode($0) }
        )
    }

    private var cncBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.cncLevel) },
            set: { viewModel.setCNCLevelDraft(Int($0.rounded())) }
        )
    }

    private var spatialAudioBinding: Binding<BossSpatialAudioMode> {
        Binding(
            get: { viewModel.spatialAudioMode },
            set: { viewModel.setSpatialAudioModeDraft($0) }
        )
    }

    private var windBlockBinding: Binding<Bool> {
        Binding(
            get: { viewModel.windBlockEnabled },
            set: { viewModel.setWindBlockEnabledDraft($0) }
        )
    }

    private var ancBinding: Binding<Bool> {
        Binding(
            get: { viewModel.ancToggleEnabled },
            set: { viewModel.setANCEnabledDraft($0) }
        )
    }
}

private struct SidebarDeviceHeader: View {
    @ObservedObject var viewModel: BossMacOSViewModel
    let palette: DevicePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "headphones")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(palette.accent)

                Text(viewModel.deviceName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.primaryText)
            }

            statusView
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.loadState {
        case .idle:
            Label("Waiting to scan", systemImage: "dot.radiowaves.left.and.right")
                .foregroundStyle(palette.secondaryText)
        case .loading(let label):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(label)
            }
            .foregroundStyle(palette.secondaryText)
        case .failed:
            Label("Operation failed. Check console output.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case .ready:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

private struct SidebarCard<Content: View>: View {
    let title: String
    let systemImage: String
    let palette: DevicePalette
    let content: Content

    init(
        title: String,
        systemImage: String,
        palette: DevicePalette,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.palette = palette
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(palette.primaryText)

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(palette.cardStroke, lineWidth: 1)
        )
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let isOn: Binding<Bool>
    let isEnabled: Bool
    let palette: DevicePalette

    var body: some View {
        Toggle(isOn: isOn) {
            Text(title)
                .fontWeight(.medium)
                .foregroundStyle(palette.primaryText)
        }
        .toggleStyle(.switch)
        .disabled(!isEnabled)
    }
}

private struct Badge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
}

private struct DevicePalette {
    let accent: Color
    let background: Color
    let sidebarBackground: Color
    let cardBackground: Color
    let cardStroke: Color
    let primaryText: Color
    let secondaryText: Color

    init(variantName: String?) {
        let key = variantName?.lowercased() ?? ""
        switch key {
        case let value where value.contains("black"):
            accent = Color(red: 0.18, green: 0.18, blue: 0.2)
            background = Color(red: 0.92, green: 0.92, blue: 0.94)
            sidebarBackground = Color(red: 0.89, green: 0.89, blue: 0.91)
        case let value where value.contains("white"):
            accent = Color(red: 0.72, green: 0.72, blue: 0.76)
            background = Color(red: 0.97, green: 0.97, blue: 0.98)
            sidebarBackground = Color(red: 0.95, green: 0.95, blue: 0.97)
        case let value where value.contains("driftwood") || value.contains("sand"):
            accent = Color(red: 0.71, green: 0.58, blue: 0.43)
            background = Color(red: 0.96, green: 0.93, blue: 0.88)
            sidebarBackground = Color(red: 0.94, green: 0.9, blue: 0.84)
        case let value where value.contains("gold"):
            accent = Color(red: 0.77, green: 0.63, blue: 0.26)
            background = Color(red: 0.98, green: 0.95, blue: 0.85)
            sidebarBackground = Color(red: 0.95, green: 0.91, blue: 0.78)
        case let value where value.contains("violet"):
            accent = Color(red: 0.4, green: 0.3, blue: 0.55)
            background = Color(red: 0.94, green: 0.92, blue: 0.98)
            sidebarBackground = Color(red: 0.9, green: 0.87, blue: 0.96)
        default:
            accent = Color.accentColor
            background = Color.accentColor.opacity(0.12)
            sidebarBackground = Color.accentColor.opacity(0.18)
        }

        cardBackground = Color.white.opacity(0.4)
        cardStroke = accent.opacity(0.18)
        primaryText = Color(red: 0.12, green: 0.11, blue: 0.1)
        secondaryText = Color(red: 0.28, green: 0.25, blue: 0.22)
    }
}

private struct SaveCustomProfileSheet: View {
    @ObservedObject var viewModel: BossMacOSViewModel
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Save Custom Profile")
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Profile name", text: $viewModel.pendingProfileName)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFieldFocused)
                .onSubmit {
                    viewModel.confirmSavingCustomProfile()
                }

            Picker("Hardware Prompt", selection: $viewModel.selectedSaveProfilePromptName) {
                ForEach(viewModel.selectableSaveProfilePrompts, id: \.name) { prompt in
                    Text(prompt.name).tag(prompt.name)
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    viewModel.cancelSavingCustomProfile()
                }

                Button("Save") {
                    viewModel.confirmSavingCustomProfile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.pendingProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .task {
            AppDelegate.activateApp()
            isNameFieldFocused = true
        }
    }
}
