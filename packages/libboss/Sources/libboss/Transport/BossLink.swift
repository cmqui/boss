import Foundation

public protocol BossLink: Sendable {
    var transportKind: BossTransportKind { get }
    var packets: AsyncThrowingStream<BmapPacket, Error> { get }
    func send(packet: BmapPacket) async throws
    func close() async
}

public final class StreamBmapLink: BossLink, @unchecked Sendable {
    public let transportKind: BossTransportKind = .stream
    public let packets: AsyncThrowingStream<BmapPacket, Error>

    private let transport: any BossTransport
    private let consumeTask: Task<Void, Never>

    public init(transport: any BossTransport) {
        self.transport = transport
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: BmapPacket.self, throwing: Error.self)
        self.packets = stream
        self.consumeTask = Task {
            var decoder = BmapFrameStreamDecoder()
            do {
                for try await frame in transport.incomingFrames {
                    for packet in try decoder.push(frame) {
                        continuation.yield(packet)
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    public func send(packet: BmapPacket) async throws {
        try await transport.send(BmapCodec.encode(packet))
    }

    public func close() async {
        consumeTask.cancel()
        await transport.close()
    }
}

public final class BleBmapLink: BossLink, @unchecked Sendable {
    public let transportKind: BossTransportKind = .ble
    public let packets: AsyncThrowingStream<BmapPacket, Error>

    private let transport: any BossTransport
    private let mtu: Int
    private let consumeTask: Task<Void, Never>

    public init(transport: any BossTransport, mtu: Int) {
        self.transport = transport
        self.mtu = mtu
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: BmapPacket.self, throwing: Error.self)
        self.packets = stream
        self.consumeTask = Task {
            var reassembler = BleSegmentReassembler()
            do {
                for try await frame in transport.incomingFrames {
                    if let packetData = try reassembler.push(frame) {
                        continuation.yield(try BmapCodec.decode(packetData))
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    public func send(packet: BmapPacket) async throws {
        let encoded = try BmapCodec.encode(packet)
        for frame in try BleSegmentation.encode(packetBytes: encoded, mtu: mtu) {
            try await transport.send(frame)
        }
    }

    public func close() async {
        consumeTask.cancel()
        await transport.close()
    }
}
