import Foundation
import libboss
import libbossApple

@MainActor
final class BossMacOSViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading(String)
        case failed(String)
        case ready
    }

    @Published var nameFilter = "Bose"
    @Published var scanTimeoutSeconds = 20
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var audioModes: [BossAudioModeConfig] = []
    @Published private(set) var customProfileModes: [BossAudioModeConfig] = []
    @Published private(set) var currentAudioModeIndex: Int?
    @Published private(set) var settings: BossAudioModeSettingsConfig?
    @Published private(set) var lastResultMessage: String?
    @Published private(set) var hasDetachedSettingsDraft = false
    @Published var isPresentingSaveProfilePrompt = false
    @Published var pendingProfileName = ""
    @Published private(set) var supportedPrompts: [BossAudioModePrompt] = []
    @Published var selectedSaveProfilePromptName = "None"

    @Published var selectedAudioModeIndex: Int?
    @Published var cncLevel = 0
    @Published var spatialAudioMode: BossSpatialAudioMode = .off
    @Published var windBlockEnabled = false
    @Published var ancToggleEnabled = false

    private var hasStartedInitialRefresh = false

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

    var canApplySettings: Bool {
        settings != nil && !isBusy
    }

    var canSaveCustomProfile: Bool {
        settings != nil && hasDetachedSettingsDraft && hasAvailableCustomProfileSlot && !isBusy
    }

    var visibleSidebarModes: [BossAudioModeConfig] {
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
        run("Connecting") {
            let controller = self.makeController()
            try await self.reloadState(using: controller)
            self.lastResultMessage = "Loaded \(self.audioModes.count) audio modes"
        }
    }

    func refreshIfNeeded() {
        guard !hasStartedInitialRefresh else {
            return
        }
        hasStartedInitialRefresh = true
        refresh()
    }

    func selectAudioMode(_ index: Int) {
        selectedAudioModeIndex = index
        run("Switching mode") {
            let controller = self.makeController()
            let result = try await controller.setCurrentAudioMode(index: index)
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

            try await self.reloadState(using: controller)
            self.lastResultMessage = "\(resultMessage); settings refreshed"
        }
    }

    func setFavorite(_ isFavorite: Bool, for mode: BossAudioModeConfig) {
        run(isFavorite ? "Adding favorite" : "Removing favorite") {
            let controller = self.makeController()
            if isFavorite {
                _ = try await controller.favoriteAudioMode(index: mode.modeIndex)
            } else {
                _ = try await controller.unfavoriteAudioMode(index: mode.modeIndex)
            }
            try await self.reloadState(using: controller)
            self.lastResultMessage = isFavorite
                ? "Added \"\(self.customProfileDisplayName(for: mode))\" to favorites"
                : "Removed \"\(self.customProfileDisplayName(for: mode))\" from favorites"
        }
    }

    func deleteCustomProfile(_ mode: BossAudioModeConfig) {
        run("Deleting custom profile") {
            let controller = self.makeController()
            _ = try await controller.deleteCustomAudioMode(slot: mode.modeIndex)
            try await self.reloadState(using: controller)
            self.lastResultMessage = "Deleted \"\(self.customProfileDisplayName(for: mode))\""
        }
    }

    func applySettings() {
        run("Applying settings") {
            let patch = BossAudioModeSettingsConfigPatch(
                cncLevel: self.cncLevel,
                spatialAudioMode: self.spatialAudioMode,
                windBlockEnabled: self.windBlockEnabled,
                ancToggleEnabled: self.ancToggleEnabled
            )
            let result = try await self.makeController().setAudioModeSettings(patch)
            switch result {
            case .unchanged(let config):
                self.applySettingsSnapshot(config)
                self.lastResultMessage = "Settings unchanged"
            case .updated(let config):
                self.applySettingsSnapshot(config)
                self.lastResultMessage = "Settings updated"
            case .verificationInconclusive(let config):
                self.applySettingsSnapshot(config)
                self.lastResultMessage = "Settings command sent; verification was inconclusive"
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

    private func makeController() -> BossAppleController {
        let trimmedNameFilter = nameFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        return BossAppleController(
            connection: BossAppleConnectionOptions(
                nameContains: trimmedNameFilter.isEmpty ? nil : trimmedNameFilter,
                scanTimeout: .seconds(scanTimeoutSeconds)
            )
        )
    }

    private func reloadState(using controller: BossAppleController) async throws {
        async let modes = controller.audioModeConfigs()
        async let currentMode = controller.currentAudioMode()
        async let settings = controller.audioModeSettings()
        let snapshot = try await (modes, currentMode, settings)
        audioModes = snapshot.0
        customProfileModes = snapshot.0.filter(\.userConfigurable)
        currentAudioModeIndex = snapshot.1
        selectedAudioModeIndex = snapshot.1
        applySettingsSnapshot(snapshot.2)
        supportedPrompts = await loadSupportedPrompts(using: controller)
        hasDetachedSettingsDraft = false
    }

    private func loadSupportedPrompts(using controller: BossAppleController) async -> [BossAudioModePrompt] {
        do {
            let prompts = try await controller.supportedAudioModePrompts()
            return prompts.isEmpty ? fallbackSupportedPrompts : prompts
        } catch let error as BossAppleControlError
            where error.bmapErrorCode == .funcNotSupp {
            return fallbackSupportedPrompts
        } catch {
            return supportedPrompts.isEmpty ? fallbackSupportedPrompts : supportedPrompts
        }
    }

    private func applySettingsSnapshot(_ config: BossAudioModeSettingsConfig) {
        settings = config
        cncLevel = config.cncLevel
        spatialAudioMode = config.spatialAudioMode
        windBlockEnabled = config.windBlockEnabled
        ancToggleEnabled = config.ancToggleEnabled
    }

    private func noteManualSettingsEdit() {
        guard settings != nil, !isBusy else {
            return
        }
        hasDetachedSettingsDraft = true
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
            let controller = self.makeController()
            let saved = try await controller.saveCustomAudioMode(
                name: profileName,
                settings: self.currentDraftConfig(),
                prompt: prompt
            )
            try await self.reloadState(using: controller)
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
            return
        }

        loadState = .loading(label)
        lastResultMessage = nil

        Task {
            do {
                try await operation()
                loadState = .ready
            } catch {
                loadState = .failed(Self.describe(error))
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
}
