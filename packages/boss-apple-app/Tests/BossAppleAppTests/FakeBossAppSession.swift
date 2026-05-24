import Foundation
import libbossApple

@testable import BossAppleApp

final class FakeBossAppSession: @unchecked Sendable, BossAppSessioning {
    var workspaceSnapshot: BossAppleWorkspaceSnapshot = .fixture()
    var workspaceSnapshotError: Error?
    var refreshModeWorkspaceSnapshotResult: BossAppleModeWorkspaceSnapshot = .fixture()
    var audioModeConfigsResult: [BossAppleAudioModeConfig]?
    var modeWorkspaceUpdateSnapshots: [BossAppleModeWorkspaceSnapshot] = []
    var supportedPrompts: [BossAppleAudioModePrompt] = [.quiet]
    var firmwareVersionInfo = BossAppleFirmwareVersionInfo(version: "1.0.0", port: 0)
    var currentAudioModeWriteResult: BossAppleCurrentAudioModeWriteResult = .unchanged(1)
    var audioModeSettingsWriteResult: BossAppleAudioModeSettingsWriteResult = .unchanged(.fixture())
    var equalizerWriteResult: BossAppleEqualizerWriteResult = .unchanged(.fixture())
    var saveCustomAudioModeError: Error?
    var savedCustomAudioModeResult: BossAppleAudioModeConfig?
    var saveCustomAudioModeCalls: [SavedCustomModeCall] = []
    var closeCallCount = 0
    var setCurrentAudioModeCalls: [Int] = []
    var audioModeSettingsPatches: [BossAppleAudioModeSettingsConfigPatch] = []

    func close() async {
        closeCallCount += 1
    }

    func loadWorkspaceSnapshot() async throws -> BossAppleWorkspaceSnapshot {
        if let workspaceSnapshotError {
            throw workspaceSnapshotError
        }
        return workspaceSnapshot
    }

    func refreshModeWorkspaceSnapshot() async throws -> BossAppleModeWorkspaceSnapshot {
        refreshModeWorkspaceSnapshotResult
    }

    func modeWorkspaceUpdates(interval: Duration) -> AsyncThrowingStream<BossAppleModeWorkspaceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            for snapshot in modeWorkspaceUpdateSnapshots {
                continuation.yield(snapshot)
            }
            continuation.finish()
        }
    }

    func supportedAudioModePrompts() async throws -> [BossAppleAudioModePrompt] {
        supportedPrompts
    }

    func audioModeConfigs() async throws -> [BossAppleAudioModeConfig] {
        audioModeConfigsResult ?? workspaceSnapshot.audioModes
    }

    func firmwareVersion(port: Int, deviceID: Int) async throws -> BossAppleFirmwareVersionInfo {
        firmwareVersionInfo
    }

    func setCurrentAudioMode(index targetIndex: Int, playVoicePrompt: Bool) async throws -> BossAppleCurrentAudioModeWriteResult {
        setCurrentAudioModeCalls.append(targetIndex)
        return currentAudioModeWriteResult
    }

    func setAudioModeSettings(_ update: BossAppleAudioModeSettingsConfigPatch) async throws -> BossAppleAudioModeSettingsWriteResult {
        audioModeSettingsPatches.append(update)
        return audioModeSettingsWriteResult
    }

    func setEqualizer(_ update: BossAppleEqualizerSettingsPatch) async throws -> BossAppleEqualizerWriteResult {
        equalizerWriteResult
    }

    func setWearDetectionEnabled(_ enabled: Bool) async throws -> BossAppleOnHeadDetectionValue {
        BossAppleOnHeadDetectionValue(isEnabled: enabled, isAutoPlayEnabled: nil, isAutoAnswerEnabled: nil, isAutoTransparencyEnabled: nil)
    }

    func setAutoAware(_ enabled: Bool) async throws -> Bool { enabled }
    func setAutoPlayPause(_ enabled: Bool) async throws -> Bool { enabled }
    func setAutoAnswer(_ enabled: Bool) async throws -> Bool { enabled }

    func setVolumeControl(_ value: BossAppleVolumeControlValue) async throws -> BossAppleVolumeControlStatus {
        BossAppleVolumeControlStatus(value: value)
    }

    func favoriteAudioMode(index: Int) async throws -> [Int] { [index] }
    func unfavoriteAudioMode(index: Int) async throws -> [Int] { [] }

    func deleteCustomAudioMode(slot: Int) async throws -> BossAppleAudioModeConfig {
        workspaceSnapshot.audioModes.first { $0.modeIndex == slot } ?? .fixture(modeIndex: slot)
    }

    func saveCustomAudioMode(
        name: String,
        settings: BossAppleAudioModeSettingsConfig,
        prompt: BossAppleAudioModePrompt,
        slot requestedSlot: Int?
    ) async throws -> BossAppleAudioModeConfig {
        saveCustomAudioModeCalls.append(
            SavedCustomModeCall(name: name, settings: settings, prompt: prompt, slot: requestedSlot)
        )
        if let saveCustomAudioModeError {
            throw saveCustomAudioModeError
        }
        if let savedCustomAudioModeResult {
            return savedCustomAudioModeResult
        }
        return BossAppleAudioModeConfig.fixture(
            modeIndex: requestedSlot ?? 10,
            name: name,
            prompt: prompt,
            settings: settings,
            userConfigurable: true,
            userConfigured: true
        )
    }
}

