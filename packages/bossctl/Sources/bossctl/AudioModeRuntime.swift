import Foundation
import libboss
import libbossApple

extension BossctlCLI {
    static func awaitAudioModeConfigs(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> [BossAudioModeInfo] {
        try await link.send(packet: BossAudioModesCodec.modeConfigStartPacket())
        return try await withThrowingTaskGroup(of: [BossAudioModeInfo].self) { group in
            group.addTask {
                var modesByIndex: [Int: BossAudioModeInfo] = [:]
                for try await packet in link.packets {
                    guard packet.functionBlock == .audioModes,
                          packet.function.rawValue == BossAudioModesCodec.modeConfigFunctionRaw else {
                        continue
                    }
                    if packet.operator == .error {
                        throw BossctlError.bmapErrorResponse(
                            context: "audioModes.\(packet.function.name)",
                            payloadHex: packet.payload.hexString
                        )
                    }
                    if packet.operator == .result {
                        return modesByIndex.values.sorted { $0.modeIndex < $1.modeIndex }
                    }
                    guard packet.operator == .status else {
                        continue
                    }
                    let mode = try BossAudioModesCodec.parseModeConfig(from: packet)
                    modesByIndex[mode.modeIndex] = mode
                }
                throw BossctlError.responseStreamEnded
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw BossctlError.responseTimedOut(seconds: timeout.components.seconds)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
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

    static func readAudioModeSettingsConfigAfterReconnect(
        connection: ConnectionOptions,
        attempts: Int = 3,
        retryDelay: Duration = .milliseconds(750)
    ) async throws -> BossAudioModeSettingsConfig {
        var lastError: Error = BossctlError.responseTimedOut(seconds: 5)
        for attempt in 0..<attempts {
            do {
                debug("settings-config read attempt \(attempt + 1)/\(attempts)")
                return try await withConnectedLinkRetrying(connection, shouldRetry: retrySecureCharacteristicIfNeeded) { link in
                    try await readAudioModeSettingsConfig(on: link, attempts: 2, timeoutPerAttempt: .seconds(5), retryDelay: .milliseconds(300))
                }
            } catch {
                debug("settings-config read attempt \(attempt + 1) failed: \(error)")
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
        var lastError: Error = BossctlError.responseTimedOut(seconds: timeoutPerAttempt.components.seconds)
        for attempt in 0..<attempts {
            do {
                debug("settings-config same-link read attempt \(attempt + 1)/\(attempts)")
                return try await requiredAudioModeSettingsConfig(on: link, timeout: timeoutPerAttempt)
            } catch {
                debug("settings-config same-link read attempt \(attempt + 1) failed: \(error)")
                lastError = error
                guard isRecoverableAudioModeSettingsConfigError(error), attempt < attempts - 1 else {
                    throw error
                }
                try await Task.sleep(for: retryDelay)
            }
        }
        throw lastError
    }

    static func setAudioModeSettingsConfigWithVerification(
        _ update: BossAudioModeSettingsConfigPatch,
        connection: ConnectionOptions
    ) async throws -> AudioModeSettingsConfigWriteResult {
        let current = try await readAudioModeSettingsConfigAfterReconnect(connection: connection)
        let target = update.merged(with: current)
        guard target != current else {
            return .unchanged(current)
        }

        var lastRecoverableError: Error?
        for attempt in 0..<2 {
            do {
                debug("settings-config write attempt \(attempt + 1)/2 target=\(describe(target))")
                let updated = try await withConnectedLinkRetrying(connection, shouldRetry: retrySecureCharacteristicIfNeeded) { link in
                    try await sendAudioModeSettingsConfigSetGet(target, on: link, timeout: .seconds(5))
                }
                guard update.matches(updated) else {
                    throw BossctlError.settingsConfigNotObserved(
                        expected: describe(target),
                        observed: describe(updated)
                    )
                }
                return .updated(updated)
            } catch {
                debug("settings-config write attempt \(attempt + 1) failed: \(error)")
                guard isRecoverableAudioModeSettingsConfigError(error) else {
                    throw error
                }
                lastRecoverableError = error

                do {
                    let verified = try await readAudioModeSettingsConfigAfterReconnect(connection: connection, attempts: 3)
                    if update.matches(verified) {
                        return .updated(verified)
                    }
                    debug("settings-config verification observed non-target config: \(describe(verified))")
                } catch {
                    debug("settings-config verification after ambiguous write failed: \(error)")
                    lastRecoverableError = error
                }

                if attempt == 0 {
                    try await Task.sleep(for: .seconds(1))
                }
            }
        }

        if let lastRecoverableError {
            debug("settings-config final verification inconclusive: \(lastRecoverableError)")
        }
        return .verificationInconclusive(target)
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
            throw BossctlError.bmapErrorResponse(
                context: "\(packet.functionBlock.displayName).\(packet.function.name)",
                payloadHex: response.payload.hexString
            )
        }
        return try BossAudioModesCodec.parseSettingsConfig(from: response)
    }

    static func verifyCurrentAudioMode(
        on link: BleBmapLink,
        targetIndex: Int,
        timeoutPerAttempt: Duration,
        attempts: Int,
        retryDelay: Duration,
        fallbackError: Error? = nil
    ) async throws -> Int {
        var lastError: Error = fallbackError ?? BossctlError.responseTimedOut(seconds: timeoutPerAttempt.components.seconds)
        var lastObservedIndex: Int?
        for attempt in 0..<attempts {
            do {
                debug("verifying current audio mode attempt \(attempt + 1)/\(attempts) target=\(targetIndex)")
                let currentIndex = try await requiredCurrentAudioMode(on: link, timeout: timeoutPerAttempt)
                debug("verification attempt \(attempt + 1) observed current mode=\(currentIndex)")
                lastObservedIndex = currentIndex
                if currentIndex == targetIndex {
                    return currentIndex
                }
            } catch {
                debug("verification attempt \(attempt + 1) failed: \(error)")
                lastError = error
            }
            if attempt < attempts - 1 {
                try await Task.sleep(for: retryDelay)
            }
        }
        if let lastObservedIndex {
            throw BossctlError.modeChangeNotObserved(targetIndex: targetIndex, observedIndex: lastObservedIndex)
        }
        throw fallbackError ?? lastError
    }

    static func verifyCurrentAudioModeAfterReconnect(
        connection: ConnectionOptions,
        targetIndex: Int,
        fallbackError: Error
    ) async throws -> Int {
        var lastError: Error = fallbackError
        for attempt in 0..<4 {
            do {
                debug("reconnect verification attempt \(attempt + 1)/4 target=\(targetIndex)")
                let currentIndex = try await withConnectedLinkRetrying(
                    audioModeReadConnectionOptions(for: connection),
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
                debug("reconnect verification succeeded with mode=\(currentIndex)")
                return currentIndex
            } catch {
                debug("reconnect verification attempt \(attempt + 1) failed: \(error)")
                lastError = error
                try await Task.sleep(for: .seconds(1))
            }
        }
        throw lastError
    }

    static func shouldFallbackForAudioModeWrite(_ error: Error) -> Bool {
        if let error = error as? BossctlError {
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
        if case BossctlError.responseTimedOut = error {
            return true
        }
        if case BossctlError.bmapErrorResponse(_, let payloadHex) = error,
           bmapErrorCode(from: payloadHex) == .insecureTransport {
            return true
        }
        return false
    }

    static func isRecoverableAudioModeSettingsConfigError(_ error: Error) -> Bool {
        if shouldFallbackForAudioModeWrite(error) {
            return true
        }
        if let error = error as? BossctlError {
            switch error {
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
        if let error = error as? BossctlError {
            switch error {
            case .bmapErrorResponse(_, let payloadHex):
                return bmapErrorCode(from: payloadHex) == .insecureTransport
            default:
                return false
            }
        }
        return false
    }

    static func displayableAudioModes(from modes: [BossAudioModeInfo]) -> [BossAudioModeInfo] {
        modes.filter { mode in
            !(mode.userConfigurable && !mode.userConfigured && mode.name == "None")
        }
    }

    static func resolveAudioModeSelection(
        _ selection: AudioModeSelection,
        on link: BleBmapLink
    ) async throws -> Int {
        switch selection {
        case .index(let index):
            return index
        case .name(let name):
            let normalizedTarget = normalizeAudioModeName(name)
            if let builtInIndex = builtInAudioModeIndex(for: normalizedTarget) {
                return builtInIndex
            }
            let modes = try await awaitAudioModeConfigs(on: link, timeout: .seconds(30))
            guard let match = displayableAudioModes(from: modes).first(where: {
                normalizeAudioModeName($0.name) == normalizedTarget
            }) else {
                throw UsageError("Unknown audio mode: \(name)")
            }
            return match.modeIndex
        }
    }

    static func normalizeAudioModeName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func builtInAudioModeIndex(for normalizedName: String) -> Int? {
        switch normalizedName {
        case "quiet":
            return 0
        case "aware":
            return 1
        case "immersion":
            return 2
        case "cinema":
            return 3
        default:
            return nil
        }
    }

}
