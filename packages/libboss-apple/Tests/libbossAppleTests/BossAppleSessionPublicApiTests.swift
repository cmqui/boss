import XCTest

@testable import libbossApple

final class BossAppleSessionPublicApiTests: XCTestCase {
    func testBootstrapCachesInjectedRustBridgeResult() async throws {
        let counter = CallCounter()
        let expected = sampleBootstrappedDevice()
        var overrides = BossAppleSessionOperationOverrides()
        overrides.bootstrap = {
            await counter.increment()
            return expected
        }

        let session = BossAppleSession(operationOverrides: overrides)

        let first = try await session.bootstrap()
        let second = try await session.bootstrap()
        let invocationCount = await counter.currentValue()

        XCTAssertEqual(first, expected)
        XCTAssertEqual(second, expected)
        XCTAssertEqual(invocationCount, 1)
    }

    func testCurrentAudioModeSettingsAndEqualizerReadsAndWritesUseInjectedBridge() async throws {
        let recorder = SessionWriteRecorder()
        let settings = sampleAudioModeSettingsConfig()
        let equalizer = sampleEqualizerSettings()

        var overrides = BossAppleSessionOperationOverrides()
        overrides.currentAudioMode = { 2 }
        overrides.setCurrentAudioMode = { targetIndex, playVoicePrompt in
            await recorder.recordCurrentAudioMode(targetIndex: targetIndex, playVoicePrompt: playVoicePrompt)
            return .updated(targetIndex)
        }
        overrides.audioModeSettings = { settings }
        overrides.setAudioModeSettings = { update in
            await recorder.recordAudioModeSettings(update)
            return .updated(update.merged(with: settings))
        }
        overrides.equalizer = { equalizer }
        overrides.setEqualizer = { update in
            await recorder.recordEqualizer(update)
            return .updated(
                BossAppleEqualizerSettings(
                    ranges: [
                        BossAppleEqualizerRangeLevel(band: .bass, currentLevel: update.bass ?? -2, minLevel: -10, maxLevel: 10),
                        BossAppleEqualizerRangeLevel(band: .mid, currentLevel: update.mid ?? 0, minLevel: -10, maxLevel: 10),
                        BossAppleEqualizerRangeLevel(band: .treble, currentLevel: update.treble ?? 1, minLevel: -10, maxLevel: 10),
                    ]
                )
            )
        }

        let session = BossAppleSession(operationOverrides: overrides)

        let currentAudioMode = try await session.currentAudioMode()
        let observedSettings = try await session.audioModeSettings()
        let observedEqualizer = try await session.equalizer()
        let currentAudioModeWrite = try await session.setCurrentAudioMode(index: 4, playVoicePrompt: true)
        XCTAssertEqual(currentAudioMode, 2)
        XCTAssertEqual(observedSettings, settings)
        XCTAssertEqual(observedEqualizer, equalizer)
        XCTAssertEqual(currentAudioModeWrite, .updated(4))

        let settingsPatch = BossAppleAudioModeSettingsConfigPatch(cncLevel: 7, windBlockEnabled: false)
        let settingsWrite = try await session.setAudioModeSettings(settingsPatch)
        XCTAssertEqual(settingsWrite, .updated(settingsPatch.merged(with: settings)))

        let equalizerPatch = BossAppleEqualizerSettingsPatch(bass: 3, treble: -1)
        let equalizerWrite = try await session.setEqualizer(equalizerPatch)
        XCTAssertEqual(
            equalizerWrite,
            .updated(
                BossAppleEqualizerSettings(
                    ranges: [
                        BossAppleEqualizerRangeLevel(band: .bass, currentLevel: 3, minLevel: -10, maxLevel: 10),
                        BossAppleEqualizerRangeLevel(band: .mid, currentLevel: 0, minLevel: -10, maxLevel: 10),
                        BossAppleEqualizerRangeLevel(band: .treble, currentLevel: -1, minLevel: -10, maxLevel: 10),
                    ]
                )
            )
        )

        let writes = await recorder.snapshot()
        XCTAssertEqual(writes.currentAudioModeTargetIndex, 4)
        XCTAssertEqual(writes.currentAudioModePlayVoicePrompt, true)
        XCTAssertEqual(writes.audioModeSettingsPatch, settingsPatch)
        XCTAssertEqual(writes.equalizerPatch, equalizerPatch)
    }

