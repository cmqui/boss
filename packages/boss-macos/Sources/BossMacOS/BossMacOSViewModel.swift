import Foundation
import libboss
import libbossApple

@MainActor
final class BossMacOSViewModel: ObservableObject {
    enum AppScreen: Equatable {
        case waitingForDevice
        case workspace
    }

    enum LoadState: Equatable {
        case idle
        case loading(String)
        case failed(String)
        case ready
    }

    @Published var nameFilter = "Bose"
    @Published var scanTimeoutSeconds = 20
    @Published private(set) var appScreen: AppScreen = .waitingForDevice
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var availableDevices: [BossAppleDiscoveredDevice] = []
    @Published var selectedDiscoveredDeviceID: UUID?
    @Published private(set) var audioModes: [BossAudioModeConfig] = []
    @Published private(set) var customProfileModes: [BossAudioModeConfig] = []
    @Published private(set) var currentAudioModeIndex: Int?
    @Published private(set) var settings: BossAudioModeSettingsConfig?
    @Published private(set) var equalizer: BossEqualizerSettings?
    @Published private(set) var deviceName = "Bose Device"
    @Published private(set) var deviceVariantName: String?
    @Published private(set) var firmwareVersion: String?
    @Published private(set) var wearDetectionEnabled: Bool?
    @Published private(set) var autoAwareEnabled: Bool?
    @Published private(set) var autoPlayPauseEnabled: Bool?
    @Published private(set) var autoAnswerEnabled: Bool?
    @Published private(set) var volumeControlValue: BossVolumeControlValue?
    @Published private(set) var lastResultMessage: String?
    @Published private(set) var waitingStatusMessage = "Looking for a Bose device nearby."
    @Published private(set) var hasDetachedSettingsDraft = false
    @Published private(set) var hasDetachedEqualizerDraft = false
    @Published var isPresentingSaveProfilePrompt = false
    @Published var pendingProfileName = ""
    @Published private(set) var supportedPrompts: [BossAudioModePrompt] = []
    @Published var selectedSaveProfilePromptName = "None"

    @Published var selectedAudioModeIndex: Int?
    @Published var cncLevel = 0
    @Published var spatialAudioMode: BossSpatialAudioMode = .off
    @Published var windBlockEnabled = false
    @Published var ancToggleEnabled = false
    @Published var bassLevel = 0
    @Published var midLevel = 0
    @Published var trebleLevel = 0

    private var hasStartedInitialRefresh = false
    private var discoveryTask: Task<Void, Never>?
    private var currentModeUpdateTask: Task<Void, Never>?
    private var settingsUpdateTask: Task<Void, Never>?
    private var equalizerUpdateTask: Task<Void, Never>?
    private var deviceSettingsUpdateTask: Task<Void, Never>?
    private var audioModeCatalogUpdateTask: Task<Void, Never>?
    private var session: BossAppleSession?
    private var selectedDeviceIdentifier: UUID?
    private var isManualDeviceSelection = false
    private var isConnectingSelectedDevice = false

    var isBusy: Bool {
        if case .loading = loadState {
            return true
        }
        return false
    }

    var selectedModeName: String {
        if hasDetachedSettingsDraft {
            return "Custom changes"
        }
        guard let currentAudioModeIndex,
              let mode = audioModes.first(where: { $0.modeIndex == currentAudioModeIndex }) else {
            return "Unknown"
        }
        return customProfileDisplayName(for: mode)
    }

    var displayedCurrentAudioModeIndex: Int? {
        hasDetachedSettingsDraft ? nil : currentAudioModeIndex
    }

    var canApplyModeSettings: Bool {
        settings != nil && hasDetachedSettingsDraft && !isBusy
    }

    var canApplyEqualizer: Bool {
        equalizer != nil && hasDetachedEqualizerDraft && !isBusy
    }

    var canSaveCustomProfile: Bool {
        settings != nil && hasDetachedSettingsDraft && hasAvailableCustomProfileSlot && !isBusy
    }

