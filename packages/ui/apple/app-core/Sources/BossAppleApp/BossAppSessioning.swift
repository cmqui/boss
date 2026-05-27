import Foundation
import libbossApple

protocol BossAppSessioning: AnyObject, Sendable {
    func close() async
    func loadWorkspaceSnapshot() async throws -> BossAppleWorkspaceSnapshot
    func refreshModeWorkspaceSnapshot() async throws -> BossAppleModeWorkspaceSnapshot
    func modeWorkspaceUpdates(interval: Duration) -> AsyncThrowingStream<BossAppleModeWorkspaceSnapshot, Error>
    func currentAudioMode() async throws -> Int
    func pollCurrentAudioMode() async throws -> Int?
    func currentAudioModeUpdateStream() async -> AsyncThrowingStream<Int, Error>
    func audioModeSettingsUpdateStream() async -> AsyncThrowingStream<BossAppleAudioModeSettingsConfig, Error>
    func equalizerUpdateStream() async -> AsyncThrowingStream<BossAppleEqualizerSettings, Error>
    func deviceSettingsUpdateStream() async -> AsyncThrowingStream<BossAppleDeviceSettingsReport, Error>
    func audioModeCatalogUpdateStream() async -> AsyncThrowingStream<[BossAppleAudioModeConfig], Error>
    func supportedAudioModePrompts() async throws -> [BossAppleAudioModePrompt]
    func audioModeConfigs() async throws -> [BossAppleAudioModeConfig]
    func firmwareVersion(port: Int, deviceID: Int) async throws -> BossAppleFirmwareVersionInfo
    func setCurrentAudioMode(index targetIndex: Int, playVoicePrompt: Bool) async throws -> BossAppleCurrentAudioModeWriteResult
    func setAudioModeSettings(_ update: BossAppleAudioModeSettingsConfigPatch) async throws -> BossAppleAudioModeSettingsWriteResult
    func setEqualizer(_ update: BossAppleEqualizerSettingsPatch) async throws -> BossAppleEqualizerWriteResult
    func setWearDetectionEnabled(_ enabled: Bool) async throws -> BossAppleOnHeadDetectionValue
    func setAutoAware(_ enabled: Bool) async throws -> Bool
    func setAutoPlayPause(_ enabled: Bool) async throws -> Bool
    func setAutoAnswer(_ enabled: Bool) async throws -> Bool
    func setVolumeControl(_ value: BossAppleVolumeControlValue) async throws -> BossAppleVolumeControlStatus
    func favoriteAudioMode(index: Int) async throws -> [Int]
    func unfavoriteAudioMode(index: Int) async throws -> [Int]
    func deleteCustomAudioMode(slot: Int) async throws -> BossAppleAudioModeConfig
    func saveCustomAudioMode(
        name: String,
        settings: BossAppleAudioModeSettingsConfig,
        prompt: BossAppleAudioModePrompt,
        slot requestedSlot: Int?
    ) async throws -> BossAppleAudioModeConfig
}

extension BossAppleSession: BossAppSessioning {}

protocol BossAppDiscoveryProviding: Sendable {
    func discoverDevices(connection: BossAppleConnectionOptions) async throws -> [BossAppleDiscoveredDevice]
}

struct BossBluetoothDiscoveryProvider: BossAppDiscoveryProviding {
    func discoverDevices(connection: BossAppleConnectionOptions) async throws -> [BossAppleDiscoveredDevice] {
        try await AppleBossDeviceDiscovery.discoverDevices(connection: connection)
    }
}
