import Foundation
import libboss

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
        try await observedWearDetection(
            from: snapshot,
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
        try await observedEnabledSetting(
            snapshotValue: snapshotValue,
            snapshotPacketExists: snapshotPacketExists,
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
        try await observedAutoAnswer(
            from: snapshot,
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
        try await observedVolumeControl(
            from: snapshot,
            read: {
                try await readVolumeControl(connection: fallbackConnection, timeout: timeout)
            }
        )
    }

    static func observeSettingAfterDirectRead<Value: Sendable & Equatable>(
        initialUnavailableReason: BossAppleSettingUnavailableReason,
        read: @escaping @Sendable () async throws -> Value?
    ) async throws -> BossAppleObservedSetting<Value> {
        let observed = try await BossSettingObservation.observeAfterDirectRead(
            initialUnavailableReason: wrap(initialUnavailableReason),
            read: read
        )
        return wrap(observed)
    }

    static func readOnHeadDetection(
        connection: BossAppleConnectionOptions,
        timeout: Duration = .seconds(5)
    ) async throws -> BossOnHeadDetectionValue? {
        try await withConnectedLinkRetrying(connection, shouldRetry: retrySecureCharacteristicIfNeeded) { link in
            try await onHeadDetectionIfAvailable(on: link, timeout: timeout)
        }
    }

    static func readStandbyTimer(
        connection: BossAppleConnectionOptions,
        timeout: Duration = .seconds(5)
    ) async throws -> BossStandbyTimerValue? {
        try await withConnectedLinkRetrying(connection, shouldRetry: retrySecureCharacteristicIfNeeded) { link in
            try await standbyTimerIfAvailable(on: link, timeout: timeout)
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

    static func standbyTimerIfAvailable(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossStandbyTimerValue? {
        let response = try await sendAndAwaitSameFunction(
            packet: BossSettingsCodec.standbyTimerGetPacket(),
            on: link,
            timeout: timeout
        )
        return try BossSettingsCodec.parseStandbyTimer(from: response)
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
        try await observedWearDetection(
            from: snapshot,
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
        try await observedEnabledSetting(
            snapshotValue: snapshotValue,
            snapshotPacketExists: snapshotPacketExists,
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
        try await observedAutoAnswer(
            from: snapshot,
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
        try await observedVolumeControl(
            from: snapshot,
            read: {
                try await volumeControlIfAvailable(on: link, timeout: timeout)
            }
        )
    }

    private static func observedWearDetection(
        from snapshot: BossSettingsSnapshot,
        read: @escaping @Sendable () async throws -> BossOnHeadDetectionValue?
    ) async throws -> BossAppleObservedSetting<BossOnHeadDetectionValue> {
        if let value = try snapshot.onHeadDetection() {
            return BossAppleObservedSetting(value: value, source: .snapshot)
        }
        return try await observeSettingAfterDirectRead(initialUnavailableReason: .missingFromSnapshot, read: read)
    }

    private static func observedEnabledSetting(
        snapshotValue: Bool?,
        snapshotPacketExists: Bool,
        read: @escaping @Sendable () async throws -> Bool?
    ) async throws -> BossAppleObservedSetting<Bool> {
        if let snapshotValue {
            return BossAppleObservedSetting(value: snapshotValue, source: .snapshot)
        }
        return try await observeSettingAfterDirectRead(
            initialUnavailableReason: snapshotPacketExists ? .dataUnavailable : .missingFromSnapshot,
            read: read
        )
    }

    private static func observedAutoAnswer(
        from snapshot: BossSettingsSnapshot,
        read: @escaping @Sendable () async throws -> Bool?
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
        return try await observeSettingAfterDirectRead(initialUnavailableReason: .missingFromSnapshot, read: read)
    }

    private static func observedVolumeControl(
        from snapshot: BossSettingsSnapshot,
        read: @escaping @Sendable () async throws -> BossVolumeControlStatus?
    ) async throws -> BossAppleObservedSetting<BossVolumeControlStatus> {
        if let value = try snapshot.volumeControl() {
            return BossAppleObservedSetting(value: value, source: .snapshot)
        }
        return try await observeSettingAfterDirectRead(initialUnavailableReason: .missingFromSnapshot, read: read)
    }
}
