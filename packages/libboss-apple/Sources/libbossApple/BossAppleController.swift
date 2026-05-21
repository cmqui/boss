import Foundation
import libboss

func bossBmapErrorCode(from payloadHex: String) -> BmapErrorCode? {
    guard payloadHex.count == 2, let rawValue = UInt8(payloadHex, radix: 16) else {
        return nil
    }
    return BmapErrorCode(rawValue: rawValue)
}

public struct BossAppleConnectionOptions: Sendable, Equatable {
    public let nameContains: String?
    public let identifier: UUID?
    public let scanTimeout: Duration
    public let characteristicPreference: AppleBossCharacteristicPreference

    public init(
        nameContains: String? = nil,
        identifier: UUID? = nil,
        scanTimeout: Duration = .seconds(20),
        characteristicPreference: AppleBossCharacteristicPreference = .automatic
    ) {
        self.nameContains = nameContains
        self.identifier = identifier
        self.scanTimeout = scanTimeout
        self.characteristicPreference = characteristicPreference
    }

    public func withCharacteristicPreference(_ preference: AppleBossCharacteristicPreference) -> BossAppleConnectionOptions {
        BossAppleConnectionOptions(
            nameContains: nameContains,
            identifier: identifier,
            scanTimeout: scanTimeout,
            characteristicPreference: preference
        )
    }

    var securePreferred: BossAppleConnectionOptions {
        guard characteristicPreference == .automatic else {
            return self
        }
        return withCharacteristicPreference(.secure)
    }

    var scanFilter: AppleBossScanFilter {
        AppleBossScanFilter(
            peripheralIdentifier: identifier,
            nameContains: nameContains,
            scanTimeout: scanTimeout
        )
    }
}

public enum BossAppleControlError: Error, Sendable, Equatable, CustomStringConvertible {
    case responseStreamEnded
    case responseTimedOut(seconds: Int64)
    case bmapErrorResponse(context: String, payloadHex: String)
    case unsupportedOperation(String)
    case modeChangeNotObserved(targetIndex: Int, observedIndex: Int)
    case equalizerNotObserved(expected: String, observed: String)
    case settingsConfigNotObserved(expected: String, observed: String)
    case noFreeCustomAudioModeSlot
    case customAudioModeSlotNotEditable(Int)
    case customAudioModeSlotNotFound(Int)

    public var bmapErrorCode: BossAppleBmapErrorCode? {
        guard case .bmapErrorResponse(_, let payloadHex) = self else {
            return nil
        }
        return Self.bmapErrorCode(from: payloadHex)
    }

    public var description: String {
        switch self {
        case .responseStreamEnded:
            return "responseStreamEnded"
        case .responseTimedOut(let seconds):
            return "responseTimedOut(seconds: \(seconds))"
        case .bmapErrorResponse(let context, let payloadHex):
            if let code = bmapErrorCode {
                return "bmapErrorResponse(context: \"\(context)\", payloadHex: \"\(payloadHex)\", code: \(code.description))"
            }
            return "bmapErrorResponse(context: \"\(context)\", payloadHex: \"\(payloadHex)\")"
        case .unsupportedOperation(let message):
            return "unsupportedOperation(\"\(message)\")"
        case .modeChangeNotObserved(let targetIndex, let observedIndex):
            return "modeChangeNotObserved(targetIndex: \(targetIndex), observedIndex: \(observedIndex))"
        case .equalizerNotObserved(let expected, let observed):
            return "equalizerNotObserved(expected: \"\(expected)\", observed: \"\(observed)\")"
        case .settingsConfigNotObserved(let expected, let observed):
            return "settingsConfigNotObserved(expected: \"\(expected)\", observed: \"\(observed)\")"
        case .noFreeCustomAudioModeSlot:
            return "noFreeCustomAudioModeSlot"
        case .customAudioModeSlotNotEditable(let slot):
            return "customAudioModeSlotNotEditable(\(slot))"
        case .customAudioModeSlotNotFound(let slot):
            return "customAudioModeSlotNotFound(\(slot))"
        }
    }

    private static func bmapErrorCode(from payloadHex: String) -> BossAppleBmapErrorCode? {
        bossBmapErrorCode(from: payloadHex)
    }
}

public enum BossAppleEqualizerWriteResult: Sendable, Equatable {
    case unchanged(BossAppleEqualizerSettings)
    case updated(BossAppleEqualizerSettings)
    case verificationInconclusive(BossAppleEqualizerSettings)
}

public enum BossAppleAudioModeSettingsWriteResult: Sendable, Equatable {
    case unchanged(BossAppleAudioModeSettingsConfig)
    case updated(BossAppleAudioModeSettingsConfig)
    case verificationInconclusive(BossAppleAudioModeSettingsConfig)
}

public enum BossAppleCurrentAudioModeWriteResult: Sendable, Equatable {
    case unchanged(Int)
    case updated(Int)
    case verificationInconclusive(targetIndex: Int)
}

public enum BossAppleSettingSource: String, Sendable, Equatable {
    case snapshot
    case compositeSnapshot
    case directGet
}

