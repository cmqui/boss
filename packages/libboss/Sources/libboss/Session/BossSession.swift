import Foundation

public enum BossSessionError: Error, Sendable, Equatable, CustomStringConvertible {
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
        guard payloadHex.count == 2, let rawValue = UInt8(payloadHex, radix: 16) else {
            return nil
        }
        return BmapErrorCode(rawValue: rawValue)
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
}

public enum BossEqualizerWriteResult: Sendable, Equatable {
    case unchanged(BossEqualizerSettings)
    case updated(BossEqualizerSettings)
    case verificationInconclusive(BossEqualizerSettings)
}

public enum BossAudioModeSettingsWriteResult: Sendable, Equatable {
    case unchanged(BossAudioModeSettingsConfig)
    case updated(BossAudioModeSettingsConfig)
    case verificationInconclusive(BossAudioModeSettingsConfig)
}

public enum BossCurrentAudioModeWriteResult: Sendable, Equatable {
    case unchanged(Int)
    case updated(Int)
    case verificationInconclusive(targetIndex: Int)
}

public enum BossSettingSource: String, Sendable, Equatable {
    case snapshot
    case compositeSnapshot
    case directGet
}

public enum BossSettingUnavailableReason: Sendable, Equatable, CustomStringConvertible {
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

public struct BossObservedSetting<Value: Sendable & Equatable>: Sendable, Equatable {
    public let value: Value?
    public let source: BossSettingSource?
    public let unavailableReason: BossSettingUnavailableReason?

    public init(
        value: Value?,
        source: BossSettingSource? = nil,
        unavailableReason: BossSettingUnavailableReason? = nil
    ) {
        self.value = value
        self.source = source
        self.unavailableReason = unavailableReason
    }

    public var isAvailable: Bool {
        value != nil
    }
}

public struct BossDeviceSettingsReport: Sendable, Equatable {
    public let wearDetection: BossObservedSetting<BossOnHeadDetectionValue>
    public let autoAwareEnabled: BossObservedSetting<Bool>
    public let autoPlayPauseEnabled: BossObservedSetting<Bool>
    public let autoAnswerEnabled: BossObservedSetting<Bool>
    public let volumeControl: BossObservedSetting<BossVolumeControlStatus>

