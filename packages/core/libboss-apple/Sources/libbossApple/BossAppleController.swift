import Foundation

func bossBmapErrorCode(from payloadHex: String) -> BossAppleBmapErrorCode? {
    guard payloadHex.count == 2, let rawValue = UInt8(payloadHex, radix: 16) else {
        return nil
    }
    return BossAppleBmapErrorCode(rawValue: rawValue)
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

    public func bootstrap() async throws -> BossAppleBootstrappedDevice {
        try await BossAppleSession(connection: connection).bootstrap()
    }

    func settingsSnapshot() async throws -> BossAppleSettingsSnapshot {
        try await BossAppleSession(connection: connection).settingsSnapshot()
    }

    public func deviceSettings() async throws -> BossAppleDeviceSettings {
        try await deviceSettingsReport().settings
    }

    public func deviceSettingsReport() async throws -> BossAppleDeviceSettingsReport {
        try await BossAppleSession(connection: connection).deviceSettingsReport()
    }

    public func standbyTimer() async throws -> BossAppleStandbyTimerValue? {
        try await BossAppleSession(connection: connection).standbyTimer()
    }

    public func setStandbyTimer(minutes: Int) async throws -> BossAppleStandbyTimerValue {
        try await BossAppleSession(connection: connection).setStandbyTimer(minutes: minutes)
    }

    public func autoAware() async throws -> Bool? {
        try await BossAppleSession(connection: connection).autoAware()
    }

    public func setAutoAware(_ enabled: Bool) async throws -> Bool {
        try await BossAppleSession(connection: connection).setAutoAware(enabled)
    }

    public func onHeadDetection() async throws -> BossAppleOnHeadDetectionValue? {
        try await BossAppleSession(connection: connection).onHeadDetection()
    }

    public func wearDetection() async throws -> BossAppleOnHeadDetectionValue? {
        try await onHeadDetection()
    }

    public func setWearDetection(_ value: BossAppleOnHeadDetectionValue) async throws -> BossAppleOnHeadDetectionValue {
        try await BossAppleSession(connection: connection).setWearDetection(value)
    }

    public func setWearDetection(_ patch: BossAppleOnHeadDetectionPatch) async throws -> BossAppleOnHeadDetectionValue {
        try await BossAppleSession(connection: connection).setWearDetection(patch)
    }

    public func updateWearDetectionRelatedSettings(_ patch: BossAppleOnHeadDetectionPatch) async throws -> BossAppleDeviceSettingsReport {
        try await BossAppleSession(connection: connection).updateWearDetectionRelatedSettings(patch)
    }

    public func setWearDetectionEnabled(_ enabled: Bool) async throws -> BossAppleOnHeadDetectionValue {
        try await BossAppleSession(connection: connection).setWearDetectionEnabled(enabled)
    }

    public func autoPlayPause() async throws -> Bool? {
        try await BossAppleSession(connection: connection).autoPlayPause()
    }

    public func setAutoPlayPause(_ enabled: Bool) async throws -> Bool {
        try await BossAppleSession(connection: connection).setAutoPlayPause(enabled)
    }

    public func autoAnswer() async throws -> Bool? {
        try await BossAppleSession(connection: connection).autoAnswer()
    }

    public func setAutoAnswer(_ enabled: Bool) async throws -> Bool {
        try await BossAppleSession(connection: connection).setAutoAnswer(enabled)
    }

    public func volumeControl() async throws -> BossAppleVolumeControlStatus? {
        try await BossAppleSession(connection: connection).volumeControl()
    }

    public func setVolumeControl(_ value: BossAppleVolumeControlValue) async throws -> BossAppleVolumeControlStatus {
        try await BossAppleSession(connection: connection).setVolumeControl(value)
    }

    public func equalizer() async throws -> BossAppleEqualizerSettings? {
        try await BossAppleSession(connection: connection).equalizer()
    }

    public func setEqualizer(
        _ update: BossAppleEqualizerSettingsPatch
    ) async throws -> BossAppleEqualizerWriteResult {
        try await BossAppleSession(connection: connection).setEqualizer(update)
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
        try await BossAppleSession(connection: connection).audioModeConfigs()
    }

    public func displayableAudioModes() async throws -> [BossAppleAudioModeInfo] {
        try await audioModes().filter { mode in
            !(mode.userConfigurable && !mode.userConfigured && mode.name == "None")
        }
    }

    public func audioModeCapabilities() async throws -> BossAppleAudioModesCapabilities {
        try await BossAppleSession(connection: connection).audioModeCapabilities()
    }

    public func supportedAudioModePrompts() async throws -> [BossAppleAudioModePrompt] {
        try await BossAppleSession(connection: connection).supportedAudioModePrompts()
    }

    public func favoriteAudioModeIndices() async throws -> [Int] {
        try await BossAppleSession(connection: connection).favoriteAudioModeIndices()
    }

    public func setFavoriteAudioModeIndices(
        _ indices: [Int],
        numberOfModes requestedNumberOfModes: Int? = nil
    ) async throws -> [Int] {
        try await BossAppleSession(connection: connection).setFavoriteAudioModeIndices(
            indices,
            numberOfModes: requestedNumberOfModes
        )
    }

    public func setAudioModeFavorite(index: Int, isFavorite: Bool) async throws -> [Int] {
        let session = BossAppleSession(connection: connection)
        if isFavorite {
            return try await session.favoriteAudioMode(index: index)
        }
        return try await session.unfavoriteAudioMode(index: index)
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
        try await BossAppleSession(connection: connection).saveCustomAudioMode(
            name: name,
            settings: settings,
            prompt: prompt,
            slot: requestedSlot
        )
    }

    public func renameCustomAudioMode(
        slot: Int,
        name: String,
        prompt: BossAppleAudioModePrompt? = nil
    ) async throws -> BossAppleAudioModeConfig {
        try await BossAppleSession(connection: connection).renameCustomAudioMode(
            slot: slot,
            name: name,
            prompt: prompt
        )
    }

    public func updateCustomAudioMode(
        slot: Int,
        name: String? = nil,
        settings: BossAppleAudioModeSettingsConfig? = nil,
        prompt: BossAppleAudioModePrompt? = nil
    ) async throws -> BossAppleAudioModeConfig {
        try await BossAppleSession(connection: connection).updateCustomAudioMode(
            slot: slot,
            name: name,
            settings: settings,
            prompt: prompt
        )
    }

    public func deleteCustomAudioMode(slot: Int) async throws -> BossAppleAudioModeConfig {
        try await BossAppleSession(connection: connection).deleteCustomAudioMode(slot: slot)
    }

    public func currentAudioMode() async throws -> Int {
        try await BossAppleSession(connection: connection).currentAudioMode()
    }

    public func setCurrentAudioMode(index targetIndex: Int, playVoicePrompt: Bool = false) async throws -> BossAppleCurrentAudioModeWriteResult {
        try await BossAppleSession(connection: connection).setCurrentAudioMode(
            index: targetIndex,
            playVoicePrompt: playVoicePrompt
        )
    }

    public func audioModeSettings() async throws -> BossAppleAudioModeSettingsConfig {
        try await BossAppleSession(connection: connection).audioModeSettings()
    }

    public func setAudioModeSettings(
        _ update: BossAppleAudioModeSettingsConfigPatch
    ) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await BossAppleSession(connection: connection).setAudioModeSettings(update)
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
