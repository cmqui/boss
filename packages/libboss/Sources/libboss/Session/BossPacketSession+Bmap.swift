import Foundation

public struct BmapResponseError: BossError, Equatable {
    public let context: String
    public let payloadHex: String
    public let code: BmapErrorCode?

    public init(context: String, payloadHex: String) {
        self.context = context
        self.payloadHex = payloadHex
        self.code = Self.bmapErrorCode(from: payloadHex)
    }

    private static func bmapErrorCode(from payloadHex: String) -> BmapErrorCode? {
        guard payloadHex.count == 2, let rawValue = UInt8(payloadHex, radix: 16) else {
            return nil
        }
        return BmapErrorCode(rawValue: rawValue)
    }
}

public extension BossPacketSession {
    func responsePacket(
        for packet: BmapPacket,
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BmapPacket {
        let response = try await sendAndAwait(
            packet: packet,
            matching: { incoming in
                incoming.functionBlock == packet.functionBlock &&
                    incoming.function == packet.function &&
                    incoming.operator.type == .response
            },
            timeout: timeout,
            timeoutError: timeoutError
        )
        if response.operator == .error {
            throw BmapResponseError(
                context: "\(packet.functionBlock.displayName).\(packet.function.name)",
                payloadHex: Self.hexString(response.payload)
            )
        }
        return response
    }

    func responsePacket(
        for packet: BmapPacket,
        matching function: BmapFunction,
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BmapPacket {
        let response = try await sendAndAwait(
            packet: packet,
            matching: { incoming in
                incoming.function == function && incoming.operator.type == .response
            },
            timeout: timeout,
            timeoutError: timeoutError
        )
        guard response.operator == .status else {
            throw UnexpectedOperatorError(expected: .status, actual: response.operator)
        }
        return response
    }

    func settingsSnapshot(
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BossSettingsSnapshot {
        try await send(packet: BossSettingsCodec.settingsPacket(
            functionRaw: BossSettingsCodec.settingsGetAllFunctionRaw,
            operatorValue: .start
        ))

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var snapshot: [UInt8: BmapPacket] = [:]

        while true {
            let remaining = clock.now.duration(to: deadline)
            if remaining <= .zero {
                throw timeoutError
            }

            let packet = try await firstPacket(
                matching: { $0.functionBlock == .settings },
                timeout: remaining,
                timeoutError: timeoutError
            )
            let rawFunction = packet.function.rawValue
            if rawFunction == BossSettingsCodec.settingsGetAllFunctionRaw, packet.operator == .error {
                throw BmapResponseError(
                    context: "settings.SettingsGetAll",
                    payloadHex: Self.hexString(packet.payload)
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
    }

    func audioModeConfigs(
        timeout: Duration,
        timeoutError: Error
    ) async throws -> [BossAudioModeConfig] {
        try await send(packet: BossAudioModesCodec.modeConfigStartPacket())

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var modesByIndex: [Int: BossAudioModeConfig] = [:]

        while true {
            let remaining = clock.now.duration(to: deadline)
            if remaining <= .zero {
                throw timeoutError
            }

            let packet = try await firstPacket(
                matching: {
                    $0.functionBlock == .audioModes && $0.function.rawValue == BossAudioModesCodec.modeConfigFunctionRaw
                },
                timeout: remaining,
                timeoutError: timeoutError
            )
            if packet.operator == .error {
                throw BmapResponseError(
                    context: "audioModes.\(packet.function.name)",
                    payloadHex: Self.hexString(packet.payload)
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
    }

    func supportedAudioModePrompts(
        timeout: Duration,
        timeoutError: Error
    ) async throws -> [BossAudioModePrompt] {
        let response = try await responsePacket(
            for: BossAudioModesCodec.namesSupportedGetPacket(),
            timeout: timeout,
            timeoutError: timeoutError
        )
        return try BossAudioModesCodec.parseSupportedPrompts(from: response)
    }

    func firmwareVersion(
        port: Int,
        deviceID: Int = 0,
        timeout: Duration,
        timeoutError: Error
    ) async throws -> FirmwareVersionInfo {
        let response = try await responsePacket(
            for: ProductInfoCommands.firmwareVersion(port: port, deviceID: deviceID),
            timeout: timeout,
            timeoutError: timeoutError
        )
        return try ProductInfoParser.parseFirmwareVersion(from: response)
    }

    func currentAudioMode(
        timeout: Duration,
        timeoutError: Error
    ) async throws -> Int {
        let response = try await responsePacket(
            for: BossAudioModesCodec.currentModeGetPacket(),
            timeout: timeout,
            timeoutError: timeoutError
        )
        return try BossAudioModesCodec.parseCurrentMode(from: response)
    }

    func audioModeCapabilities(
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BossAudioModesCapabilities {
        let response = try await responsePacket(
            for: BossAudioModesCodec.capabilitiesGetPacket(),
            timeout: timeout,
            timeoutError: timeoutError
        )
        return try BossAudioModesCodec.parseCapabilities(from: response)
    }

    func favoriteAudioModeIndices(
        timeout: Duration,
        timeoutError: Error
    ) async throws -> [Int] {
        let response = try await responsePacket(
            for: BossAudioModesCodec.favoritesGetPacket(),
            timeout: timeout,
            timeoutError: timeoutError
        )
        return try BossAudioModesCodec.parseFavorites(from: response)
    }

    func audioModeSettingsConfig(
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BossAudioModeSettingsConfig {
        let response = try await responsePacket(
            for: BossAudioModesCodec.settingsConfigGetPacket(),
            timeout: timeout,
            timeoutError: timeoutError
        )
        return try BossAudioModesCodec.parseSettingsConfig(from: response)
    }

    func setAudioModeSettingsConfig(
        _ config: BossAudioModeSettingsConfig,
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BossAudioModeSettingsConfig {
        let packet = try BossAudioModesCodec.settingsConfigSetGetPacket(config)
        let response = try await responsePacket(for: packet, timeout: timeout, timeoutError: timeoutError)
        return try BossAudioModesCodec.parseSettingsConfig(from: response)
    }

    func setAudioModeConfig(
        modeIndex: Int,
        prompt: BossAudioModePrompt,
        name: String,
        settings: BossAudioModeSettingsConfig,
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BossAudioModeConfig {
        let packet = try BossAudioModesCodec.modeConfigSetGetPacket(
            modeIndex: modeIndex,
            prompt: prompt,
            name: name,
            settings: settings
        )
        let response = try await responsePacket(for: packet, timeout: timeout, timeoutError: timeoutError)
        return try BossAudioModesCodec.parseModeConfigDetail(from: response)
    }

    func setFavoriteAudioModeIndices(
        numberOfModes: Int,
        favoriteModeIndices: [Int],
        timeout: Duration,
        timeoutError: Error
    ) async throws -> [Int] {
        let packet = try BossAudioModesCodec.favoritesSetGetPacket(
            numberOfModes: numberOfModes,
            favoriteModeIndices: favoriteModeIndices
        )
        let response = try await responsePacket(for: packet, timeout: timeout, timeoutError: timeoutError)
        return try BossAudioModesCodec.parseFavorites(from: response)
    }

    func equalizerSettings(
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BossEqualizerSettings {
        let response = try await responsePacket(
            for: BossSettingsCodec.equalizerGetPacket(),
            timeout: timeout,
            timeoutError: timeoutError
        )
        return try BossSettingsCodec.parseEqualizer(from: response)
    }

    func setEqualizer(
        requests: [(BossEqualizerBand, Int)],
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BossEqualizerSettings {
        var lastSettings: BossEqualizerSettings?
        for (band, level) in requests {
            let packet = try BossSettingsCodec.equalizerSetGetPacket(targetLevel: level, band: band)
            let response = try await responsePacket(for: packet, timeout: timeout, timeoutError: timeoutError)
            lastSettings = try BossSettingsCodec.parseEqualizer(from: response)
        }
        guard let lastSettings else {
            throw BossSettingsCodecError.invalidPayload("At least one equalizer band update is required")
        }
        return lastSettings
    }

    func onHeadDetection(
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BossOnHeadDetectionValue {
        let response = try await responsePacket(
            for: BossSettingsCodec.onHeadDetectionGetPacket(),
            timeout: timeout,
            timeoutError: timeoutError
        )
        return try BossSettingsCodec.parseOnHeadDetection(from: response)
    }

    func enabledSetting(
        functionRaw: UInt8,
        timeout: Duration,
        timeoutError: Error
    ) async throws -> Bool {
        let response = try await responsePacket(
            for: BossSettingsCodec.settingsPacket(
                functionRaw: functionRaw,
                operatorValue: .get
            ),
            timeout: timeout,
            timeoutError: timeoutError
        )
        return try BossSettingsCodec.parseEnabledFlag(from: response)
    }

    func setEnabledSetting(
        functionRaw: UInt8,
        enabled: Bool,
        timeout: Duration,
        timeoutError: Error
    ) async throws -> Bool {
        let response = try await responsePacket(
            for: BossSettingsCodec.settingsPacket(
                functionRaw: functionRaw,
                operatorValue: .setGet,
                payload: Data([enabled ? 0x01 : 0x00])
            ),
            timeout: timeout,
            timeoutError: timeoutError
        )
        return try BossSettingsCodec.parseEnabledFlag(from: response)
    }

    func setOnHeadDetection(
        _ value: BossOnHeadDetectionValue,
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BossOnHeadDetectionValue {
        let response = try await responsePacket(
            for: BossSettingsCodec.onHeadDetectionSetGetPacket(value),
            timeout: timeout,
            timeoutError: timeoutError
        )
        return try BossSettingsCodec.parseOnHeadDetection(from: response)
    }

    func volumeControlStatus(
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BossVolumeControlStatus {
        let response = try await responsePacket(
            for: BossSettingsCodec.settingsPacket(
                functionRaw: BossSettingsCodec.volumeControlFunctionRaw,
                operatorValue: .get
            ),
            timeout: timeout,
            timeoutError: timeoutError
        )
        return try BossAudioModesCodec.parseVolumeControlStatus(from: response)
    }

    func setVolumeControl(
        _ value: BossVolumeControlValue,
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BossVolumeControlStatus {
        let response = try await responsePacket(
            for: BossSettingsCodec.settingsPacket(
                functionRaw: BossSettingsCodec.volumeControlFunctionRaw,
                operatorValue: .setGet,
                payload: Data([value.rawValue])
            ),
            timeout: timeout,
            timeoutError: timeoutError
        )
        return try BossAudioModesCodec.parseVolumeControlStatus(from: response)
    }

    func startCurrentAudioModeChange(
        modeIndex: Int,
        playVoicePrompt: Bool,
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BmapPacket {
        try await responsePacket(
            for: BossAudioModesCodec.currentModeStartPacket(
                modeIndex: modeIndex,
                playVoicePrompt: playVoicePrompt
            ),
            timeout: timeout,
            timeoutError: timeoutError
        )
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}