    func testCurrentAudioModeReusesLastKnownValueWhenOverrideReturns255() async throws {
        let counter = CallCounter()
        var overrides = BossAppleSessionOperationOverrides()
        overrides.currentAudioMode = {
            let invocation = await counter.nextValue()
            return invocation == 1 ? 6 : 255
        }

        let session = BossAppleSession(operationOverrides: overrides)

        let first = try await session.currentAudioMode()
        let second = try await session.currentAudioMode()

        XCTAssertEqual(first, 6)
        XCTAssertEqual(second, 6)
    }

    func testRefreshModeWorkspaceSnapshotReusesLastKnownValueWhenOverrideReturns255() async throws {
        let counter = CallCounter()
        let settings = sampleAudioModeSettingsConfig()
        let equalizer = sampleEqualizerSettings()
        let deviceSettings = sampleDeviceSettingsReport()
        var overrides = BossAppleSessionOperationOverrides()
        overrides.refreshModeWorkspaceSnapshot = {
            let invocation = await counter.nextValue()
            return BossAppleModeWorkspaceSnapshot(
                currentAudioModeIndex: invocation == 1 ? 6 : 255,
                settings: settings,
                equalizer: equalizer,
                deviceSettings: deviceSettings
            )
        }

        let session = BossAppleSession(operationOverrides: overrides)
        let first = try await session.refreshModeWorkspaceSnapshot()
        let second = try await session.refreshModeWorkspaceSnapshot()

        XCTAssertEqual(first.currentAudioModeIndex, 6)
        XCTAssertEqual(second.currentAudioModeIndex, 6)
    }

    func testLoadWorkspaceSnapshotReusesModeSnapshotEqualizer() async throws {
        let settings = sampleAudioModeSettingsConfig()
        let equalizer = sampleEqualizerSettings()
        let deviceSettings = sampleDeviceSettingsReport()
        let audioMode = BossAppleAudioModeConfig(
            modeIndex: 2,
            prompt: .comfort,
            name: "Comfort",
            favorite: true,
            userConfigurable: false,
            userConfigured: false,
            settings: settings
        )

        var overrides = BossAppleSessionOperationOverrides()
        overrides.bootstrap = {
            BossAppleBootstrappedDevice(
                bmapVersion: BossAppleBmapVersionInfo(version: "1.0"),
                productID: 0x4082,
                productName: "QC Ultra",
                productVariant: BossAppleProductVariant(productID: 0x4082, variant: 1, product: nil, variantName: "Black"),
                protocolSupport: BossAppleProtocolSupport(
                    functionBlocks: BossAppleFunctionBlockSet(bits: [1, 31]),
                    transportKind: .ble,
                    defaultDeviceID: 0,
                    defaultPort: 0
                ),
                capabilities: BossAppleDeviceCapabilities(
                    settings: BossAppleSettingsCapabilities(
                        standbyTimer: .readWrite,
                        wearDetection: .readWrite,
                        autoAware: .readWrite,
                        autoPlayPause: .readWrite,
                        autoAnswer: .readWrite,
                        volumeControl: .readWrite
                    ),
                    audioModes: BossAppleAudioModeCapabilities(
                        modes: .supported,
                        currentMode: .readWrite,
                        settingsConfig: .readWrite,
                        favorites: .readWrite,
                        customProfiles: .readWrite,
                        supportedPrompts: .unsupported
                    ),
                    sound: BossAppleSoundCapabilities(equalizer: .readWrite)
                )
            )
        }
        overrides.refreshModeWorkspaceSnapshot = {
            BossAppleModeWorkspaceSnapshot(
                currentAudioModeIndex: 2,
                settings: settings,
                equalizer: equalizer,
                deviceSettings: deviceSettings
            )
        }
        overrides.audioModeConfigs = { [audioMode] }
        overrides.standbyTimer = { nil }
        overrides.equalizer = {
            throw BossAppleControlError.unsupportedOperation("loadWorkspaceSnapshot should reuse the mode snapshot equalizer")
        }

        let session = BossAppleSession(operationOverrides: overrides)
        let workspace = try await session.loadWorkspaceSnapshot()

        XCTAssertEqual(workspace.equalizer, equalizer)
        XCTAssertEqual(workspace.settingsWorkspace.deviceSettings, deviceSettings)
        XCTAssertEqual(workspace.audioModeWorkspace?.audioModes, [audioMode])
    }