public enum BossAppleSettingUnavailableReason: Sendable, Equatable, CustomStringConvertible {
    case missingFromSnapshot
    case timedOut
    case responseStreamEnded
    case functionUnsupported
    case operatorUnsupported
    case dataUnavailable
    case insecureTransport
    case unexpectedStreamTermination
    case bmapError(BossAppleBmapErrorCode?)

    public var description: String {
        switch self {
        case .missingFromSnapshot:
            return "missing from snapshot"
        case .timedOut:
            return "timed out"
        case .responseStreamEnded:
            return "response stream ended"
        case .functionUnsupported:
            return "function unsupported"
        case .operatorUnsupported:
            return "operator unsupported"
        case .dataUnavailable:
            return "data unavailable"
        case .insecureTransport:
            return "insecure transport"
        case .unexpectedStreamTermination:
            return "unexpected stream termination"
        case .bmapError(let code):
            if let code {
                return "BMAP error: \(code.description)"
            }
            return "unknown BMAP error"
        }
    }
}

public struct BossAppleObservedSetting<Value: Sendable & Equatable>: Sendable, Equatable {
    public let value: Value?
    public let source: BossAppleSettingSource?
    public let unavailableReason: BossAppleSettingUnavailableReason?

    public init(
        value: Value?,
        source: BossAppleSettingSource? = nil,
        unavailableReason: BossAppleSettingUnavailableReason? = nil
    ) {
        self.value = value
        self.source = source
        self.unavailableReason = unavailableReason
    }

    public var isAvailable: Bool {
        value != nil
    }
}

public struct BossAppleDeviceSettingsReport: Sendable, Equatable {
    public let wearDetection: BossAppleObservedSetting<BossAppleOnHeadDetectionValue>
    public let autoAwareEnabled: BossAppleObservedSetting<Bool>
    public let autoPlayPauseEnabled: BossAppleObservedSetting<Bool>
    public let autoAnswerEnabled: BossAppleObservedSetting<Bool>
    public let volumeControl: BossAppleObservedSetting<BossAppleVolumeControlStatus>

    public init(
        wearDetection: BossAppleObservedSetting<BossAppleOnHeadDetectionValue>,
        autoAwareEnabled: BossAppleObservedSetting<Bool>,
        autoPlayPauseEnabled: BossAppleObservedSetting<Bool>,
        autoAnswerEnabled: BossAppleObservedSetting<Bool>,
        volumeControl: BossAppleObservedSetting<BossAppleVolumeControlStatus>
    ) {
        self.wearDetection = wearDetection
        self.autoAwareEnabled = autoAwareEnabled
        self.autoPlayPauseEnabled = autoPlayPauseEnabled
        self.autoAnswerEnabled = autoAnswerEnabled
        self.volumeControl = volumeControl
    }

    public var settings: BossAppleDeviceSettings {
        BossAppleDeviceSettings(
            wearDetection: wearDetection.value,
            autoAwareEnabled: autoAwareEnabled.value,
            autoPlayPauseEnabled: autoPlayPauseEnabled.value,
            autoAnswerEnabled: autoAnswerEnabled.value,
            volumeControl: volumeControl.value
        )
    }
}

public struct BossAppleController: Sendable {
    public let connection: BossAppleConnectionOptions

    public init(connection: BossAppleConnectionOptions = BossAppleConnectionOptions()) {
        self.connection = connection
    }

    public func withConnectedLink<T: Sendable>(
        _ operation: @escaping @Sendable (BossAppleLink) async throws -> T
    ) async throws -> T {
        try await Self.withConnectedLink(connection, operation: operation)
    }

    public func bootstrap() async throws -> BossAppleBootstrappedDevice {
        try await withRustPreferred(
            { try await $0.bootstrap() },
            fallback: { try await self.swiftFallbackBootstrap() }
        )
    }

    public func settingsSnapshot() async throws -> BossAppleSettingsSnapshot {
        try await withRustPreferred(
            { try await $0.settingsSnapshot() },
            fallback: { try await self.swiftFallbackSettingsSnapshot() }
        )
    }

    public func deviceSettings() async throws -> BossAppleDeviceSettings {
        try await deviceSettingsReport().settings
    }

    public func deviceSettingsReport() async throws -> BossAppleDeviceSettingsReport {
        try await withRustPreferred(
            { try await $0.deviceSettingsReport() },
            fallback: { try await self.swiftFallbackDeviceSettingsReport() }
        )
    }

    public func standbyTimer() async throws -> BossAppleStandbyTimerValue? {
        try await withRustPreferred(
            { try await $0.standbyTimer() },
            fallback: { try await self.swiftFallbackStandbyTimer() }
        )
    }

    public func setStandbyTimer(minutes: Int) async throws -> BossAppleStandbyTimerValue {
        try await withRustPreferred(
            { try await $0.setStandbyTimer(minutes: minutes) },
            fallback: { try await self.swiftFallbackSetStandbyTimer(minutes: minutes) }
        )
    }

    public func autoAware() async throws -> Bool? {
        try await withRustPreferred(
            { try await $0.autoAware() },
            fallback: { try await self.swiftFallbackAutoAware() }
        )
    }