    var selectableAudioModes: [BossAudioModeConfig] {
        audioModes.filter { mode in
            if mode.userConfigurable {
                return mode.userConfigured && hasCustomProfileName(mode)
            }
            return true
        }
    }

    var selectableSaveProfilePrompts: [BossAudioModePrompt] {
        let nonNone = supportedPrompts.filter { $0 != .none }
        return nonNone.isEmpty ? supportedPrompts : nonNone
    }

    func refresh() {
        cancelDiscoveryLoop()
        cancelBackgroundLoad()
        run("Connecting") {
            let session = self.makeSession()
            do {
                try await self.reloadAllState(using: session)
                self.appScreen = .workspace
                self.waitingStatusMessage = "Connected."
                self.startBackgroundLoad(using: session)
            } catch {
                await self.clearSession()
                self.enterWaitingMode(message: Self.describe(error))
                self.startDiscoveryLoopIfNeeded()
                throw error
            }
        }
    }

    func refreshIfNeeded() {
        guard !hasStartedInitialRefresh else {
            return
        }
        hasStartedInitialRefresh = true
        isManualDeviceSelection = false
        startDiscoveryLoopIfNeeded()
    }

    func retryWaitingNow() {
        cancelDiscoveryLoop()
        startDiscoveryLoopIfNeeded(forceImmediateRefresh: true)
    }

    func connectToSelectedDiscoveredDevice() {
        guard let selectedDiscoveredDeviceID,
              let device = availableDevices.first(where: { $0.id == selectedDiscoveredDeviceID }) else {
            return
        }
        connect(to: device)
    }

    func connectToDiscoveredDevice(_ device: BossAppleDiscoveredDevice) {
        connect(to: device)
    }

    func returnToDeviceSelection() {
        cancelDiscoveryLoop()
        cancelBackgroundLoad()
        isManualDeviceSelection = true
        selectedDeviceIdentifier = nil
        selectedDiscoveredDeviceID = nil
        Task {
            await self.clearSession()
        }
        resetWorkspaceState()
        enterWaitingMode(message: "Looking for a Bose device nearby.")
        startDiscoveryLoopIfNeeded(forceImmediateRefresh: true)
    }

    func selectAudioMode(_ index: Int) {
        selectedAudioModeIndex = index
        run("Switching mode") {
            let session = self.makeSession()
            let result = try await session.setCurrentAudioMode(index: index)
            let resultMessage: String

            switch result {
            case .unchanged(let currentIndex):
                self.currentAudioModeIndex = currentIndex
                resultMessage = "Mode unchanged"
            case .updated(let updatedIndex):
                self.currentAudioModeIndex = updatedIndex
                resultMessage = "Mode updated"
            case .verificationInconclusive(let targetIndex):
                self.currentAudioModeIndex = targetIndex
                resultMessage = "Mode command sent; verification was inconclusive"
            }

            try await self.reloadModeWorkspace(using: session)
            self.lastResultMessage = "\(resultMessage); settings refreshed"
        }
    }

    func setFavorite(_ isFavorite: Bool, for mode: BossAudioModeConfig) {
        run(isFavorite ? "Adding favorite" : "Removing favorite") {
            let session = self.makeSession()
            if isFavorite {
                _ = try await session.favoriteAudioMode(index: mode.modeIndex)
            } else {
                _ = try await session.unfavoriteAudioMode(index: mode.modeIndex)
            }
            self.lastResultMessage = isFavorite
                ? "Added \"\(self.customProfileDisplayName(for: mode))\" to favorites"
                : "Removed \"\(self.customProfileDisplayName(for: mode))\" from favorites"
        }
    }

    func deleteCustomProfile(_ mode: BossAudioModeConfig) {
        run("Deleting custom profile") {
            let session = self.makeSession()
            let displayName = self.customProfileDisplayName(for: mode)
            _ = try await session.deleteCustomAudioMode(slot: mode.modeIndex)
            self.lastResultMessage = "Deleted \"\(displayName)\""
        }
    }

