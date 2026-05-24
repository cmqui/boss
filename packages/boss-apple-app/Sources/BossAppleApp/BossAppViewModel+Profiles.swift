import Foundation
import libbossApple

extension BossAppViewModel {
    public func setFavorite(_ isFavorite: Bool, for mode: BossAppleAudioModeConfig) {
        run(isFavorite ? "Adding favorite" : "Removing favorite") {
            let session = self.makeSession()
            let favoriteIndices: [Int]
            if isFavorite {
                favoriteIndices = try await session.favoriteAudioMode(index: mode.modeIndex)
            } else {
                favoriteIndices = try await session.unfavoriteAudioMode(index: mode.modeIndex)
            }
            self.applyFavoriteIndices(favoriteIndices)
            self.lastResultMessage = isFavorite
                ? "Added \"\(self.customProfileDisplayName(for: mode))\" to favorites"
                : "Removed \"\(self.customProfileDisplayName(for: mode))\" from favorites"
        }
    }

    public func deleteCustomProfile(_ mode: BossAppleAudioModeConfig) {
        run("Deleting custom profile") {
            let session = self.makeSession()
            let displayName = self.customProfileDisplayName(for: mode)
            let deleted = try await session.deleteCustomAudioMode(slot: mode.modeIndex)
            var updatedModes = self.audioModes
            if let existingIndex = updatedModes.firstIndex(where: { $0.modeIndex == deleted.modeIndex }) {
                updatedModes[existingIndex] = deleted
                self.applyAudioModes(updatedModes)
            } else {
                self.applyAudioModes(try await session.audioModeConfigs())
            }
            self.lastResultMessage = "Deleted \"\(displayName)\""
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

    public func customProfileDisplayName(for mode: BossAppleAudioModeConfig) -> String {
        displayName(for: mode)
    }

    public func canDelete(_ mode: BossAppleAudioModeConfig) -> Bool {
        mode.userConfigurable && mode.userConfigured
    }

    var hasAvailableCustomProfileSlot: Bool {
        customProfileModes.contains { !$0.userConfigured || !hasCustomProfileName($0) }
    }

    func saveCustomProfile(profileName: String, prompt: BossAppleAudioModePrompt) {
        run("Saving custom profile") {
            let session = self.makeSession()
            let saved = try await session.saveCustomAudioMode(
                name: profileName,
                settings: self.currentDraftConfig(),
                prompt: prompt,
                slot: nil
            )
            self.applyAudioModes(self.mergedAudioModes(with: saved))
            let switchResult = try await session.setCurrentAudioMode(index: saved.modeIndex, playVoicePrompt: false)
            switch switchResult {
            case .unchanged(let currentIndex):
                self.currentAudioModeIndex = currentIndex
            case .updated(let updatedIndex):
                self.currentAudioModeIndex = updatedIndex
            case .verificationInconclusive(let targetIndex):
                self.currentAudioModeIndex = targetIndex
            }
            self.selectedAudioModeIndex = saved.modeIndex
            try await self.reloadModeWorkspace(using: session)
            self.lastResultMessage = "Saved profile \"\(saved.name)\""
        }
    }

    func displayName(for mode: BossAppleAudioModeConfig) -> String {
        if !hasCustomProfileName(mode) {
            return mode.userConfigurable ? "Custom profile" : "Mode \(mode.modeIndex)"
        }
        return normalizedCustomProfileName(mode.name)
    }

    func hasCustomProfileName(_ mode: BossAppleAudioModeConfig) -> Bool {
        let normalizedName = normalizedCustomProfileName(mode.name)
        return !normalizedName.isEmpty && normalizedName != "None"
    }

    func normalizedCustomProfileName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func promptMatchingName(_ profileName: String) -> BossAppleAudioModePrompt? {
        let normalizedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return BossAppleAudioModePrompt.allKnown.first { $0.name.lowercased() == normalizedName }
    }

    func defaultPromptForNewCustomProfile() -> BossAppleAudioModePrompt {
        selectableSaveProfilePrompts.first ?? .none
    }

    var fallbackSupportedPrompts: [BossAppleAudioModePrompt] {
        BossAppleAudioModePrompt.allKnown.filter { $0 != .none }
    }

    func applyFavoriteIndices(_ favoriteIndices: [Int]) {
        let favoriteSet = Set(favoriteIndices)
        applyAudioModes(audioModes.map { mode in
            BossAppleAudioModeConfig(
                modeIndex: mode.modeIndex,
                prompt: mode.prompt,
                name: mode.name,
                favorite: favoriteSet.contains(mode.modeIndex),
                userConfigurable: mode.userConfigurable,
                userConfigured: mode.userConfigured,
                settings: mode.settings
            )
        })
    }

    func mergedAudioModes(with updatedMode: BossAppleAudioModeConfig) -> [BossAppleAudioModeConfig] {
        var mergedModes = audioModes
        if let existingIndex = mergedModes.firstIndex(where: { $0.modeIndex == updatedMode.modeIndex }) {
            mergedModes[existingIndex] = updatedMode
        } else {
            mergedModes.append(updatedMode)
            mergedModes.sort { $0.modeIndex < $1.modeIndex }
        }
        return mergedModes
    }

    func resolvedSavePrompt(for profileName: String) -> BossAppleAudioModePrompt {
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
}