    public func setAutoAware(_ enabled: Bool) async throws -> Bool {
        try await withRustPreferred(
            { try await $0.setAutoAware(enabled) },
            fallback: { try await self.swiftFallbackSetAutoAware(enabled) }
        )
    }

    public func onHeadDetection() async throws -> BossAppleOnHeadDetectionValue? {
        try await withRustPreferred(
            { try await $0.onHeadDetection() },
            fallback: { try await self.swiftFallbackOnHeadDetection() }
        )
    }

    public func wearDetection() async throws -> BossAppleOnHeadDetectionValue? {
        try await onHeadDetection()
    }

    public func setWearDetection(_ value: BossAppleOnHeadDetectionValue) async throws -> BossAppleOnHeadDetectionValue {
        try await withRustPreferred(
            { try await $0.setWearDetection(value) },
            fallback: { try await self.swiftFallbackSetWearDetection(value) }
        )
    }

    public func setWearDetection(_ patch: BossAppleOnHeadDetectionPatch) async throws -> BossAppleOnHeadDetectionValue {
        try await withRustPreferred(
            { try await $0.setWearDetection(patch) },
            fallback: { try await self.swiftFallbackSetWearDetection(patch) }
        )
    }

    public func updateWearDetectionRelatedSettings(_ patch: BossAppleOnHeadDetectionPatch) async throws -> BossAppleDeviceSettingsReport {
        try await withRustPreferred(
            { try await $0.updateWearDetectionRelatedSettings(patch) },
            fallback: { try await self.swiftFallbackUpdateWearDetectionRelatedSettings(patch) }
        )
    }

    public func setWearDetectionEnabled(_ enabled: Bool) async throws -> BossAppleOnHeadDetectionValue {
        try await withRustPreferred(
            { try await $0.setWearDetectionEnabled(enabled) },
            fallback: { try await self.swiftFallbackSetWearDetectionEnabled(enabled) }
        )
    }

    public func autoPlayPause() async throws -> Bool? {
        try await withRustPreferred(
            { try await $0.autoPlayPause() },
            fallback: { try await self.swiftFallbackAutoPlayPause() }
        )
    }

    public func setAutoPlayPause(_ enabled: Bool) async throws -> Bool {
        try await withRustPreferred(
            { try await $0.setAutoPlayPause(enabled) },
            fallback: { try await self.swiftFallbackSetAutoPlayPause(enabled) }
        )
    }

    public func autoAnswer() async throws -> Bool? {
        try await withRustPreferred(
            { try await $0.autoAnswer() },
            fallback: { try await self.swiftFallbackAutoAnswer() }
        )
    }

    public func setAutoAnswer(_ enabled: Bool) async throws -> Bool {
        try await withRustPreferred(
            { try await $0.setAutoAnswer(enabled) },
            fallback: { try await self.swiftFallbackSetAutoAnswer(enabled) }
        )
    }

    public func volumeControl() async throws -> BossAppleVolumeControlStatus? {
        try await withRustPreferred(
            { try await $0.volumeControl() },
            fallback: { try await self.swiftFallbackVolumeControl() }
        )
    }

    public func setVolumeControl(_ value: BossAppleVolumeControlValue) async throws -> BossAppleVolumeControlStatus {
        try await withRustPreferred(
            { try await $0.setVolumeControl(value) },
            fallback: { try await self.swiftFallbackSetVolumeControl(value) }
        )
    }

    public func equalizer() async throws -> BossAppleEqualizerSettings? {
        try await withRustPreferred(
            { try await $0.equalizer() },
            fallback: { try await self.swiftFallbackEqualizer() }
        )
    }

    public func setEqualizer(
        _ update: BossAppleEqualizerSettingsPatch
    ) async throws -> BossAppleEqualizerWriteResult {
        try await withRustPreferred(
            { try await $0.setEqualizer(update) },
            fallback: { try await self.swiftFallbackSetEqualizer(update) }
        )
    }

    public func setEqualizerBass(_ level: Int) async throws -> BossAppleEqualizerWriteResult {
        try await setEqualizer(BossAppleEqualizerSettingsPatch(bass: level))
    }

    public func setEqualizerMid(_ level: Int) async throws -> BossAppleEqualizerWriteResult {
        try await setEqualizer(BossAppleEqualizerSettingsPatch(mid: level))
    }

    public func setEqualizerTreble(_ level: Int) async throws -> BossAppleEqualizerWriteResult {
        try await setEqualizer(BossAppleEqualizerSettingsPatch(treble: level))
    }

    public func audioModes() async throws -> [BossAppleAudioModeInfo] {
        try await audioModeConfigs().map(\.info)
    }

    public func audioModeConfigs() async throws -> [BossAppleAudioModeConfig] {
        try await withRustPreferred(
            { try await $0.audioModeConfigs() },
            fallback: { try await self.swiftFallbackAudioModeConfigs() }
        )
    }

    public func displayableAudioModes() async throws -> [BossAppleAudioModeInfo] {
        try await audioModes().filter { mode in
            !(mode.userConfigurable && !mode.userConfigured && mode.name == "None")
        }
    }

