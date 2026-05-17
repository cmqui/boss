import Foundation
import libboss

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

    fileprivate var securePreferred: BossAppleConnectionOptions {
        guard characteristicPreference == .automatic else {
            return self
        }
        return withCharacteristicPreference(.secure)
    }

    fileprivate var scanFilter: AppleBossScanFilter {
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

    public var bmapErrorCode: BmapErrorCode? {
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

    private static func bmapErrorCode(from payloadHex: String) -> BmapErrorCode? {
        guard payloadHex.count == 2, let rawValue = UInt8(payloadHex, radix: 16) else {
            return nil
        }
        return BmapErrorCode(rawValue: rawValue)
    }
}

public enum BossAppleEqualizerWriteResult: Sendable, Equatable {
    case unchanged(BossEqualizerSettings)
    case updated(BossEqualizerSettings)
    case verificationInconclusive(BossEqualizerSettings)
}

public enum BossAppleAudioModeSettingsWriteResult: Sendable, Equatable {
    case unchanged(BossAudioModeSettingsConfig)
    case updated(BossAudioModeSettingsConfig)
    case verificationInconclusive(BossAudioModeSettingsConfig)
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
    case bmapError(BmapErrorCode?)

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
    public let wearDetection: BossAppleObservedSetting<BossOnHeadDetectionValue>
    public let autoAwareEnabled: BossAppleObservedSetting<Bool>
    public let autoPlayPauseEnabled: BossAppleObservedSetting<Bool>
    public let autoAnswerEnabled: BossAppleObservedSetting<Bool>
    public let volumeControl: BossAppleObservedSetting<BossVolumeControlStatus>

    public init(
        wearDetection: BossAppleObservedSetting<BossOnHeadDetectionValue>,
        autoAwareEnabled: BossAppleObservedSetting<Bool>,
        autoPlayPauseEnabled: BossAppleObservedSetting<Bool>,
        autoAnswerEnabled: BossAppleObservedSetting<Bool>,
        volumeControl: BossAppleObservedSetting<BossVolumeControlStatus>
    ) {
        self.wearDetection = wearDetection
        self.autoAwareEnabled = autoAwareEnabled
        self.autoPlayPauseEnabled = autoPlayPauseEnabled
        self.autoAnswerEnabled = autoAnswerEnabled
        self.volumeControl = volumeControl
    }

    public var settings: BossDeviceSettings {
        BossDeviceSettings(
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
        _ operation: @escaping @Sendable (BleBmapLink) async throws -> T
    ) async throws -> T {
        try await Self.withConnectedLink(connection, operation: operation)
    }

    public func bootstrap() async throws -> BootstrappedDevice {
        try await withConnectedLink { link in
            try await BootstrapSession(link: link).bootstrap()
        }
    }

    public func settingsSnapshot() async throws -> BossSettingsSnapshot {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.awaitSettingsSnapshot(on: link, timeout: .seconds(5))
        }
    }

    public func deviceSettings() async throws -> BossDeviceSettings {
        try await deviceSettingsReport().settings
    }

    public func deviceSettingsReport() async throws -> BossAppleDeviceSettingsReport {
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

    public func standbyTimer() async throws -> BossStandbyTimerValue? {
        try await settingsSnapshot().standbyTimer()
    }

    public func setStandbyTimer(minutes: Int) async throws -> BossStandbyTimerValue {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            let response = try await Self.sendAndAwaitSameFunction(
                packet: BossSettingsCodec.settingsPacket(
                    functionRaw: BossSettingsCodec.standbyTimerFunctionRaw,
                    operatorValue: .setGet,
                    payload: BossSettingsCodec.encodeStandbyTimerMinutes(minutes)
                ),
                on: link,
                timeout: .seconds(5)
            )
            return try BossSettingsCodec.parseStandbyTimer(from: response)
        }
    }

    public func autoAware() async throws -> Bool? {
        if let value = try await settingsSnapshot().autoAware() {
            return value
        }
        return try await Self.readEnabledSetting(
            functionRaw: BossSettingsCodec.autoAwareFunctionRaw,
            connection: connection.securePreferred
        )
    }

    public func setAutoAware(_ enabled: Bool) async throws -> Bool {
        try await Self.setEnabledSetting(
            functionRaw: BossSettingsCodec.autoAwareFunctionRaw,
            enabled: enabled,
            connection: connection.securePreferred
        )
    }

    public func onHeadDetection() async throws -> BossOnHeadDetectionValue? {
        if let value = try await settingsSnapshot().onHeadDetection() {
            return value
        }
        return try await Self.readOnHeadDetection(connection: connection.securePreferred)
    }

    public func wearDetection() async throws -> BossOnHeadDetectionValue? {
        try await onHeadDetection()
    }

    public func setWearDetection(_ value: BossOnHeadDetectionValue) async throws -> BossOnHeadDetectionValue {
        try await Self.withConnectedLinkRetrying(connection.securePreferred, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            let response = try await Self.sendAndAwaitSameFunction(
                packet: BossSettingsCodec.onHeadDetectionSetGetPacket(value),
                on: link,
                timeout: .seconds(5)
            )
            return try BossSettingsCodec.parseOnHeadDetection(from: response)
        }
    }

    public func setWearDetection(_ patch: BossOnHeadDetectionPatch) async throws -> BossOnHeadDetectionValue {
        guard !patch.isEmpty else {
            guard let current = try await wearDetection() else {
                throw BossAppleControlError.unsupportedOperation("Wear detection is not exposed by this device/session")
            }
            return current
        }

        do {
            let current = try await wearDetection() ?? BossOnHeadDetectionValue(
                isEnabled: false,
                isAutoPlayEnabled: nil,
                isAutoAnswerEnabled: nil,
                isAutoTransparencyEnabled: nil
            )
            return try await setWearDetection(patch.merged(with: current))
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

    public func updateWearDetectionRelatedSettings(_ patch: BossOnHeadDetectionPatch) async throws -> BossAppleDeviceSettingsReport {
        if patch.isEmpty {
            return try await deviceSettingsReport()
        }
        do {
            let current = try await wearDetection() ?? BossOnHeadDetectionValue(
                isEnabled: false,
                isAutoPlayEnabled: nil,
                isAutoAnswerEnabled: nil,
                isAutoTransparencyEnabled: nil
            )
            _ = try await setWearDetection(patch.merged(with: current))
            return try await deviceSettingsReport()
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
            _ = try await setAutoPlayPause(enabled)
        }
        if let enabled = patch.isAutoAnswerEnabled {
            _ = try await setAutoAnswer(enabled)
        }
        if let enabled = patch.isAutoTransparencyEnabled {
            do {
                _ = try await setAutoAware(enabled)
            } catch {
                if Self.isCompositeInPlaceDetectionUnsupported(error) || Self.isUnavailableSettingReadError(error) {
                    throw BossAppleControlError.unsupportedOperation(
                        "Auto-transparency is not exposed by this device/session over the standalone auto-aware setting path"
                    )
                }
                throw error
            }
        }

        return try await deviceSettingsReport()
    }

    public func setWearDetectionEnabled(_ enabled: Bool) async throws -> BossOnHeadDetectionValue {
        try await setWearDetection(BossOnHeadDetectionPatch(isEnabled: enabled))
    }

    public func autoPlayPause() async throws -> Bool? {
        try await settingsSnapshot().autoPlayPause()
    }

    public func setAutoPlayPause(_ enabled: Bool) async throws -> Bool {
        try await Self.setEnabledSetting(
            functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw,
            enabled: enabled,
            connection: connection
        )
    }

    public func autoAnswer() async throws -> Bool? {
        try await settingsSnapshot().autoAnswer()
    }

    public func setAutoAnswer(_ enabled: Bool) async throws -> Bool {
        try await Self.setEnabledSetting(
            functionRaw: BossSettingsCodec.autoAnswerFunctionRaw,
            enabled: enabled,
            connection: connection
        )
    }

    public func volumeControl() async throws -> BossVolumeControlStatus? {
        if let value = try await settingsSnapshot().volumeControl() {
            return value
        }
        return try await Self.readVolumeControl(connection: connection.securePreferred)
    }

    public func setVolumeControl(_ value: BossVolumeControlValue) async throws -> BossVolumeControlStatus {
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

    public func equalizer() async throws -> BossEqualizerSettings? {
        if let value = try await settingsSnapshot().equalizer() {
            return value
        }
        return try await Self.readEqualizerAfterReconnect(connection: connection.securePreferred)
    }

    public func setEqualizer(
        _ update: BossEqualizerSettingsPatch
    ) async throws -> BossAppleEqualizerWriteResult {
        try await Self.setEqualizerWithVerification(update, connection: connection.securePreferred)
    }

    public func setEqualizerBass(_ level: Int) async throws -> BossAppleEqualizerWriteResult {
        try await setEqualizer(BossEqualizerSettingsPatch(bass: level))
    }

    public func setEqualizerMid(_ level: Int) async throws -> BossAppleEqualizerWriteResult {
        try await setEqualizer(BossEqualizerSettingsPatch(mid: level))
    }

    public func setEqualizerTreble(_ level: Int) async throws -> BossAppleEqualizerWriteResult {
        try await setEqualizer(BossEqualizerSettingsPatch(treble: level))
    }

    public func audioModes() async throws -> [BossAudioModeInfo] {
        try await audioModeConfigs().map(\.info)
    }

    public func audioModeConfigs() async throws -> [BossAudioModeConfig] {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.awaitAudioModeConfigs(on: link, timeout: .seconds(30))
        }
    }

    public func displayableAudioModes() async throws -> [BossAudioModeInfo] {
        try await audioModes().filter { mode in
            !(mode.userConfigurable && !mode.userConfigured && mode.name == "None")
        }
    }

    public func audioModeCapabilities() async throws -> BossAudioModesCapabilities {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.requiredAudioModeCapabilities(on: link, timeout: .seconds(5))
        }
    }

    public func supportedAudioModePrompts() async throws -> [BossAudioModePrompt] {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            let response = try await Self.sendAndAwaitSameFunction(
                packet: BossAudioModesCodec.namesSupportedGetPacket(),
                on: link,
                timeout: .seconds(5)
            )
            return try BossAudioModesCodec.parseSupportedPrompts(from: response)
        }
    }

    public func favoriteAudioModeIndices() async throws -> [Int] {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.requiredFavoriteAudioModeIndices(on: link, timeout: .seconds(5))
        }
    }

    public func setFavoriteAudioModeIndices(
        _ indices: [Int],
        numberOfModes requestedNumberOfModes: Int? = nil
    ) async throws -> [Int] {
        let numberOfModes: Int
        if let requestedNumberOfModes {
            numberOfModes = requestedNumberOfModes
        } else {
            numberOfModes = try await audioModeCapabilities().totalModes
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

    public func setAudioModeFavorite(index: Int, isFavorite: Bool) async throws -> [Int] {
        let numberOfModes = try await audioModeCapabilities().totalModes
        var favorites = Set(try await favoriteAudioModeIndices())
        if isFavorite {
            favorites.insert(index)
        } else {
            favorites.remove(index)
        }
        return try await setFavoriteAudioModeIndices(Array(favorites).sorted(), numberOfModes: numberOfModes)
    }

    public func favoriteAudioMode(index: Int) async throws -> [Int] {
        try await setAudioModeFavorite(index: index, isFavorite: true)
    }

    public func unfavoriteAudioMode(index: Int) async throws -> [Int] {
        try await setAudioModeFavorite(index: index, isFavorite: false)
    }

    public func saveCustomAudioMode(
        name: String,
        settings: BossAudioModeSettingsConfig,
        prompt: BossAudioModePrompt = .none,
        slot requestedSlot: Int? = nil
    ) async throws -> BossAudioModeConfig {
        let configs = try await audioModeConfigs()
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

    public func renameCustomAudioMode(
        slot: Int,
        name: String,
        prompt: BossAudioModePrompt? = nil
    ) async throws -> BossAudioModeConfig {
        let configs = try await audioModeConfigs()
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

    public func updateCustomAudioMode(
        slot: Int,
        name: String? = nil,
        settings: BossAudioModeSettingsConfig? = nil,
        prompt: BossAudioModePrompt? = nil
    ) async throws -> BossAudioModeConfig {
        let configs = try await audioModeConfigs()
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

    public func deleteCustomAudioMode(slot: Int) async throws -> BossAudioModeConfig {
        let configs = try await audioModeConfigs()
        guard let existing = configs.first(where: { $0.modeIndex == slot }) else {
            throw BossAppleControlError.customAudioModeSlotNotFound(slot)
        }
        guard existing.userConfigurable else {
            throw BossAppleControlError.customAudioModeSlotNotEditable(slot)
        }

        if existing.favorite {
            _ = try await unfavoriteAudioMode(index: slot)
        }

        let cleared = try await writeCustomAudioMode(
            slot: slot,
            name: "",
            settings: existing.deletedSettingsBaseline,
            prompt: .none
        )

        return cleared
    }

    public func currentAudioMode() async throws -> Int {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.requiredCurrentAudioMode(on: link, timeout: .seconds(5))
        }
    }

    public func setCurrentAudioMode(index targetIndex: Int, playVoicePrompt: Bool = false) async throws -> BossAppleCurrentAudioModeWriteResult {
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

    public func audioModeSettings() async throws -> BossAudioModeSettingsConfig {
        try await Self.readAudioModeSettingsConfigAfterReconnect(connection: connection.securePreferred)
    }

    public func setAudioModeSettings(
        _ update: BossAudioModeSettingsConfigPatch
    ) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await Self.setAudioModeSettingsConfigWithVerification(update, connection: connection.securePreferred)
    }

    public func setCNCLevel(_ level: Int) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await setAudioModeSettings(BossAudioModeSettingsConfigPatch(cncLevel: level))
    }

    public func setSpatialAudioMode(_ mode: BossSpatialAudioMode) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await setAudioModeSettings(BossAudioModeSettingsConfigPatch(spatialAudioMode: mode))
    }

    public func setWindBlockEnabled(_ enabled: Bool) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await setAudioModeSettings(BossAudioModeSettingsConfigPatch(windBlockEnabled: enabled))
    }

    public func setANCEnabled(_ enabled: Bool) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await setAudioModeSettings(BossAudioModeSettingsConfigPatch(ancToggleEnabled: enabled))
    }

    private func writeCustomAudioMode(
        slot: Int,
        name: String,
        settings: BossAudioModeSettingsConfig,
        prompt: BossAudioModePrompt
    ) async throws -> BossAudioModeConfig {
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

extension BossAppleController {
    static func supportedAudioModePrompts(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> [BossAudioModePrompt] {
        let response = try await sendAndAwaitSameFunction(
            packet: BossAudioModesCodec.namesSupportedGetPacket(),
            on: link,
            timeout: timeout
        )
        return try BossAudioModesCodec.parseSupportedPrompts(from: response)
    }

    static func awaitSettingsSnapshot(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossSettingsSnapshot {
        try await link.send(packet: BossSettingsCodec.settingsPacket(
            functionRaw: BossSettingsCodec.settingsGetAllFunctionRaw,
            operatorValue: .start
        ))
        return try await withThrowingTaskGroup(of: BossSettingsSnapshot.self) { group in
            group.addTask {
                var snapshot: [UInt8: BmapPacket] = [:]
                for try await packet in link.packets {
                    guard packet.functionBlock == .settings else {
                        continue
                    }
                    let rawFunction = packet.function.rawValue
                    if rawFunction == BossSettingsCodec.settingsGetAllFunctionRaw, packet.operator == .error {
                        throw BossAppleControlError.bmapErrorResponse(
                            context: "settings.SettingsGetAll",
                            payloadHex: hexString(packet.payload)
                        )
                    }
                    if rawFunction == BossSettingsCodec.settingsGetAllFunctionRaw, packet.operator == .result {
                        return BossSettingsSnapshot(packetsByFunctionRaw: snapshot)
                    }
                    guard packet.operator == .status else {
                        continue
                    }
                    snapshot[rawFunction] = packet
                }
                throw BossAppleControlError.responseStreamEnded
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw BossAppleControlError.responseTimedOut(seconds: timeout.components.seconds)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    static func withConnectedLink<T: Sendable>(
        _ options: BossAppleConnectionOptions,
        operation: @escaping @Sendable (BleBmapLink) async throws -> T
    ) async throws -> T {
        try await withConnectedLinkRetrying(options, shouldRetry: { _, _ in false }, operation: operation)
    }

    static func withConnectedLinkRetrying<T: Sendable>(
        _ options: BossAppleConnectionOptions,
        shouldRetry: @escaping @Sendable (Error, AppleBossCharacteristicPreference) -> Bool,
        operation: @escaping @Sendable (BleBmapLink) async throws -> T
    ) async throws -> T {
        let preferences: [AppleBossCharacteristicPreference] = options.characteristicPreference == .automatic
            ? [.unsecure, .secure]
            : [options.characteristicPreference]
        var lastError: Error?

        for preference in preferences {
            let attemptOptions = options.withCharacteristicPreference(preference)
            do {
                return try await withConnectedLinkOnce(attemptOptions, operation: operation)
            } catch {
                lastError = error
                guard shouldRetry(error, preference) else {
                    throw error
                }
            }
        }

        throw lastError ?? AppleBleBossTransportError.transportClosed
    }

    static func withConnectedLinkOnce<T: Sendable>(
        _ options: BossAppleConnectionOptions,
        operation: @escaping @Sendable (BleBmapLink) async throws -> T
    ) async throws -> T {
        let transport = try await AppleBleBossTransport.connect(
            filter: options.scanFilter,
            characteristicPreference: options.characteristicPreference
        )
        defer {
            Task {
                await transport.close()
            }
        }
        let link = BleBmapLink(transport: transport)
        return try await operation(link)
    }

    static func nextResponse(
        from stream: AsyncThrowingStream<BmapPacket, Error>,
        matching predicate: @escaping @Sendable (BmapPacket) -> Bool,
        timeout: Duration
    ) async throws -> BmapPacket {
        try await withThrowingTaskGroup(of: BmapPacket.self) { group in
            group.addTask {
                for try await packet in stream {
                    if predicate(packet) {
                        return packet
                    }
                }
                throw BossAppleControlError.responseStreamEnded
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw BossAppleControlError.responseTimedOut(seconds: timeout.components.seconds)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    static func sendAndAwaitSameFunction(
        packet: BmapPacket,
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BmapPacket {
        try await link.send(packet: packet)
        let response = try await nextResponse(
            from: link.packets,
            matching: { incoming in
                incoming.functionBlock == packet.functionBlock &&
                incoming.function == packet.function &&
                incoming.operator.type == .response
            },
            timeout: timeout
        )
        if response.operator == .error {
            throw BossAppleControlError.bmapErrorResponse(
                context: "\(packet.functionBlock.displayName).\(packet.function.name)",
                payloadHex: hexString(response.payload)
            )
        }
        return response
    }
}

extension BossAppleController {
    static func awaitAudioModeConfigs(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> [BossAudioModeConfig] {
        try await link.send(packet: BossAudioModesCodec.modeConfigStartPacket())
        return try await withThrowingTaskGroup(of: [BossAudioModeConfig].self) { group in
            group.addTask {
                var modesByIndex: [Int: BossAudioModeConfig] = [:]
                for try await packet in link.packets {
                    guard packet.functionBlock == .audioModes,
                          packet.function.rawValue == BossAudioModesCodec.modeConfigFunctionRaw else {
                        continue
                    }
                    if packet.operator == .error {
                        throw BossAppleControlError.bmapErrorResponse(
                            context: "audioModes.\(packet.function.name)",
                            payloadHex: hexString(packet.payload)
                        )
                    }
                    if packet.operator == .result {
                        return modesByIndex.values.sorted { $0.modeIndex < $1.modeIndex }
                    }
                    guard packet.operator == .status else {
                        continue
                    }
                    let mode = try BossAudioModesCodec.parseModeConfigDetail(from: packet)
                    modesByIndex[mode.modeIndex] = mode
                }
                throw BossAppleControlError.responseStreamEnded
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw BossAppleControlError.responseTimedOut(seconds: timeout.components.seconds)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    static func firstFreeCustomAudioModeSlot(in configs: [BossAudioModeConfig]) -> Int? {
        configs
            .filter { $0.userConfigurable && !$0.userConfigured }
            .sorted { $0.modeIndex < $1.modeIndex }
            .first(where: { $0.name.isEmpty || $0.name.caseInsensitiveCompare("None") == .orderedSame })?
            .modeIndex
    }

    static func currentAudioModeIfAvailable(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> Int? {
        do {
            let response = try await sendAndAwaitSameFunction(
                packet: BossAudioModesCodec.currentModeGetPacket(),
                on: link,
                timeout: timeout
            )
            return try BossAudioModesCodec.parseCurrentMode(from: response)
        } catch {
            guard shouldFallbackForAudioModeWrite(error) else {
                throw error
            }
            return nil
        }
    }

    static func requiredCurrentAudioMode(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> Int {
        let response = try await sendAndAwaitSameFunction(
            packet: BossAudioModesCodec.currentModeGetPacket(),
            on: link,
            timeout: timeout
        )
        return try BossAudioModesCodec.parseCurrentMode(from: response)
    }

    static func requiredEqualizer(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossEqualizerSettings {
        let response = try await sendAndAwaitSameFunction(
            packet: BossSettingsCodec.equalizerGetPacket(),
            on: link,
            timeout: timeout
        )
        return try BossSettingsCodec.parseEqualizer(from: response)
    }

    static func requiredAudioModeSettingsConfig(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossAudioModeSettingsConfig {
        let response = try await sendAndAwaitSameFunction(
            packet: BossAudioModesCodec.settingsConfigGetPacket(),
            on: link,
            timeout: timeout
        )
        return try BossAudioModesCodec.parseSettingsConfig(from: response)
    }

    static func requiredFavoriteAudioModeIndices(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> [Int] {
        let response = try await sendAndAwaitSameFunction(
            packet: BossAudioModesCodec.favoritesGetPacket(),
            on: link,
            timeout: timeout
        )
        return try BossAudioModesCodec.parseFavorites(from: response)
    }

    static func requiredAudioModeCapabilities(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossAudioModesCapabilities {
        let response = try await sendAndAwaitSameFunction(
            packet: BossAudioModesCodec.capabilitiesGetPacket(),
            on: link,
            timeout: timeout
        )
        return try BossAudioModesCodec.parseCapabilities(from: response)
    }

    static func readEqualizerAfterReconnect(
        connection: BossAppleConnectionOptions,
        attempts: Int = 3,
        retryDelay: Duration = .milliseconds(750)
    ) async throws -> BossEqualizerSettings {
        var lastError: Error = BossAppleControlError.responseTimedOut(seconds: 5)
        for attempt in 0..<attempts {
            do {
                return try await withConnectedLinkRetrying(connection, shouldRetry: retrySecureCharacteristicIfNeeded) { link in
                    try await requiredEqualizer(on: link, timeout: .seconds(5))
                }
            } catch {
                lastError = error
                guard isRecoverableEqualizerError(error), attempt < attempts - 1 else {
                    throw error
                }
                try await Task.sleep(for: retryDelay)
            }
        }
        throw lastError
    }

    static func readAudioModeSettingsConfigAfterReconnect(
        connection: BossAppleConnectionOptions,
        attempts: Int = 3,
        retryDelay: Duration = .milliseconds(750)
    ) async throws -> BossAudioModeSettingsConfig {
        var lastError: Error = BossAppleControlError.responseTimedOut(seconds: 5)
        for attempt in 0..<attempts {
            do {
                return try await withConnectedLinkRetrying(connection, shouldRetry: retrySecureCharacteristicIfNeeded) { link in
                    try await readAudioModeSettingsConfig(on: link, attempts: 2, timeoutPerAttempt: .seconds(5), retryDelay: .milliseconds(300))
                }
            } catch {
                lastError = error
                guard isRecoverableAudioModeSettingsConfigError(error), attempt < attempts - 1 else {
                    throw error
                }
                try await Task.sleep(for: retryDelay)
            }
        }
        throw lastError
    }

    static func readAudioModeSettingsConfig(
        on link: BleBmapLink,
        attempts: Int,
        timeoutPerAttempt: Duration,
        retryDelay: Duration
    ) async throws -> BossAudioModeSettingsConfig {
        var lastError: Error = BossAppleControlError.responseTimedOut(seconds: timeoutPerAttempt.components.seconds)
        for attempt in 0..<attempts {
            do {
                return try await requiredAudioModeSettingsConfig(on: link, timeout: timeoutPerAttempt)
            } catch {
                lastError = error
                guard isRecoverableAudioModeSettingsConfigError(error), attempt < attempts - 1 else {
                    throw error
                }
                try await Task.sleep(for: retryDelay)
            }
        }
        throw lastError
    }

    static func setEqualizerWithVerification(
        _ update: BossEqualizerSettingsPatch,
        connection: BossAppleConnectionOptions
    ) async throws -> BossAppleEqualizerWriteResult {
        let current = try await readEqualizerAfterReconnect(connection: connection)
        guard !update.isEmpty else {
            return .unchanged(current)
        }

        let requested = try validatedEqualizerRequests(update, current: current)
        let target = BossEqualizerSettings(
            ranges: current.ranges.map { range in
                if let requestedLevel = requested.first(where: { $0.0 == range.band })?.1 {
                    return BossEqualizerRangeLevel(
                        band: range.band,
                        currentLevel: requestedLevel,
                        minLevel: range.minLevel,
                        maxLevel: range.maxLevel
                    )
                }
                return range
            }
        )
        guard requested.contains(where: { band, level in
            current.range(for: band)?.currentLevel != level
        }) else {
            return .unchanged(current)
        }

        var lastRecoverableError: Error?
        for attempt in 0..<2 {
            do {
                let updated = try await withConnectedLinkRetrying(connection, shouldRetry: retrySecureCharacteristicIfNeeded) { link in
                    try await sendEqualizerSetGets(requested, on: link, timeout: .seconds(5))
                }
                guard update.matches(updated) else {
                    throw BossAppleControlError.equalizerNotObserved(
                        expected: describe(update),
                        observed: describe(updated)
                    )
                }
                return .updated(updated)
            } catch {
                guard isRecoverableEqualizerError(error) else {
                    throw error
                }
                lastRecoverableError = error

                do {
                    let verified = try await readEqualizerAfterReconnect(connection: connection, attempts: 3)
                    if update.matches(verified) {
                        return .updated(verified)
                    }
                } catch {
                    lastRecoverableError = error
                }

                if attempt == 0 {
                    try await Task.sleep(for: .seconds(1))
                }
            }
        }

        _ = lastRecoverableError
        return .verificationInconclusive(target)
    }

    static func setAudioModeSettingsConfigWithVerification(
        _ update: BossAudioModeSettingsConfigPatch,
        connection: BossAppleConnectionOptions
    ) async throws -> BossAppleAudioModeSettingsWriteResult {
        let current = try await readAudioModeSettingsConfigAfterReconnect(connection: connection)
        let target = update.merged(with: current)
        guard target != current else {
            return .unchanged(current)
        }

        var lastRecoverableError: Error?
        for attempt in 0..<2 {
            do {
                let updated = try await withConnectedLinkRetrying(connection, shouldRetry: retrySecureCharacteristicIfNeeded) { link in
                    try await sendAudioModeSettingsConfigSetGet(target, on: link, timeout: .seconds(5))
                }
                guard update.matches(updated) else {
                    throw BossAppleControlError.settingsConfigNotObserved(
                        expected: describe(target),
                        observed: describe(updated)
                    )
                }
                return .updated(updated)
            } catch {
                guard isRecoverableAudioModeSettingsConfigError(error) else {
                    throw error
                }
                lastRecoverableError = error

                do {
                    let verified = try await readAudioModeSettingsConfigAfterReconnect(connection: connection, attempts: 3)
                    if update.matches(verified) {
                        return .updated(verified)
                    }
                } catch {
                    lastRecoverableError = error
                }

                if attempt == 0 {
                    try await Task.sleep(for: .seconds(1))
                }
            }
        }

        _ = lastRecoverableError
        return .verificationInconclusive(target)
    }

    static func sendEqualizerSetGets(
        _ requests: [(BossEqualizerBand, Int)],
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossEqualizerSettings {
        var lastSettings: BossEqualizerSettings?
        for (band, level) in requests {
            lastSettings = try await sendEqualizerSetGet(
                targetLevel: level,
                band: band,
                on: link,
                timeout: timeout
            )
        }
        guard let lastSettings else {
            throw BossAppleControlError.unsupportedOperation("At least one equalizer band update is required")
        }
        return lastSettings
    }

    static func sendEqualizerSetGet(
        targetLevel: Int,
        band: BossEqualizerBand,
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossEqualizerSettings {
        let packet = try BossSettingsCodec.equalizerSetGetPacket(targetLevel: targetLevel, band: band)
        let response = try await sendAndAwaitSameFunction(packet: packet, on: link, timeout: timeout)
        return try BossSettingsCodec.parseEqualizer(from: response)
    }

    static func sendAudioModeSettingsConfigSetGet(
        _ config: BossAudioModeSettingsConfig,
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossAudioModeSettingsConfig {
        let packet = try BossAudioModesCodec.settingsConfigSetGetPacket(config)
        try await link.send(packet: packet)
        let response = try await nextResponse(
            from: link.packets,
            matching: { incoming in
                incoming.functionBlock == packet.functionBlock &&
                incoming.function == packet.function &&
                incoming.operator.type == .response
            },
            timeout: timeout
        )
        if response.operator == .error {
            throw BossAppleControlError.bmapErrorResponse(
                context: "\(packet.functionBlock.displayName).\(packet.function.name)",
                payloadHex: hexString(response.payload)
            )
        }
        return try BossAudioModesCodec.parseSettingsConfig(from: response)
    }

    static func sendAudioModeConfigSetGet(
        modeIndex: Int,
        prompt: BossAudioModePrompt,
        name: String,
        settings: BossAudioModeSettingsConfig,
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossAudioModeConfig {
        let packet = try BossAudioModesCodec.modeConfigSetGetPacket(
            modeIndex: modeIndex,
            prompt: prompt,
            name: name,
            settings: settings
        )
        let response = try await sendAndAwaitSameFunction(packet: packet, on: link, timeout: timeout)
        return try BossAudioModesCodec.parseModeConfigDetail(from: response)
    }

    static func sendAudioModeFavoritesSetGet(
        numberOfModes: Int,
        favoriteModeIndices: [Int],
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> [Int] {
        let packet = try BossAudioModesCodec.favoritesSetGetPacket(
            numberOfModes: numberOfModes,
            favoriteModeIndices: favoriteModeIndices
        )
        let response = try await sendAndAwaitSameFunction(packet: packet, on: link, timeout: timeout)
        return try BossAudioModesCodec.parseFavorites(from: response)
    }

    static func observedWearDetection(
        from snapshot: BossSettingsSnapshot,
        fallbackConnection: BossAppleConnectionOptions,
        timeout: Duration
    ) async throws -> BossAppleObservedSetting<BossOnHeadDetectionValue> {
        if let value = try snapshot.onHeadDetection() {
            return BossAppleObservedSetting(value: value, source: .snapshot)
        }
        return try await observeSettingAfterDirectRead(
            initialUnavailableReason: .missingFromSnapshot,
            read: {
                try await readOnHeadDetection(connection: fallbackConnection, timeout: timeout)
            }
        )
    }

    static func observedEnabledSetting(
        functionRaw: UInt8,
        snapshotValue: Bool?,
        snapshotPacketExists: Bool,
        fallbackConnection: BossAppleConnectionOptions,
        timeout: Duration
    ) async throws -> BossAppleObservedSetting<Bool> {
        if let snapshotValue {
            return BossAppleObservedSetting(value: snapshotValue, source: .snapshot)
        }
        return try await observeSettingAfterDirectRead(
            initialUnavailableReason: snapshotPacketExists ? .dataUnavailable : .missingFromSnapshot,
            read: {
                try await readEnabledSetting(
                    functionRaw: functionRaw,
                    connection: fallbackConnection,
                    timeout: timeout
                )
            }
        )
    }

    static func observedAutoAnswer(
        from snapshot: BossSettingsSnapshot,
        fallbackConnection: BossAppleConnectionOptions,
        timeout: Duration
    ) async throws -> BossAppleObservedSetting<Bool> {
        if let packet = snapshot.packet(functionRaw: BossSettingsCodec.autoAnswerFunctionRaw) {
            return BossAppleObservedSetting(
                value: try BossSettingsCodec.parseEnabledFlag(from: packet),
                source: .snapshot
            )
        }
        if let derived = try snapshot.onHeadDetection()?.isAutoAnswerEnabled {
            return BossAppleObservedSetting(value: derived, source: .compositeSnapshot)
        }
        return try await observeSettingAfterDirectRead(
            initialUnavailableReason: .missingFromSnapshot,
            read: {
                try await readEnabledSetting(
                    functionRaw: BossSettingsCodec.autoAnswerFunctionRaw,
                    connection: fallbackConnection,
                    timeout: timeout
                )
            }
        )
    }

    static func observedVolumeControl(
        from snapshot: BossSettingsSnapshot,
        fallbackConnection: BossAppleConnectionOptions,
        timeout: Duration
    ) async throws -> BossAppleObservedSetting<BossVolumeControlStatus> {
        if let value = try snapshot.volumeControl() {
            return BossAppleObservedSetting(value: value, source: .snapshot)
        }
        return try await observeSettingAfterDirectRead(
            initialUnavailableReason: .missingFromSnapshot,
            read: {
                try await readVolumeControl(connection: fallbackConnection, timeout: timeout)
            }
        )
    }

    static func observeSettingAfterDirectRead<Value: Sendable & Equatable>(
        initialUnavailableReason: BossAppleSettingUnavailableReason,
        read: @escaping @Sendable () async throws -> Value?
    ) async throws -> BossAppleObservedSetting<Value> {
        do {
            if let value = try await read() {
                return BossAppleObservedSetting(value: value, source: .directGet)
            }
            return BossAppleObservedSetting(value: nil, unavailableReason: initialUnavailableReason)
        } catch {
            if let reason = unavailableSettingReason(error) {
                return BossAppleObservedSetting(value: nil, unavailableReason: reason)
            }
            throw error
        }
    }

    static func readOnHeadDetection(
        connection: BossAppleConnectionOptions,
        timeout: Duration = .seconds(5)
    ) async throws -> BossOnHeadDetectionValue? {
        try await withConnectedLinkRetrying(connection, shouldRetry: retrySecureCharacteristicIfNeeded) { link in
            try await onHeadDetectionIfAvailable(on: link, timeout: timeout)
        }
    }

    static func readEnabledSetting(
        functionRaw: UInt8,
        connection: BossAppleConnectionOptions,
        timeout: Duration = .seconds(5)
    ) async throws -> Bool? {
        try await withConnectedLinkRetrying(connection, shouldRetry: retrySecureCharacteristicIfNeeded) { link in
            try await enabledSettingIfAvailable(functionRaw: functionRaw, on: link, timeout: timeout)
        }
    }

    static func readVolumeControl(
        connection: BossAppleConnectionOptions,
        timeout: Duration = .seconds(5)
    ) async throws -> BossVolumeControlStatus? {
        try await withConnectedLinkRetrying(connection, shouldRetry: retrySecureCharacteristicIfNeeded) { link in
            try await volumeControlIfAvailable(on: link, timeout: timeout)
        }
    }

    static func onHeadDetectionIfAvailable(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossOnHeadDetectionValue? {
        let response = try await sendAndAwaitSameFunction(
            packet: BossSettingsCodec.onHeadDetectionGetPacket(),
            on: link,
            timeout: timeout
        )
        return try BossSettingsCodec.parseOnHeadDetection(from: response)
    }

    static func enabledSettingIfAvailable(
        functionRaw: UInt8,
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> Bool? {
        let response = try await sendAndAwaitSameFunction(
            packet: BossSettingsCodec.settingsPacket(
                functionRaw: functionRaw,
                operatorValue: .get
            ),
            on: link,
            timeout: timeout
        )
        return try BossSettingsCodec.parseEnabledFlag(from: response)
    }

    static func volumeControlIfAvailable(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossVolumeControlStatus? {
        let response = try await sendAndAwaitSameFunction(
            packet: BossSettingsCodec.settingsPacket(
                functionRaw: BossSettingsCodec.volumeControlFunctionRaw,
                operatorValue: .get
            ),
            on: link,
            timeout: timeout
        )
        return try BossAudioModesCodec.parseVolumeControlStatus(from: response)
    }

    static func setEnabledSetting(
        functionRaw: UInt8,
        enabled: Bool,
        connection: BossAppleConnectionOptions
    ) async throws -> Bool {
        try await withConnectedLinkRetrying(connection, shouldRetry: retrySecureCharacteristicIfNeeded) { link in
            let response = try await sendAndAwaitSameFunction(
                packet: BossSettingsCodec.settingsPacket(
                    functionRaw: functionRaw,
                    operatorValue: .setGet,
                    payload: Data([enabled ? 0x01 : 0x00])
                ),
                on: link,
                timeout: .seconds(5)
            )
            return try BossSettingsCodec.parseEnabledFlag(from: response)
        }
    }

    static func deviceSettingsReport(
        from snapshot: BossSettingsSnapshot,
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossAppleDeviceSettingsReport {
        let wearDetection = try await observedWearDetection(from: snapshot, on: link, timeout: timeout)
        let autoAwareEnabled = try await observedEnabledSetting(
            functionRaw: BossSettingsCodec.autoAwareFunctionRaw,
            snapshotValue: try snapshot.autoAware(),
            snapshotPacketExists: snapshot.packet(functionRaw: BossSettingsCodec.autoAwareFunctionRaw) != nil,
            on: link,
            timeout: timeout
        )
        let autoPlayPauseEnabled = try await observedEnabledSetting(
            functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw,
            snapshotValue: try snapshot.autoPlayPause(),
            snapshotPacketExists: snapshot.packet(functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw) != nil,
            on: link,
            timeout: timeout
        )
        let autoAnswerEnabled = try await observedAutoAnswer(from: snapshot, on: link, timeout: timeout)
        let volumeControl = try await observedVolumeControl(from: snapshot, on: link, timeout: timeout)

        return BossAppleDeviceSettingsReport(
            wearDetection: wearDetection,
            autoAwareEnabled: autoAwareEnabled,
            autoPlayPauseEnabled: autoPlayPauseEnabled,
            autoAnswerEnabled: autoAnswerEnabled,
            volumeControl: volumeControl
        )
    }

    static func equalizerIfAvailable(
        from snapshot: BossSettingsSnapshot,
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossEqualizerSettings? {
        if let value = try snapshot.equalizer() {
            return value
        }
        return try await observeSettingAfterDirectRead(
            initialUnavailableReason: .missingFromSnapshot,
            read: {
                try await requiredEqualizer(on: link, timeout: timeout)
            }
        ).value
    }

    static func observedWearDetection(
        from snapshot: BossSettingsSnapshot,
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossAppleObservedSetting<BossOnHeadDetectionValue> {
        if let value = try snapshot.onHeadDetection() {
            return BossAppleObservedSetting(value: value, source: .snapshot)
        }
        return try await observeSettingAfterDirectRead(
            initialUnavailableReason: .missingFromSnapshot,
            read: {
                try await onHeadDetectionIfAvailable(on: link, timeout: timeout)
            }
        )
    }

    static func observedEnabledSetting(
        functionRaw: UInt8,
        snapshotValue: Bool?,
        snapshotPacketExists: Bool,
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossAppleObservedSetting<Bool> {
        if let snapshotValue {
            return BossAppleObservedSetting(value: snapshotValue, source: .snapshot)
        }
        return try await observeSettingAfterDirectRead(
            initialUnavailableReason: snapshotPacketExists ? .dataUnavailable : .missingFromSnapshot,
            read: {
                try await enabledSettingIfAvailable(functionRaw: functionRaw, on: link, timeout: timeout)
            }
        )
    }

    static func observedAutoAnswer(
        from snapshot: BossSettingsSnapshot,
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossAppleObservedSetting<Bool> {
        if let packet = snapshot.packet(functionRaw: BossSettingsCodec.autoAnswerFunctionRaw) {
            return BossAppleObservedSetting(
                value: try BossSettingsCodec.parseEnabledFlag(from: packet),
                source: .snapshot
            )
        }
        if let derived = try snapshot.onHeadDetection()?.isAutoAnswerEnabled {
            return BossAppleObservedSetting(value: derived, source: .compositeSnapshot)
        }
        return try await observeSettingAfterDirectRead(
            initialUnavailableReason: .missingFromSnapshot,
            read: {
                try await enabledSettingIfAvailable(
                    functionRaw: BossSettingsCodec.autoAnswerFunctionRaw,
                    on: link,
                    timeout: timeout
                )
            }
        )
    }

    static func observedVolumeControl(
        from snapshot: BossSettingsSnapshot,
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossAppleObservedSetting<BossVolumeControlStatus> {
        if let value = try snapshot.volumeControl() {
            return BossAppleObservedSetting(value: value, source: .snapshot)
        }
        return try await observeSettingAfterDirectRead(
            initialUnavailableReason: .missingFromSnapshot,
            read: {
                try await volumeControlIfAvailable(on: link, timeout: timeout)
            }
        )
    }
}

extension BossAppleController {
    static func verifyCurrentAudioMode(
        on link: BleBmapLink,
        targetIndex: Int,
        timeoutPerAttempt: Duration,
        attempts: Int,
        retryDelay: Duration,
        fallbackError: Error? = nil
    ) async throws -> Int {
        var lastError: Error = fallbackError ?? BossAppleControlError.responseTimedOut(seconds: timeoutPerAttempt.components.seconds)
        var lastObservedIndex: Int?
        for attempt in 0..<attempts {
            do {
                let currentIndex = try await requiredCurrentAudioMode(on: link, timeout: timeoutPerAttempt)
                lastObservedIndex = currentIndex
                if currentIndex == targetIndex {
                    return currentIndex
                }
            } catch {
                lastError = error
            }
            if attempt < attempts - 1 {
                try await Task.sleep(for: retryDelay)
            }
        }
        if let lastObservedIndex {
            throw BossAppleControlError.modeChangeNotObserved(targetIndex: targetIndex, observedIndex: lastObservedIndex)
        }
        throw fallbackError ?? lastError
    }

    static func verifyCurrentAudioModeAfterReconnect(
        connection: BossAppleConnectionOptions,
        targetIndex: Int,
        fallbackError: Error
    ) async throws -> Int {
        var lastError: Error = fallbackError
        for attempt in 0..<4 {
            do {
                return try await withConnectedLinkRetrying(
                    connection,
                    shouldRetry: { error, preference in
                        guard preference == .unsecure else {
                            return false
                        }
                        return shouldFallbackForAudioModeWrite(error)
                    }
                ) { link in
                    try await verifyCurrentAudioMode(
                        on: link,
                        targetIndex: targetIndex,
                        timeoutPerAttempt: .seconds(3),
                        attempts: 3,
                        retryDelay: .milliseconds(750),
                        fallbackError: fallbackError
                    )
                }
            } catch {
                lastError = error
                if attempt < 3 {
                    try await Task.sleep(for: .seconds(1))
                }
            }
        }
        throw lastError
    }

    static func shouldFallbackForAudioModeWrite(_ error: Error) -> Bool {
        if let error = error as? BossAppleControlError {
            switch error {
            case .responseTimedOut, .responseStreamEnded:
                return true
            default:
                return false
            }
        }
        if let error = error as? BossLinkError, error == .unexpectedStreamTermination {
            return true
        }
        return false
    }

    static func retrySecureCharacteristicIfNeeded(_ error: Error, _ preference: AppleBossCharacteristicPreference) -> Bool {
        guard preference == .unsecure else {
            return false
        }
        if case BossAppleControlError.responseTimedOut = error {
            return true
        }
        if case BossAppleControlError.bmapErrorResponse(_, let payloadHex) = error,
           bmapErrorCode(from: payloadHex) == .insecureTransport {
            return true
        }
        return false
    }

    static func isRecoverableAudioModeSettingsConfigError(_ error: Error) -> Bool {
        if shouldFallbackForAudioModeWrite(error) {
            return true
        }
        if let error = error as? BossAppleControlError {
            switch error {
            case .settingsConfigNotObserved:
                return true
            case .bmapErrorResponse(_, let payloadHex):
                return bmapErrorCode(from: payloadHex) == .insecureTransport ||
                    bmapErrorCode(from: payloadHex) == .timeout ||
                    bmapErrorCode(from: payloadHex) == .busy
            default:
                return false
            }
        }
        return false
    }

    static func isRecoverableEqualizerError(_ error: Error) -> Bool {
        if shouldFallbackForAudioModeWrite(error) {
            return true
        }
        if let error = error as? BossAppleControlError {
            switch error {
            case .equalizerNotObserved:
                return true
            case .bmapErrorResponse(_, let payloadHex):
                return bmapErrorCode(from: payloadHex) == .insecureTransport ||
                    bmapErrorCode(from: payloadHex) == .timeout ||
                    bmapErrorCode(from: payloadHex) == .busy
            default:
                return false
            }
        }
        return false
    }

    static func isVerificationInconclusiveError(_ error: Error) -> Bool {
        if shouldFallbackForAudioModeWrite(error) {
            return true
        }
        if let error = error as? BossAppleControlError {
            switch error {
            case .bmapErrorResponse(_, let payloadHex):
                return bmapErrorCode(from: payloadHex) == .insecureTransport
            default:
                return false
            }
        }
        return false
    }

    static func isCompositeInPlaceDetectionUnsupported(_ error: Error) -> Bool {
        guard let error = unavailableSettingReason(error) else {
            return false
        }
        switch error {
        case .functionUnsupported, .operatorUnsupported:
            return true
        default:
            return false
        }
    }

    static func unavailableSettingReason(_ error: Error) -> BossAppleSettingUnavailableReason? {
        if let error = error as? BossAppleControlError {
            switch error {
            case .responseTimedOut:
                return .timedOut
            case .responseStreamEnded:
                return .responseStreamEnded
            case .bmapErrorResponse(_, let payloadHex):
                switch bmapErrorCode(from: payloadHex) {
                case .fblockNotSupp?, .funcNotSupp?:
                    return .functionUnsupported
                case .opNotSupp?:
                    return .operatorUnsupported
                case .dataUnavailable?:
                    return .dataUnavailable
                case .insecureTransport?:
                    return .insecureTransport
                case let code:
                    return .bmapError(code)
                }
            default:
                return nil
            }
        }
        if let error = error as? BossLinkError, error == .unexpectedStreamTermination {
            return .unexpectedStreamTermination
        }
        return nil
    }

    static func isUnavailableSettingReadError(_ error: Error) -> Bool {
        unavailableSettingReason(error) != nil
    }

    static func bmapErrorCode(from payloadHex: String) -> BmapErrorCode? {
        guard payloadHex.count == 2, let rawValue = UInt8(payloadHex, radix: 16) else {
            return nil
        }
        return BmapErrorCode(rawValue: rawValue)
    }

    static func validatedEqualizerRequests(
        _ update: BossEqualizerSettingsPatch,
        current: BossEqualizerSettings
    ) throws -> [(BossEqualizerBand, Int)] {
        try update.requestedLevels.map { band, level in
            guard let range = current.range(for: band) else {
                throw BossAppleControlError.unsupportedOperation(
                    "This device/session does not expose the \(band.displayName) equalizer band over BMAP"
                )
            }
            guard (range.minLevel...range.maxLevel).contains(level) else {
                throw BossAppleControlError.unsupportedOperation(
                    "Requested \(band.displayName) equalizer level \(level) is outside the supported range \(range.minLevel)...\(range.maxLevel)"
                )
            }
            return (band, level)
        }
    }

    static func describe(_ update: BossEqualizerSettingsPatch) -> String {
        update.requestedLevels
            .map { "\($0.0.displayName)=\($0.1)" }
            .joined(separator: ",")
    }

    static func describe(_ settings: BossEqualizerSettings) -> String {
        settings.ranges
            .map { "\($0.band.displayName)=\($0.currentLevel)[\($0.minLevel)...\($0.maxLevel)]" }
            .joined(separator: ",")
    }

    static func describe(_ config: BossAudioModeSettingsConfig) -> String {
        "cnc=\(config.cncLevel),autoCNC=\(config.autoCNCEnabled),spatial=\(config.spatialAudioMode.displayName),wind=\(config.windBlockEnabled),anc=\(config.ancToggleEnabled)"
    }

    static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}
