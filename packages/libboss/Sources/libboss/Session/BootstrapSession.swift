import Foundation

public final class BootstrapSession: @unchecked Sendable {
    private let link: any BossLink
    private let configuration: SessionConfiguration

    public init(link: any BossLink, configuration: SessionConfiguration = SessionConfiguration()) {
        self.link = link
        self.configuration = configuration
    }

    public func bootstrap() async throws -> BootstrappedDevice {
        let cursor = PacketCursor(stream: link.packets)
        let pump = Task {
            do {
                for try await packet in link.packets {
                    await cursor.enqueue(packet)
                }
                await cursor.finish()
            } catch {
                await cursor.finish(error: error)
            }
        }
        defer { pump.cancel() }

        let versionPacket = ProductInfoCommands.bmapVersion(
            deviceID: configuration.defaultDeviceID,
            port: configuration.defaultPort
        )

        let versionResponse: BmapPacket
        do {
            try await link.send(packet: versionPacket)
            versionResponse = try await nextPacket(
                cursor: cursor,
                matching: versionPacket.function,
                timeout: configuration.firstVersionTimeout,
                timeoutError: BootstrapTimeoutError.bmapVersion(timeoutMilliseconds: configuration.firstVersionTimeout.millisecondsValue)
            )
        } catch is BootstrapTimeoutError {
            try await link.send(packet: versionPacket)
            versionResponse = try await nextPacket(
                cursor: cursor,
                matching: versionPacket.function,
                timeout: configuration.retryVersionTimeout,
                timeoutError: BootstrapTimeoutError.bmapVersion(timeoutMilliseconds: configuration.retryVersionTimeout.millisecondsValue)
            )
        }
        let versionInfo = try ProductInfoParser.parseBmapVersion(from: versionResponse)

        let productRequest = ProductInfoCommands.productIDVariant(
            deviceID: configuration.defaultDeviceID,
            port: configuration.defaultPort
        )
        try await link.send(packet: productRequest)
        let productPacket = try await nextPacket(
            cursor: cursor,
            matching: productRequest.function,
            timeout: configuration.requestTimeout,
            timeoutError: BootstrapTimeoutError.packet(function: productRequest.function.name, timeoutMilliseconds: configuration.requestTimeout.millisecondsValue)
        )
        let productVariant = try ProductInfoParser.parseProductIDVariant(from: productPacket)

        let blockRequest = ProductInfoCommands.allFunctionBlocksGet(
            deviceID: configuration.defaultDeviceID,
            port: configuration.defaultPort
        )
        try await link.send(packet: blockRequest)
        let blocksPacket = try await nextPacket(
            cursor: cursor,
            matching: blockRequest.function,
            timeout: configuration.requestTimeout,
            timeoutError: BootstrapTimeoutError.packet(function: blockRequest.function.name, timeoutMilliseconds: configuration.requestTimeout.millisecondsValue)
        )
        let functionBlocks = try ProductInfoParser.parseFunctionBlocks(from: blocksPacket)

        return BootstrappedDevice(
            bmapVersion: versionInfo,
            productID: productVariant.productID,
            productName: productVariant.product?.displayName ?? "Unknown Bose Product",
            productVariant: productVariant,
            supportedFunctionBlocks: functionBlocks,
            transportKind: link.transportKind,
            defaultDeviceID: configuration.defaultDeviceID,
            defaultPort: configuration.defaultPort
        )
    }

    private func nextPacket(
        cursor: PacketCursor,
        matching function: BmapFunction,
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BmapPacket {
        try await withThrowingTimeout(timeout, timeoutError: timeoutError) {
            while let packet = try await cursor.next() {
                if Task.isCancelled {
                    await cursor.prepend(packet)
                    throw CancellationError()
                }
                guard packet.function == function else {
                    continue
                }
                guard packet.operator == .status else {
                    throw UnexpectedOperatorError(expected: .status, actual: packet.operator)
                }
                return packet
            }
            throw timeoutError
        }
    }
}

private actor PacketCursor {
    private var buffered: [BmapPacket] = []
    private var waiters: [UUID: CheckedContinuation<BmapPacket?, Error>] = [:]
    private var terminalError: Error?
    private var didFinish = false

    init(stream: AsyncThrowingStream<BmapPacket, Error>) {}

    func next() async throws -> BmapPacket? {
        if !buffered.isEmpty {
            return buffered.removeFirst()
        }
        if let terminalError {
            throw terminalError
        }
        if didFinish {
            return nil
        }

        let token = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters[token] = continuation
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: token)
            }
        }
    }

    func prepend(_ packet: BmapPacket) {
        if let waiterID = waiters.keys.first, let continuation = waiters.removeValue(forKey: waiterID) {
            continuation.resume(returning: packet)
        } else {
            buffered.insert(packet, at: 0)
        }
    }

    func enqueue(_ packet: BmapPacket) {
        if let waiterID = waiters.keys.first, let continuation = waiters.removeValue(forKey: waiterID) {
            continuation.resume(returning: packet)
        } else {
            buffered.append(packet)
        }
    }

    func finish(error: Error? = nil) {
        terminalError = error
        didFinish = true
        let activeWaiters = waiters.values
        waiters.removeAll()
        for continuation in activeWaiters {
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: nil)
            }
        }
    }

    private func cancelWaiter(id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}

private extension Duration {
    var millisecondsValue: Int {
        let components = self.components
        return Int(components.seconds * 1_000) + Int(components.attoseconds / 1_000_000_000_000_000)
    }
}

private func withThrowingTimeout<T: Sendable>(
    _ timeout: Duration,
    timeoutError: Error,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw timeoutError
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