    func testCurrentAudioModeUpdateStreamReusesLastKnownValueWhenStreamYields255() async throws {
        var overrides = BossAppleSessionOperationOverrides()
        overrides.currentAudioModeUpdateStream = { makeStream(elements: [6, 255, 6]) }

        let session = BossAppleSession(operationOverrides: overrides)
        let updates = try await collect(session.currentAudioModeUpdateStream())

        XCTAssertEqual(updates, [6, 6, 6])
    }

    func testFavoritesOperationsCoverReadSetAndSingleModeFavoritePaths() async throws {
        let recorder = FavoritesRecorder()
        var overrides = BossAppleSessionOperationOverrides()
        overrides.favoriteAudioModeIndices = { [1, 3] }
        overrides.audioModeCapabilities = { BossAppleAudioModesCapabilities(boseModes: 3, userModes: 2) }
        overrides.setFavoriteAudioModeIndices = { indices, numberOfModes in
            await recorder.recordSetFavoriteAudioModeIndices(indices: indices, numberOfModes: numberOfModes)
            return indices.sorted()
        }
        overrides.setAudioModeFavorite = { index, isFavorite in
            await recorder.recordSingleFavorite(index: index, isFavorite: isFavorite)
            return isFavorite ? [index, 3] : [3]
        }

        let session = BossAppleSession(operationOverrides: overrides)

        let favoriteIndices = try await session.favoriteAudioModeIndices()
        let updatedFavoriteIndices = try await session.setFavoriteAudioModeIndices([4, 2])
        let favoriteModeResult = try await session.favoriteAudioMode(index: 2)
        let unfavoriteModeResult = try await session.unfavoriteAudioMode(index: 1)
        XCTAssertEqual(favoriteIndices, [1, 3])
        XCTAssertEqual(updatedFavoriteIndices, [2, 4])
        XCTAssertEqual(favoriteModeResult, [2, 3])
        XCTAssertEqual(unfavoriteModeResult, [3])

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.indices, [4, 2])
        XCTAssertEqual(snapshot.numberOfModes, 5)
        XCTAssertEqual(
            snapshot.singleFavoriteCalls,
            [SingleFavoriteCall(index: 2, isFavorite: true), SingleFavoriteCall(index: 1, isFavorite: false)]
        )
    }

    func testCustomModeSaveDeleteUpdateAndRenamePathsUseInjectedBridge() async throws {
        let recorder = CustomModeRecorder()
        let existingSettings = sampleAudioModeSettingsConfig()
        let existing = BossAppleAudioModeConfig(
            modeIndex: 7,
            prompt: .focus,
            name: "Existing",
            favorite: false,
            userConfigurable: true,
            userConfigured: true,
            settings: existingSettings
        )

        var overrides = BossAppleSessionOperationOverrides()
        overrides.audioModeConfigs = { [existing] }
        overrides.saveCustomAudioMode = { name, settings, prompt, slot in
            await recorder.record(name: name, settings: settings, prompt: prompt, slot: slot)
            return BossAppleAudioModeConfig(
                modeIndex: slot ?? 9,
                prompt: prompt,
                name: name,
                favorite: false,
                userConfigurable: true,
                userConfigured: true,
                settings: settings
            )
        }
        overrides.deleteCustomAudioMode = { slot in
            await recorder.recordDeletedSlot(slot)
            return BossAppleAudioModeConfig(
                modeIndex: slot,
                prompt: .none,
                name: "Deleted",
                favorite: false,
                userConfigurable: true,
                userConfigured: false,
                settings: existing.deletedSettingsBaseline
            )
        }

        let session = BossAppleSession(operationOverrides: overrides)

        let saved = try await session.saveCustomAudioMode(
            name: "Created",
            settings: existingSettings,
            prompt: .quiet
        )
        let updated = try await session.updateCustomAudioMode(slot: 7, name: "Updated")
        let renamed = try await session.renameCustomAudioMode(slot: 7, name: "Renamed", prompt: .aware)
        let deleted = try await session.deleteCustomAudioMode(slot: 7)

        XCTAssertEqual(saved.modeIndex, 9)
        XCTAssertEqual(saved.name, "Created")
        XCTAssertEqual(updated.modeIndex, 7)
        XCTAssertEqual(updated.name, "Updated")
        XCTAssertEqual(updated.settings, existingSettings)
        XCTAssertEqual(updated.prompt, .focus)
        XCTAssertEqual(renamed.modeIndex, 7)
        XCTAssertEqual(renamed.name, "Renamed")
        XCTAssertEqual(renamed.prompt, .aware)
        XCTAssertEqual(deleted.modeIndex, 7)
        XCTAssertEqual(deleted.name, "Deleted")

        let writes = await recorder.snapshot()
        XCTAssertEqual(
            writes.savedCalls,
            [
                SavedCustomModeCall(name: "Created", settings: existingSettings, prompt: .quiet, slot: nil),
                SavedCustomModeCall(name: "Updated", settings: existingSettings, prompt: .focus, slot: 7),
                SavedCustomModeCall(name: "Renamed", settings: existingSettings, prompt: .aware, slot: 7),
            ]
        )
        XCTAssertEqual(writes.deletedSlots, [7])
    }

    func testUpdateStreamsExposeInjectedRustBridgeStreams() async throws {
        let settingsA = sampleAudioModeSettingsConfig()
        let settingsB = BossAppleAudioModeSettingsConfig(
            cncLevel: 7,
            autoCNCEnabled: false,
            spatialAudioMode: .head,
            windBlockEnabled: false,
            ancToggleEnabled: true
        )
        let equalizerA = sampleEqualizerSettings()
        let equalizerB = BossAppleEqualizerSettings(
            ranges: [
                BossAppleEqualizerRangeLevel(band: .bass, currentLevel: 2, minLevel: -10, maxLevel: 10),
                BossAppleEqualizerRangeLevel(band: .mid, currentLevel: -1, minLevel: -10, maxLevel: 10),
                BossAppleEqualizerRangeLevel(band: .treble, currentLevel: 4, minLevel: -10, maxLevel: 10),
            ]
        )

        var overrides = BossAppleSessionOperationOverrides()
        overrides.currentAudioModeUpdateStream = { makeStream(elements: [1, 2]) }
        overrides.audioModeSettingsUpdateStream = { makeStream(elements: [settingsA, settingsB]) }
        overrides.equalizerUpdateStream = { makeStream(elements: [equalizerA, equalizerB]) }

        let session = BossAppleSession(operationOverrides: overrides)

        let currentModeStream = await session.currentAudioModeUpdateStream()
        let settingsStream = await session.audioModeSettingsUpdateStream()
        let equalizerStream = await session.equalizerUpdateStream()
        let currentModeUpdates = try await collect(currentModeStream)
        let settingsUpdates = try await collect(settingsStream)
        let equalizerUpdates = try await collect(equalizerStream)

        XCTAssertEqual(currentModeUpdates, [1, 2])
        XCTAssertEqual(settingsUpdates, [settingsA, settingsB])
        XCTAssertEqual(equalizerUpdates, [equalizerA, equalizerB])
    }

    func testRuntimeFailureModesRemainExplicitWhenRustRuntimeIsUnavailable() async throws {
        let session = BossAppleSession(rustBridgeProvider: { nil })

        do {
            _ = try await session.bootstrap()
            XCTFail("Expected bootstrap to fail without a Rust runtime")
        } catch {
            XCTAssertEqual(
                error as? BossAppleControlError,
                .unsupportedOperation("Rust runtime is required for bootstrap")
            )
        }

        do {
            _ = try await session.currentAudioMode()
            XCTFail("Expected read to fail without a Rust runtime")
        } catch {
            XCTAssertEqual(
                error as? BossAppleControlError,
                .unsupportedOperation("Rust runtime is required for BossAppleSession")
            )
        }

        do {
            _ = try await collect(session.currentAudioModeUpdateStream())
            XCTFail("Expected stream to fail without a Rust runtime")
        } catch {
            XCTAssertEqual(
                error as? BossAppleControlError,
                .unsupportedOperation("Rust runtime is required for BossAppleSession streams")
            )
        }
    }

}