    public func audioModeCapabilities() async throws -> BossAppleAudioModesCapabilities {
        try await withRustPreferred(
            { try await $0.audioModeCapabilities() },
            fallback: { try await self.swiftFallbackAudioModeCapabilities() }
        )
    }

    public func supportedAudioModePrompts() async throws -> [BossAppleAudioModePrompt] {
        try await withRustPreferred(
            { try await $0.supportedAudioModePrompts() },
            fallback: { try await self.swiftFallbackSupportedAudioModePrompts() }
        )
    }

    public func favoriteAudioModeIndices() async throws -> [Int] {
        try await withRustPreferred(
            { try await $0.favoriteAudioModeIndices() },
            fallback: { try await self.swiftFallbackFavoriteAudioModeIndices() }
        )
    }

    public func setFavoriteAudioModeIndices(
        _ indices: [Int],
        numberOfModes requestedNumberOfModes: Int? = nil
    ) async throws -> [Int] {
        try await withRustPreferred(
            {
                try await $0.setFavoriteAudioModeIndices(
                    indices,
                    numberOfModes: requestedNumberOfModes
                )
            },
            fallback: {
                try await self.swiftFallbackSetFavoriteAudioModeIndices(
                    indices,
                    numberOfModes: requestedNumberOfModes
                )
            }
        )
    }

    public func setAudioModeFavorite(index: Int, isFavorite: Bool) async throws -> [Int] {
        try await withRustPreferred(
            {
                if isFavorite {
                    return try await $0.favoriteAudioMode(index: index)
                }
                return try await $0.unfavoriteAudioMode(index: index)
            },
            fallback: { try await self.swiftFallbackSetAudioModeFavorite(index: index, isFavorite: isFavorite) }
        )
    }

    public func favoriteAudioMode(index: Int) async throws -> [Int] {
        try await setAudioModeFavorite(index: index, isFavorite: true)
    }

    public func unfavoriteAudioMode(index: Int) async throws -> [Int] {
        try await setAudioModeFavorite(index: index, isFavorite: false)
    }

    public func saveCustomAudioMode(
        name: String,
        settings: BossAppleAudioModeSettingsConfig,
        prompt: BossAppleAudioModePrompt = .none,
        slot requestedSlot: Int? = nil
    ) async throws -> BossAppleAudioModeConfig {
        try await withRustPreferred(
            {
                try await $0.saveCustomAudioMode(
                    name: name,
                    settings: settings,
                    prompt: prompt,
                    slot: requestedSlot
                )
            },
            fallback: {
                try await self.swiftFallbackSaveCustomAudioMode(
                    name: name,
                    settings: settings,
                    prompt: prompt,
                    slot: requestedSlot
                )
            }
        )
    }

    public func renameCustomAudioMode(
        slot: Int,
        name: String,
        prompt: BossAppleAudioModePrompt? = nil
    ) async throws -> BossAppleAudioModeConfig {
        try await withRustPreferred(
            {
                try await $0.renameCustomAudioMode(
                    slot: slot,
                    name: name,
                    prompt: prompt
                )
            },
            fallback: { try await self.swiftFallbackRenameCustomAudioMode(slot: slot, name: name, prompt: prompt) }
        )
    }

    public func updateCustomAudioMode(
        slot: Int,
        name: String? = nil,
        settings: BossAppleAudioModeSettingsConfig? = nil,
        prompt: BossAppleAudioModePrompt? = nil
    ) async throws -> BossAppleAudioModeConfig {
        try await withRustPreferred(
            {
                try await $0.updateCustomAudioMode(
                    slot: slot,
                    name: name,
                    settings: settings,
                    prompt: prompt
                )
            },
            fallback: {
                try await self.swiftFallbackUpdateCustomAudioMode(
                    slot: slot,
                    name: name,
                    settings: settings,
                    prompt: prompt
                )
            }
        )
    }

    public func deleteCustomAudioMode(slot: Int) async throws -> BossAppleAudioModeConfig {
        try await withRustPreferred(
            { try await $0.deleteCustomAudioMode(slot: slot) },
            fallback: { try await self.swiftFallbackDeleteCustomAudioMode(slot: slot) }
        )
    }

    public func currentAudioMode() async throws -> Int {
        try await withRustPreferred(
            { try await $0.currentAudioMode() },
            fallback: { try await self.swiftFallbackCurrentAudioMode() }
        )
    }

    public func setCurrentAudioMode(index targetIndex: Int, playVoicePrompt: Bool = false) async throws -> BossAppleCurrentAudioModeWriteResult {
        try await withRustPreferred(
            {
                try await $0.setCurrentAudioMode(
                    index: targetIndex,
                    playVoicePrompt: playVoicePrompt
                )
            },
            fallback: {
                try await self.swiftFallbackSetCurrentAudioMode(
                    index: targetIndex,
                    playVoicePrompt: playVoicePrompt
                )
            }
        )
    }