    func applyModeSettings() {
        guard canApplyModeSettings else {
            return
        }
        run("Applying mode settings") {
            let session = self.makeSession()
            let patch = BossAudioModeSettingsConfigPatch(
                cncLevel: self.cncLevel,
                spatialAudioMode: self.spatialAudioMode,
                windBlockEnabled: self.windBlockEnabled,
                ancToggleEnabled: self.ancToggleEnabled
            )
            let result = try await session.setAudioModeSettings(patch)
            switch result {
            case .unchanged(let config):
                self.applySettingsSnapshot(config)
                self.lastResultMessage = "Mode settings unchanged"
            case .updated(let config):
                self.applySettingsSnapshot(config)
                self.lastResultMessage = "Mode settings updated"
            case .verificationInconclusive(let config):
                self.applySettingsSnapshot(config)
                self.lastResultMessage = "Mode settings verification was inconclusive"
            }
        }
    }

    func applyEqualizerSettings() {
        guard canApplyEqualizer else {
            return
        }
        run("Applying EQ settings") {
            let session = self.makeSession()
            let result = try await session.setEqualizer(self.currentEqualizerPatch())
            switch result {
            case .unchanged(let settings):
                self.applyEqualizerSnapshot(settings)
                self.lastResultMessage = "EQ unchanged"
            case .updated(let settings):
                self.applyEqualizerSnapshot(settings)
                self.lastResultMessage = "EQ updated"
            case .verificationInconclusive(let settings):
                self.applyEqualizerSnapshot(settings)
                self.lastResultMessage = "EQ verification was inconclusive"
            }
        }
    }

    func beginSavingCustomProfile() {
        guard canSaveCustomProfile else {
            return
        }
        pendingProfileName = ""
        selectedSaveProfilePromptName = defaultPromptForNewCustomProfile().name
        isPresentingSaveProfilePrompt = true
    }

    func cancelSavingCustomProfile() {
        isPresentingSaveProfilePrompt = false
        pendingProfileName = ""
    }

    func confirmSavingCustomProfile() {
        let trimmedName = normalizedCustomProfileName(pendingProfileName)
        guard !trimmedName.isEmpty else {
            return
        }

        isPresentingSaveProfilePrompt = false
        pendingProfileName = ""
        saveCustomProfile(profileName: trimmedName, prompt: resolvedSavePrompt(for: trimmedName))
    }

    func setCNCLevelDraft(_ level: Int) {
        cncLevel = level
        noteManualSettingsEdit()
    }

    func setSpatialAudioModeDraft(_ mode: BossSpatialAudioMode) {
        spatialAudioMode = mode
        noteManualSettingsEdit()
    }

    func setWindBlockEnabledDraft(_ enabled: Bool) {
        windBlockEnabled = enabled
        noteManualSettingsEdit()
    }

    func setANCEnabledDraft(_ enabled: Bool) {
        ancToggleEnabled = enabled
        noteManualSettingsEdit()
    }

    func setBassLevelDraft(_ level: Int) {
        bassLevel = level
        noteManualEqualizerEdit()
    }

    func setMidLevelDraft(_ level: Int) {
        midLevel = level
        noteManualEqualizerEdit()
    }

    func setTrebleLevelDraft(_ level: Int) {
        trebleLevel = level
        noteManualEqualizerEdit()
    }

    func setWearDetectionEnabled(_ enabled: Bool) {
        guard let previousValue = wearDetectionEnabled else {
            return
        }
        wearDetectionEnabled = enabled
        run("Updating Wear Detection") {
            let session = self.makeSession()
            do {
                let updated = try await session.setWearDetectionEnabled(enabled)
                self.wearDetectionEnabled = updated.isEnabled
                self.lastResultMessage = "Wear detection updated"
            } catch {
                self.wearDetectionEnabled = previousValue
                throw error
            }
        }
    }

