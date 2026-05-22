import Combine
import Foundation
import libbossApple

@MainActor
public final class BossAppViewModel: ObservableObject {
    public enum AppScreen: Equatable {
        case waitingForDevice
        case workspace
    }

    public enum LoadState: Equatable {
        case idle
        case loading(String)
        case failed(String)
        case ready
    }

    @Published public var nameFilter = "Bose"
    @Published public var scanTimeoutSeconds = 20
    @Published public private(set) var appScreen: AppScreen = .waitingForDevice
    @Published public private(set) var loadState: LoadState = .idle
    @Published public private(set) var availableDevices: [BossAppleDiscoveredDevice] = []
    @Published public var selectedDiscoveredDeviceID: UUID?
    @Published public private(set) var audioModes: [BossAppleAudioModeConfig] = []
    @Published public private(set) var customProfileModes: [BossAppleAudioModeConfig] = []
    @Published public private(set) var currentAudioModeIndex: Int?
    @Published public private(set) var settings: BossAppleAudioModeSettingsConfig?
    @Published public private(set) var equalizer: BossAppleEqualizerSettings?
    @Published public private(set) var deviceName = "Bose Device"
    @Published public private(set) var deviceVariantName: String?
    @Published public private(set) var firmwareVersion: String?
    @Published public private(set) var wearDetectionEnabled: Bool?
    @Published public private(set) var autoAwareEnabled: Bool?
    @Published public private(set) var autoPlayPauseEnabled: Bool?
    @Published public private(set) var autoAnswerEnabled: Bool?
    @Published public private(set) var volumeControlValue: BossAppleVolumeControlValue?
    @Published public private(set) var lastResultMessage: String?
    @Published public private(set) var waitingStatusMessage = "Looking for a Bose device nearby."
    @Published public private(set) var hasDetachedSettingsDraft = false
    @Published public private(set) var hasDetachedEqualizerDraft = false
    @Published public var isPresentingSaveProfilePrompt = false
    @Published public var pendingProfileName = ""
    @Published public private(set) var supportedPrompts: [BossAppleAudioModePrompt] = []
    @Published public var selectedSaveProfilePromptName = "None"

    @Published public var selectedAudioModeIndex: Int?
    @Published public var cncLevel = 0
    @Published public var spatialAudioMode: BossAppleSpatialAudioMode = .off
    @Published public var windBlockEnabled = false
    @Published public var ancToggleEnabled = false
    @Published public var bassLevel = 0
    @Published public var midLevel = 0
    @Published public var trebleLevel = 0

    private var hasStartedInitialRefresh = false
    private var discoveryTask: Task<Void, Never>?
    private var workspaceUpdateTask: Task<Void, Never>?
    private static let audioModeCatalogPollInterval = 6
    private var session: BossAppleSession?
    private var selectedDeviceIdentifier: UUID?
    private var isManualDeviceSelection = false
    private var isConnectingSelectedDevice = false
    private let cncTotalSteps = 11
    private var cncDisplayMaximum: Int { cncTotalSteps - 1 }

    public init() {}

    public var isBusy: Bool {
        if case .loading = loadState {
            return true
        }
        return false
    }

    public var selectedModeName: String {
        if hasDetachedSettingsDraft {
            return "Custom changes"
        }
        guard let currentAudioModeIndex,
              let mode = audioModes.first(where: { $0.modeIndex == currentAudioModeIndex }) else {
            return "Unknown"
        }
        return customProfileDisplayName(for: mode)
    }

    public var displayedCurrentAudioModeIndex: Int? {
        hasDetachedSettingsDraft ? nil : currentAudioModeIndex
    }

    public var canApplyModeSettings: Bool {
        settings != nil && hasDetachedSettingsDraft && !isBusy
    }

    public var isCNCForcedToDisplayMaximumByCurrentConstraint: Bool {
        windBlockEnabled
    }

    public var canApplyEqualizer: Bool {
        equalizer != nil && hasDetachedEqualizerDraft && !isBusy
    }