    public func audioModeSettings() async throws -> BossAppleAudioModeSettingsConfig {
        try await withRustPreferred(
            { try await $0.audioModeSettings() },
            fallback: { try await self.swiftFallbackAudioModeSettings() }
        )
    }

    public func setAudioModeSettings(
        _ update: BossAppleAudioModeSettingsConfigPatch
    ) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await withRustPreferred(
            { try await $0.setAudioModeSettings(update) },
            fallback: { try await self.swiftFallbackSetAudioModeSettings(update) }
        )
    }

    public func setCNCLevel(_ level: Int) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await setAudioModeSettings(BossAppleAudioModeSettingsConfigPatch(cncLevel: level))
    }

    public func setSpatialAudioMode(_ mode: BossAppleSpatialAudioMode) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await setAudioModeSettings(BossAppleAudioModeSettingsConfigPatch(spatialAudioMode: mode))
    }

    public func setWindBlockEnabled(_ enabled: Bool) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await setAudioModeSettings(BossAppleAudioModeSettingsConfigPatch(windBlockEnabled: enabled))
    }

    public func setANCEnabled(_ enabled: Bool) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await setAudioModeSettings(BossAppleAudioModeSettingsConfigPatch(ancToggleEnabled: enabled))
    }

    private func withRustPreferred<T: Sendable>(
        _ rustOperation: @escaping @Sendable (BossAppleSession) async throws -> T,
        fallback: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard BossRustSessionBridge.shared != nil else {
            return try await fallback()
        }
        return try await rustOperation(BossAppleSession(connection: connection))
    }

    func writeCustomAudioMode(
        slot: Int,
        name: String,
        settings: BossAppleAudioModeSettingsConfig,
        prompt: BossAppleAudioModePrompt
    ) async throws -> BossAppleAudioModeConfig {
        try await Self.withConnectedLinkRetrying(connection.securePreferred, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.sendAudioModeConfigSetGet(
                modeIndex: slot,
                prompt: prompt,
                name: name,
                settings: settings,
                on: link,
                timeout: .seconds(5)
            )
        }
    }
}

private extension BossAppleController {
    func swiftFallbackBootstrap() async throws -> BootstrappedDevice {
        try await withConnectedLink { link in
            try await BootstrapSession(link: link.asCoreLink()).bootstrap()
        }
    }