    func setAutoAwareEnabled(_ enabled: Bool) {
        guard let previousValue = autoAwareEnabled else {
            return
        }
        autoAwareEnabled = enabled
        run("Updating Auto-Aware") {
            let session = self.makeSession()
            do {
                _ = try await session.setAutoAware(enabled)
                self.lastResultMessage = "Auto-Aware updated"
            } catch {
                self.autoAwareEnabled = previousValue
                throw error
            }
        }
    }

    func setAutoPlayPauseEnabled(_ enabled: Bool) {
        guard let previousValue = autoPlayPauseEnabled else {
            return
        }
        autoPlayPauseEnabled = enabled
        run("Updating Auto-Play/Pause") {
            let session = self.makeSession()
            do {
                _ = try await session.setAutoPlayPause(enabled)
                self.lastResultMessage = "Auto-Play/Pause updated"
            } catch {
                self.autoPlayPauseEnabled = previousValue
                throw error
            }
        }
    }

    func setAutoAnswerEnabled(_ enabled: Bool) {
        guard let previousValue = autoAnswerEnabled else {
            return
        }
        autoAnswerEnabled = enabled
        run("Updating Auto-Answer") {
            let session = self.makeSession()
            do {
                _ = try await session.setAutoAnswer(enabled)
                self.lastResultMessage = "Auto-Answer updated"
            } catch {
                self.autoAnswerEnabled = previousValue
                throw error
            }
        }
    }

    func setVolumeControl(_ value: BossVolumeControlValue) {
        guard let previousValue = volumeControlValue else {
            return
        }
        volumeControlValue = value
        run("Updating Volume Control") {
            let session = self.makeSession()
            do {
                let updated = try await session.setVolumeControl(value)
                self.volumeControlValue = updated.value
                self.lastResultMessage = "Volume control updated"
            } catch {
                self.volumeControlValue = previousValue
                throw error
            }
        }
    }

    private func makeConnectionOptions() -> BossAppleConnectionOptions {
        let connectionScanTimeout = selectedDeviceIdentifier == nil
            ? scanTimeoutSeconds
            : min(scanTimeoutSeconds, 6)
        return BossAppleConnectionOptions(
            nameContains: selectedDeviceIdentifier == nil ? "Bose" : nil,
            identifier: selectedDeviceIdentifier,
            scanTimeout: .seconds(connectionScanTimeout)
        )
    }

    private func makeSession() -> BossAppleSession {
        let currentOptions = makeConnectionOptions()
        if let session {
            return session
        }
        let newSession = BossAppleSession(connection: currentOptions)
        session = newSession
        return newSession
    }

    private func clearSession() async {
        let existing = session
        session = nil
        if let existing {
            await existing.close()
        }
    }

    private func reloadAllState(using session: BossAppleSession) async throws {
        async let workspaceSnapshot = session.loadWorkspaceSnapshot()
        async let promptsTask = loadSupportedPrompts(using: session)
        async let firmwareVersionTask = loadFirmwareVersion(using: session)

        let workspace = try await workspaceSnapshot
        let prompts = await promptsTask
        let firmwareVersion = await firmwareVersionTask

        currentAudioModeIndex = workspace.modeWorkspace.currentAudioModeIndex
        selectedAudioModeIndex = workspace.modeWorkspace.currentAudioModeIndex
        applySettingsSnapshot(workspace.modeWorkspace.settings)
        applyEqualizerSnapshot(workspace.modeWorkspace.equalizer)
        applyDeviceSettings(workspace.modeWorkspace.deviceSettings.settings)
        deviceName = workspace.bootstrappedDevice.productName
        deviceVariantName = workspace.bootstrappedDevice.productVariant.variantName
        self.firmwareVersion = firmwareVersion
        applyAudioModes(workspace.audioModes)
        supportedPrompts = prompts
        hasDetachedSettingsDraft = false
        hasDetachedEqualizerDraft = false
        lastResultMessage = "Loaded \(audioModes.count) audio modes"
    }