struct SavedCustomModeCall: Equatable {
    let name: String
    let settings: BossAppleAudioModeSettingsConfig
    let prompt: BossAppleAudioModePrompt
    let slot: Int?
}

extension BossAppleWorkspaceSnapshot {
    static func fixture(
        currentAudioModeIndex: Int = 1,
        settings: BossAppleAudioModeSettingsConfig = .fixture(),
        audioModes: [BossAppleAudioModeConfig] = [
            .fixture(modeIndex: 1, name: "Quiet", prompt: .quiet, settings: .fixture(cncLevel: 3)),
            .fixture(modeIndex: 2, name: "Aware", prompt: .aware, settings: .fixture(cncLevel: 4)),
        ]
    ) -> BossAppleWorkspaceSnapshot {
        BossAppleWorkspaceSnapshot(
            bootstrappedDevice: BossAppleBootstrappedDevice(
                bmapVersion: BossAppleBmapVersionInfo(version: "1.0"),
                productID: 0x1234,
                productName: "QuietComfort Ultra",
                productVariant: BossAppleProductVariant(productID: 0x1234, variant: 0x02, product: nil, variantName: "Black"),
                supportedFunctionBlocks: BossAppleFunctionBlockSet(bits: [1, 31]),
                transportKind: .ble,
                defaultDeviceID: 0,
                defaultPort: 0
            ),
            modeWorkspace: .fixture(currentAudioModeIndex: currentAudioModeIndex, settings: settings),
            audioModes: audioModes
        )
    }
}

extension BossAppleModeWorkspaceSnapshot {
    static func fixture(
        currentAudioModeIndex: Int = 1,
        settings: BossAppleAudioModeSettingsConfig = .fixture()
    ) -> BossAppleModeWorkspaceSnapshot {
        BossAppleModeWorkspaceSnapshot(
            currentAudioModeIndex: currentAudioModeIndex,
            settings: settings,
            equalizer: .fixture(),
            deviceSettings: BossAppleDeviceSettingsReport(
                wearDetection: BossAppleObservedSetting(value: BossAppleOnHeadDetectionValue(isEnabled: true, isAutoPlayEnabled: true, isAutoAnswerEnabled: false, isAutoTransparencyEnabled: nil)),
                autoAwareEnabled: BossAppleObservedSetting(value: true),
                autoPlayPauseEnabled: BossAppleObservedSetting(value: true),
                autoAnswerEnabled: BossAppleObservedSetting(value: false),
                volumeControl: BossAppleObservedSetting(value: BossAppleVolumeControlStatus(value: .button))
            )
        )
    }
}

extension BossAppleAudioModeConfig {
    static func fixture(
        modeIndex: Int = 1,
        name: String = "Quiet",
        prompt: BossAppleAudioModePrompt = .quiet,
        settings: BossAppleAudioModeSettingsConfig = .fixture(),
        favorite: Bool = false,
        userConfigurable: Bool = false,
        userConfigured: Bool = false
    ) -> BossAppleAudioModeConfig {
        BossAppleAudioModeConfig(
            modeIndex: modeIndex,
            prompt: prompt,
            name: name,
            favorite: favorite,
            userConfigurable: userConfigurable,
            userConfigured: userConfigured,
            settings: settings
        )
    }
}

extension BossAppleAudioModeSettingsConfig {
    static func fixture(
        cncLevel: Int = 3,
        autoCNCEnabled: Bool = false,
        spatialAudioMode: BossAppleSpatialAudioMode = .off,
        windBlockEnabled: Bool = false,
        ancToggleEnabled: Bool = false
    ) -> BossAppleAudioModeSettingsConfig {
        BossAppleAudioModeSettingsConfig(
            cncLevel: cncLevel,
            autoCNCEnabled: autoCNCEnabled,
            spatialAudioMode: spatialAudioMode,
            windBlockEnabled: windBlockEnabled,
            ancToggleEnabled: ancToggleEnabled
        )
    }
}

extension BossAppleEqualizerSettings {
    static func fixture() -> BossAppleEqualizerSettings {
        BossAppleEqualizerSettings(
            ranges: [
                BossAppleEqualizerRangeLevel(band: .bass, currentLevel: 1, minLevel: -10, maxLevel: 10),
                BossAppleEqualizerRangeLevel(band: .mid, currentLevel: 0, minLevel: -10, maxLevel: 10),
                BossAppleEqualizerRangeLevel(band: .treble, currentLevel: -1, minLevel: -10, maxLevel: 10),
            ]
        )
    }
}