    func swiftFallbackSettingsSnapshot() async throws -> BossSettingsSnapshot {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.awaitSettingsSnapshot(on: link, timeout: .seconds(5))
        }
    }

    func swiftFallbackDeviceSettingsReport() async throws -> BossAppleDeviceSettingsReport {
        let secureReadConnection = connection.securePreferred
        return try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            let snapshot = try await Self.awaitSettingsSnapshot(on: link, timeout: .seconds(5))
            let wearDetection = try await Self.observedWearDetection(
                from: snapshot,
                fallbackConnection: secureReadConnection,
                timeout: .seconds(5)
            )
            let autoAwareEnabled = try await Self.observedEnabledSetting(
                functionRaw: BossSettingsCodec.autoAwareFunctionRaw,
                snapshotValue: try snapshot.autoAware(),
                snapshotPacketExists: snapshot.packet(functionRaw: BossSettingsCodec.autoAwareFunctionRaw) != nil,
                fallbackConnection: secureReadConnection,
                timeout: .seconds(5)
            )
            let autoPlayPauseEnabled = try await Self.observedEnabledSetting(
                functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw,
                snapshotValue: try snapshot.autoPlayPause(),
                snapshotPacketExists: snapshot.packet(functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw) != nil,
                fallbackConnection: secureReadConnection,
                timeout: .seconds(5)
            )
            let autoAnswerEnabled = try await Self.observedAutoAnswer(
                from: snapshot,
                fallbackConnection: secureReadConnection,
                timeout: .seconds(5)
            )
            let volumeControl = try await Self.observedVolumeControl(
                from: snapshot,
                fallbackConnection: secureReadConnection,
                timeout: .seconds(5)
            )

            return BossAppleDeviceSettingsReport(
                wearDetection: wearDetection,
                autoAwareEnabled: autoAwareEnabled,
                autoPlayPauseEnabled: autoPlayPauseEnabled,
                autoAnswerEnabled: autoAnswerEnabled,
                volumeControl: volumeControl
            )
        }
    }

    func swiftFallbackStandbyTimer() async throws -> BossStandbyTimerValue? {
        if let value = try await swiftFallbackSettingsSnapshot().standbyTimer() {
            return value
        }
        return try await Self.readStandbyTimer(connection: connection.securePreferred)
    }

    func swiftFallbackSetStandbyTimer(minutes: Int) async throws -> BossStandbyTimerValue {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            let response = try await Self.sendAndAwaitSameFunction(
                packet: try BossSettingsCodec.standbyTimerSetGetPacket(minutes: minutes),
                on: link,
                timeout: .seconds(5)
            )
            return try BossSettingsCodec.parseStandbyTimer(from: response)
        }
    }

    func swiftFallbackAutoAware() async throws -> Bool? {
        if let value = try await swiftFallbackSettingsSnapshot().autoAware() {
            return value
        }
        return try await Self.readEnabledSetting(
            functionRaw: BossSettingsCodec.autoAwareFunctionRaw,
            connection: connection.securePreferred
        )
    }

    func swiftFallbackSetAutoAware(_ enabled: Bool) async throws -> Bool {
        try await Self.setEnabledSetting(
            functionRaw: BossSettingsCodec.autoAwareFunctionRaw,
            enabled: enabled,
            connection: connection.securePreferred
        )
    }

    func swiftFallbackOnHeadDetection() async throws -> BossOnHeadDetectionValue? {
        if let value = try await swiftFallbackSettingsSnapshot().onHeadDetection() {
            return value
        }
        return try await Self.readOnHeadDetection(connection: connection.securePreferred)
    }

    func swiftFallbackSetWearDetection(_ value: BossOnHeadDetectionValue) async throws -> BossOnHeadDetectionValue {
        try await Self.withConnectedLinkRetrying(connection.securePreferred, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            let response = try await Self.sendAndAwaitSameFunction(
                packet: BossSettingsCodec.onHeadDetectionSetGetPacket(value),
                on: link,
                timeout: .seconds(5)
            )
            return try BossSettingsCodec.parseOnHeadDetection(from: response)
        }
    }

    func swiftFallbackSetWearDetection(_ patch: BossOnHeadDetectionPatch) async throws -> BossOnHeadDetectionValue {
        guard !patch.isEmpty else {
            guard let current = try await swiftFallbackOnHeadDetection() else {
                throw BossAppleControlError.unsupportedOperation("Wear detection is not exposed by this device/session")
            }
            return current
        }

        do {
            let current = try await swiftFallbackOnHeadDetection() ?? BossOnHeadDetectionValue(
                isEnabled: false,
                isAutoPlayEnabled: nil,
                isAutoAnswerEnabled: nil,
                isAutoTransparencyEnabled: nil
            )
            return try await swiftFallbackSetWearDetection(patch.merged(with: current))
        } catch {
            guard Self.isCompositeInPlaceDetectionUnsupported(error) else {
                throw error
            }
        }

        guard patch.isEnabled == nil else {
            throw BossAppleControlError.unsupportedOperation(
                "This device does not expose the master wear-detection toggle over BMAP; only auto-play, auto-answer, and auto-transparency subsettings are writable"
            )
        }

        throw BossAppleControlError.unsupportedOperation(
            "This device does not expose a composite wear-detection state over BMAP; use updateWearDetectionRelatedSettings(_:) for subordinate auto-play, auto-answer, and auto-transparency writes"
        )
    }

    func swiftFallbackUpdateWearDetectionRelatedSettings(
        _ patch: BossOnHeadDetectionPatch
    ) async throws -> BossAppleDeviceSettingsReport {
        if patch.isEmpty {
            return try await swiftFallbackDeviceSettingsReport()
        }
        do {
            let current = try await swiftFallbackOnHeadDetection() ?? BossOnHeadDetectionValue(
                isEnabled: false,
                isAutoPlayEnabled: nil,
                isAutoAnswerEnabled: nil,
                isAutoTransparencyEnabled: nil
            )
            _ = try await swiftFallbackSetWearDetection(patch.merged(with: current))
            return try await swiftFallbackDeviceSettingsReport()
        } catch {
            guard Self.isCompositeInPlaceDetectionUnsupported(error) else {
                throw error
            }
        }

        guard patch.isEnabled == nil else {
            throw BossAppleControlError.unsupportedOperation(
                "This device does not expose the master wear-detection toggle over BMAP; only auto-play, auto-answer, and auto-transparency subsettings are writable"
            )
        }

        if let enabled = patch.isAutoPlayEnabled {
            _ = try await swiftFallbackSetAutoPlayPause(enabled)
        }
        if let enabled = patch.isAutoAnswerEnabled {
            _ = try await swiftFallbackSetAutoAnswer(enabled)
        }
        if let enabled = patch.isAutoTransparencyEnabled {
            do {
                _ = try await swiftFallbackSetAutoAware(enabled)
            } catch {
                if Self.isCompositeInPlaceDetectionUnsupported(error) || Self.isUnavailableSettingReadError(error) {
                    throw BossAppleControlError.unsupportedOperation(
                        "Auto-transparency is not exposed by this device/session over the standalone auto-aware setting path"
                    )
                }
                throw error
            }
        }

        return try await swiftFallbackDeviceSettingsReport()
    }

    func swiftFallbackSetWearDetectionEnabled(_ enabled: Bool) async throws -> BossOnHeadDetectionValue {
        try await swiftFallbackSetWearDetection(BossOnHeadDetectionPatch(isEnabled: enabled))
    }

    func swiftFallbackAutoPlayPause() async throws -> Bool? {
        if let value = try await swiftFallbackSettingsSnapshot().autoPlayPause() {
            return value
        }
        return try await Self.readEnabledSetting(
            functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw,
            connection: connection.securePreferred
        )
    }

    func swiftFallbackSetAutoPlayPause(_ enabled: Bool) async throws -> Bool {
        try await Self.setEnabledSetting(
            functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw,
            enabled: enabled,
            connection: connection
        )
    }

    func swiftFallbackAutoAnswer() async throws -> Bool? {
        if let value = try await swiftFallbackSettingsSnapshot().autoAnswer() {
            return value
        }
        return try await Self.readEnabledSetting(
            functionRaw: BossSettingsCodec.autoAnswerFunctionRaw,
            connection: connection.securePreferred
        )
    }

    func swiftFallbackSetAutoAnswer(_ enabled: Bool) async throws -> Bool {
        try await Self.setEnabledSetting(
            functionRaw: BossSettingsCodec.autoAnswerFunctionRaw,
            enabled: enabled,
            connection: connection
        )
    }

    func swiftFallbackVolumeControl() async throws -> BossVolumeControlStatus? {
        if let value = try await swiftFallbackSettingsSnapshot().volumeControl() {
            return value
        }
        return try await Self.readVolumeControl(connection: connection.securePreferred)
    }

    func swiftFallbackSetVolumeControl(_ value: BossVolumeControlValue) async throws -> BossVolumeControlStatus {
        try await Self.withConnectedLinkRetrying(connection.securePreferred, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            let response = try await Self.sendAndAwaitSameFunction(
                packet: BossSettingsCodec.settingsPacket(
                    functionRaw: BossSettingsCodec.volumeControlFunctionRaw,
                    operatorValue: .setGet,
                    payload: Data([value.rawValue])
                ),
                on: link,
                timeout: .seconds(5)
            )
            return try BossAudioModesCodec.parseVolumeControlStatus(from: response)
        }
    }

    func swiftFallbackEqualizer() async throws -> BossEqualizerSettings? {
        if let value = try await swiftFallbackSettingsSnapshot().equalizer() {
            return value
        }
        return try await Self.readEqualizerAfterReconnect(connection: connection.securePreferred)
    }

    func swiftFallbackSetEqualizer(
        _ update: BossEqualizerSettingsPatch
    ) async throws -> BossAppleEqualizerWriteResult {
        try await Self.setEqualizerWithVerification(update, connection: connection.securePreferred)
    }

    func swiftFallbackAudioModeConfigs() async throws -> [BossAudioModeConfig] {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.awaitAudioModeConfigs(on: link, timeout: .seconds(30))
        }
    }

    func swiftFallbackAudioModeCapabilities() async throws -> BossAudioModesCapabilities {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.requiredAudioModeCapabilities(on: link, timeout: .seconds(5))
        }
    }

    func swiftFallbackSupportedAudioModePrompts() async throws -> [BossAudioModePrompt] {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            let response = try await Self.sendAndAwaitSameFunction(
                packet: BossAudioModesCodec.namesSupportedGetPacket(),
                on: link,
                timeout: .seconds(5)
            )
            return try BossAudioModesCodec.parseSupportedPrompts(from: response)
        }
    }

    func swiftFallbackFavoriteAudioModeIndices() async throws -> [Int] {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.requiredFavoriteAudioModeIndices(on: link, timeout: .seconds(5))
        }
    }

    func swiftFallbackSetFavoriteAudioModeIndices(
        _ indices: [Int],
        numberOfModes requestedNumberOfModes: Int? = nil
    ) async throws -> [Int] {
        let numberOfModes: Int
        if let requestedNumberOfModes {
            numberOfModes = requestedNumberOfModes
        } else {
            numberOfModes = try await swiftFallbackAudioModeCapabilities().totalModes
        }

        return try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.sendAudioModeFavoritesSetGet(
                numberOfModes: numberOfModes,
                favoriteModeIndices: indices,
                on: link,
                timeout: .seconds(5)
            )
        }
    }

    func swiftFallbackSetAudioModeFavorite(index: Int, isFavorite: Bool) async throws -> [Int] {
        let numberOfModes = try await swiftFallbackAudioModeCapabilities().totalModes
        var favorites = Set(try await swiftFallbackFavoriteAudioModeIndices())
        if isFavorite {
            favorites.insert(index)
        } else {
            favorites.remove(index)
        }
        return try await swiftFallbackSetFavoriteAudioModeIndices(
            Array(favorites).sorted(),
            numberOfModes: numberOfModes
        )
    }

    func swiftFallbackSaveCustomAudioMode(
        name: String,
        settings: BossAudioModeSettingsConfig,
        prompt: BossAudioModePrompt = .none,
        slot requestedSlot: Int? = nil
    ) async throws -> BossAudioModeConfig {
        let configs = try await swiftFallbackAudioModeConfigs()
        let slot: Int
        if let requestedSlot {
            guard configs.first(where: { $0.modeIndex == requestedSlot })?.userConfigurable == true else {
                throw BossAppleControlError.customAudioModeSlotNotEditable(requestedSlot)
            }
            slot = requestedSlot
        } else {
            guard let freeSlot = Self.firstFreeCustomAudioModeSlot(in: configs) else {
                throw BossAppleControlError.noFreeCustomAudioModeSlot
            }
            slot = freeSlot
        }
        return try await writeCustomAudioMode(slot: slot, name: name, settings: settings, prompt: prompt)
    }

    func swiftFallbackRenameCustomAudioMode(
        slot: Int,
        name: String,
        prompt: BossAudioModePrompt? = nil
    ) async throws -> BossAudioModeConfig {
        let configs = try await swiftFallbackAudioModeConfigs()
        guard let existing = configs.first(where: { $0.modeIndex == slot }) else {
            throw BossAppleControlError.customAudioModeSlotNotFound(slot)
        }
        guard existing.userConfigurable else {
            throw BossAppleControlError.customAudioModeSlotNotEditable(slot)
        }
        return try await writeCustomAudioMode(
            slot: slot,
            name: name,
            settings: existing.settings,
            prompt: prompt ?? existing.prompt
        )
    }

    func swiftFallbackUpdateCustomAudioMode(
        slot: Int,
        name: String? = nil,
        settings: BossAudioModeSettingsConfig? = nil,
        prompt: BossAudioModePrompt? = nil
    ) async throws -> BossAudioModeConfig {
        let configs = try await swiftFallbackAudioModeConfigs()
        guard let existing = configs.first(where: { $0.modeIndex == slot }) else {
            throw BossAppleControlError.customAudioModeSlotNotFound(slot)
        }
        guard existing.userConfigurable else {
            throw BossAppleControlError.customAudioModeSlotNotEditable(slot)
        }
        return try await writeCustomAudioMode(
            slot: slot,
            name: name ?? existing.name,
            settings: settings ?? existing.settings,
            prompt: prompt ?? existing.prompt
        )
    }

    func swiftFallbackDeleteCustomAudioMode(slot: Int) async throws -> BossAudioModeConfig {
        let configs = try await swiftFallbackAudioModeConfigs()
        guard let existing = configs.first(where: { $0.modeIndex == slot }) else {
            throw BossAppleControlError.customAudioModeSlotNotFound(slot)
        }
        guard existing.userConfigurable else {
            throw BossAppleControlError.customAudioModeSlotNotEditable(slot)
        }

        if existing.favorite {
            _ = try await swiftFallbackSetAudioModeFavorite(index: slot, isFavorite: false)
        }

        return try await writeCustomAudioMode(
            slot: slot,
            name: "",
            settings: existing.deletedSettingsBaseline,
            prompt: .none
        )
    }

    func swiftFallbackCurrentAudioMode() async throws -> Int {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.requiredCurrentAudioMode(on: link, timeout: .seconds(5))
        }
    }

    func swiftFallbackSetCurrentAudioMode(
        index targetIndex: Int,
        playVoicePrompt: Bool = false
    ) async throws -> BossAppleCurrentAudioModeWriteResult {
        let commandConnection = connection.securePreferred
        return try await Self.withConnectedLinkRetrying(commandConnection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            if let currentIndex = try await Self.currentAudioModeIfAvailable(on: link, timeout: .seconds(2)),
               currentIndex == targetIndex {
                return .unchanged(currentIndex)
            }

            do {
                let response = try await Self.sendAndAwaitSameFunction(
                    packet: BossAudioModesCodec.currentModeStartPacket(modeIndex: targetIndex, playVoicePrompt: playVoicePrompt),
                    on: link,
                    timeout: .seconds(5)
                )
                if response.operator == .result {
                    if let responseModeIndex = response.payload.first {
                        return .updated(Int(responseModeIndex))
                    }
                    let verified = try await Self.verifyCurrentAudioMode(
                        on: link,
                        targetIndex: targetIndex,
                        timeoutPerAttempt: .seconds(2),
                        attempts: 3,
                        retryDelay: .milliseconds(500)
                    )
                    return .updated(verified)
                }
                return .updated(try BossAudioModesCodec.parseCurrentMode(from: response))
            } catch {
                guard Self.shouldFallbackForAudioModeWrite(error) else {
                    throw error
                }
                do {
                    let verified = try await Self.verifyCurrentAudioMode(
                        on: link,
                        targetIndex: targetIndex,
                        timeoutPerAttempt: .seconds(3),
                        attempts: 4,
                        retryDelay: .seconds(1),
                        fallbackError: error
                    )
                    return .updated(verified)
                } catch {
                    do {
                        let verified = try await Self.verifyCurrentAudioModeAfterReconnect(
                            connection: connection,
                            targetIndex: targetIndex,
                            fallbackError: error
                        )
                        return .updated(verified)
                    } catch let reconnectError {
                        if Self.isVerificationInconclusiveError(reconnectError) {
                            return .verificationInconclusive(targetIndex: targetIndex)
                        }
                        throw reconnectError
                    }
                }
            }
        }
    }

    func swiftFallbackAudioModeSettings() async throws -> BossAudioModeSettingsConfig {
        try await Self.readAudioModeSettingsConfigAfterReconnect(connection: connection.securePreferred)
    }

    func swiftFallbackSetAudioModeSettings(
        _ update: BossAudioModeSettingsConfigPatch
    ) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await Self.setAudioModeSettingsConfigWithVerification(update, connection: connection.securePreferred)
    }
}
