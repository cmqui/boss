import Foundation
import libbossApple

actor MockBossAppDeviceStore {
    static let shared = MockBossAppDeviceStore()

    private let discoveredDevice = BossAppleDiscoveredDevice(
        id: UUID(uuidString: "40824082-0000-4000-8000-000000000002") ?? UUID(),
        name: "Bose QC Ultra 2 HP",
        isCurrentlyConnected: true
    )
    private let bootstrappedDevice: BossAppleBootstrappedDevice
    private let supportedPrompts: [BossAppleAudioModePrompt]
    private let firmwareVersion = BossAppleFirmwareVersionInfo(version: "99.9.9-mock", port: 0)

    private var currentAudioModeIndex: Int
    private var audioModes: [BossAppleAudioModeConfig]
    private var equalizer: BossAppleEqualizerSettings
    private var wearDetection: BossAppleOnHeadDetectionValue
    private var autoAwareEnabled: Bool
    private var autoPlayPauseEnabled: Bool
    private var autoAnswerEnabled: Bool
    private var volumeControlStatus: BossAppleVolumeControlStatus

    init() {
        let product = BossAppleProductDefinition(
            id: 0x4082,
            codeName: "Wolverine",
            displayName: "Bose QC Ultra 2 HP",
            variants: [
                1: "WolverineBlack",
                2: "WolverineWhiteSmoke",
                3: "WolverineDriftwoodSand",
                4: "WolverineMidnightViolet",
                5: "WolverineDesertGold",
            ]
        )

        bootstrappedDevice = BossAppleBootstrappedDevice(
            bmapVersion: BossAppleBmapVersionInfo(version: "1.0-mock"),
            productID: product.id,
            productName: product.displayName,
            productVariant: BossAppleProductVariant(
                productID: product.id,
                variant: 1,
                product: product,
                variantName: product.variants[1]
            ),
            supportedFunctionBlocks: BossAppleFunctionBlockSet(bits: [1, 2, 7, 18, 31]),
            transportKind: .stream,
            defaultDeviceID: 0,
            defaultPort: 0
        )
        supportedPrompts = [.quiet, .aware, .immersion, .commute, .focus, .workout, .home]
        currentAudioModeIndex = 1
        audioModes = [
            Self.mode(modeIndex: 1, prompt: .quiet, name: "Quiet", settings: Self.settings(cncLevel: 10, spatial: .off, windBlock: false, ancToggle: false), favorite: true),
            Self.mode(modeIndex: 2, prompt: .aware, name: "Aware", settings: Self.settings(cncLevel: 2, spatial: .off, windBlock: false, ancToggle: true)),
            Self.mode(modeIndex: 3, prompt: .immersion, name: "Immersion", settings: Self.settings(cncLevel: 7, spatial: .head, windBlock: false, ancToggle: false)),
            Self.mode(modeIndex: 4, prompt: .commute, name: "Commute", settings: Self.settings(cncLevel: 8, spatial: .room, windBlock: true, ancToggle: false)),
            Self.mode(modeIndex: 10, prompt: .focus, name: "Deep Focus", settings: Self.settings(cncLevel: 6, spatial: .off, windBlock: false, ancToggle: true), favorite: true, userConfigurable: true, userConfigured: true),
            Self.mode(modeIndex: 11, prompt: .home, name: "None", settings: Self.settings(cncLevel: 5, spatial: .off, windBlock: false, ancToggle: false), userConfigurable: true, userConfigured: false),
        ]
        equalizer = Self.equalizer(bass: 4, mid: 1, treble: -2)
        wearDetection = BossAppleOnHeadDetectionValue(
            isEnabled: true,
            isAutoPlayEnabled: true,
            isAutoAnswerEnabled: false,
            isAutoTransparencyEnabled: nil
        )
        autoAwareEnabled = true
        autoPlayPauseEnabled = true
        autoAnswerEnabled = false
        volumeControlStatus = BossAppleVolumeControlStatus(
            value: .capTouch,
            supportedValues: [.disabled, .button, .capTouch]
        )
    }

    func discoverDevices(matching connection: BossAppleConnectionOptions) -> [BossAppleDiscoveredDevice] {
        if let identifier = connection.identifier, identifier != discoveredDevice.id {
            return []
        }

        let needle = connection.nameContains?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !needle.isEmpty, !discoveredDevice.name.localizedCaseInsensitiveContains(needle) {
            return []
        }

        return [discoveredDevice]
    }

    func validateConnection(_ connection: BossAppleConnectionOptions) throws {
        if let identifier = connection.identifier, identifier != discoveredDevice.id {
            throw BossAppleControlError.unsupportedOperation("Mock device not found for identifier \(identifier.uuidString)")
        }
    }

    func workspaceSnapshot() -> BossAppleWorkspaceSnapshot {
        BossAppleWorkspaceSnapshot(
            bootstrappedDevice: bootstrappedDevice,
            modeWorkspace: modeWorkspaceSnapshot(),
            audioModes: audioModes
        )
    }

    func modeWorkspaceSnapshot() -> BossAppleModeWorkspaceSnapshot {
        BossAppleModeWorkspaceSnapshot(
            currentAudioModeIndex: currentAudioModeIndex,
            settings: currentMode.settings,
            equalizer: equalizer,
            deviceSettings: deviceSettingsReport()
        )
    }

    func prompts() -> [BossAppleAudioModePrompt] {
        supportedPrompts
    }

    func configs() -> [BossAppleAudioModeConfig] {
        audioModes
    }

    func firmware(port: Int) -> BossAppleFirmwareVersionInfo {
        BossAppleFirmwareVersionInfo(version: firmwareVersion.version, port: port)
    }

    func setCurrentAudioMode(index targetIndex: Int) throws -> BossAppleCurrentAudioModeWriteResult {
        guard audioModes.contains(where: { $0.modeIndex == targetIndex }) else {
            throw BossAppleControlError.unsupportedOperation("Mock mode \(targetIndex) does not exist")
        }

        if currentAudioModeIndex == targetIndex {
            return .unchanged(targetIndex)
        }

        currentAudioModeIndex = targetIndex
        return .updated(targetIndex)
    }

    func setAudioModeSettings(_ update: BossAppleAudioModeSettingsConfigPatch) -> BossAppleAudioModeSettingsWriteResult {
        let merged = update.merged(with: currentMode.settings)
        let unchanged = merged == currentMode.settings
        replaceMode(at: currentAudioModeIndex) { mode in
            BossAppleAudioModeConfig(
                modeIndex: mode.modeIndex,
                prompt: mode.prompt,
                name: mode.name,
                favorite: mode.favorite,
                userConfigurable: mode.userConfigurable,
                userConfigured: mode.userConfigured,
                settings: merged
            )
        }
        return unchanged ? .unchanged(merged) : .updated(merged)
    }

    func setEqualizer(_ update: BossAppleEqualizerSettingsPatch) -> BossAppleEqualizerWriteResult {
        let updated = BossAppleEqualizerSettings(
            ranges: equalizer.ranges.map { range in
                let nextLevel: Int
                switch range.band {
                case .bass:
                    nextLevel = update.bass ?? range.currentLevel
                case .mid:
                    nextLevel = update.mid ?? range.currentLevel
                case .treble:
                    nextLevel = update.treble ?? range.currentLevel
                case .unknown:
                    nextLevel = range.currentLevel
                }

                return BossAppleEqualizerRangeLevel(
                    band: range.band,
                    currentLevel: nextLevel,
                    minLevel: range.minLevel,
                    maxLevel: range.maxLevel
                )
            }
        )

        let unchanged = updated == equalizer
        equalizer = updated
        return unchanged ? .unchanged(updated) : .updated(updated)
    }

    func setWearDetectionEnabled(_ enabled: Bool) -> BossAppleOnHeadDetectionValue {
        wearDetection = BossAppleOnHeadDetectionValue(
            isEnabled: enabled,
            isAutoPlayEnabled: wearDetection.isAutoPlayEnabled,
            isAutoAnswerEnabled: wearDetection.isAutoAnswerEnabled,
            isAutoTransparencyEnabled: wearDetection.isAutoTransparencyEnabled
        )
        return wearDetection
    }

    func setAutoAware(_ enabled: Bool) -> Bool {
        autoAwareEnabled = enabled
        return enabled
    }

    func setAutoPlayPause(_ enabled: Bool) -> Bool {
        autoPlayPauseEnabled = enabled
        wearDetection = BossAppleOnHeadDetectionValue(
            isEnabled: wearDetection.isEnabled,
            isAutoPlayEnabled: enabled,
            isAutoAnswerEnabled: wearDetection.isAutoAnswerEnabled,
            isAutoTransparencyEnabled: wearDetection.isAutoTransparencyEnabled
        )
        return enabled
    }

    func setAutoAnswer(_ enabled: Bool) -> Bool {
        autoAnswerEnabled = enabled
        wearDetection = BossAppleOnHeadDetectionValue(
            isEnabled: wearDetection.isEnabled,
            isAutoPlayEnabled: wearDetection.isAutoPlayEnabled,
            isAutoAnswerEnabled: enabled,
            isAutoTransparencyEnabled: wearDetection.isAutoTransparencyEnabled
        )
        return enabled
    }

    func setVolumeControl(_ value: BossAppleVolumeControlValue) -> BossAppleVolumeControlStatus {
        volumeControlStatus = BossAppleVolumeControlStatus(
            value: value,
            supportedValues: volumeControlStatus.supportedValues
        )
        return volumeControlStatus
    }

    func setFavorite(modeIndex: Int, isFavorite: Bool) throws -> [Int] {
        guard audioModes.contains(where: { $0.modeIndex == modeIndex }) else {
            throw BossAppleControlError.unsupportedOperation("Mock mode \(modeIndex) does not exist")
        }

        replaceMode(at: modeIndex) { mode in
            BossAppleAudioModeConfig(
                modeIndex: mode.modeIndex,
                prompt: mode.prompt,
                name: mode.name,
                favorite: isFavorite,
                userConfigurable: mode.userConfigurable,
                userConfigured: mode.userConfigured,
                settings: mode.settings
            )
        }

        return audioModes.filter(\.favorite).map(\.modeIndex).sorted()
    }

    func deleteCustomAudioMode(slot: Int) throws -> BossAppleAudioModeConfig {
        guard let mode = audioModes.first(where: { $0.modeIndex == slot }) else {
            throw BossAppleControlError.customAudioModeSlotNotFound(slot)
        }
        guard mode.userConfigurable else {
            throw BossAppleControlError.customAudioModeSlotNotEditable(slot)
        }

        let cleared = BossAppleAudioModeConfig(
            modeIndex: slot,
            prompt: .none,
            name: "None",
            favorite: false,
            userConfigurable: true,
            userConfigured: false,
            settings: mode.deletedSettingsBaseline
        )
        replaceMode(at: slot) { _ in cleared }

        if currentAudioModeIndex == slot {
            currentAudioModeIndex = 1
        }

        return cleared
    }

    func saveCustomAudioMode(
        name: String,
        settings: BossAppleAudioModeSettingsConfig,
        prompt: BossAppleAudioModePrompt,
        slot requestedSlot: Int?
    ) throws -> BossAppleAudioModeConfig {
        let resolvedSlot: Int
        if let requestedSlot {
            resolvedSlot = requestedSlot
        } else if let freeSlot = audioModes.first(where: { $0.userConfigurable && (!$0.userConfigured || $0.name == "None") })?.modeIndex {
            resolvedSlot = freeSlot
        } else {
            throw BossAppleControlError.noFreeCustomAudioModeSlot
        }

        guard let existing = audioModes.first(where: { $0.modeIndex == resolvedSlot }) else {
            throw BossAppleControlError.customAudioModeSlotNotFound(resolvedSlot)
        }
        guard existing.userConfigurable else {
            throw BossAppleControlError.customAudioModeSlotNotEditable(resolvedSlot)
        }

        let saved = BossAppleAudioModeConfig(
            modeIndex: resolvedSlot,
            prompt: prompt,
            name: name,
            favorite: existing.favorite,
            userConfigurable: true,
            userConfigured: true,
            settings: settings
        )
        replaceMode(at: resolvedSlot) { _ in saved }
        currentAudioModeIndex = resolvedSlot
        return saved
    }

    private var currentMode: BossAppleAudioModeConfig {
        audioModes.first(where: { $0.modeIndex == currentAudioModeIndex }) ?? audioModes[0]
    }

    private func deviceSettingsReport() -> BossAppleDeviceSettingsReport {
        BossAppleDeviceSettingsReport(
            wearDetection: BossAppleObservedSetting(value: wearDetection),
            autoAwareEnabled: BossAppleObservedSetting(value: autoAwareEnabled),
            autoPlayPauseEnabled: BossAppleObservedSetting(value: autoPlayPauseEnabled),
            autoAnswerEnabled: BossAppleObservedSetting(value: autoAnswerEnabled),
            volumeControl: BossAppleObservedSetting(value: volumeControlStatus)
        )
    }

    private func replaceMode(
        at modeIndex: Int,
        _ transform: (BossAppleAudioModeConfig) -> BossAppleAudioModeConfig
    ) {
        guard let index = audioModes.firstIndex(where: { $0.modeIndex == modeIndex }) else {
            return
        }
        audioModes[index] = transform(audioModes[index])
    }

    private static func mode(
        modeIndex: Int,
        prompt: BossAppleAudioModePrompt,
        name: String,
        settings: BossAppleAudioModeSettingsConfig,
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

    private static func settings(
        cncLevel: Int,
        spatial: BossAppleSpatialAudioMode,
        windBlock: Bool,
        ancToggle: Bool
    ) -> BossAppleAudioModeSettingsConfig {
        BossAppleAudioModeSettingsConfig(
            cncLevel: cncLevel,
            autoCNCEnabled: false,
            spatialAudioMode: spatial,
            windBlockEnabled: windBlock,
            ancToggleEnabled: ancToggle
        )
    }

    private static func equalizer(bass: Int, mid: Int, treble: Int) -> BossAppleEqualizerSettings {
        BossAppleEqualizerSettings(
            ranges: [
                BossAppleEqualizerRangeLevel(band: .bass, currentLevel: bass, minLevel: -10, maxLevel: 10),
                BossAppleEqualizerRangeLevel(band: .mid, currentLevel: mid, minLevel: -10, maxLevel: 10),
                BossAppleEqualizerRangeLevel(band: .treble, currentLevel: treble, minLevel: -10, maxLevel: 10),
            ]
        )
    }
}

struct MockBossAppDiscoveryProvider: BossAppDiscoveryProviding {
    private let store: MockBossAppDeviceStore

    init(store: MockBossAppDeviceStore = .shared) {
        self.store = store
    }

    func discoverDevices(connection: BossAppleConnectionOptions) async throws -> [BossAppleDiscoveredDevice] {
        await store.discoverDevices(matching: connection)
    }
}

final class MockBossAppSession: @unchecked Sendable, BossAppSessioning {
    private let connection: BossAppleConnectionOptions
    private let store: MockBossAppDeviceStore

    init(
        connection: BossAppleConnectionOptions,
        store: MockBossAppDeviceStore = .shared
    ) {
        self.connection = connection
        self.store = store
    }

    func close() async {}

    func loadWorkspaceSnapshot() async throws -> BossAppleWorkspaceSnapshot {
        try await store.validateConnection(connection)
        return await store.workspaceSnapshot()
    }

    func refreshModeWorkspaceSnapshot() async throws -> BossAppleModeWorkspaceSnapshot {
        try await store.validateConnection(connection)
        return await store.modeWorkspaceSnapshot()
    }

    func modeWorkspaceUpdates(interval: Duration) -> AsyncThrowingStream<BossAppleModeWorkspaceSnapshot, Error> {
        let store = self.store
        let connection = self.connection
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        try await store.validateConnection(connection)
                        continuation.yield(await store.modeWorkspaceSnapshot())
                        try await Task.sleep(for: interval)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func currentAudioMode() async throws -> Int {
        try await store.validateConnection(connection)
        return await store.modeWorkspaceSnapshot().currentAudioModeIndex
    }

    func currentAudioModeUpdateStream() async -> AsyncThrowingStream<Int, Error> {
        try? await store.validateConnection(connection)
        let currentIndex = await store.modeWorkspaceSnapshot().currentAudioModeIndex
        return AsyncThrowingStream { continuation in
            continuation.yield(currentIndex)
            continuation.finish()
        }
    }

    func audioModeSettingsUpdateStream() async -> AsyncThrowingStream<BossAppleAudioModeSettingsConfig, Error> {
        try? await store.validateConnection(connection)
        let settings = await store.modeWorkspaceSnapshot().settings
        return AsyncThrowingStream { continuation in
            continuation.yield(settings)
            continuation.finish()
        }
    }

    func equalizerUpdateStream() async -> AsyncThrowingStream<BossAppleEqualizerSettings, Error> {
        try? await store.validateConnection(connection)
        let equalizer = await store.modeWorkspaceSnapshot().equalizer
        return AsyncThrowingStream { continuation in
            if let equalizer {
                continuation.yield(equalizer)
            }
            continuation.finish()
        }
    }

    func deviceSettingsUpdateStream() async -> AsyncThrowingStream<BossAppleDeviceSettingsReport, Error> {
        try? await store.validateConnection(connection)
        let report = await store.modeWorkspaceSnapshot().deviceSettings
        return AsyncThrowingStream { continuation in
            continuation.yield(report)
            continuation.finish()
        }
    }

    func audioModeCatalogUpdateStream() async -> AsyncThrowingStream<[BossAppleAudioModeConfig], Error> {
        try? await store.validateConnection(connection)
        let modes = await store.configs()
        return AsyncThrowingStream { continuation in
            continuation.yield(modes)
            continuation.finish()
        }
    }

    func supportedAudioModePrompts() async throws -> [BossAppleAudioModePrompt] {
        try await store.validateConnection(connection)
        return await store.prompts()
    }

    func audioModeConfigs() async throws -> [BossAppleAudioModeConfig] {
        try await store.validateConnection(connection)
        return await store.configs()
    }

    func firmwareVersion(port: Int, deviceID: Int) async throws -> BossAppleFirmwareVersionInfo {
        try await store.validateConnection(connection)
        return await store.firmware(port: port)
    }

    func setCurrentAudioMode(index targetIndex: Int, playVoicePrompt: Bool) async throws -> BossAppleCurrentAudioModeWriteResult {
        try await store.validateConnection(connection)
        return try await store.setCurrentAudioMode(index: targetIndex)
    }

    func setAudioModeSettings(_ update: BossAppleAudioModeSettingsConfigPatch) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await store.validateConnection(connection)
        return await store.setAudioModeSettings(update)
    }

    func setEqualizer(_ update: BossAppleEqualizerSettingsPatch) async throws -> BossAppleEqualizerWriteResult {
        try await store.validateConnection(connection)
        return await store.setEqualizer(update)
    }

    func setWearDetectionEnabled(_ enabled: Bool) async throws -> BossAppleOnHeadDetectionValue {
        try await store.validateConnection(connection)
        return await store.setWearDetectionEnabled(enabled)
    }

    func setAutoAware(_ enabled: Bool) async throws -> Bool {
        try await store.validateConnection(connection)
        return await store.setAutoAware(enabled)
    }

    func setAutoPlayPause(_ enabled: Bool) async throws -> Bool {
        try await store.validateConnection(connection)
        return await store.setAutoPlayPause(enabled)
    }

    func setAutoAnswer(_ enabled: Bool) async throws -> Bool {
        try await store.validateConnection(connection)
        return await store.setAutoAnswer(enabled)
    }

    func setVolumeControl(_ value: BossAppleVolumeControlValue) async throws -> BossAppleVolumeControlStatus {
        try await store.validateConnection(connection)
        return await store.setVolumeControl(value)
    }

    func favoriteAudioMode(index: Int) async throws -> [Int] {
        try await store.validateConnection(connection)
        return try await store.setFavorite(modeIndex: index, isFavorite: true)
    }

    func unfavoriteAudioMode(index: Int) async throws -> [Int] {
        try await store.validateConnection(connection)
        return try await store.setFavorite(modeIndex: index, isFavorite: false)
    }

    func deleteCustomAudioMode(slot: Int) async throws -> BossAppleAudioModeConfig {
        try await store.validateConnection(connection)
        return try await store.deleteCustomAudioMode(slot: slot)
    }

    func saveCustomAudioMode(
        name: String,
        settings: BossAppleAudioModeSettingsConfig,
        prompt: BossAppleAudioModePrompt,
        slot requestedSlot: Int?
    ) async throws -> BossAppleAudioModeConfig {
        try await store.validateConnection(connection)
        return try await store.saveCustomAudioMode(
            name: name,
            settings: settings,
            prompt: prompt,
            slot: requestedSlot
        )
    }
}
