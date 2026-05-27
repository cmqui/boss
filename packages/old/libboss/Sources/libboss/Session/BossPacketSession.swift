import Foundation

public final class BossPacketSession: @unchecked Sendable {
    public let transportKind: BossTransportKind

    private let link: any BossLink
    private let router = PacketRouter()
    private let consumeTask: Task<Void, Never>

    public init(link: any BossLink) {
        self.link = link
        self.transportKind = link.transportKind
        let router = self.router
        self.consumeTask = Task {
            do {
                for try await packet in link.packets {
                    await router.enqueue(packet)
                }
                await router.finish()
            } catch {
                await router.finish(error: error)
            }
        }
    }

    deinit {
        consumeTask.cancel()
    }

    public func invalidate() {
        consumeTask.cancel()
        Task {
            await router.finish(error: CancellationError())
        }
    }

    public func send(packet: BmapPacket) async throws {
        try await link.send(packet: packet)
    }

    public func firstPacket(
        matching predicate: @escaping @Sendable (BmapPacket) -> Bool,
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BmapPacket {
        try await withThrowingTimeout(timeout, timeoutError: timeoutError) {
            try await self.router.nextPacket(matching: predicate)
        }
    }

    public func sendAndAwait(
        packet: BmapPacket,
        matching predicate: @escaping @Sendable (BmapPacket) -> Bool,
        timeout: Duration,
        timeoutError: Error
    ) async throws -> BmapPacket {
        try await send(packet: packet)
        return try await firstPacket(
            matching: predicate,
            timeout: timeout,
            timeoutError: timeoutError
        )
    }

    public func packetStream(
        matching predicate: @escaping @Sendable (BmapPacket) -> Bool
    ) -> AsyncThrowingStream<BmapPacket, Error> {
        let router = self.router
        return AsyncThrowingStream { continuation in
            let token = UUID()
            Task {
                await router.addSubscriber(
                    id: token,
                    predicate: predicate,
                    continuation: continuation
                )
            }
            continuation.onTermination = { _ in
                Task {
                    await router.removeSubscriber(id: token)
                }
            }
        }
    }
}

private actor PacketRouter {
    private struct Waiter {
        let id: UUID
        let predicate: @Sendable (BmapPacket) -> Bool
        let continuation: CheckedContinuation<BmapPacket, Error>
    }

    private struct Subscriber {
        let predicate: @Sendable (BmapPacket) -> Bool
        let continuation: AsyncThrowingStream<BmapPacket, Error>.Continuation
    }

    private var buffered: [BmapPacket] = []
    private var waiters: [Waiter] = []
    private var subscribers: [UUID: Subscriber] = [:]
    private var terminalError: Error?
    private var didFinish = false

    func nextPacket(
        matching predicate: @escaping @Sendable (BmapPacket) -> Bool
    ) async throws -> BmapPacket {
        if let index = buffered.firstIndex(where: predicate) {
            return buffered.remove(at: index)
        }
        if let terminalError {
            throw terminalError
        }
        if didFinish {
            throw BossLinkError.unexpectedStreamTermination
        }

        let token = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(
                    Waiter(id: token, predicate: predicate, continuation: continuation)
                )
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: token)
            }
        }
    }

    func addSubscriber(
        id: UUID,
        predicate: @escaping @Sendable (BmapPacket) -> Bool,
        continuation: AsyncThrowingStream<BmapPacket, Error>.Continuation
    ) {
        if let terminalError {
            continuation.finish(throwing: terminalError)
            return
        }
        if didFinish {
            continuation.finish()
            return
        }
        subscribers[id] = Subscriber(predicate: predicate, continuation: continuation)
    }

    func removeSubscriber(id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    func enqueue(_ packet: BmapPacket) {
        for subscriber in subscribers.values where subscriber.predicate(packet) {
            subscriber.continuation.yield(packet)
        }

        if let index = waiters.firstIndex(where: { $0.predicate(packet) }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(returning: packet)
            return
        }

        buffered.append(packet)
    }

    func finish(error: Error? = nil) {
        guard !didFinish else {
            return
        }
        terminalError = error
        didFinish = true

        let activeWaiters = waiters
        waiters.removeAll()
        for waiter in activeWaiters {
            if let error {
                waiter.continuation.resume(throwing: error)
            } else {
                waiter.continuation.resume(throwing: BossLinkError.unexpectedStreamTermination)
            }
        }

        let activeSubscribers = subscribers.values
        subscribers.removeAll()
        for subscriber in activeSubscribers {
            if let error {
                subscriber.continuation.finish(throwing: error)
            } else {
                subscriber.continuation.finish()
            }
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}
