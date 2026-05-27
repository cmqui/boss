import BossAppleApp
import SwiftUI
import libbossApple

struct BossIOSRootView: View {
    @ObservedObject var viewModel: BossAppViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack(alignment: .top) {
            BossIOSPalette.background
                .ignoresSafeArea()

            currentScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            viewModel.refreshIfNeeded()
        }
        .sheet(isPresented: $viewModel.isPresentingSaveProfilePrompt) {
            BossIOSSaveProfileSheet(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch viewModel.appScreen {
        case .waitingForDevice:
            waitingForDevice
        case .workspace:
            workspace
        }
    }

    private var waitingForDevice: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                screenTitle("Boss")

                headerCard(
                    title: "Waiting For Bose Device",
                    subtitle: viewModel.waitingStatusMessage,
                    systemImage: "headphones.circle.fill"
                )

                if case .loading = viewModel.loadState, viewModel.availableDevices.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }

                if viewModel.shouldShowDevicePickerCard || !viewModel.availableDevices.isEmpty {
                    card(title: "Available Bose Devices", systemImage: "dot.radiowaves.left.and.right") {
                        if viewModel.availableDevices.isEmpty {
                            Text("No compatible Bose devices detected yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.availableDevices) { device in
                                Button {
                                    viewModel.connectToDiscoveredDevice(device)
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(device.name)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            if device.isCurrentlyConnected {
                                                Text("Already connected to this iPhone")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)

                                if device.id != viewModel.availableDevices.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button("Scan Again") {
                        viewModel.retryWaitingNow()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BossIOSPalette.accent)

                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var workspace: some View {
        Group {
            if horizontalSizeClass == .compact {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        screenTitle("Boss")
                        workspaceCompactContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                NavigationSplitView {
                    ScrollView {
                        workspaceSidebarContent
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .navigationTitle("Boss")
                } detail: {
                    NavigationStack {
                        ScrollView {
                            workspaceDetailContent
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .navigationTitle(viewModel.selectedModeName)
                    }
                }
            }
        }
    }

    private func screenTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.bottom, 8)
    }

    private var workspaceCompactContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            workspaceSidebarContent
            workspaceDetailContent
        }
    }

    private var workspaceSidebarContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerCard(
                title: viewModel.deviceName,
                subtitle: viewModel.firmwareVersion.map { "Firmware \($0)" } ?? "Connected",
                systemImage: "headphones"
            )

            if hasSupportedDeviceSettings {
                card(title: "Device Settings", systemImage: "switch.2") {
                    settingsToggle(
                        "Wear Detection",
                        isOn: viewModel.wearDetectionEnabled.map { currentValue in
                            Binding(
                                get: { currentValue },
                                set: { viewModel.setWearDetectionEnabled($0) }
                            )
                        }
                    )
                    settingsToggle(
                        "Auto-Aware",
                        isOn: viewModel.autoAwareEnabled.map { currentValue in
                            Binding(
                                get: { currentValue },
                                set: { viewModel.setAutoAwareEnabled($0) }
                            )
                        }
                    )
                    settingsToggle(
                        "Auto-Play/Pause",
                        isOn: viewModel.autoPlayPauseEnabled.map { currentValue in
                            Binding(
                                get: { currentValue },
                                set: { viewModel.setAutoPlayPauseEnabled($0) }
                            )
                        }
                    )
                    settingsToggle(
                        "Auto-Answer",
                        isOn: viewModel.autoAnswerEnabled.map { currentValue in
                            Binding(
                                get: { currentValue },
                                set: { viewModel.setAutoAnswerEnabled($0) }
                            )
                        }
                    )

                    if let volumeControlValue = viewModel.volumeControlValue {
                        Picker(
                            "Volume Control",
                            selection: Binding(
                                get: { volumeControlValue },
                                set: { viewModel.setVolumeControl($0) }
                            )
                        ) {
                            ForEach(BossAppleVolumeControlValue.allCases, id: \.rawValue) { value in
                                Text(value.displayName.capitalized).tag(value)
                            }
                        }
                        .disabled(viewModel.isBusy)
                    }
                }
            }

            card(title: "Connection", systemImage: "antenna.radiowaves.left.and.right") {
                VStack(spacing: 12) {
                    Button {
                        viewModel.returnToDeviceSelection()
                    } label: {
                        Label("Choose Device", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BossIOSPalette.accent)

                    Button {
                        viewModel.refresh()
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isBusy)
                }
            }
        }
    }

    private var workspaceDetailContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if horizontalSizeClass == .compact {
                Text(viewModel.selectedModeName)
                    .font(.title2.weight(.semibold))
            }

            modeToolbar
            modeSettingsCard
            if viewModel.equalizer != nil {
                equalizerCard
            }
        }
    }

