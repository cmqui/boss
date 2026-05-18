import AppKit
import libboss
import SwiftUI

private func deferMain(_ action: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        action()
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: BossMacOSViewModel

    var body: some View {
        let workspacePalette = DevicePalette(variantName: viewModel.deviceVariantName)
        let pickerPalette = DevicePalette.devicePicker

        Group {
            switch viewModel.appScreen {
            case .waitingForDevice:
                waitingForDevice(palette: pickerPalette)
            case .workspace:
                HStack(spacing: 0) {
                    sidebar(palette: workspacePalette)
                        .frame(width: 300)

                    Divider()

                    detail(palette: workspacePalette)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            viewModel.refreshIfNeeded()
        }
        .sheet(isPresented: $viewModel.isPresentingSaveProfilePrompt) {
            SaveCustomProfileSheet(viewModel: viewModel)
        }
    }

    private func waitingForDevice(palette: DevicePalette) -> some View {
        ZStack {
            LinearGradient(
                colors: [palette.sidebarBackground, Color(nsColor: .windowBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 22) {
                BossHeadphonesMark(size: 54)

                VStack(spacing: 8) {
                    Text("Waiting For Bose Device")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))

                    Text(viewModel.waitingStatusMessage)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                if viewModel.availableDevices.isEmpty, case .loading = viewModel.loadState {
                    ProgressView()
                        .controlSize(.large)
                        .padding(.top, 4)
                }

                if viewModel.shouldShowDevicePickerCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            Text("Available Bose Devices")
                                .font(.headline)

                            if case .loading = viewModel.loadState {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        if viewModel.availableDevices.isEmpty {
                            Text("No compatible Bose devices detected yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(viewModel.availableDevices) { device in
                                    Button {
                                        viewModel.connectToDiscoveredDevice(device)
                                    } label: {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(device.name)
                                                    .fontWeight(.medium)
                                                if device.isCurrentlyConnected {
                                                    Text("Already connected to this Mac")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(Color.white.opacity(0.35))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.45))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(palette.cardStroke, lineWidth: 1)
                    )
                }
            }
            .padding(32)
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
                                        set: { newValue in
                                            deferMain {
                                                viewModel.setWearDetectionEnabled(newValue)
                                            }
                                        }
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
                                        set: { newValue in
                                            deferMain {
                                                viewModel.setAutoAwareEnabled(newValue)
                                            }
                                        }
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
                                        set: { newValue in
                                            deferMain {
                                                viewModel.setAutoPlayPauseEnabled(newValue)
                                            }
                                        }
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
                                        set: { newValue in
                                            deferMain {
                                                viewModel.setAutoAnswerEnabled(newValue)
                                            }
                                        }
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
                                            set: { newValue in
                                                deferMain {
                                                    viewModel.setVolumeControl(newValue)
                                                }
                                            }
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
                        Button {
                            viewModel.returnToDeviceSelection()
                        } label: {
                            Label("Choose Device", systemImage: "dot.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                        .disabled(viewModel.isBusy)

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
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
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
            HStack(alignment: .center, spacing: 16) {
                Picker("Audio Mode", selection: selectedModeBinding) {
                    ForEach(viewModel.selectableAudioModes, id: \.modeIndex) { mode in
                        Text(viewModel.customProfileDisplayName(for: mode)).tag(mode.modeIndex)
                    }
                }
                .labelsHidden()
                .frame(width: 300, alignment: .leading)
                .controlSize(.large)
                .font(.title3.weight(.semibold))
                .disabled(viewModel.selectableAudioModes.isEmpty || viewModel.isBusy)

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                        if let selectedMode {
                            Button {
                                viewModel.setFavorite(!selectedMode.favorite, for: selectedMode)
                            } label: {
                                AdaptiveToolbarLabel(
                                title: selectedMode.favorite ? "Favorited" : "Favorite",
                                systemImage: selectedMode.favorite ? "star.fill" : "star",
                                iconColor: selectedMode.favorite ? .yellow : nil
                            )
                        }
                        .disabled(viewModel.isBusy)

                            if viewModel.canDelete(selectedMode) {
                                Button(role: .destructive) {
                                    viewModel.deleteCustomProfile(selectedMode)
                                } label: {
                                    AdaptiveToolbarLabel(title: "Delete", systemImage: "trash")
                                }
                                .disabled(viewModel.isBusy)
                            }
                        }

                        if viewModel.canSaveCustomProfile {
                            Button {
                                viewModel.beginSavingCustomProfile()
                            } label: {
                                AdaptiveToolbarLabel(title: "Save as Custom", systemImage: "square.and.arrow.down")
                            }
                        }

                    if viewModel.canApplyModeSettings {
                        Button {
                            viewModel.applyModeSettings()
                        } label: {
                            AdaptiveToolbarLabel(title: "Apply", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(viewModel.hasDetachedSettingsDraft ? "Editing unsaved custom changes" : "Select a built-in or saved custom mode.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
                    Picker("", selection: spatialAudioBinding) {
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
            .disabled((viewModel.settings == nil && viewModel.equalizer == nil) || viewModel.isBusy)

            if viewModel.equalizer != nil {
                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Text("Equalizer")
                            .font(.headline)

                        Spacer()

                        Button {
                            viewModel.applyEqualizerSettings()
                        } label: {
                            AdaptiveToolbarLabel(title: "Apply", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                        .disabled(!viewModel.canApplyEqualizer)
                        .opacity(viewModel.canApplyEqualizer ? 1 : 0)
                    }

                    EqualizerControlGroup(viewModel: viewModel)
                }
            }

            if viewModel.settings == nil && viewModel.equalizer == nil {
                ContentUnavailableView(
                    "No Mode Controls Loaded",
                    systemImage: "slider.horizontal.3",
                    description: Text(emptyModeControlsMessage)
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            }

        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var selectedModeBinding: Binding<Int> {
        Binding(
            get: {
                viewModel.selectedAudioModeIndex ?? viewModel.selectableAudioModes.first?.modeIndex ?? 0
            },
            set: { newValue in
                deferMain {
                    viewModel.selectAudioMode(newValue)
                }
            }
        )
    }

    private var cncBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.cncLevel) },
            set: { newValue in
                deferMain {
                    viewModel.setCNCLevelDraft(Int(newValue.rounded()))
                }
            }
        )
    }

    private var spatialAudioBinding: Binding<BossSpatialAudioMode> {
        Binding(
            get: { viewModel.spatialAudioMode },
            set: { newValue in
                deferMain {
                    viewModel.setSpatialAudioModeDraft(newValue)
                }
            }
        )
    }

    private var windBlockBinding: Binding<Bool> {
        Binding(
            get: { viewModel.windBlockEnabled },
            set: { newValue in
                deferMain {
                    viewModel.setWindBlockEnabledDraft(newValue)
                }
            }
        )
    }

    private var ancBinding: Binding<Bool> {
        Binding(
            get: { viewModel.ancToggleEnabled },
            set: { newValue in
                deferMain {
                    viewModel.setANCEnabledDraft(newValue)
                }
            }
        )
    }

    private var emptyModeControlsMessage: String {
        switch viewModel.loadState {
        case .loading:
            return "Loading the audio-mode and EQ controls for this device."
        default:
            return "Reconnect to load the audio-mode and EQ controls for this device."
        }
    }
}

private struct EqualizerControlGroup: View {
    @ObservedObject var viewModel: BossMacOSViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let range = viewModel.equalizer?.bass {
                EqualizerBandSliderRow(
                    title: "Bass",
                    range: range,
                    value: Binding(
                        get: { Double(viewModel.bassLevel) },
                        set: { viewModel.setBassLevelDraft(Int($0.rounded())) }
                    )
                )
            }

            if let range = viewModel.equalizer?.mid {
                EqualizerBandSliderRow(
                    title: "Mid",
                    range: range,
                    value: Binding(
                        get: { Double(viewModel.midLevel) },
                        set: { viewModel.setMidLevelDraft(Int($0.rounded())) }
                    )
                )
            }

            if let range = viewModel.equalizer?.treble {
                EqualizerBandSliderRow(
                    title: "Treble",
                    range: range,
                    value: Binding(
                        get: { Double(viewModel.trebleLevel) },
                        set: { viewModel.setTrebleLevelDraft(Int($0.rounded())) }
                    )
                )
            }
        }
    }
}

private struct EqualizerBandSliderRow: View {
    let title: String
    let range: BossEqualizerRangeLevel
    let value: Binding<Double>

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 52, alignment: .leading)

            Text("\(range.minLevel)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            Slider(
                value: value,
                in: Double(range.minLevel)...Double(range.maxLevel),
                step: 1
            )

            Text("\(range.maxLevel)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            Text("\(Int(value.wrappedValue))")
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
        }
    }
}

private struct SidebarDeviceHeader: View {
    @ObservedObject var viewModel: BossMacOSViewModel
    let palette: DevicePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                BossHeadphonesMark(size: 26)

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

private struct BossHeadphonesMark: View {
    let size: CGFloat

    var body: some View {
        if let image = BossImageResource.headphonesMark.nsImage() {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
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

private struct AdaptiveToolbarLabel: View {
    let title: String
    let systemImage: String
    let iconColor: Color?

    init(title: String, systemImage: String, iconColor: Color? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.iconColor = iconColor
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                toolbarIcon
                Text(title)
            }

            toolbarIcon
        }
    }

    @ViewBuilder
    private var toolbarIcon: some View {
        if let iconColor {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
        } else {
            Image(systemName: systemImage)
        }
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

    static let devicePicker = DevicePalette(
        accent: Color(red: 0.56, green: 0.46, blue: 0.71),
        background: Color(red: 0.22, green: 0.18, blue: 0.23),
        sidebarBackground: Color(red: 0.2, green: 0.16, blue: 0.21),
        cardBackground: Color.white.opacity(0.2),
        cardStroke: Color.white.opacity(0.12),
        primaryText: .white,
        secondaryText: Color.white.opacity(0.7)
    )

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

    private init(
        accent: Color,
        background: Color,
        sidebarBackground: Color,
        cardBackground: Color,
        cardStroke: Color,
        primaryText: Color,
        secondaryText: Color
    ) {
        self.accent = accent
        self.background = background
        self.sidebarBackground = sidebarBackground
        self.cardBackground = cardBackground
        self.cardStroke = cardStroke
        self.primaryText = primaryText
        self.secondaryText = secondaryText
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
