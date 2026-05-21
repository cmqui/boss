import Foundation

extension BossAppleController {
    static func awaitAudioModeConfigs(
        on link: BossAppleLink,
        timeout: Duration
    ) async throws -> [BossAudioModeConfig] {
        try await link.send(packet: try modeConfigStartPacket())
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
                    let mode = try parseModeConfigDetail(from: packet)
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
        on link: BossAppleLink,
        timeout: Duration
    ) async throws -> Int? {
        do {
            let response = try await sendAndAwaitSameFunction(
                packet: try currentModeGetPacket(),
                on: link,
                timeout: timeout
            )
            return try parseCurrentMode(from: response)
        } catch {
            guard shouldFallbackForAudioModeWrite(error) else {
                throw error
            }
            return nil
        }
    }

    static func requiredCurrentAudioMode(
        on link: BossAppleLink,
        timeout: Duration
    ) async throws -> Int {
        let response = try await sendAndAwaitSameFunction(
            packet: try currentModeGetPacket(),
            on: link,
            timeout: timeout
        )
        return try parseCurrentMode(from: response)
    }

    static func requiredEqualizer(
        on link: BossAppleLink,
        timeout: Duration
    ) async throws -> BossEqualizerSettings {
        let response = try await sendAndAwaitSameFunction(
            packet: try equalizerGetPacket(),
            on: link,
            timeout: timeout
        )
        return try parseEqualizer(from: response)
    }

    static func requiredAudioModeSettingsConfig(
        on link: BossAppleLink,
        timeout: Duration
    ) async throws -> BossAudioModeSettingsConfig {
        let response = try await sendAndAwaitSameFunction(
            packet: try settingsConfigGetPacket(),
            on: link,
            timeout: timeout
        )
        return try parseSettingsConfig(from: response)
    }

    static func requiredFavoriteAudioModeIndices(
        on link: BossAppleLink,
        timeout: Duration
    ) async throws -> [Int] {
        let response = try await sendAndAwaitSameFunction(
            packet: try favoritesGetPacket(),
            on: link,
            timeout: timeout
        )
        return try parseFavorites(from: response)
    }

    static func requiredAudioModeCapabilities(
        on link: BossAppleLink,
        timeout: Duration
    ) async throws -> BossAudioModesCapabilities {
        let response = try await sendAndAwaitSameFunction(
            packet: try capabilitiesGetPacket(),
            on: link,
            timeout: timeout
        )
        return try parseCapabilities(from: response)
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
        on link: BossAppleLink,
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
        on link: BossAppleLink,
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
        on link: BossAppleLink,
        timeout: Duration
    ) async throws -> BossEqualizerSettings {
        let packet = try equalizerSetGetPacket(targetLevel: targetLevel, band: band)
        let response = try await sendAndAwaitSameFunction(packet: packet, on: link, timeout: timeout)
        return try parseEqualizer(from: response)
    }

    static func sendAudioModeSettingsConfigSetGet(
        _ config: BossAudioModeSettingsConfig,
        on link: BossAppleLink,
        timeout: Duration
    ) async throws -> BossAudioModeSettingsConfig {
        let packet = try settingsConfigSetGetPacket(config)
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
        return try parseSettingsConfig(from: response)
    }

    static func sendAudioModeConfigSetGet(
        modeIndex: Int,
        prompt: BossAudioModePrompt,
        name: String,
        settings: BossAudioModeSettingsConfig,
        on link: BossAppleLink,
        timeout: Duration
    ) async throws -> BossAudioModeConfig {
        let packet = try modeConfigSetGetPacket(modeIndex: modeIndex, prompt: prompt, name: name, settings: settings)
        let response = try await sendAndAwaitSameFunction(packet: packet, on: link, timeout: timeout)
        return try parseModeConfigDetail(from: response)
    }

    static func sendAudioModeFavoritesSetGet(
        numberOfModes: Int,
        favoriteModeIndices: [Int],
        on link: BossAppleLink,
        timeout: Duration
    ) async throws -> [Int] {
        let packet = try favoritesSetGetPacket(numberOfModes: numberOfModes, favoriteModeIndices: favoriteModeIndices)
        let response = try await sendAndAwaitSameFunction(packet: packet, on: link, timeout: timeout)
        return try parseFavorites(from: response)
    }