    private func startDiscoveryLoopIfNeeded(forceImmediateRefresh: Bool = false) {
        guard discoveryTask == nil else {
            return
        }
        appScreen = .waitingForDevice
        discoveryTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer { self.discoveryTask = nil }

            if forceImmediateRefresh {
                await self.refreshAvailableDevices()
            }

            while !Task.isCancelled && self.appScreen == .waitingForDevice {
                await self.refreshAvailableDevices()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func cancelDiscoveryLoop() {
        discoveryTask?.cancel()
        discoveryTask = nil
    }

    private func refreshAvailableDevices() async {
        guard !isBusy, !isConnectingSelectedDevice else {
            return
        }
        loadState = .loading("Scanning for Bose devices")
        waitingStatusMessage = "Scanning for a nearby Bose device..."
        Self.log("Starting: Device discovery scan")

        do {
            let devices = try await AppleBossDeviceDiscovery.discoverDevices(
                nameContains: "Bose",
                scanTimeout: .seconds(4)
            )
            guard !isConnectingSelectedDevice else {
                Self.log("Ignoring discovery results because a selected device is already connecting")
                return
            }
            availableDevices = devices
            if selectedDiscoveredDeviceID == nil || !devices.contains(where: { $0.id == selectedDiscoveredDeviceID }) {
                selectedDiscoveredDeviceID = devices.first?.id
            }
            if devices.count == 1, let device = devices.first, !isManualDeviceSelection {
                waitingStatusMessage = "Found \(device.name). Opening controls..."
                loadState = .idle
                connect(to: device)
                return
            }
            waitingStatusMessage = devices.isEmpty
                ? "No Bose devices found yet. Retrying automatically..."
                : "Select a Bose device to open its controls."
            loadState = .idle
            Self.log("Completed: Device discovery scan (\(devices.count) devices)")
        } catch {
            guard !isConnectingSelectedDevice else {
                Self.log("Ignoring discovery error because a selected device is already connecting")
                return
            }
            let description = Self.describe(error)
            waitingStatusMessage = waitingMessage(for: error, description: description)
            loadState = .idle
            Self.log("Device discovery scan failed | \(description)")
        }
    }

    private func connect(to device: BossAppleDiscoveredDevice) {
        cancelDiscoveryLoop()
        cancelBackgroundLoad()
        clearDiscoveryBusyState()
        isConnectingSelectedDevice = true
        isManualDeviceSelection = false
        selectedDiscoveredDeviceID = device.id
        selectedDeviceIdentifier = device.id
        deviceName = device.name
        waitingStatusMessage = "Found \(device.name). Opening controls..."
        run("Connecting to \(device.name)") {
            await self.clearSession()
            let session = self.makeSession()
            do {
                try await self.reloadAllState(using: session)
                self.isConnectingSelectedDevice = false
                self.appScreen = .workspace
                self.waitingStatusMessage = "Connected."
                self.startBackgroundLoad(using: session)
            } catch {
                self.isConnectingSelectedDevice = false
                self.selectedDeviceIdentifier = nil
                await self.clearSession()
                self.enterWaitingMode(message: Self.describe(error))
                self.startDiscoveryLoopIfNeeded()
                throw error
            }
        }
    }

    private func enterWaitingMode(message: String) {
        isConnectingSelectedDevice = false
        appScreen = .waitingForDevice
        waitingStatusMessage = message
    }

    private func clearDiscoveryBusyState() {
        guard case .loading(let label) = loadState,
              label == "Scanning for Bose devices" else {
            return
        }
        loadState = .idle
    }

    var shouldShowDevicePickerCard: Bool {
        isManualDeviceSelection || availableDevices.count > 1
    }

    private func resetWorkspaceState() {
        cancelBackgroundLoad()
        audioModes = []
        customProfileModes = []
        currentAudioModeIndex = nil
        settings = nil
        equalizer = nil
        deviceName = "Bose Device"
        deviceVariantName = nil
        firmwareVersion = nil
        wearDetectionEnabled = nil
        autoAwareEnabled = nil
        autoPlayPauseEnabled = nil
        autoAnswerEnabled = nil
        volumeControlValue = nil
        lastResultMessage = nil
        hasDetachedSettingsDraft = false
        hasDetachedEqualizerDraft = false
    }

    private func startBackgroundLoad(using session: BossAppleSession) {
        cancelBackgroundLoad()
        currentModeUpdateTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let updates = await session.currentAudioModeUpdateStream()
                for try await currentAudioModeIndex in updates {
                    guard !Task.isCancelled else {
                        break
                    }
                    let shouldRefreshWorkspace = await MainActor.run {
                        guard self.appScreen == .workspace else {
                            return false
                        }
                        let modeChanged =
                            self.currentAudioModeIndex != currentAudioModeIndex ||
                            self.selectedAudioModeIndex != currentAudioModeIndex
                        self.currentAudioModeIndex = currentAudioModeIndex
                        self.selectedAudioModeIndex = currentAudioModeIndex
                        return modeChanged
                    }

                    if shouldRefreshWorkspace {
                        await MainActor.run {
                            self.loadState = .loading("Refreshing mode state")
                        }
                        try await self.reloadModeWorkspace(using: session)
                        await MainActor.run {
                            self.loadState = .ready
                            self.lastResultMessage = "Mode changed on device; controls refreshed"
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.appScreen == .workspace, !self.isBusy else {
                        return
                    }
                    self.lastResultMessage = "Live mode updates paused: \(Self.describe(error))"
                }
            }
        }

        settingsUpdateTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let updates = await session.audioModeSettingsUpdateStream()
                for try await config in updates {
                    guard !Task.isCancelled else {
                        break
                    }
                    await MainActor.run {
                        guard self.appScreen == .workspace, !self.hasDetachedSettingsDraft else {
                            return
                        }
                        self.applySettingsSnapshot(config)
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.appScreen == .workspace, !self.isBusy else {
                        return
                    }
                    self.lastResultMessage = "Live settings updates paused: \(Self.describe(error))"
                }
            }
        }

        equalizerUpdateTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let updates = await session.equalizerUpdateStream()
                for try await settings in updates {
                    guard !Task.isCancelled else {
                        break
                    }
                    await MainActor.run {
                        guard self.appScreen == .workspace, !self.hasDetachedEqualizerDraft else {
                            return
                        }
                        self.applyEqualizerSnapshot(settings)
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.appScreen == .workspace, !self.isBusy else {
                        return
                    }
                    self.lastResultMessage = "Live EQ updates paused: \(Self.describe(error))"
                }
            }
        }

        deviceSettingsUpdateTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let updates = await session.deviceSettingsUpdateStream()
                for try await report in updates {
                    guard !Task.isCancelled else {
                        break
                    }
                    await MainActor.run {
                        guard self.appScreen == .workspace else {
                            return
                        }
                        self.applyDeviceSettings(report.settings)
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.appScreen == .workspace, !self.isBusy else {
                        return
                    }
                    self.lastResultMessage = "Live device settings updates paused: \(Self.describe(error))"
                }
            }
        }

        audioModeCatalogUpdateTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let updates = await session.audioModeCatalogUpdateStream()
                for try await modes in updates {
                    guard !Task.isCancelled else {
                        break
                    }
                    await MainActor.run {
                        guard self.appScreen == .workspace else {
                            return
                        }
                        self.applyAudioModes(modes)
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.appScreen == .workspace, !self.isBusy else {
                        return
                    }
                    self.lastResultMessage = "Live audio mode updates paused: \(Self.describe(error))"
                }
            }
        }
    }

    private func cancelBackgroundLoad() {
        currentModeUpdateTask?.cancel()
        currentModeUpdateTask = nil
        settingsUpdateTask?.cancel()
        settingsUpdateTask = nil
        equalizerUpdateTask?.cancel()
        equalizerUpdateTask = nil
        deviceSettingsUpdateTask?.cancel()
        deviceSettingsUpdateTask = nil
        audioModeCatalogUpdateTask?.cancel()
        audioModeCatalogUpdateTask = nil
    }

    private func waitingMessage(for error: Error, description: String) -> String {
        if let error = error as? AppleBleBossTransportError {
            switch error {
            case .scanTimedOut:
                return "No Bose device found yet. Retrying automatically..."
            case .bluetoothUnavailable:
                return "Bluetooth is unavailable. Waiting for it to come back..."
            case .bluetoothUnauthorized:
                return "Bluetooth access is not authorized. Grant access and the app will retry."
            case .bluetoothUnsupported:
                return "Bluetooth is unsupported on this Mac."
            default:
                return description
            }
        }
        return description
    }

    private func reloadModeWorkspace(using session: BossAppleSession) async throws {
        let snapshot = try await session.refreshModeWorkspaceSnapshot()
        currentAudioModeIndex = snapshot.currentAudioModeIndex
        selectedAudioModeIndex = snapshot.currentAudioModeIndex
        applySettingsSnapshot(snapshot.settings)
        applyEqualizerSnapshot(snapshot.equalizer)
        applyDeviceSettings(snapshot.deviceSettings.settings)
    }

    private func loadSupportedPrompts(using session: BossAppleSession) async -> [BossAudioModePrompt] {
        do {
            let prompts = try await session.supportedAudioModePrompts()
            return prompts.isEmpty ? fallbackSupportedPrompts : prompts
        } catch let error as BossAppleControlError
            where error.bmapErrorCode == .funcNotSupp {
            return fallbackSupportedPrompts
        } catch {
            return supportedPrompts.isEmpty ? fallbackSupportedPrompts : supportedPrompts
        }
    }

    private func loadFirmwareVersion(using session: BossAppleSession) async -> String? {
        do {
            return try await session.firmwareVersion().version
        } catch {
            return nil
        }
    }

    private func applySettingsSnapshot(_ config: BossAudioModeSettingsConfig) {
        settings = config
        cncLevel = config.cncLevel
        spatialAudioMode = config.spatialAudioMode
        windBlockEnabled = config.windBlockEnabled
        ancToggleEnabled = config.ancToggleEnabled
        hasDetachedSettingsDraft = false
    }

    private func applyEqualizerSnapshot(_ settings: BossEqualizerSettings?) {
        equalizer = settings
        bassLevel = settings?.bass?.currentLevel ?? 0
        midLevel = settings?.mid?.currentLevel ?? 0
        trebleLevel = settings?.treble?.currentLevel ?? 0
        hasDetachedEqualizerDraft = false
    }

    private func applyDeviceSettings(_ deviceSettings: BossDeviceSettings) {
        wearDetectionEnabled = deviceSettings.wearDetection?.isEnabled
        autoAwareEnabled = deviceSettings.autoAwareEnabled
        autoPlayPauseEnabled = deviceSettings.autoPlayPauseEnabled ?? deviceSettings.wearDetection?.isAutoPlayEnabled
        autoAnswerEnabled = deviceSettings.autoAnswerEnabled ?? deviceSettings.wearDetection?.isAutoAnswerEnabled
        volumeControlValue = deviceSettings.volumeControl?.value
    }

    private func applyAudioModes(_ modes: [BossAudioModeConfig]) {
        audioModes = modes
        customProfileModes = modes.filter(\.userConfigurable)
    }

    private func noteManualSettingsEdit() {
        guard settings != nil, !isBusy else {
            return
        }
        hasDetachedSettingsDraft = true
    }

    private func noteManualEqualizerEdit() {
        guard let equalizer, !isBusy else {
            return
        }
        hasDetachedEqualizerDraft =
            bassLevel != (equalizer.bass?.currentLevel ?? 0) ||
            midLevel != (equalizer.mid?.currentLevel ?? 0) ||
            trebleLevel != (equalizer.treble?.currentLevel ?? 0)
    }

    private func currentDraftConfig() -> BossAudioModeSettingsConfig {
        BossAudioModeSettingsConfig(
            cncLevel: cncLevel,
            autoCNCEnabled: settings?.autoCNCEnabled ?? false,
            spatialAudioMode: spatialAudioMode,
            windBlockEnabled: windBlockEnabled,
            ancToggleEnabled: ancToggleEnabled
        )
    }

    private func currentEqualizerPatch() -> BossEqualizerSettingsPatch {
        BossEqualizerSettingsPatch(
            bass: equalizer?.bass != nil ? bassLevel : nil,
            mid: equalizer?.mid != nil ? midLevel : nil,
            treble: equalizer?.treble != nil ? trebleLevel : nil
        )
    }

    func customProfileDisplayName(for mode: BossAudioModeConfig) -> String {
        displayName(for: mode)
    }

    func canDelete(_ mode: BossAudioModeConfig) -> Bool {
        mode.userConfigurable && mode.userConfigured && hasCustomProfileName(mode)
    }

    private var hasAvailableCustomProfileSlot: Bool {
        customProfileModes.contains { !$0.userConfigured || !hasCustomProfileName($0) }
    }

    private func saveCustomProfile(profileName: String, prompt: BossAudioModePrompt) {
        run("Saving custom profile") {
            let session = self.makeSession()
            let saved = try await session.saveCustomAudioMode(
                name: profileName,
                settings: self.currentDraftConfig(),
                prompt: prompt
            )
            self.applySettingsSnapshot(saved.settings)
            self.currentAudioModeIndex = saved.modeIndex
            self.selectedAudioModeIndex = saved.modeIndex
            self.lastResultMessage = "Saved profile \"\(saved.name)\""
        }
    }

    private func displayName(for mode: BossAudioModeConfig) -> String {
        if !hasCustomProfileName(mode) {
            return mode.userConfigurable ? "Custom profile" : "Mode \(mode.modeIndex)"
        }
        return normalizedCustomProfileName(mode.name)
    }

    private func hasCustomProfileName(_ mode: BossAudioModeConfig) -> Bool {
        let normalizedName = normalizedCustomProfileName(mode.name)
        return !normalizedName.isEmpty && normalizedName != "None"
    }

    private func normalizedCustomProfileName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func promptMatchingName(_ profileName: String) -> BossAudioModePrompt? {
        let normalizedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return BossAudioModePrompt.allKnown.first { $0.name.lowercased() == normalizedName }
    }

    private func defaultPromptForNewCustomProfile() -> BossAudioModePrompt {
        selectableSaveProfilePrompts.first ?? .none
    }

    private var fallbackSupportedPrompts: [BossAudioModePrompt] {
        BossAudioModePrompt.allKnown.filter { $0 != .none }
    }

    private func resolvedSavePrompt(for profileName: String) -> BossAudioModePrompt {
        if let exactMatch = promptMatchingName(profileName),
           supportedPrompts.contains(exactMatch) {
            return exactMatch
        }
        if let selectedPrompt = selectableSaveProfilePrompts.first(where: { $0.name == selectedSaveProfilePromptName }),
           selectedPrompt != .none {
            return selectedPrompt
        }
        return defaultPromptForNewCustomProfile()
    }

    private func run(_ label: String, operation: @escaping () async throws -> Void) {
        guard !isBusy else {
            Self.log("Ignoring operation while busy: \(label)")
            return
        }

        Self.log("Starting: \(label)")
        loadState = .loading(label)
        lastResultMessage = nil

        Task {
            do {
                try await operation()
                loadState = .ready
                Self.log("Completed: \(label)")
            } catch {
                let description = Self.describe(error)
                loadState = .failed(description)
                Self.log("Failed: \(label) | \(description)")
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return String(describing: error)
    }

    private static func log(_ message: String) {
        fputs("[boss-macos] \(message)\n", stderr)
    }
}
