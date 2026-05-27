import CBossRustFFI
import Foundation

final class BossAppleLink: @unchecked Sendable {
    let transportKind: BossAppleTransportKind = .ble
    let packets: AsyncThrowingStream<BossAppleBmapPacket, Error>

    private let transport: AppleBleBossTransport
    private let consumeTask: Task<Void, Never>

    init(transport: AppleBleBossTransport) {
        self.transport = transport
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: BossAppleBmapPacket.self, throwing: Error.self)
        self.packets = stream
        self.consumeTask = Task {
            do {
                let runtime = try requireBossRustRuntime()
                guard let reassembler = BossAppleRustBleReassembler(runtime: runtime) else {
                    throw BossAppleControlError.unsupportedOperation("Rust BLE reassembler was unavailable")
                }
                for try await frame in transport.incomingFrames {
                    if let packetData = try reassembler.push(frame) {
                        continuation.yield(try BossRustCodecBridge.decode(packetData, runtime: runtime))
                    }
                }

                if Task.isCancelled {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: BossAppleLinkError.unexpectedStreamTermination)
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    func send(packet: BossAppleBmapPacket) async throws {
        let runtime = try requireBossRustRuntime()
        let packetData = try BossRustCodecBridge.encode(packet, runtime: runtime)
        let frames = try BossAppleRustBleSegmentation.segment(packetData, mtu: transport.attMTU, runtime: runtime)

        for frame in frames {
            try await transport.send(frame)
        }
    }

    func close() async {
        consumeTask.cancel()
        await transport.close()
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

private func requireBossRustRuntime() throws -> BossRustFfiRuntime {
    guard let runtime = BossRustFfiRuntime.shared else {
        throw BossAppleControlError.unsupportedOperation("Rust runtime is required for packet transport")
    }
    return runtime
}
