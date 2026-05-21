import Foundation
import libboss

extension BossAppleController {
    static func supportedAudioModePrompts(
        on link: BossAppleLink,
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
        on link: BossAppleLink,
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
        operation: @escaping @Sendable (BossAppleLink) async throws -> T
    ) async throws -> T {
        try await withConnectedLinkRetrying(options, shouldRetry: { _, _ in false }, operation: operation)
    }

    static func withConnectedLinkRetrying<T: Sendable>(
        _ options: BossAppleConnectionOptions,
        shouldRetry: @escaping @Sendable (Error, AppleBossCharacteristicPreference) -> Bool,
        operation: @escaping @Sendable (BossAppleLink) async throws -> T
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
        operation: @escaping @Sendable (BossAppleLink) async throws -> T
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
        let link = BossAppleLink(transport: transport)
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
        on link: BossAppleLink,
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