private extension BossAppleSessionPublicApiTests {
    func collect<Element: Sendable>(_ stream: AsyncThrowingStream<Element, Error>) async throws -> [Element] {
        var values: [Element] = []
        for try await value in stream {
            values.append(value)
        }
        return values
    }

    func sampleBootstrappedDevice() -> BossAppleBootstrappedDevice {
        BossAppleBootstrappedDevice(
            bmapVersion: BossAppleBmapVersionInfo(version: "1.0"),
            productID: 0x4082,
            productName: "QC Ultra",
            productVariant: BossAppleProductVariant(productID: 0x4082, variant: 1, product: nil, variantName: "Black"),
            protocolSupport: BossAppleProtocolSupport(
                functionBlocks: BossAppleFunctionBlockSet(bits: [1, 31]),
                transportKind: .ble,
                defaultDeviceID: 0,
                defaultPort: 0
            ),
            capabilities: BossAppleDeviceCapabilities(
                settings: BossAppleSettingsCapabilities(
                    standbyTimer: .readWrite,
                    wearDetection: .readWrite,
                    autoAware: .readWrite,
                    autoPlayPause: .readWrite,
                    autoAnswer: .readWrite,
                    volumeControl: .readWrite
                ),
                audioModes: BossAppleAudioModeCapabilities(
                    modes: .supported,
                    currentMode: .readWrite,
                    settingsConfig: .readWrite,
                    favorites: .readWrite,
                    customProfiles: .readWrite,
                    supportedPrompts: .supported
                ),
                sound: BossAppleSoundCapabilities(equalizer: .readWrite)
            )
        )
    }