    public var canSaveCustomProfile: Bool {
        settings != nil && hasDetachedSettingsDraft && hasAvailableCustomProfileSlot && !isBusy
    }

    public var selectableAudioModes: [BossAppleAudioModeConfig] {
        audioModes.filter { mode in
            if mode.userConfigurable {
                return mode.userConfigured && hasCustomProfileName(mode)
            }
            return true
        }
    }

    public var selectableSaveProfilePrompts: [BossAppleAudioModePrompt] {
        let nonNone = supportedPrompts.filter { $0 != .none }
        return nonNone.isEmpty ? supportedPrompts : nonNone
    }

    public var resolvedSelectedAudioModeIndex: Int? {
        if let selectedAudioModeIndex,
           selectableAudioModes.contains(where: { $0.modeIndex == selectedAudioModeIndex }) {
            return selectedAudioModeIndex
        }

        if let currentAudioModeIndex,
           selectableAudioModes.contains(where: { $0.modeIndex == currentAudioModeIndex }) {
            return currentAudioModeIndex
        }

        return selectableAudioModes.first?.modeIndex
    }

    public func refresh() {
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

    public func refreshIfNeeded() {
        guard !hasStartedInitialRefresh else {
            return
        }
        hasStartedInitialRefresh = true
        isManualDeviceSelection = false
        startDiscoveryLoopIfNeeded()
    }

    public func retryWaitingNow() {
        cancelDiscoveryLoop()
        startDiscoveryLoopIfNeeded(forceImmediateRefresh: true)
    }

    public func connectToSelectedDiscoveredDevice() {
        guard let selectedDiscoveredDeviceID,
              let device = availableDevices.first(where: { $0.id == selectedDiscoveredDeviceID }) else {
            return
        }
        connect(to: device)
    }

    public func connectToDiscoveredDevice(_ device: BossAppleDiscoveredDevice) {
        connect(to: device)
    }

    public func returnToDeviceSelection() {
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

    public func selectAudioMode(_ index: Int) {
        selectedAudioModeIndex = index
        if let selectedMode = audioModes.first(where: { $0.modeIndex == index }) {
            applySettingsSnapshot(selectedMode.settings)
        }
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

    public func setFavorite(_ isFavorite: Bool, for mode: BossAppleAudioModeConfig) {
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

    public func deleteCustomProfile(_ mode: BossAppleAudioModeConfig) {
        run("Deleting custom profile") {
            let session = self.makeSession()
            let displayName = self.customProfileDisplayName(for: mode)
            _ = try await session.deleteCustomAudioMode(slot: mode.modeIndex)
            self.lastResultMessage = "Deleted \"\(displayName)\""
        }
    }

    public func applyModeSettings() {
        guard canApplyModeSettings else {
            return
        }
        run("Applying mode settings") {
            let session = self.makeSession()
            let draftSettings = self.currentDraftConfig()
            Self.log(self.debugSummary(
                "Apply mode settings requested",
                selectedModeIndex: self.resolvedSelectedAudioModeIndex,
                currentModeIndex: self.currentAudioModeIndex,
                draftSettings: draftSettings
            ))

            if let selectedMode = self.selectedModeConfig,
               selectedMode.userConfigurable,
               selectedMode.userConfigured,
               self.hasCustomProfileName(selectedMode) {
                Self.log(self.debugSummary(
                    "Saving custom mode",
                    selectedModeIndex: selectedMode.modeIndex,
                    currentModeIndex: self.currentAudioModeIndex,
                    mode: selectedMode,
                    draftSettings: draftSettings
                ))
                let saved = try await self.saveCustomModeSettingsSequentially(
                    using: session,
                    startingFrom: selectedMode,
                    targetSettings: draftSettings
                )
                Self.log(self.debugSummary(
                    "Custom mode save returned",
                    selectedModeIndex: self.resolvedSelectedAudioModeIndex,
                    currentModeIndex: self.currentAudioModeIndex,
                    mode: saved,
                    draftSettings: draftSettings,
                    returnedSettings: saved.settings
                ))
                self.applySettingsSnapshot(saved.settings)
                self.selectedAudioModeIndex = saved.modeIndex

                var updatedModes = self.audioModes
                if let existingIndex = updatedModes.firstIndex(where: { $0.modeIndex == saved.modeIndex }) {
                    updatedModes[existingIndex] = saved
                    self.applyAudioModes(updatedModes)
                } else {
                    self.applyAudioModes(try await session.audioModeConfigs())
                }

                if saved.settings == draftSettings {
                    self.lastResultMessage = "Updated \"\(self.customProfileDisplayName(for: saved))\""
                } else {
                    self.lastResultMessage = "Updated \"\(self.customProfileDisplayName(for: saved))\", but firmware normalized the settings"
                }
            } else {
                let targetModeIndex = self.resolvedSelectedAudioModeIndex

                if let targetModeIndex,
                   self.currentAudioModeIndex != targetModeIndex {
                    Self.log(self.debugSummary(
                        "Switching current mode before live settings write",
                        selectedModeIndex: targetModeIndex,
                        currentModeIndex: self.currentAudioModeIndex
                    ))
                    _ = try await session.setCurrentAudioMode(index: targetModeIndex)
                    self.currentAudioModeIndex = targetModeIndex
                    self.selectedAudioModeIndex = targetModeIndex
                }

                let patch = BossAppleAudioModeSettingsConfigPatch(
                    cncLevel: self.rawCNCLevel(fromDisplay: self.cncLevel),
                    spatialAudioMode: self.spatialAudioMode,
                    windBlockEnabled: self.windBlockEnabled,
                    ancToggleEnabled: self.ancToggleEnabled
                )
                Self.log(self.debugSummary(
                    "Writing live mode settings patch",
                    selectedModeIndex: self.resolvedSelectedAudioModeIndex,
                    currentModeIndex: self.currentAudioModeIndex,
                    draftSettings: draftSettings
                ))
                let result = try await session.setAudioModeSettings(patch)
                switch result {
                case .unchanged(let config):
                    Self.log(self.debugSummary(
                        "Live mode settings returned unchanged",
                        selectedModeIndex: self.resolvedSelectedAudioModeIndex,
                        currentModeIndex: self.currentAudioModeIndex,
                        draftSettings: draftSettings,
                        returnedSettings: config
                    ))
                    self.applySettingsSnapshot(config)
                    self.lastResultMessage = "Mode settings unchanged"
                case .updated(let config):
                    Self.log(self.debugSummary(
                        "Live mode settings returned updated",
                        selectedModeIndex: self.resolvedSelectedAudioModeIndex,
                        currentModeIndex: self.currentAudioModeIndex,
                        draftSettings: draftSettings,
                        returnedSettings: config
                    ))
                    self.applySettingsSnapshot(config)
                    self.lastResultMessage = "Mode settings updated"
                case .verificationInconclusive(let config):
                    Self.log(self.debugSummary(
                        "Live mode settings verification inconclusive",
                        selectedModeIndex: self.resolvedSelectedAudioModeIndex,
                        currentModeIndex: self.currentAudioModeIndex,
                        draftSettings: draftSettings,
                        returnedSettings: config
                    ))
                    self.applySettingsSnapshot(config)
                    self.lastResultMessage = "Mode settings verification was inconclusive"
                }
            }
        }
    }

    public func applyEqualizerSettings() {
        guard canApplyEqualizer else {
            return
        }
        run("Applying EQ settings") {
            let session = self.makeSession()
            let targetModeIndex = self.resolvedSelectedAudioModeIndex

            if let targetModeIndex,
               self.currentAudioModeIndex != targetModeIndex {
                _ = try await session.setCurrentAudioMode(index: targetModeIndex)
                self.currentAudioModeIndex = targetModeIndex
                self.selectedAudioModeIndex = targetModeIndex
            }

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

            try await self.reloadModeWorkspace(using: session)
        }
    }

    public func beginSavingCustomProfile() {
        guard canSaveCustomProfile else {
            return
        }
        pendingProfileName = ""
        selectedSaveProfilePromptName = defaultPromptForNewCustomProfile().name
        isPresentingSaveProfilePrompt = true
    }

    public func cancelSavingCustomProfile() {
        isPresentingSaveProfilePrompt = false
        pendingProfileName = ""
    }

    public func confirmSavingCustomProfile() {
        let trimmedName = normalizedCustomProfileName(pendingProfileName)
        guard !trimmedName.isEmpty else {
            return
        }

        isPresentingSaveProfilePrompt = false
        pendingProfileName = ""
        saveCustomProfile(profileName: trimmedName, prompt: resolvedSavePrompt(for: trimmedName))
    }

    public func setCNCLevelDraft(_ level: Int) {
        if isCNCForcedToDisplayMaximumByCurrentConstraint {
            cncLevel = cncDisplayMaximum
            noteManualSettingsEdit()
            return
        }
        cncLevel = normalizedDisplayCNCLevel(level)
        noteManualSettingsEdit()
    }

    public func setSpatialAudioModeDraft(_ mode: BossAppleSpatialAudioMode) {
        spatialAudioMode = mode
        noteManualSettingsEdit()
    }

    public func setWindBlockEnabledDraft(_ enabled: Bool) {
        windBlockEnabled = enabled
        enforceConfirmedModeSettingConstraints()
        noteManualSettingsEdit()
    }

    public func setANCEnabledDraft(_ enabled: Bool) {
        ancToggleEnabled = enabled
        enforceConfirmedModeSettingConstraints()
        noteManualSettingsEdit()
    }

    public func setBassLevelDraft(_ level: Int) {
        bassLevel = level
        noteManualEqualizerEdit()
    }

    public func setMidLevelDraft(_ level: Int) {
        midLevel = level
        noteManualEqualizerEdit()
    }

    public func setTrebleLevelDraft(_ level: Int) {
        trebleLevel = level
        noteManualEqualizerEdit()
    }

    public func setWearDetectionEnabled(_ enabled: Bool) {
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

    public func setAutoAwareEnabled(_ enabled: Bool) {
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

    public func setAutoPlayPauseEnabled(_ enabled: Bool) {
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

    public func setAutoAnswerEnabled(_ enabled: Bool) {
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

    public func setVolumeControl(_ value: BossAppleVolumeControlValue) {
        guard let previousValue = volumeControlValue else {
            return
        }
        volumeControlValue = value
        run("Updating Volume Control") {
            let session = self.makeSession()
            do {
                let updated = try await session.setVolumeControl(
                    BossAppleVolumeControlValue(rawValue: value.rawValue) ?? .disabled
                )
                self.volumeControlValue = BossAppleVolumeControlValue(rawValue: updated.value.rawValue) ?? .disabled
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
        deviceName = workspace.bootstrappedDevice.productName
        deviceVariantName = workspace.bootstrappedDevice.productVariant.variantName
        self.firmwareVersion = firmwareVersion
        applyAudioModes(workspace.audioModes)
        applyDisplayedModeSettings(liveConfig: workspace.modeWorkspace.settings)
        applyEqualizerSnapshot(workspace.modeWorkspace.equalizer)
        applyDeviceSettings(workspace.modeWorkspace.deviceSettings.settings)
        supportedPrompts = prompts
        hasDetachedSettingsDraft = false
        hasDetachedEqualizerDraft = false
        lastResultMessage = "Loaded \(audioModes.count) audio modes"
        Self.log(debugSummary(
            "Reloaded all workspace state",
            selectedModeIndex: selectedAudioModeIndex,
            currentModeIndex: currentAudioModeIndex,
            draftSettings: settings,
            liveSettings: workspace.modeWorkspace.settings
        ))
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
                connection: BossAppleConnectionOptions(
                    nameContains: nameFilter,
                    scanTimeout: .seconds(4)
                )
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

    public var shouldShowDevicePickerCard: Bool {
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
        workspaceUpdateTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let updates = session.modeWorkspaceUpdates(interval: .seconds(5))
                var pollCount = 0
                for try await snapshot in updates {
                    guard !Task.isCancelled else {
                        break
                    }

                    await MainActor.run {
                        guard self.appScreen == .workspace else {
                            return
                        }

                        let modeChanged = self.currentAudioModeIndex != snapshot.currentAudioModeIndex
                        self.currentAudioModeIndex = snapshot.currentAudioModeIndex
                        Self.log(self.debugSummary(
                            "Mode workspace poll update",
                            selectedModeIndex: self.selectedAudioModeIndex,
                            currentModeIndex: self.currentAudioModeIndex,
                            liveSettings: snapshot.settings
                        ))

                        if !self.hasDetachedSettingsDraft {
                            self.applyDisplayedModeSettings(liveConfig: snapshot.settings)
                        }
                        if !self.hasDetachedEqualizerDraft {
                            self.applyEqualizerSnapshot(snapshot.equalizer)
                        }
                        self.applyDeviceSettings(snapshot.deviceSettings.settings)

                        if modeChanged {
                            self.lastResultMessage = "Mode changed on device; controls refreshed"
                        }
                    }

                    pollCount += 1
                    if pollCount >= Self.audioModeCatalogPollInterval {
                        pollCount = 0
                        try await self.refreshAudioModeCatalog(using: session)
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.appScreen == .workspace, !self.isBusy else {
                        return
                    }
                    self.lastResultMessage = "Live updates paused: \(Self.describe(error))"
                }
            }
        }
    }

    private func refreshAudioModeCatalog(using session: BossAppleSession) async throws {
        let modes = try await session.audioModeConfigs()
        await MainActor.run {
            guard self.appScreen == .workspace else {
                return
            }
            let selectedMode = self.selectedModeConfig
            Self.log(self.debugSummary(
                "Audio mode catalog poll update",
                selectedModeIndex: self.selectedAudioModeIndex,
                currentModeIndex: self.currentAudioModeIndex,
                mode: selectedMode,
                draftSettings: selectedMode?.settings
            ) + " catalogCount=\(modes.count)")
            self.applyAudioModes(modes)
        }
    }

    private func cancelBackgroundLoad() {
        workspaceUpdateTask?.cancel()
        workspaceUpdateTask = nil
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
                return bluetoothUnsupportedMessage
            default:
                return description
            }
        }
        return description
    }

    private var bluetoothUnsupportedMessage: String {
#if os(iOS)
        #if targetEnvironment(simulator)
            return "Bluetooth isn't available in the iOS Simulator. Run Boss on a physical iPhone or iPad to scan for devices."
        #else
            return "Bluetooth isn't available on this device."
        #endif
#elseif os(macOS)
        return "Bluetooth is unsupported on this Mac."
#else
        return "Bluetooth isn't supported on this device."
#endif
    }

    private func reloadModeWorkspace(using session: BossAppleSession) async throws {
        let snapshot = try await session.refreshModeWorkspaceSnapshot()
        currentAudioModeIndex = snapshot.currentAudioModeIndex
        Self.log(debugSummary(
            "Reloaded mode workspace snapshot",
            selectedModeIndex: selectedAudioModeIndex,
            currentModeIndex: currentAudioModeIndex,
            liveSettings: snapshot.settings
        ))
        applyDisplayedModeSettings(liveConfig: snapshot.settings)
        applyEqualizerSnapshot(snapshot.equalizer)
        applyDeviceSettings(snapshot.deviceSettings.settings)
    }

    private func loadSupportedPrompts(using session: BossAppleSession) async -> [BossAppleAudioModePrompt] {
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

    private func applySettingsSnapshot(_ config: BossAppleAudioModeSettingsConfig) {
        settings = config
        cncLevel = displayCNCLevel(fromRaw: config.cncLevel)
        spatialAudioMode = config.spatialAudioMode
        windBlockEnabled = config.windBlockEnabled
        ancToggleEnabled = config.ancToggleEnabled
        hasDetachedSettingsDraft = false
    }

    private func applyEqualizerSnapshot(_ settings: BossAppleEqualizerSettings?) {
        equalizer = settings
        bassLevel = settings?.bass?.currentLevel ?? 0
        midLevel = settings?.mid?.currentLevel ?? 0
        trebleLevel = settings?.treble?.currentLevel ?? 0
        hasDetachedEqualizerDraft = false
    }

    private func applyDeviceSettings(_ deviceSettings: BossAppleDeviceSettings) {
        wearDetectionEnabled = deviceSettings.wearDetection?.isEnabled
        autoAwareEnabled = deviceSettings.autoAwareEnabled
        autoPlayPauseEnabled = deviceSettings.autoPlayPauseEnabled ?? deviceSettings.wearDetection?.isAutoPlayEnabled
        autoAnswerEnabled = deviceSettings.autoAnswerEnabled ?? deviceSettings.wearDetection?.isAutoAnswerEnabled
        volumeControlValue = deviceSettings.volumeControl.map {
            BossAppleVolumeControlValue(rawValue: $0.value.rawValue) ?? .disabled
        }
    }

    private func applyAudioModes(_ modes: [BossAppleAudioModeConfig]) {
        audioModes = modes
        customProfileModes = modes.filter(\.userConfigurable)

        if let selectedAudioModeIndex,
           !selectableAudioModes.contains(where: { $0.modeIndex == selectedAudioModeIndex }) {
            self.selectedAudioModeIndex = resolvedSelectedAudioModeIndex
        }

        if !hasDetachedSettingsDraft,
           let selectedModeConfig,
           selectedModeConfig.modeIndex != currentAudioModeIndex {
            Self.log(debugSummary(
                "Applying selected mode settings from catalog",
                selectedModeIndex: selectedAudioModeIndex,
                currentModeIndex: currentAudioModeIndex,
                mode: selectedModeConfig,
                draftSettings: selectedModeConfig.settings
            ))
            applySettingsSnapshot(selectedModeConfig.settings)
        }
    }

    private func applyDisplayedModeSettings(liveConfig: BossAppleAudioModeSettingsConfig) {
        if let selectedModeConfig,
           selectedModeConfig.modeIndex != currentAudioModeIndex {
            Self.log(debugSummary(
                "Ignoring live settings in favor of selected catalog mode",
                selectedModeIndex: selectedAudioModeIndex,
                currentModeIndex: currentAudioModeIndex,
                mode: selectedModeConfig,
                draftSettings: selectedModeConfig.settings,
                liveSettings: liveConfig
            ))
            applySettingsSnapshot(selectedModeConfig.settings)
            return
        }
        Self.log(debugSummary(
            "Applying live settings to UI",
            selectedModeIndex: selectedAudioModeIndex,
            currentModeIndex: currentAudioModeIndex,
            liveSettings: liveConfig
        ))
        applySettingsSnapshot(liveConfig)
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

    private func currentDraftConfig() -> BossAppleAudioModeSettingsConfig {
        BossAppleAudioModeSettingsConfig(
            cncLevel: rawCNCLevel(fromDisplay: cncLevel),
            autoCNCEnabled: settings?.autoCNCEnabled ?? false,
            spatialAudioMode: spatialAudioMode,
            windBlockEnabled: windBlockEnabled,
            ancToggleEnabled: ancToggleEnabled
        )
    }

    private func enforceConfirmedModeSettingConstraints() {
        if isCNCForcedToDisplayMaximumByCurrentConstraint {
            cncLevel = cncDisplayMaximum
        }
    }

    private func displayCNCLevel(fromRaw rawValue: Int) -> Int {
        abs(normalizedRawCNCLevel(rawValue) - cncDisplayMaximum)
    }

    private func rawCNCLevel(fromDisplay displayValue: Int) -> Int {
        abs(normalizedDisplayCNCLevel(displayValue) - cncDisplayMaximum)
    }

    private func normalizedDisplayCNCLevel(_ value: Int) -> Int {
        min(max(value, 0), cncDisplayMaximum)
    }

    private func normalizedRawCNCLevel(_ value: Int) -> Int {
        min(max(value, 0), cncDisplayMaximum)
    }

    private func currentEqualizerPatch() -> BossAppleEqualizerSettingsPatch {
        BossAppleEqualizerSettingsPatch(
            bass: equalizer?.bass != nil ? bassLevel : nil,
            mid: equalizer?.mid != nil ? midLevel : nil,
            treble: equalizer?.treble != nil ? trebleLevel : nil
        )
    }

    private func saveCustomModeSettingsSequentially(
        using session: BossAppleSession,
        startingFrom initialMode: BossAppleAudioModeConfig,
        targetSettings: BossAppleAudioModeSettingsConfig
    ) async throws -> BossAppleAudioModeConfig {
        let normalizedName = normalizedCustomProfileName(initialMode.name)
        var workingMode = initialMode

        func saveStep(
            _ label: String,
            transform: (BossAppleAudioModeSettingsConfig) -> BossAppleAudioModeSettingsConfig
        ) async throws {
            let stepSettings = transform(workingMode.settings)
            guard stepSettings != workingMode.settings else {
                return
            }
            Self.log(debugSummary(
                "Saving custom mode step: \(label)",
                selectedModeIndex: workingMode.modeIndex,
                currentModeIndex: currentAudioModeIndex,
                mode: workingMode,
                draftSettings: stepSettings
            ))
            workingMode = try await session.saveCustomAudioMode(
                name: normalizedName,
                settings: stepSettings,
                prompt: initialMode.prompt,
                slot: workingMode.modeIndex
            )
            Self.log(debugSummary(
                "Custom mode step returned: \(label)",
                selectedModeIndex: workingMode.modeIndex,
                currentModeIndex: currentAudioModeIndex,
                mode: workingMode,
                returnedSettings: workingMode.settings
            ))
        }

        try await saveStep("spatial") { current in
            BossAppleAudioModeSettingsConfig(
                cncLevel: current.cncLevel,
                autoCNCEnabled: current.autoCNCEnabled,
                spatialAudioMode: targetSettings.spatialAudioMode,
                windBlockEnabled: current.windBlockEnabled,
                ancToggleEnabled: current.ancToggleEnabled
            )
        }

        let ancWillChange = workingMode.settings.ancToggleEnabled != targetSettings.ancToggleEnabled
        try await saveStep("anc") { current in
            BossAppleAudioModeSettingsConfig(
                cncLevel: current.cncLevel,
                autoCNCEnabled: current.autoCNCEnabled,
                spatialAudioMode: current.spatialAudioMode,
                windBlockEnabled: current.windBlockEnabled,
                ancToggleEnabled: targetSettings.ancToggleEnabled
            )
        }

        if ancWillChange || workingMode.settings.windBlockEnabled != targetSettings.windBlockEnabled {
            try await saveStep("wind") { current in
                BossAppleAudioModeSettingsConfig(
                    cncLevel: current.cncLevel,
                    autoCNCEnabled: current.autoCNCEnabled,
                    spatialAudioMode: current.spatialAudioMode,
                    windBlockEnabled: targetSettings.windBlockEnabled,
                    ancToggleEnabled: current.ancToggleEnabled
                )
            }
        }

        try await saveStep("cnc") { current in
            BossAppleAudioModeSettingsConfig(
                cncLevel: targetSettings.cncLevel,
                autoCNCEnabled: current.autoCNCEnabled,
                spatialAudioMode: current.spatialAudioMode,
                windBlockEnabled: current.windBlockEnabled,
                ancToggleEnabled: current.ancToggleEnabled
            )
        }

        return workingMode
    }

    public func customProfileDisplayName(for mode: BossAppleAudioModeConfig) -> String {
        displayName(for: mode)
    }

    private var selectedModeConfig: BossAppleAudioModeConfig? {
        guard let selectedAudioModeIndex = resolvedSelectedAudioModeIndex else {
            return nil
        }
        return audioModes.first(where: { $0.modeIndex == selectedAudioModeIndex })
    }

    public func canDelete(_ mode: BossAppleAudioModeConfig) -> Bool {
        mode.userConfigurable && mode.userConfigured && hasCustomProfileName(mode)
    }

    private var hasAvailableCustomProfileSlot: Bool {
        customProfileModes.contains { !$0.userConfigured || !hasCustomProfileName($0) }
    }

    private func saveCustomProfile(profileName: String, prompt: BossAppleAudioModePrompt) {
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

    private func displayName(for mode: BossAppleAudioModeConfig) -> String {
        if !hasCustomProfileName(mode) {
            return mode.userConfigurable ? "Custom profile" : "Mode \(mode.modeIndex)"
        }
        return normalizedCustomProfileName(mode.name)
    }

    private func hasCustomProfileName(_ mode: BossAppleAudioModeConfig) -> Bool {
        let normalizedName = normalizedCustomProfileName(mode.name)
        return !normalizedName.isEmpty && normalizedName != "None"
    }

    private func normalizedCustomProfileName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func promptMatchingName(_ profileName: String) -> BossAppleAudioModePrompt? {
        let normalizedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return BossAppleAudioModePrompt.allKnown.first { $0.name.lowercased() == normalizedName }
    }

    private func defaultPromptForNewCustomProfile() -> BossAppleAudioModePrompt {
        selectableSaveProfilePrompts.first ?? .none
    }

    private var fallbackSupportedPrompts: [BossAppleAudioModePrompt] {
        BossAppleAudioModePrompt.allKnown.filter { $0 != .none }
    }

    private func resolvedSavePrompt(for profileName: String) -> BossAppleAudioModePrompt {
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

    private func debugSummary(
        _ prefix: String,
        selectedModeIndex: Int?,
        currentModeIndex: Int?,
        incomingModeIndex: Int? = nil,
        mode: BossAppleAudioModeConfig? = nil,
        draftSettings: BossAppleAudioModeSettingsConfig? = nil,
        returnedSettings: BossAppleAudioModeSettingsConfig? = nil,
        liveSettings: BossAppleAudioModeSettingsConfig? = nil
    ) -> String {
        var fields: [String] = [
            "selected=\(selectedModeIndex.map(String.init) ?? "nil")",
            "current=\(currentModeIndex.map(String.init) ?? "nil")"
        ]

        if let incomingModeIndex {
            fields.append("incoming=\(incomingModeIndex)")
        }

        if let mode {
            fields.append("mode=\(debugModeLabel(mode))")
        }

        if let draftSettings {
            fields.append("draft=\(debugSettingsLabel(draftSettings))")
        }

        if let returnedSettings {
            fields.append("returned=\(debugSettingsLabel(returnedSettings))")
        }

        if let liveSettings {
            fields.append("live=\(debugSettingsLabel(liveSettings))")
        }

        return "\(prefix) | " + fields.joined(separator: " | ")
    }

    private func debugModeLabel(_ mode: BossAppleAudioModeConfig) -> String {
        "\(customProfileDisplayName(for: mode))#\(mode.modeIndex){userConfigurable=\(mode.userConfigurable),userConfigured=\(mode.userConfigured),favorite=\(mode.favorite),prompt=\(mode.prompt.name),settings=\(debugSettingsLabel(mode.settings))}"
    }

    private func debugSettingsLabel(_ settings: BossAppleAudioModeSettingsConfig) -> String {
        "{cnc=\(settings.cncLevel),autoCNC=\(settings.autoCNCEnabled),spatial=\(String(describing: settings.spatialAudioMode)),wind=\(settings.windBlockEnabled),ancToggle=\(settings.ancToggleEnabled)}"
    }

    private static func log(_ message: String) {
        fputs("[boss-apple-app] \(message)\n", stderr)
    }
}
