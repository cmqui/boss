import Foundation
import libbossApple

extension BossAppViewModel {
    public func refresh() {
        cancelDiscoveryLoop()
        cancelBackgroundLoad()
        run(usesMockDeviceBackend ? "Opening mock device" : "Connecting") {
            let session = self.makeSession()
            do {
                try await self.reloadAllState(using: session)
                self.appScreen = .workspace
                self.waitingStatusMessage = self.usesMockDeviceBackend ? "Connected to mock device." : "Connected."
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
        enterWaitingMode(message: usesMockDeviceBackend ? "Mock QC Ultra 2 HP mode is enabled." : "Looking for a Bose device nearby.")
        startDiscoveryLoopIfNeeded(forceImmediateRefresh: true)
    }

    func makeConnectionOptions() -> BossAppleConnectionOptions {
        let connectionScanTimeout = selectedDeviceIdentifier == nil
            ? scanTimeoutSeconds
            : min(scanTimeoutSeconds, 6)
        return BossAppleConnectionOptions(
            nameContains: selectedDeviceIdentifier == nil ? "Bose" : nil,
            identifier: selectedDeviceIdentifier,
            scanTimeout: .seconds(connectionScanTimeout)
        )
    }

    func makeSession() -> any BossAppSessioning {
        let currentOptions = makeConnectionOptions()
        if let session {
            return session
        }
        let newSession = sessionFactory(currentOptions)
        session = newSession
        return newSession
    }

    func clearSession() async {
        let existing = session
        session = nil
        if let existing {
            await existing.close()
        }
    }

    func reloadAllState(using session: any BossAppSessioning) async throws {
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

    func startBackgroundLoad(using session: any BossAppSessioning) {
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
                        self.syncSelectedAudioModeToCurrentModeIfNeeded()
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

    func refreshAudioModeCatalog(using session: any BossAppSessioning) async throws {
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

    func cancelBackgroundLoad() {
        workspaceUpdateTask?.cancel()
        workspaceUpdateTask = nil
    }

    func loadSupportedPrompts(using session: any BossAppSessioning) async -> [BossAppleAudioModePrompt] {
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

    func loadFirmwareVersion(using session: any BossAppSessioning) async -> String? {
        do {
            return try await session.firmwareVersion(port: 0, deviceID: 0).version
        } catch {
            return nil
        }
    }

    func run(_ label: String, operation: @escaping () async throws -> Void) {
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

    static func describe(_ error: Error) -> String {
        if let controlError = error as? BossAppleControlError {
            switch controlError {
            case .noFreeCustomAudioModeSlot:
                return "No free custom profile slots are available on the device. Delete an existing custom profile or overwrite one instead."
            case .customAudioModeSlotNotEditable(let slot):
                return "Custom profile slot \(slot) is not editable."
            case .customAudioModeSlotNotFound(let slot):
                return "Custom profile slot \(slot) was not found on the device."
            default:
                break
            }
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return String(describing: error)
    }
}