    func sampleAudioModeSettingsConfig() -> BossAppleAudioModeSettingsConfig {
        BossAppleAudioModeSettingsConfig(
            cncLevel: 5,
            autoCNCEnabled: true,
            spatialAudioMode: .room,
            windBlockEnabled: true,
            ancToggleEnabled: false
        )
    }

    func sampleEqualizerSettings() -> BossAppleEqualizerSettings {
        BossAppleEqualizerSettings(
            ranges: [
                BossAppleEqualizerRangeLevel(band: .bass, currentLevel: -2, minLevel: -10, maxLevel: 10),
                BossAppleEqualizerRangeLevel(band: .mid, currentLevel: 0, minLevel: -10, maxLevel: 10),
                BossAppleEqualizerRangeLevel(band: .treble, currentLevel: 1, minLevel: -10, maxLevel: 10),
            ]
        )
    }

    func sampleDeviceSettingsReport() -> BossAppleDeviceSettingsReport {
        BossAppleDeviceSettingsReport(
            wearDetection: BossAppleObservedSetting(
                value: BossAppleOnHeadDetectionValue(
                    isEnabled: true,
                    isAutoPlayEnabled: true,
                    isAutoAnswerEnabled: false,
                    isAutoTransparencyEnabled: nil
                )
            ),
            autoAwareEnabled: BossAppleObservedSetting(value: true),
            autoPlayPauseEnabled: BossAppleObservedSetting(value: true),
            autoAnswerEnabled: BossAppleObservedSetting(value: false),
            volumeControl: BossAppleObservedSetting(value: BossAppleVolumeControlStatus(value: .button))
        )
    }
}

private actor CallCounter {
    private var value = 0

    func increment() {
        value += 1
    }

    func currentValue() -> Int {
        value
    }

    func nextValue() -> Int {
        value += 1
        return value
    }
}

