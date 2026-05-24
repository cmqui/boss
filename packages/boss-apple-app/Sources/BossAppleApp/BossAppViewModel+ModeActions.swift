import Foundation
import libbossApple

extension BossAppViewModel {
    public func selectAudioMode(_ index: Int) {
        selectedAudioModeIndex = index
        if let selectedMode = audioModes.first(where: { $0.modeIndex == index }) {
            applySettingsSnapshot(selectedMode.settings)
        }
        run("Switching mode") {
            let session = self.makeSession()
            let result = try await session.setCurrentAudioMode(index: index, playVoicePrompt: false)
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
                do {
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
                } catch {
                    guard self.isCustomAudioModeSlotNotEditableError(error),
                          selectedMode.modeIndex == self.currentAudioModeIndex else {
                        throw error
                    }

                    Self.log(self.debugSummary(
                        "Custom mode save failed; retrying as live current-mode settings write",
                        selectedModeIndex: selectedMode.modeIndex,
                        currentModeIndex: self.currentAudioModeIndex,
                        mode: selectedMode,
                        draftSettings: draftSettings
                    ) + " error=\(Self.describe(error))")

                    let liveResult = try await self.writeLiveModeSettings(
                        using: session,
                        draftSettings: draftSettings
                    )
                    try await self.reloadModeWorkspace(using: session)
                    let refreshedModes = try await session.audioModeConfigs()
                    self.applyAudioModes(refreshedModes)

                    if let refreshedMode = refreshedModes.first(where: { $0.modeIndex == selectedMode.modeIndex }),
                       refreshedMode.settings == draftSettings {
                        self.lastResultMessage = "Updated \"\(self.customProfileDisplayName(for: refreshedMode))\" after live fallback"
                    } else {
                        self.lastResultMessage = "\(liveResult); current mode updated, but the saved profile may not have persisted this change"
                    }
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
                    _ = try await session.setCurrentAudioMode(index: targetModeIndex, playVoicePrompt: false)
                    self.currentAudioModeIndex = targetModeIndex
                    self.selectedAudioModeIndex = targetModeIndex
                }

                Self.log(self.debugSummary(
                    "Writing live mode settings patch",
                    selectedModeIndex: self.resolvedSelectedAudioModeIndex,
                    currentModeIndex: self.currentAudioModeIndex,
                    draftSettings: draftSettings
                ))
                self.lastResultMessage = try await self.writeLiveModeSettings(
                    using: session,
                    draftSettings: draftSettings
                )
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
                _ = try await session.setCurrentAudioMode(index: targetModeIndex, playVoicePrompt: false)
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

    func writeLiveModeSettings(
        using session: any BossAppSessioning,
        draftSettings: BossAppleAudioModeSettingsConfig
    ) async throws -> String {
        let patch = BossAppleAudioModeSettingsConfigPatch(
            cncLevel: rawCNCLevel(fromDisplay: cncLevel),
            spatialAudioMode: spatialAudioMode,
            windBlockEnabled: windBlockEnabled,
            ancToggleEnabled: ancToggleEnabled
        )
        let result = try await session.setAudioModeSettings(patch)
        switch result {
        case .unchanged(let config):
            Self.log(debugSummary(
                "Live mode settings returned unchanged",
                selectedModeIndex: resolvedSelectedAudioModeIndex,
                currentModeIndex: currentAudioModeIndex,
                draftSettings: draftSettings,
                returnedSettings: config
            ))
            applySettingsSnapshot(config)
            return "Mode settings unchanged"
        case .updated(let config):
            Self.log(debugSummary(
                "Live mode settings returned updated",
                selectedModeIndex: resolvedSelectedAudioModeIndex,
                currentModeIndex: currentAudioModeIndex,
                draftSettings: draftSettings,
                returnedSettings: config
            ))
            applySettingsSnapshot(config)
            return "Mode settings updated"
        case .verificationInconclusive(let config):
            Self.log(debugSummary(
                "Live mode settings verification inconclusive",
                selectedModeIndex: resolvedSelectedAudioModeIndex,
                currentModeIndex: currentAudioModeIndex,
                draftSettings: draftSettings,
                returnedSettings: config
            ))
            applySettingsSnapshot(config)
            return "Mode settings verification was inconclusive"
        }
    }

    func isCustomAudioModeSlotNotEditableError(_ error: Error) -> Bool {
        guard let controlError = error as? BossAppleControlError else {
            return false
        }
        switch controlError {
        case .customAudioModeSlotNotEditable:
            return true
        case .unsupportedOperation(let message):
            return message.contains("CustomAudioModeSlotNotEditable")
                || message.localizedCaseInsensitiveContains("slot is not editable")
        default:
            return false
        }
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
        updateOptionalBoolSetting(
            current: wearDetectionEnabled,
            optimisticValue: enabled,
            assign: { self.wearDetectionEnabled = $0 },
            label: "Updating Wear Detection",
            successMessage: "Wear detection updated"
        ) { session in
            try await session.setWearDetectionEnabled(enabled).isEnabled
        }
    }

    public func setAutoAwareEnabled(_ enabled: Bool) {
        updateOptionalBoolSetting(
            current: autoAwareEnabled,
            optimisticValue: enabled,
            assign: { self.autoAwareEnabled = $0 },
            label: "Updating Auto-Aware",
            successMessage: "Auto-Aware updated"
        ) { session in
            _ = try await session.setAutoAware(enabled)
            return enabled
        }
    }

    public func setAutoPlayPauseEnabled(_ enabled: Bool) {
        updateOptionalBoolSetting(
            current: autoPlayPauseEnabled,
            optimisticValue: enabled,
            assign: { self.autoPlayPauseEnabled = $0 },
            label: "Updating Auto-Play/Pause",
            successMessage: "Auto-Play/Pause updated"
        ) { session in
            _ = try await session.setAutoPlayPause(enabled)
            return enabled
        }
    }

    public func setAutoAnswerEnabled(_ enabled: Bool) {
        updateOptionalBoolSetting(
            current: autoAnswerEnabled,
            optimisticValue: enabled,
            assign: { self.autoAnswerEnabled = $0 },
            label: "Updating Auto-Answer",
            successMessage: "Auto-Answer updated"
        ) { session in
            _ = try await session.setAutoAnswer(enabled)
            return enabled
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

    func reloadModeWorkspace(using session: any BossAppSessioning) async throws {
        let snapshot = try await session.refreshModeWorkspaceSnapshot()
        currentAudioModeIndex = snapshot.currentAudioModeIndex
        syncSelectedAudioModeToCurrentModeIfNeeded()
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

    func applySettingsSnapshot(_ config: BossAppleAudioModeSettingsConfig) {
        settings = config
        cncLevel = displayCNCLevel(fromRaw: config.cncLevel)
        spatialAudioMode = config.spatialAudioMode
        windBlockEnabled = config.windBlockEnabled
        ancToggleEnabled = config.ancToggleEnabled
        hasDetachedSettingsDraft = false
    }

    func applyEqualizerSnapshot(_ settings: BossAppleEqualizerSettings?) {
        equalizer = settings
        bassLevel = settings?.bass?.currentLevel ?? 0
        midLevel = settings?.mid?.currentLevel ?? 0
        trebleLevel = settings?.treble?.currentLevel ?? 0
        hasDetachedEqualizerDraft = false
    }

    func applyDeviceSettings(_ deviceSettings: BossAppleDeviceSettings) {
        wearDetectionEnabled = deviceSettings.wearDetection?.isEnabled
        autoAwareEnabled = deviceSettings.autoAwareEnabled
        autoPlayPauseEnabled = deviceSettings.autoPlayPauseEnabled ?? deviceSettings.wearDetection?.isAutoPlayEnabled
        autoAnswerEnabled = deviceSettings.autoAnswerEnabled ?? deviceSettings.wearDetection?.isAutoAnswerEnabled
        volumeControlValue = deviceSettings.volumeControl.map {
            BossAppleVolumeControlValue(rawValue: $0.value.rawValue) ?? .disabled
        }
    }

    func applyAudioModes(_ modes: [BossAppleAudioModeConfig]) {
        audioModes = modes
        customProfileModes = modes.filter(\.userConfigurable)

        if let selectedAudioModeIndex,
           !selectableAudioModes.contains(where: { $0.modeIndex == selectedAudioModeIndex }) {
            self.selectedAudioModeIndex = resolvedSelectedAudioModeIndex
        }

        if !hasDetachedSettingsDraft,
           let selectedModeConfig,
           let knownCurrentModeIndex,
           selectedModeConfig.modeIndex != knownCurrentModeIndex {
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

    func syncSelectedAudioModeToCurrentModeIfNeeded() {
        guard !hasDetachedSettingsDraft,
              let knownCurrentModeIndex,
              selectableAudioModes.contains(where: { $0.modeIndex == knownCurrentModeIndex }) else {
            return
        }
        selectedAudioModeIndex = knownCurrentModeIndex
    }

    func applyDisplayedModeSettings(liveConfig: BossAppleAudioModeSettingsConfig) {
        if let selectedModeConfig,
           let knownCurrentModeIndex,
           selectedModeConfig.modeIndex != knownCurrentModeIndex {
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

    var knownCurrentModeIndex: Int? {
        guard let currentAudioModeIndex,
              audioModes.contains(where: { $0.modeIndex == currentAudioModeIndex }) else {
            return nil
        }
        return currentAudioModeIndex
    }

    func noteManualSettingsEdit() {
        guard settings != nil, !isBusy else {
            return
        }
        hasDetachedSettingsDraft = true
    }

    func noteManualEqualizerEdit() {
        guard let equalizer, !isBusy else {
            return
        }
        hasDetachedEqualizerDraft =
            bassLevel != (equalizer.bass?.currentLevel ?? 0) ||
            midLevel != (equalizer.mid?.currentLevel ?? 0) ||
            trebleLevel != (equalizer.treble?.currentLevel ?? 0)
    }

    func currentDraftConfig() -> BossAppleAudioModeSettingsConfig {
        BossAppleAudioModeSettingsConfig(
            cncLevel: rawCNCLevel(fromDisplay: cncLevel),
            autoCNCEnabled: settings?.autoCNCEnabled ?? false,
            spatialAudioMode: spatialAudioMode,
            windBlockEnabled: windBlockEnabled,
            ancToggleEnabled: ancToggleEnabled
        )
    }

    func enforceConfirmedModeSettingConstraints() {
        if isCNCForcedToDisplayMaximumByCurrentConstraint {
            cncLevel = cncDisplayMaximum
        }
    }

    func displayCNCLevel(fromRaw rawValue: Int) -> Int {
        abs(normalizedRawCNCLevel(rawValue) - cncDisplayMaximum)
    }

    func rawCNCLevel(fromDisplay displayValue: Int) -> Int {
        abs(normalizedDisplayCNCLevel(displayValue) - cncDisplayMaximum)
    }

    func normalizedDisplayCNCLevel(_ value: Int) -> Int {
        min(max(value, 0), cncDisplayMaximum)
    }

    func normalizedRawCNCLevel(_ value: Int) -> Int {
        min(max(value, 0), cncDisplayMaximum)
    }

    func currentEqualizerPatch() -> BossAppleEqualizerSettingsPatch {
        BossAppleEqualizerSettingsPatch(
            bass: equalizer?.bass != nil ? bassLevel : nil,
            mid: equalizer?.mid != nil ? midLevel : nil,
            treble: equalizer?.treble != nil ? trebleLevel : nil
        )
    }

    func saveCustomModeSettingsSequentially(
        using session: any BossAppSessioning,
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

    var selectedModeConfig: BossAppleAudioModeConfig? {
        guard let selectedAudioModeIndex = resolvedSelectedAudioModeIndex else {
            return nil
        }
        return audioModes.first(where: { $0.modeIndex == selectedAudioModeIndex })
    }

    func updateOptionalBoolSetting(
        current: Bool?,
        optimisticValue: Bool,
        assign: @escaping (Bool) -> Void,
        label: String,
        successMessage: String,
        operation: @escaping (any BossAppSessioning) async throws -> Bool
    ) {
        guard let previousValue = current else {
            return
        }
        assign(optimisticValue)
        run(label) {
            let session = self.makeSession()
            do {
                let updatedValue = try await operation(session)
                assign(updatedValue)
                self.lastResultMessage = successMessage
            } catch {
                assign(previousValue)
                throw error
            }
        }
    }
}
