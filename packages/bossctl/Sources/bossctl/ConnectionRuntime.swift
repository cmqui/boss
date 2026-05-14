import Foundation
import libboss
import libbossApple

extension BossctlCLI {
    static func settingsConnectionOptions(for options: ConnectionOptions) -> ConnectionOptions {
        guard options.characteristicPreference == .automatic else {
            return options
        }
        return options.withCharacteristicPreference(.secure)
    }

    static func audioModeConnectionOptions(for command: AudioModeCommand) -> ConnectionOptions {
        switch command.action {
        case .setCurrent, .getSettingsConfig, .setSettingsConfig, .setFavorite:
            return settingsConnectionOptions(for: command.connection)
        case .list, .getCurrent, .getFavorites:
            return command.connection
        }
    }

    static func audioModeReadConnectionOptions(for options: ConnectionOptions) -> ConnectionOptions {
        options
    }

    static func withConnectedLink<T: Sendable>(
        _ options: ConnectionOptions,
        operation: @escaping @Sendable (BleBmapLink) async throws -> T
    ) async throws -> T {
        try await withConnectedLinkRetrying(options, shouldRetry: { _, _ in false }, operation: operation)
    }

    static func withConnectedLinkRetrying<T: Sendable>(
        _ options: ConnectionOptions,
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
        _ options: ConnectionOptions,
        operation: @escaping @Sendable (BleBmapLink) async throws -> T
    ) async throws -> T {
        let filter = AppleBossScanFilter(
            peripheralIdentifier: options.identifier,
            nameContains: options.nameContains,
            scanTimeout: .seconds(options.timeoutSeconds)
        )
        let transport = try await AppleBleBossTransport.connect(
            filter: filter,
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

    static func debug(_ message: String) {
        guard debugLoggingEnabled else {
            return
        }
        fputs("[bossctl] \(message)\n", stderr)
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

    static func tracePackets(
        from stream: AsyncThrowingStream<BmapPacket, Error>,
        timeout: Duration,
        predicate: @escaping @Sendable (BmapPacket) -> Bool
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await packet in stream {
                    guard predicate(packet) else {
                        continue
                    }
                    print("Received \(describe(packet))")
                    print("Payload hex: \(packet.payload.hexString)")
                    if let utf8 = String(data: packet.payload, encoding: .utf8), !utf8.isEmpty {
                        print("Payload utf8: \(utf8)")
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
            }
            _ = try await group.next()
            group.cancelAll()
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
            throw BossctlError.bmapErrorResponse(
                context: "\(packet.functionBlock.displayName).\(packet.function.name)",
                payloadHex: response.payload.hexString
            )
        }
        return response
    }
}