private actor SessionWriteRecorder {
    private(set) var currentAudioModeTargetIndex: Int?
    private(set) var currentAudioModePlayVoicePrompt: Bool?
    private(set) var audioModeSettingsPatch: BossAppleAudioModeSettingsConfigPatch?
    private(set) var equalizerPatch: BossAppleEqualizerSettingsPatch?

    func recordCurrentAudioMode(targetIndex: Int, playVoicePrompt: Bool) {
        currentAudioModeTargetIndex = targetIndex
        currentAudioModePlayVoicePrompt = playVoicePrompt
    }

    func recordAudioModeSettings(_ patch: BossAppleAudioModeSettingsConfigPatch) {
        audioModeSettingsPatch = patch
    }

    func recordEqualizer(_ patch: BossAppleEqualizerSettingsPatch) {
        equalizerPatch = patch
    }

    func snapshot() -> SessionWriteRecorderSnapshot {
        SessionWriteRecorderSnapshot(
            currentAudioModeTargetIndex: currentAudioModeTargetIndex,
            currentAudioModePlayVoicePrompt: currentAudioModePlayVoicePrompt,
            audioModeSettingsPatch: audioModeSettingsPatch,
            equalizerPatch: equalizerPatch
        )
    }
}

private struct SessionWriteRecorderSnapshot: Equatable {
    let currentAudioModeTargetIndex: Int?
    let currentAudioModePlayVoicePrompt: Bool?
    let audioModeSettingsPatch: BossAppleAudioModeSettingsConfigPatch?
    let equalizerPatch: BossAppleEqualizerSettingsPatch?
}

private actor FavoritesRecorder {
    private(set) var indices: [Int] = []
    private(set) var numberOfModes: Int?
    private(set) var singleFavoriteCalls: [SingleFavoriteCall] = []

    func recordSetFavoriteAudioModeIndices(indices: [Int], numberOfModes: Int) {
        self.indices = indices
        self.numberOfModes = numberOfModes
    }

    func recordSingleFavorite(index: Int, isFavorite: Bool) {
        singleFavoriteCalls.append(SingleFavoriteCall(index: index, isFavorite: isFavorite))
    }

    func snapshot() -> FavoritesRecorderSnapshot {
        FavoritesRecorderSnapshot(
            indices: indices,
            numberOfModes: numberOfModes,
            singleFavoriteCalls: singleFavoriteCalls
        )
    }
}

private struct FavoritesRecorderSnapshot: Equatable {
    let indices: [Int]
    let numberOfModes: Int?
    let singleFavoriteCalls: [SingleFavoriteCall]
}

private struct SingleFavoriteCall: Equatable {
    let index: Int
    let isFavorite: Bool
}

private actor CustomModeRecorder {
    private(set) var savedCalls: [SavedCustomModeCall] = []
    private(set) var deletedSlots: [Int] = []

    func record(name: String, settings: BossAppleAudioModeSettingsConfig, prompt: BossAppleAudioModePrompt, slot: Int?) {
        savedCalls.append(SavedCustomModeCall(name: name, settings: settings, prompt: prompt, slot: slot))
    }

    func recordDeletedSlot(_ slot: Int) {
        deletedSlots.append(slot)
    }

    func snapshot() -> CustomModeRecorderSnapshot {
        CustomModeRecorderSnapshot(savedCalls: savedCalls, deletedSlots: deletedSlots)
    }
}

private struct CustomModeRecorderSnapshot: Equatable {
    let savedCalls: [SavedCustomModeCall]
    let deletedSlots: [Int]
}

private struct SavedCustomModeCall: Equatable {
    let name: String
    let settings: BossAppleAudioModeSettingsConfig
    let prompt: BossAppleAudioModePrompt
    let slot: Int?
}

private func makeStream<Element: Sendable>(elements: [Element]) -> AsyncThrowingStream<Element, Error> {
    AsyncThrowingStream { continuation in
        for element in elements {
            continuation.yield(element)
        }
        continuation.finish()
    }
}
