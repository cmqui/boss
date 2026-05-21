import CBossRustFFI
import Foundation
import libboss

public final class BossAppleLink: @unchecked Sendable {
    public let transportKind: BossAppleTransportKind = .ble
    public let packets: AsyncThrowingStream<BossAppleBmapPacket, Error>

    private let transport: AppleBleBossTransport
    private let consumeTask: Task<Void, Never>

    public init(transport: AppleBleBossTransport) {
        self.transport = transport
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: BossAppleBmapPacket.self, throwing: Error.self)
        self.packets = stream
        self.consumeTask = Task {
            do {
                if let runtime = BossRustFfiRuntime.shared,
                   let reassembler = BossAppleRustBleReassembler(runtime: runtime) {
                    for try await frame in transport.incomingFrames {
                        if let packetData = try reassembler.push(frame) {
                            continuation.yield(try BmapCodec.decode(packetData))
                        }
                    }
                } else {
                    var reassembler = BleSegmentReassembler()
                    for try await frame in transport.incomingFrames {
                        if let packetData = try reassembler.push(frame) {
                            continuation.yield(try BmapCodec.decode(packetData))
                        }
                    }
                }

                if Task.isCancelled {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: BossLinkError.unexpectedStreamTermination)
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    public func send(packet: BossAppleBmapPacket) async throws {
        let packetData = try BmapCodec.encode(packet)
        let frames: [Data]
        if let runtime = BossRustFfiRuntime.shared {
            frames = try BossAppleRustBleSegmentation.segment(packetData, mtu: transport.attMTU, runtime: runtime)
        } else {
            frames = try BleSegmentation.encode(packetBytes: packetData, mtu: transport.attMTU)
        }

        for frame in frames {
            try await transport.send(frame)
        }
    }

    public func close() async {
        consumeTask.cancel()
        await transport.close()
    }
}

extension BossAppleLink {
    func asCoreLink() -> any BossLink {
        BossAppleCoreLinkAdapter(link: self)
    }
}

private final class BossAppleCoreLinkAdapter: BossLink, @unchecked Sendable {
    let transportKind: BossTransportKind
    let packets: AsyncThrowingStream<BmapPacket, Error>

    private let link: BossAppleLink

    init(link: BossAppleLink) {
        self.link = link
        self.transportKind = link.transportKind
        self.packets = link.packets
    }

    func send(packet: BmapPacket) async throws {
        try await link.send(packet: packet)
    }

    func close() async {
        await link.close()
    }
}

private final class BossAppleRustBleReassembler: @unchecked Sendable {
    private let runtime: BossRustFfiRuntime
    private let handle: UnsafeMutableRawPointer

    init?(runtime: BossRustFfiRuntime) {
        guard let handle = runtime.bossBleReassemblerCreate() else {
            return nil
        }
        self.runtime = runtime
        self.handle = handle
    }

    deinit {
        runtime.bossBleReassemblerFree(handle)
    }

    func push(_ frame: Data) throws -> Data? {
        var packet = BossBuffer(data: nil, len: 0)
        var hasPacket = false
        var operationError = emptyBossAppleLinkError()
        let success = frame.withUnsafeBytes { bytes in
            runtime.bossBleReassemblerPush(
                handle,
                bytes.bindMemory(to: UInt8.self).baseAddress,
                bytes.count,
                &packet,
                &hasPacket,
                &operationError
            )
        }
        guard success else {
            defer { runtime.bossErrorFree(operationError) }
            throw bossAppleLinkError(from: operationError)
        }
        guard hasPacket else {
            return nil
        }
        defer { runtime.bossBufferFree(packet) }
        guard let data = packet.data else {
            return Data()
        }
        return Data(bytes: data, count: packet.len)
    }
}

private enum BossAppleRustBleSegmentation {
    static func segment(_ packetData: Data, mtu: Int, runtime: BossRustFfiRuntime) throws -> [Data] {
        var frames = BossBufferList(data: nil, len: 0)
        var operationError = emptyBossAppleLinkError()
        let success = packetData.withUnsafeBytes { bytes in
            runtime.bossBleSegmentPacket(
                bytes.bindMemory(to: UInt8.self).baseAddress,
                bytes.count,
                mtu,
                &frames,
                &operationError
            )
        }
        guard success else {
            defer { runtime.bossErrorFree(operationError) }
            throw bossAppleLinkError(from: operationError)
        }
        defer { runtime.bossBufferListFree(frames) }

        let buffers = UnsafeBufferPointer(start: frames.data, count: frames.len)
        return buffers.map { buffer in
            guard let data = buffer.data else {
                return Data()
            }
            return Data(bytes: data, count: buffer.len)
        }
    }
}

private func emptyBossAppleLinkError() -> BossFfiError {
    BossFfiError(
        code: BOSS_FFI_ERROR_NONE,
        message: BossBuffer(data: nil, len: 0),
        has_bmap_error_code: false,
        bmap_error_code: 0
    )
}

private func bossAppleLinkError(from ffiError: BossFfiError) -> BossAppleControlError {
    let message: String
    if let data = ffiError.message.data, ffiError.message.len > 0 {
        let bytes = UnsafeBufferPointer(start: data, count: ffiError.message.len)
        message = String(decoding: bytes, as: UTF8.self)
    } else {
        message = ""
    }

    switch ffiError.code {
    case BOSS_FFI_ERROR_INVALID_ARGUMENT, BOSS_FFI_ERROR_UNSUPPORTED_OPERATION:
        return .unsupportedOperation(message.isEmpty ? "BossAppleLink FFI reported an unsupported operation" : message)
    default:
        return .unsupportedOperation(message.isEmpty ? "BossAppleLink FFI error code \(ffiError.code)" : message)
    }
}
