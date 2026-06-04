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
                self.markRecentPollingActivity()
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
        async let firmwareVersionTask = loadFirmwareVersion(using: session)

        let workspace = try await workspaceSnapshot
        let firmwareVersion = await firmwareVersionTask

        currentAudioModeIndex = workspace.audioModeWorkspace?.currentAudioModeIndex
        selectedAudioModeIndex = workspace.audioModeWorkspace?.currentAudioModeIndex
        deviceName = workspace.bootstrappedDevice.productName
        deviceVariantName = workspace.bootstrappedDevice.productVariant.variantName
        deviceProductFamily = workspace.bootstrappedDevice.productFamily
        deviceCapabilities = workspace.capabilities
        self.firmwareVersion = firmwareVersion
        applyAudioModes(workspace.audioModeWorkspace?.audioModes ?? [])
        if let audioModeWorkspace = workspace.audioModeWorkspace {
            applyDisplayedModeSettings(liveConfig: audioModeWorkspace.settings)
            supportedPrompts = await loadSupportedPrompts(using: session)
        } else {
            settings = nil
            supportedPrompts = []
        }
        applyEqualizerSnapshot(workspace.equalizer)
        applyDeviceSettings(workspace.settingsWorkspace.deviceSettings.settings)
        hasDetachedSettingsDraft = false
        hasDetachedEqualizerDraft = false
        lastResultMessage = workspace.audioModeWorkspace == nil
            ? "Loaded device settings"
            : "Loaded \(audioModes.count) audio modes"
        Self.log(debugSummary(
            "Reloaded all workspace state",
            selectedModeIndex: selectedAudioModeIndex,
            currentModeIndex: currentAudioModeIndex,
            draftSettings: settings,
            liveSettings: workspace.audioModeWorkspace?.settings
        ))
    }

    func startBackgroundLoad(using session: any BossAppSessioning) {
        cancelBackgroundLoad()
        guard deviceCapabilities?.audioModes.modes == .supported else {
            return
        }
        backgroundLoadGeneration &+= 1
        let generation = backgroundLoadGeneration
        liveUpdateTasks = [
            Task { [weak self] in
                guard let self else { return }
                await self.pollCurrentAudioMode(session: session, generation: generation)
            },
        ]
    }

    func startFallbackBackgroundPolling(using session: any BossAppSessioning) {
        guard workspaceUpdateTask == nil else {
            return
        }
        let generation = backgroundLoadGeneration

        workspaceUpdateTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let updates = session.modeWorkspaceUpdates(interval: .seconds(5))
                for try await snapshot in updates {
                    guard !Task.isCancelled else {
                        break
                    }

                    await MainActor.run {
                        guard self.appScreen == .workspace,
                              !self.isBusy,
                              self.backgroundLoadGeneration == generation else {
                            return
                        }
                        self.applyStreamingWorkspaceSnapshot(snapshot, source: "Mode workspace poll update")
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.appScreen == .workspace,
                          !self.isBusy,
                          self.backgroundLoadGeneration == generation else {
                        return
                    }
                    self.lastResultMessage = "Live updates paused: \(Self.describe(error))"
                }
            }
        }
    }

    func cancelBackgroundLoad() {
        backgroundLoadGeneration &+= 1
        liveUpdateTasks.forEach { $0.cancel() }
        liveUpdateTasks.removeAll()
        workspaceUpdateTask?.cancel()
        workspaceUpdateTask = nil
    }

    func stopBackgroundLoad() async {
        let liveTasks = liveUpdateTasks
        liveUpdateTasks = []
        liveTasks.forEach { $0.cancel() }
        for task in liveTasks {
            await task.value
        }

        let pollingTask = workspaceUpdateTask
        workspaceUpdateTask = nil
        pollingTask?.cancel()
        if let pollingTask {
            await pollingTask.value
        }
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
                if self.appScreen == .workspace {
                    self.cancelBackgroundLoad()
                }
                self.markRecentPollingActivity()
                try await operation()
                loadState = .ready
                Self.log("Completed: \(label)")
            } catch {
                let description = Self.describe(error)
                loadState = .failed(description)
                Self.log("Failed: \(label) | \(description)")
            }

            if self.appScreen == .workspace,
               self.liveUpdateTasks.isEmpty,
               self.workspaceUpdateTask == nil,
               let session = self.session {
                self.startBackgroundLoad(using: session)
            }
        }
    }

    private func pollCurrentAudioMode(
        session: any BossAppSessioning,
        generation: UInt64
    ) async {
        do {
            var lastObservedModeIndex: Int?
            while !Task.isCancelled {
                guard let modeIndex = try await session.pollCurrentAudioMode() else {
                    try await Task.sleep(for: await MainActor.run { self.currentBackgroundCurrentModePollingInterval() })
                    continue
                }
                let shouldResync = await MainActor.run { () -> Bool in
                    guard self.appScreen == .workspace,
                          !self.isBusy,
                          self.backgroundLoadGeneration == generation else {
                        return false
                    }

                    if lastObservedModeIndex == nil {
                        lastObservedModeIndex = modeIndex
                        return false
                    }

                    let modeChanged = self.currentAudioModeIndex != modeIndex
                    lastObservedModeIndex = modeIndex
                    guard modeChanged else {
                        return false
                    }

                    self.currentAudioModeIndex = modeIndex
                    if !self.hasDetachedSettingsDraft {
                        self.selectedAudioModeIndex = modeIndex
                    }

                    let updatedMode = self.audioModes.first(where: { $0.modeIndex == modeIndex })
                    if !self.hasDetachedSettingsDraft, let updatedMode {
                        self.applySettingsSnapshot(updatedMode.settings)
                    }
                    self.markRecentPollingActivity()

                    Self.log("Current mode poll update | selected=\(self.selectedAudioModeIndex.map(String.init) ?? "nil") | current=\(modeIndex)")

                    if self.hasDetachedSettingsDraft || self.hasDetachedEqualizerDraft {
                        self.lastResultMessage = "Mode changed on device; local edits were preserved"
                        return false
                    }
                    if updatedMode != nil {
                        self.lastResultMessage = "Mode changed on device"
                        return false
                    }
                    self.lastResultMessage = "Mode changed on device; refreshing controls"
                    return true
                }

                if shouldResync {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard self.backgroundLoadGeneration == generation else { return }
                        self.markRecentPollingActivity()
                        await self.resyncWorkspaceAfterBackgroundModeChange(using: session)
                    }
                    return
                }

                try await Task.sleep(for: await MainActor.run { self.currentBackgroundCurrentModePollingInterval() })
            }
        } catch {
            await handleLiveUpdateFailure(error, session: session, source: "current audio mode")
        }
    }

    @MainActor
    private func resyncWorkspaceAfterBackgroundModeChange(
        using session: any BossAppSessioning
    ) async {
        guard appScreen == .workspace, !isBusy else {
            return
        }

        await stopBackgroundLoad()
        guard appScreen == .workspace else {
            return
        }

        do {
            try await reloadModeWorkspace(using: session)
            applyAudioModes(try await session.audioModeConfigs())
            lastResultMessage = "Mode changed on device; controls refreshed"
            markRecentPollingActivity()
        } catch {
            lastResultMessage = "Mode changed on device, but refresh failed: \(Self.describe(error))"
        }

        guard appScreen == .workspace,
              liveUpdateTasks.isEmpty,
              workspaceUpdateTask == nil,
              self.session != nil else {
            return
        }
        startBackgroundLoad(using: session)
    }

    private func handleLiveUpdateFailure(
        _ error: Error,
        session: any BossAppSessioning,
        source: String
    ) async {
        guard !Task.isCancelled else {
            return
        }

        await MainActor.run {
            guard self.appScreen == .workspace, !self.isBusy else {
                return
            }
            self.markRecentPollingActivity()
            self.lastResultMessage = "Live \(source) updates paused: \(Self.describe(error))"
            self.liveUpdateTasks.forEach { $0.cancel() }
            self.liveUpdateTasks.removeAll()
            self.startFallbackBackgroundPolling(using: session)
        }
    }

    private func applyStreamingWorkspaceSnapshot(
        _ snapshot: BossAppleModeWorkspaceSnapshot,
        source: String
    ) {
        let modeChanged = currentAudioModeIndex != snapshot.currentAudioModeIndex
        currentAudioModeIndex = snapshot.currentAudioModeIndex
        syncSelectedAudioModeToCurrentModeIfNeeded()
        Self.log(debugSummary(
            source,
            selectedModeIndex: selectedAudioModeIndex,
            currentModeIndex: currentAudioModeIndex,
            liveSettings: snapshot.settings
        ))

        if !hasDetachedSettingsDraft {
            applyDisplayedModeSettings(liveConfig: snapshot.settings)
        }
        if !hasDetachedEqualizerDraft {
            applyEqualizerSnapshot(snapshot.equalizer)
        }
        applyDeviceSettings(snapshot.deviceSettings.settings)

        if modeChanged {
            lastResultMessage = "Mode changed on device; controls refreshed"
            markRecentPollingActivity()
        }
    }

    func markRecentPollingActivity() {
        let clock = ContinuousClock()
        backgroundCurrentModePollingFastUntil = clock.now + backgroundCurrentModePollingFastWindow
    }

    func currentBackgroundCurrentModePollingInterval() -> Duration {
        let clock = ContinuousClock()
        if let fastUntil = backgroundCurrentModePollingFastUntil, clock.now < fastUntil {
            return backgroundCurrentModePollingFastInterval
        }
        return backgroundCurrentModePollingIdleInterval
    }

    static func describe(_ error: Error) -> String {
        if let controlError = error as? BossAppleControlError {
            if controlError.isLikelyDeviceStandby {
                return "The device appears to be in standby. Wake it up, then try again."
            }
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