    static func namesSupportedGetPacket() throws -> BossAppleBmapPacket {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.namesSupportedGetPacket(runtime: runtime)
        }
        return BossAudioModesCodec.namesSupportedGetPacket()
    }

    static func settingsGetAllStartPacket() throws -> BossAppleBmapPacket {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.settingsGetAllStartPacket(runtime: runtime)
        }
        return BossSettingsCodec.settingsPacket(functionRaw: BossSettingsCodec.settingsGetAllFunctionRaw, operatorValue: .start)
    }

    static func modeConfigStartPacket() throws -> BossAppleBmapPacket {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.modeConfigStartPacket(runtime: runtime)
        }
        return BossAudioModesCodec.modeConfigStartPacket()
    }

    static func currentModeGetPacket() throws -> BossAppleBmapPacket {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.currentModeGetPacket(runtime: runtime)
        }
        return BossAudioModesCodec.currentModeGetPacket()
    }

    static func equalizerGetPacket() throws -> BossAppleBmapPacket {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.equalizerGetPacket(runtime: runtime)
        }
        return BossSettingsCodec.equalizerGetPacket()
    }

    static func settingsConfigGetPacket() throws -> BossAppleBmapPacket {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.settingsConfigGetPacket(runtime: runtime)
        }
        return BossAudioModesCodec.settingsConfigGetPacket()
    }

    static func favoritesGetPacket() throws -> BossAppleBmapPacket {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.favoritesGetPacket(runtime: runtime)
        }
        return BossAudioModesCodec.favoritesGetPacket()
    }

    static func capabilitiesGetPacket() throws -> BossAppleBmapPacket {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.capabilitiesGetPacket(runtime: runtime)
        }
        return BossAudioModesCodec.capabilitiesGetPacket()
    }

    static func equalizerSetGetPacket(targetLevel: Int, band: BossEqualizerBand) throws -> BossAppleBmapPacket {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.equalizerSetGetPacket(targetLevel: targetLevel, band: band, runtime: runtime)
        }
        return try BossSettingsCodec.equalizerSetGetPacket(targetLevel: targetLevel, band: band)
    }

    static func settingsConfigSetGetPacket(_ config: BossAudioModeSettingsConfig) throws -> BossAppleBmapPacket {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.settingsConfigSetGetPacket(config, runtime: runtime)
        }
        return try BossAudioModesCodec.settingsConfigSetGetPacket(config)
    }

    static func modeConfigSetGetPacket(modeIndex: Int, prompt: BossAudioModePrompt, name: String, settings: BossAudioModeSettingsConfig) throws -> BossAppleBmapPacket {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.modeConfigSetGetPacket(modeIndex: modeIndex, prompt: prompt, name: name, settings: settings, runtime: runtime)
        }
        return try BossAudioModesCodec.modeConfigSetGetPacket(modeIndex: modeIndex, prompt: prompt, name: name, settings: settings)
    }

    static func favoritesSetGetPacket(numberOfModes: Int, favoriteModeIndices: [Int]) throws -> BossAppleBmapPacket {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.favoritesSetGetPacket(numberOfModes: numberOfModes, favoriteModeIndices: favoriteModeIndices, runtime: runtime)
        }
        return try BossAudioModesCodec.favoritesSetGetPacket(numberOfModes: numberOfModes, favoriteModeIndices: favoriteModeIndices)
    }

    static func parseSupportedPrompts(from packet: BossAppleBmapPacket) throws -> [BossAudioModePrompt] {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.parseSupportedPrompts(from: packet, runtime: runtime)
        }
        return try BossAudioModesCodec.parseSupportedPrompts(from: packet)
    }

    static func parseCurrentMode(from packet: BossAppleBmapPacket) throws -> Int {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.parseCurrentMode(from: packet, runtime: runtime)
        }
        return try BossAudioModesCodec.parseCurrentMode(from: packet)
    }

    static func parseEqualizer(from packet: BossAppleBmapPacket) throws -> BossEqualizerSettings {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.parseEqualizer(from: packet, runtime: runtime)
        }
        return try BossSettingsCodec.parseEqualizer(from: packet)
    }

    static func parseSettingsConfig(from packet: BossAppleBmapPacket) throws -> BossAudioModeSettingsConfig {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.parseSettingsConfig(from: packet, runtime: runtime)
        }
        return try BossAudioModesCodec.parseSettingsConfig(from: packet)
    }

    static func parseFavorites(from packet: BossAppleBmapPacket) throws -> [Int] {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.parseFavorites(from: packet, runtime: runtime)
        }
        return try BossAudioModesCodec.parseFavorites(from: packet)
    }

    static func parseCapabilities(from packet: BossAppleBmapPacket) throws -> BossAudioModesCapabilities {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.parseCapabilities(from: packet, runtime: runtime)
        }
        return try BossAudioModesCodec.parseCapabilities(from: packet)
    }

    static func parseModeConfigDetail(from packet: BossAppleBmapPacket) throws -> BossAudioModeConfig {
        if let runtime = BossRustFfiRuntime.shared {
            return try BossRustCodecBridge.parseModeConfigDetail(from: packet, runtime: runtime)
        }
        return try BossAudioModesCodec.parseModeConfigDetail(from: packet)
    }

}
