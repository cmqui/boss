import Foundation

extension BossAppleController {
    static func supportedAudioModePrompts(
        on link: BossAppleLink,
        timeout: Duration
    ) async throws -> [BossAppleAudioModePrompt] {
        let response = try await sendAndAwaitSameFunction(
            packet: try namesSupportedGetPacket(),
            on: link,
            timeout: timeout
        )
        return try parseSupportedPrompts(from: response)
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
        from stream: AsyncThrowingStream<BossAppleBmapPacket, Error>,
        matching predicate: @escaping @Sendable (BossAppleBmapPacket) -> Bool,
        timeout: Duration
    ) async throws -> BossAppleBmapPacket {
        try await withThrowingTaskGroup(of: BossAppleBmapPacket.self) { group in
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
        packet: BossAppleBmapPacket,
        on link: BossAppleLink,
        timeout: Duration
    ) async throws -> BossAppleBmapPacket {
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