    public init(
        wearDetection: BossObservedSetting<BossOnHeadDetectionValue>,
        autoAwareEnabled: BossObservedSetting<Bool>,
        autoPlayPauseEnabled: BossObservedSetting<Bool>,
        autoAnswerEnabled: BossObservedSetting<Bool>,
        volumeControl: BossObservedSetting<BossVolumeControlStatus>
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

public struct BossModeWorkspaceSnapshot: Sendable, Equatable {
    public let currentAudioModeIndex: Int
    public let settings: BossAudioModeSettingsConfig
    public let equalizer: BossEqualizerSettings?
    public let deviceSettings: BossDeviceSettingsReport

    public init(
        currentAudioModeIndex: Int,
        settings: BossAudioModeSettingsConfig,
        equalizer: BossEqualizerSettings?,
        deviceSettings: BossDeviceSettingsReport
    ) {
        self.currentAudioModeIndex = currentAudioModeIndex
        self.settings = settings
        self.equalizer = equalizer
        self.deviceSettings = deviceSettings
    }
}

public struct BossWorkspaceSnapshot: Sendable, Equatable {
    public let bootstrappedDevice: BootstrappedDevice
    public let modeWorkspace: BossModeWorkspaceSnapshot
    public let audioModes: [BossAudioModeConfig]

    public init(
        bootstrappedDevice: BootstrappedDevice,
        modeWorkspace: BossModeWorkspaceSnapshot,
        audioModes: [BossAudioModeConfig]
    ) {
        self.bootstrappedDevice = bootstrappedDevice
        self.modeWorkspace = modeWorkspace
        self.audioModes = audioModes
    }
}

public enum BossSettingObservation {
    public static func observeAfterDirectRead<Value: Sendable & Equatable>(
        initialUnavailableReason: BossSettingUnavailableReason,
        read: @escaping @Sendable () async throws -> Value?
    ) async throws -> BossObservedSetting<Value> {
        do {
            if let value = try await read() {
                return BossObservedSetting(value: value, source: .directGet)
            }
            return BossObservedSetting(value: nil, unavailableReason: initialUnavailableReason)
        } catch {
            if let reason = unavailableReason(for: error) {
                return BossObservedSetting(value: nil, unavailableReason: reason)
            }
            throw error
        }
    }

    public static func unavailableReason(for error: Error) -> BossSettingUnavailableReason? {
        if let error = error as? BossSessionError {
            switch error {
            case .responseTimedOut:
                return .timedOut
            case .responseStreamEnded:
                return .responseStreamEnded
            case .bmapErrorResponse:
                switch error.bmapErrorCode {
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
}

public actor BossSession {
    private let packetSession: BossPacketSession

    public init(packetSession: BossPacketSession) {
        self.packetSession = packetSession
    }

    public nonisolated func packetStream(
        matching predicate: @escaping @Sendable (BmapPacket) -> Bool
    ) -> AsyncThrowingStream<BmapPacket, Error> {
        packetSession.packetStream(matching: predicate)
    }

    public nonisolated func settingsPacketStream() -> AsyncThrowingStream<BmapPacket, Error> {
        packetStream { $0.functionBlock == .settings }
    }

    public nonisolated func audioModePacketStream() -> AsyncThrowingStream<BmapPacket, Error> {
        packetStream { $0.functionBlock == .audioModes }
    }

    public nonisolated func notificationPacketStream() -> AsyncThrowingStream<BmapPacket, Error> {
        packetStream { $0.functionBlock == .notification }
    }

    public nonisolated func currentAudioModeUpdateStream() -> AsyncThrowingStream<Int, Error> {
        let packets = packetStream {
            $0.functionBlock == .audioModes &&
                $0.function.rawValue == BossAudioModesCodec.currentModeFunctionRaw &&
                $0.operator == .status
        }
        return Self.mapStream(packets) { packet in
            try BossAudioModesCodec.parseCurrentMode(from: packet)
        }
    }

    public nonisolated func audioModeSettingsUpdateStream() -> AsyncThrowingStream<BossAudioModeSettingsConfig, Error> {
        let packets = packetStream {
            $0.functionBlock == .audioModes &&
                $0.function.rawValue == BossAudioModesCodec.settingsConfigFunctionRaw &&
                $0.operator == .status
        }
        return Self.mapStream(packets) { packet in
            try BossAudioModesCodec.parseSettingsConfig(from: packet)
        }
    }

    public nonisolated func equalizerUpdateStream() -> AsyncThrowingStream<BossEqualizerSettings, Error> {
        let packets = packetStream {
            $0.functionBlock == .settings &&
                $0.function.rawValue == BossSettingsCodec.rangeControlFunctionRaw &&
                $0.operator == .status
        }
        return Self.mapStream(packets) { packet in
            try BossSettingsCodec.parseEqualizer(from: packet)
        }
    }

    public func loadWorkspaceSnapshot(
        bootstrappedDevice: BootstrappedDevice
    ) async throws -> BossWorkspaceSnapshot {
        let modeWorkspace = try await refreshModeWorkspaceSnapshot()
        let audioModes = try await audioModeConfigs()
        return BossWorkspaceSnapshot(
            bootstrappedDevice: bootstrappedDevice,
            modeWorkspace: modeWorkspace,
            audioModes: audioModes
        )
    }

    public func refreshModeWorkspaceSnapshot() async throws -> BossModeWorkspaceSnapshot {
        let settingsSnapshot = try await awaitSettingsSnapshot(timeout: .seconds(5))
        let currentAudioModeIndex = try await requiredCurrentAudioMode(timeout: .seconds(5))
        let settings = try await readAudioModeSettingsConfig(
            attempts: 2,
            timeoutPerAttempt: .seconds(5),
            retryDelay: .milliseconds(300)
        )
        let equalizer = try await equalizerIfAvailable(from: settingsSnapshot, timeout: .seconds(5))
        let deviceSettings = try await deviceSettingsReport(from: settingsSnapshot, timeout: .seconds(5))

        return BossModeWorkspaceSnapshot(
            currentAudioModeIndex: currentAudioModeIndex,
            settings: settings,
            equalizer: equalizer,
            deviceSettings: deviceSettings
        )
    }

    public nonisolated func modeWorkspaceUpdates(
        interval: Duration = .seconds(5)
    ) -> AsyncThrowingStream<BossModeWorkspaceSnapshot, Error> {
        let session = self
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        continuation.yield(try await session.refreshModeWorkspaceSnapshot())
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

    public func supportedAudioModePrompts() async throws -> [BossAudioModePrompt] {
        try await mapSessionErrors {
            try await packetSession.supportedAudioModePrompts(
                timeout: .seconds(5),
                timeoutError: timeoutError(for: .seconds(5))
            )
        }
    }

    public func audioModeConfigs() async throws -> [BossAudioModeConfig] {
        try await awaitAudioModeConfigs(timeout: .seconds(30))
    }

    public func setCurrentAudioMode(
        index targetIndex: Int,
        playVoicePrompt: Bool = false
    ) async throws -> BossCurrentAudioModeWriteResult {
        if let currentIndex = try await currentAudioModeIfAvailable(timeout: .seconds(2)),
           currentIndex == targetIndex {
            return .unchanged(currentIndex)
        }

        do {
            let response = try await mapSessionErrors {
                try await packetSession.startCurrentAudioModeChange(
                    modeIndex: targetIndex,
                    playVoicePrompt: playVoicePrompt,
                    timeout: .seconds(5),
                    timeoutError: timeoutError(for: .seconds(5))
                )
            }
            if response.operator == .result {
                if let responseModeIndex = response.payload.first {
                    return .updated(Int(responseModeIndex))
                }
                let verified = try await verifyCurrentAudioMode(
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
                let verified = try await verifyCurrentAudioMode(
                    targetIndex: targetIndex,
                    timeoutPerAttempt: .seconds(3),
                    attempts: 4,
                    retryDelay: .seconds(1),
                    fallbackError: error
                )
                return .updated(verified)
            } catch {
                return .verificationInconclusive(targetIndex: targetIndex)
            }
        }
    }

    public func setAudioModeSettings(
        _ update: BossAudioModeSettingsConfigPatch
    ) async throws -> BossAudioModeSettingsWriteResult {
        let current = try await readAudioModeSettingsConfig(
            attempts: 2,
            timeoutPerAttempt: .seconds(5),
            retryDelay: .milliseconds(300)
        )
        let target = update.merged(with: current)
        guard target != current else {
            return .unchanged(current)
        }

        do {
            let updated = try await sendAudioModeSettingsConfigSetGet(target, timeout: .seconds(5))
            guard update.matches(updated) else {
                throw BossSessionError.settingsConfigNotObserved(
                    expected: Self.describe(target),
                    observed: Self.describe(updated)
                )
            }
            return .updated(updated)
        } catch {
            guard Self.isRecoverableAudioModeSettingsConfigError(error) else {
                throw error
            }

            let verified = try await refreshModeWorkspaceSnapshot().settings
            if update.matches(verified) {
                return .updated(verified)
            }
            return .verificationInconclusive(target)
        }
    }

    public func setEqualizer(
        _ update: BossEqualizerSettingsPatch
    ) async throws -> BossEqualizerWriteResult {
        let current = try await requiredEqualizer(timeout: .seconds(5))
        guard !update.isEmpty else {
            return .unchanged(current)
        }

        let requested = try Self.validatedEqualizerRequests(update, current: current)
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

        do {
            let updated = try await sendEqualizerSetGets(requested, timeout: .seconds(5))
            guard update.matches(updated) else {
                throw BossSessionError.equalizerNotObserved(
                    expected: Self.describe(update),
                    observed: Self.describe(updated)
                )
            }
            return .updated(updated)
        } catch {
            guard Self.isRecoverableEqualizerError(error) else {
                throw error
            }

            let verified = try await refreshModeWorkspaceSnapshot().equalizer ?? target
            if update.matches(verified) {
                return .updated(verified)
            }
            return .verificationInconclusive(target)
        }
    }

    public func setWearDetectionEnabled(_ enabled: Bool) async throws -> BossOnHeadDetectionValue {
        let current = try await onHeadDetectionIfAvailable(timeout: .seconds(5))
        guard let current else {
            throw BossSessionError.unsupportedOperation("Wear detection is not exposed by this device/session")
        }

        return try await mapSessionErrors {
            try await packetSession.setOnHeadDetection(
                BossOnHeadDetectionPatch(isEnabled: enabled).merged(with: current),
                timeout: .seconds(5),
                timeoutError: timeoutError(for: .seconds(5))
            )
        }
    }

    public func setAutoAware(_ enabled: Bool) async throws -> Bool {
        try await setEnabledSetting(functionRaw: BossSettingsCodec.autoAwareFunctionRaw, enabled: enabled)
    }

    public func setAutoPlayPause(_ enabled: Bool) async throws -> Bool {
        try await setEnabledSetting(functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw, enabled: enabled)
    }

    public func setAutoAnswer(_ enabled: Bool) async throws -> Bool {
        try await setEnabledSetting(functionRaw: BossSettingsCodec.autoAnswerFunctionRaw, enabled: enabled)
    }

    public func setVolumeControl(_ value: BossVolumeControlValue) async throws -> BossVolumeControlStatus {
        try await mapSessionErrors {
            try await packetSession.setVolumeControl(
                value,
                timeout: .seconds(5),
                timeoutError: timeoutError(for: .seconds(5))
            )
        }
    }

    public func favoriteAudioMode(index: Int) async throws -> [Int] {
        try await setAudioModeFavorite(index: index, isFavorite: true)
    }

    public func unfavoriteAudioMode(index: Int) async throws -> [Int] {
        try await setAudioModeFavorite(index: index, isFavorite: false)
    }

    public func deleteCustomAudioMode(slot: Int) async throws -> BossAudioModeConfig {
        let configs = try await audioModeConfigs()
        guard let existing = configs.first(where: { $0.modeIndex == slot }) else {
            throw BossSessionError.customAudioModeSlotNotFound(slot)
        }
        guard existing.userConfigurable else {
            throw BossSessionError.customAudioModeSlotNotEditable(slot)
        }

        if existing.favorite {
            _ = try await unfavoriteAudioMode(index: slot)
        }

        return try await writeCustomAudioMode(
            slot: slot,
            name: "",
            settings: existing.deletedSettingsBaseline,
            prompt: .none
        )
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
                throw BossSessionError.customAudioModeSlotNotEditable(requestedSlot)
            }
            slot = requestedSlot
        } else {
            guard let freeSlot = Self.firstFreeCustomAudioModeSlot(in: configs) else {
                throw BossSessionError.noFreeCustomAudioModeSlot
            }
            slot = freeSlot
        }

        return try await writeCustomAudioMode(slot: slot, name: name, settings: settings, prompt: prompt)
    }
}

private extension BossSession {
    func timeoutError(for timeout: Duration) -> BossSessionError {
        .responseTimedOut(seconds: timeout.components.seconds)
    }

    func mapSessionErrors<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let error as BmapResponseError {
            throw BossSessionError.bmapErrorResponse(
                context: error.context,
                payloadHex: error.payloadHex
            )
        } catch let error as BossLinkError where error == .unexpectedStreamTermination {
            throw BossSessionError.responseStreamEnded
        }
    }

    func awaitSettingsSnapshot(timeout: Duration) async throws -> BossSettingsSnapshot {
        try await mapSessionErrors {
            try await packetSession.settingsSnapshot(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func awaitAudioModeConfigs(timeout: Duration) async throws -> [BossAudioModeConfig] {
        try await mapSessionErrors {
            try await packetSession.audioModeConfigs(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func currentAudioModeIfAvailable(timeout: Duration) async throws -> Int? {
        do {
            return try await requiredCurrentAudioMode(timeout: timeout)
        } catch {
            guard Self.shouldFallbackForAudioModeWrite(error) else {
                throw error
            }
            return nil
        }
    }

    func requiredCurrentAudioMode(timeout: Duration) async throws -> Int {
        try await mapSessionErrors {
            try await packetSession.currentAudioMode(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func requiredEqualizer(timeout: Duration) async throws -> BossEqualizerSettings {
        try await mapSessionErrors {
            try await packetSession.equalizerSettings(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func requiredAudioModeSettingsConfig(timeout: Duration) async throws -> BossAudioModeSettingsConfig {
        try await mapSessionErrors {
            try await packetSession.audioModeSettingsConfig(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func requiredFavoriteAudioModeIndices(timeout: Duration) async throws -> [Int] {
        try await mapSessionErrors {
            try await packetSession.favoriteAudioModeIndices(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func requiredAudioModeCapabilities(timeout: Duration) async throws -> BossAudioModesCapabilities {
        try await mapSessionErrors {
            try await packetSession.audioModeCapabilities(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func readAudioModeSettingsConfig(
        attempts: Int,
        timeoutPerAttempt: Duration,
        retryDelay: Duration
    ) async throws -> BossAudioModeSettingsConfig {
        var lastError: Error = timeoutError(for: timeoutPerAttempt)
        for attempt in 0..<attempts {
            do {
                return try await requiredAudioModeSettingsConfig(timeout: timeoutPerAttempt)
            } catch {
                lastError = error
                guard Self.isRecoverableAudioModeSettingsConfigError(error), attempt < attempts - 1 else {
                    throw error
                }
                try await Task.sleep(for: retryDelay)
            }
        }
        throw lastError
    }

    func sendEqualizerSetGets(
        _ requests: [(BossEqualizerBand, Int)],
        timeout: Duration
    ) async throws -> BossEqualizerSettings {
        try await mapSessionErrors {
            try await packetSession.setEqualizer(
                requests: requests,
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func sendAudioModeSettingsConfigSetGet(
        _ config: BossAudioModeSettingsConfig,
        timeout: Duration
    ) async throws -> BossAudioModeSettingsConfig {
        try await mapSessionErrors {
            try await packetSession.setAudioModeSettingsConfig(
                config,
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func sendAudioModeConfigSetGet(
        modeIndex: Int,
        prompt: BossAudioModePrompt,
        name: String,
        settings: BossAudioModeSettingsConfig,
        timeout: Duration
    ) async throws -> BossAudioModeConfig {
        try await mapSessionErrors {
            try await packetSession.setAudioModeConfig(
                modeIndex: modeIndex,
                prompt: prompt,
                name: name,
                settings: settings,
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func sendAudioModeFavoritesSetGet(
        numberOfModes: Int,
        favoriteModeIndices: [Int],
        timeout: Duration
    ) async throws -> [Int] {
        try await mapSessionErrors {
            try await packetSession.setFavoriteAudioModeIndices(
                numberOfModes: numberOfModes,
                favoriteModeIndices: favoriteModeIndices,
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func onHeadDetectionIfAvailable(timeout: Duration) async throws -> BossOnHeadDetectionValue? {
        try await mapSessionErrors {
            try await packetSession.onHeadDetection(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func enabledSettingIfAvailable(functionRaw: UInt8, timeout: Duration) async throws -> Bool? {
        try await mapSessionErrors {
            try await packetSession.enabledSetting(
                functionRaw: functionRaw,
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func volumeControlIfAvailable(timeout: Duration) async throws -> BossVolumeControlStatus? {
        try await mapSessionErrors {
            try await packetSession.volumeControlStatus(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func equalizerIfAvailable(
        from snapshot: BossSettingsSnapshot,
        timeout: Duration
    ) async throws -> BossEqualizerSettings? {
        if let value = try snapshot.equalizer() {
            return value
        }
        return try await Self.observeSettingAfterDirectRead(
            initialUnavailableReason: .missingFromSnapshot,
            read: { try await self.requiredEqualizer(timeout: timeout) }
        ).value
    }

    func deviceSettingsReport(
        from snapshot: BossSettingsSnapshot,
        timeout: Duration
    ) async throws -> BossDeviceSettingsReport {
        let wearDetection = try await observedWearDetection(from: snapshot, timeout: timeout)
        let autoAwareEnabled = try await observedEnabledSetting(
            functionRaw: BossSettingsCodec.autoAwareFunctionRaw,
            snapshotValue: try snapshot.autoAware(),
            snapshotPacketExists: snapshot.packet(functionRaw: BossSettingsCodec.autoAwareFunctionRaw) != nil,
            timeout: timeout
        )
        let autoPlayPauseEnabled = try await observedEnabledSetting(
            functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw,
            snapshotValue: try snapshot.autoPlayPause(),
            snapshotPacketExists: snapshot.packet(functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw) != nil,
            timeout: timeout
        )
        let autoAnswerEnabled = try await observedAutoAnswer(from: snapshot, timeout: timeout)
        let volumeControl = try await observedVolumeControl(from: snapshot, timeout: timeout)

        return BossDeviceSettingsReport(
            wearDetection: wearDetection,
            autoAwareEnabled: autoAwareEnabled,
            autoPlayPauseEnabled: autoPlayPauseEnabled,
            autoAnswerEnabled: autoAnswerEnabled,
            volumeControl: volumeControl
        )
    }

    func observedWearDetection(
        from snapshot: BossSettingsSnapshot,
        timeout: Duration
    ) async throws -> BossObservedSetting<BossOnHeadDetectionValue> {
        if let value = try snapshot.onHeadDetection() {
            return BossObservedSetting(value: value, source: .snapshot)
        }
        return try await Self.observeSettingAfterDirectRead(
            initialUnavailableReason: .missingFromSnapshot,
            read: { try await self.onHeadDetectionIfAvailable(timeout: timeout) }
        )
    }

    func observedEnabledSetting(
        functionRaw: UInt8,
        snapshotValue: Bool?,
        snapshotPacketExists: Bool,
        timeout: Duration
    ) async throws -> BossObservedSetting<Bool> {
        if let snapshotValue {
            return BossObservedSetting(value: snapshotValue, source: .snapshot)
        }
        return try await Self.observeSettingAfterDirectRead(
            initialUnavailableReason: snapshotPacketExists ? .dataUnavailable : .missingFromSnapshot,
            read: { try await self.enabledSettingIfAvailable(functionRaw: functionRaw, timeout: timeout) }
        )
    }

    func observedAutoAnswer(
        from snapshot: BossSettingsSnapshot,
        timeout: Duration
    ) async throws -> BossObservedSetting<Bool> {
        if let packet = snapshot.packet(functionRaw: BossSettingsCodec.autoAnswerFunctionRaw) {
            return BossObservedSetting(
                value: try BossSettingsCodec.parseEnabledFlag(from: packet),
                source: .snapshot
            )
        }
        if let derived = try snapshot.onHeadDetection()?.isAutoAnswerEnabled {
            return BossObservedSetting(value: derived, source: .compositeSnapshot)
        }
        return try await Self.observeSettingAfterDirectRead(
            initialUnavailableReason: .missingFromSnapshot,
            read: { try await self.enabledSettingIfAvailable(functionRaw: BossSettingsCodec.autoAnswerFunctionRaw, timeout: timeout) }
        )
    }

    func observedVolumeControl(
        from snapshot: BossSettingsSnapshot,
        timeout: Duration
    ) async throws -> BossObservedSetting<BossVolumeControlStatus> {
        if let value = try snapshot.volumeControl() {
            return BossObservedSetting(value: value, source: .snapshot)
        }
        return try await Self.observeSettingAfterDirectRead(
            initialUnavailableReason: .missingFromSnapshot,
            read: { try await self.volumeControlIfAvailable(timeout: timeout) }
        )
    }

    func verifyCurrentAudioMode(
        targetIndex: Int,
        timeoutPerAttempt: Duration,
        attempts: Int,
        retryDelay: Duration,
        fallbackError: Error? = nil
    ) async throws -> Int {
        var lastError: Error = fallbackError ?? timeoutError(for: timeoutPerAttempt)
        var lastObservedIndex: Int?
        for attempt in 0..<attempts {
            do {
                let currentIndex = try await requiredCurrentAudioMode(timeout: timeoutPerAttempt)
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
            throw BossSessionError.modeChangeNotObserved(targetIndex: targetIndex, observedIndex: lastObservedIndex)
        }
        throw fallbackError ?? lastError
    }

    func setEnabledSetting(functionRaw: UInt8, enabled: Bool) async throws -> Bool {
        try await mapSessionErrors {
            try await packetSession.setEnabledSetting(
                functionRaw: functionRaw,
                enabled: enabled,
                timeout: .seconds(5),
                timeoutError: timeoutError(for: .seconds(5))
            )
        }
    }

    func setAudioModeFavorite(index: Int, isFavorite: Bool) async throws -> [Int] {
        let numberOfModes = try await requiredAudioModeCapabilities(timeout: .seconds(5)).totalModes
        var favorites = Set(try await requiredFavoriteAudioModeIndices(timeout: .seconds(5)))
        if isFavorite {
            favorites.insert(index)
        } else {
            favorites.remove(index)
        }
        let requestedFavorites = Array(favorites).sorted()

        return try await sendAudioModeFavoritesSetGet(
            numberOfModes: numberOfModes,
            favoriteModeIndices: requestedFavorites,
            timeout: .seconds(5)
        )
    }

    func writeCustomAudioMode(
        slot: Int,
        name: String,
        settings: BossAudioModeSettingsConfig,
        prompt: BossAudioModePrompt
    ) async throws -> BossAudioModeConfig {
        try await sendAudioModeConfigSetGet(
            modeIndex: slot,
            prompt: prompt,
            name: name,
            settings: settings,
            timeout: .seconds(5)
        )
    }

    static func observeSettingAfterDirectRead<Value: Sendable & Equatable>(
        initialUnavailableReason: BossSettingUnavailableReason,
        read: @escaping @Sendable () async throws -> Value?
    ) async throws -> BossObservedSetting<Value> {
        try await BossSettingObservation.observeAfterDirectRead(
            initialUnavailableReason: initialUnavailableReason,
            read: read
        )
    }

    static func unavailableSettingReason(_ error: Error) -> BossSettingUnavailableReason? {
        BossSettingObservation.unavailableReason(for: error)
    }

    static func shouldFallbackForAudioModeWrite(_ error: Error) -> Bool {
        if let error = error as? BossSessionError {
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

    static func isRecoverableAudioModeSettingsConfigError(_ error: Error) -> Bool {
        if shouldFallbackForAudioModeWrite(error) {
            return true
        }
        if let error = error as? BossSessionError {
            switch error {
            case .settingsConfigNotObserved:
                return true
            case .bmapErrorResponse:
                return error.bmapErrorCode == .insecureTransport ||
                    error.bmapErrorCode == .timeout ||
                    error.bmapErrorCode == .busy
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
        if let error = error as? BossSessionError {
            switch error {
            case .equalizerNotObserved:
                return true
            case .bmapErrorResponse:
                return error.bmapErrorCode == .insecureTransport ||
                    error.bmapErrorCode == .timeout ||
                    error.bmapErrorCode == .busy
            default:
                return false
            }
        }
        return false
    }

    static func validatedEqualizerRequests(
        _ update: BossEqualizerSettingsPatch,
        current: BossEqualizerSettings
    ) throws -> [(BossEqualizerBand, Int)] {
        try update.requestedLevels.map { band, level in
            guard let range = current.range(for: band) else {
                throw BossSessionError.unsupportedOperation(
                    "This device/session does not expose the \(band.displayName) equalizer band over BMAP"
                )
            }
            guard (range.minLevel...range.maxLevel).contains(level) else {
                throw BossSessionError.unsupportedOperation(
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

    static func firstFreeCustomAudioModeSlot(in configs: [BossAudioModeConfig]) -> Int? {
        configs
            .filter(\.userConfigurable)
            .first(where: { !$0.userConfigured && $0.name.isEmpty })?
            .modeIndex
    }

    static func bmapErrorCode(from payloadHex: String) -> BmapErrorCode? {
        guard payloadHex.count == 2, let rawValue = UInt8(payloadHex, radix: 16) else {
            return nil
        }
        return BmapErrorCode(rawValue: rawValue)
    }

    static func mapStream<T: Sendable>(
        _ upstream: AsyncThrowingStream<BmapPacket, Error>,
        transform: @escaping @Sendable (BmapPacket) throws -> T
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await packet in upstream {
                        continuation.yield(try transform(packet))
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
}