    private var modeToolbar: some View {
        card(title: "Audio Mode", systemImage: "waveform") {
            Picker(
                "Audio Mode",
                selection: Binding(
                    get: { viewModel.resolvedSelectedAudioModeIndex ?? 0 },
                    set: { viewModel.selectAudioMode($0) }
                )
            ) {
                ForEach(viewModel.selectableAudioModes, id: \.modeIndex) { mode in
                    Text(viewModel.customProfileDisplayName(for: mode)).tag(mode.modeIndex)
                }
            }
            .pickerStyle(.menu)
            .disabled(viewModel.selectableAudioModes.isEmpty || viewModel.isBusy)

            if let selectedMode = selectedMode {
                modeBadges(for: selectedMode)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if let selectedMode = selectedMode {
                        Button {
                            viewModel.setFavorite(!selectedMode.favorite, for: selectedMode)
                        } label: {
                            Label(selectedMode.favorite ? "Favorited" : "Favorite", systemImage: selectedMode.favorite ? "star.fill" : "star")
                        }
                        .buttonStyle(.bordered)

                        if viewModel.canDelete(selectedMode) {
                            Button(role: .destructive) {
                                viewModel.deleteCustomProfile(selectedMode)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if viewModel.canSaveCustomProfile {
                        Button {
                            viewModel.beginSavingCustomProfile()
                        } label: {
                            Label("Save as Custom", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                    }

                    if viewModel.canApplyModeSettings {
                        Button {
                            viewModel.applyModeSettings()
                        } label: {
                            Label("Apply Changes", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BossIOSPalette.accent)
                    }
                }
            }

            Text(
                viewModel.hasDetachedSettingsDraft
                    ? "Editing unsaved custom changes"
                    : "Select a built-in or saved custom mode."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var modeSettingsCard: some View {
        card(title: "Mode Settings", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("CNC")
                            .font(.headline)
                        Spacer()
                        Text("\(viewModel.cncLevel)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.cncLevel) },
                            set: { viewModel.setCNCLevelDraft(Int($0.rounded())) }
                        ),
                        in: 0...10,
                        step: 1
                    )
                    .disabled(viewModel.isCNCForcedToDisplayMaximumByCurrentConstraint)

                    if viewModel.isCNCForcedToDisplayMaximumByCurrentConstraint {
                        Text("This device forces CNC to 10 while Wind Block is enabled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Spatial Audio")
                        .font(.headline)
                    Picker(
                        "Spatial Audio",
                        selection: Binding(
                            get: { viewModel.spatialAudioMode },
                            set: { viewModel.setSpatialAudioModeDraft($0) }
                        )
                    ) {
                        ForEach(BossAppleSpatialAudioMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Toggle(
                    "Wind Block",
                    isOn: Binding(
                        get: { viewModel.windBlockEnabled },
                        set: { viewModel.setWindBlockEnabledDraft($0) }
                    )
                )

                Toggle(
                    "ANC Toggle",
                    isOn: Binding(
                        get: { viewModel.ancToggleEnabled },
                        set: { viewModel.setANCEnabledDraft($0) }
                    )
                )

                if viewModel.settings == nil && viewModel.equalizer == nil {
                    ContentUnavailableView(
                        "No Mode Controls Loaded",
                        systemImage: "slider.horizontal.3",
                        description: Text(emptyModeControlsMessage)
                    )
                }
            }
            .disabled((viewModel.settings == nil && viewModel.equalizer == nil) || viewModel.isBusy)
        }
    }

    private var equalizerCard: some View {
        card(title: "Equalizer", systemImage: "slider.horizontal.below.rectangle") {
            ForEach(equalizerBands, id: \.title) { band in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(band.title)
                            .font(.headline)
                        Spacer()
                        Text("\(Int(band.value.wrappedValue))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: band.value,
                        in: Double(band.range.minLevel)...Double(band.range.maxLevel),
                        step: 1
                    )

                    HStack {
                        Text("\(band.range.minLevel)")
                        Spacer()
                        Text("\(band.range.maxLevel)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if band.title != equalizerBands.last?.title {
                    Divider()
                }
            }

            if viewModel.canApplyEqualizer {
                Button {
                    viewModel.applyEqualizerSettings()
                } label: {
                    Label("Apply EQ", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(BossIOSPalette.accent)
            }
        }
    }

    private func headerCard(title: String, subtitle: String, systemImage: String) -> some View {
        card {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 30))
                    .foregroundStyle(BossIOSPalette.accent)
                    .frame(width: 46, height: 46)
                    .background(BossIOSPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private func modeBadges(for mode: BossAppleAudioModeConfig) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                BossIOSBadge(
                    text: mode.userConfigurable ? "Custom" : "Built-In",
                    tint: BossIOSPalette.accent
                )
                if mode.favorite {
                    BossIOSBadge(text: "Favorite", tint: .yellow)
                }
                BossIOSBadge(text: "Prompt: \(mode.prompt.name)", tint: .secondary)
            }
        }
    }

    private func settingsToggle(_ title: String, isOn: Binding<Bool>?) -> some View {
        Group {
            if let isOn {
                Toggle(title, isOn: isOn)
                .disabled(viewModel.isBusy)
            }
        }
    }

    private func card<Content: View>(
        title: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title, let systemImage {
                Label(title, systemImage: systemImage)
                    .font(.headline)
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var selectedMode: BossAppleAudioModeConfig? {
        guard let selectedAudioModeIndex = viewModel.resolvedSelectedAudioModeIndex else {
            return nil
        }
        return viewModel.selectableAudioModes.first(where: { $0.modeIndex == selectedAudioModeIndex })
    }

    private var hasSupportedDeviceSettings: Bool {
        viewModel.wearDetectionEnabled != nil ||
            viewModel.autoAwareEnabled != nil ||
            viewModel.autoPlayPauseEnabled != nil ||
            viewModel.autoAnswerEnabled != nil ||
            viewModel.volumeControlValue != nil
    }

    private var equalizerBands: [(title: String, range: BossAppleEqualizerRangeLevel, value: Binding<Double>)] {
        var bands: [(title: String, range: BossAppleEqualizerRangeLevel, value: Binding<Double>)] = []

        if let range = viewModel.equalizer?.bass {
            bands.append((
                title: "Bass",
                range: range,
                value: Binding(
                    get: { Double(viewModel.bassLevel) },
                    set: { viewModel.setBassLevelDraft(Int($0.rounded())) }
                )
            ))
        }

        if let range = viewModel.equalizer?.mid {
            bands.append((
                title: "Mid",
                range: range,
                value: Binding(
                    get: { Double(viewModel.midLevel) },
                    set: { viewModel.setMidLevelDraft(Int($0.rounded())) }
                )
            ))
        }

        if let range = viewModel.equalizer?.treble {
            bands.append((
                title: "Treble",
                range: range,
                value: Binding(
                    get: { Double(viewModel.trebleLevel) },
                    set: { viewModel.setTrebleLevelDraft(Int($0.rounded())) }
                )
            ))
        }

        return bands
    }

    private var emptyModeControlsMessage: String {
        switch viewModel.loadState {
        case .loading:
            return "Loading the audio-mode and EQ controls for this device."
        default:
            return "Reconnect to load the audio-mode and EQ controls for this device."
        }
    }

    private var statusText: String {
        switch viewModel.loadState {
        case .idle:
            return "Ready to scan"
        case .loading(let label):
            return label
        case .failed(let message):
            return message
        case .ready:
            return "Connected"
        }
    }
}

private struct BossIOSSaveProfileSheet: View {
    @ObservedObject var viewModel: BossAppViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Name") {
                    TextField("Profile name", text: $viewModel.pendingProfileName)
                        .focused($isNameFieldFocused)
                        .textInputAutocapitalization(.words)
                }

                Section("Hardware Prompt") {
                    Picker("Prompt", selection: $viewModel.selectedSaveProfilePromptName) {
                        ForEach(viewModel.selectableSaveProfilePrompts, id: \.name) { prompt in
                            Text(prompt.name).tag(prompt.name)
                        }
                    }
                }
            }
            .navigationTitle("Save Custom Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelSavingCustomProfile()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.confirmSavingCustomProfile()
                        dismiss()
                    }
                    .disabled(viewModel.pendingProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                isNameFieldFocused = true
            }
        }
        .presentationDetents([.medium])
    }
}

private struct BossIOSBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

private enum BossIOSPalette {
    static let accent = Color(red: 0.69, green: 0.32, blue: 0.78)
    static let background = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.06, blue: 0.08),
            Color(red: 0.10, green: 0.10, blue: 0.12),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
