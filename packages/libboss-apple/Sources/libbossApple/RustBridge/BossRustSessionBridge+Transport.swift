import CBossRustFFI
import Dispatch
import Foundation

private final class BossRustBleReassembler: @unchecked Sendable {
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
        var operationError = emptyRustTransportError()
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
            throw rustTransportError(from: operationError)
        }
        guard hasPacket else {
            return nil
        }
        defer { runtime.bossBufferFree(packet) }
        return Data(bytes: packet.data!, count: packet.len)
    }
}

private final class BossRustPacketQueue: @unchecked Sendable {
    enum Event {
        case packet(Data)
        case streamEnded
        case unexpectedStreamTermination
        case otherError
    }

    private let condition = NSCondition()
    private var events: [Event] = []

    private func push(_ event: Event) {
        condition.lock()
        events.append(event)
        condition.signal()
        condition.unlock()
    }

    private func next(timeout: Duration) -> Event? {
        let deadline = Date().addingTimeInterval(timeout.timeInterval)
        condition.lock()
        defer { condition.unlock() }

        while events.isEmpty {
            if !condition.wait(until: deadline) {
                return nil
            }
        }

        return events.removeFirst()
    }

    func pushPacket(_ packet: Data) {
        push(.packet(packet))
    }

    func pushStreamEnded() {
        push(.streamEnded)
    }

    func pushUnexpectedStreamTermination() {
        push(.unexpectedStreamTermination)
    }

    func pushOtherError() {
        push(.otherError)
    }

    func nextPacketEvent(timeout: Duration) -> Event? {
        next(timeout: timeout)
    }
}

protocol BossRustPacketByteBridge: AnyObject, Sendable {
    func send(packetBytes: UnsafePointer<UInt8>?, len: Int) -> BossFfiLinkStatus
    func nextPacket(timeoutMilliseconds: UInt64, outPacket: UnsafeMutablePointer<BossBuffer>?) -> BossFfiLinkStatus
}

private final class BossRustFfiSendResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var status: BossFfiLinkStatus = BOSS_FFI_LINK_STATUS_OTHER

    func set(_ status: BossFfiLinkStatus) {
        lock.lock()
        self.status = status
        lock.unlock()
    }

    func get() -> BossFfiLinkStatus {
        lock.lock()
        defer { lock.unlock() }
        return status
    }
}

final class BossRustBleTransportBridge: BossRustPacketByteBridge, @unchecked Sendable {
    private let runtime: BossRustFfiRuntime
    private let transport: AppleBleBossTransport
    private let queue = BossRustPacketQueue()
    private var consumeTask: Task<Void, Never>?

    init(runtime: BossRustFfiRuntime, transport: AppleBleBossTransport) {
        self.runtime = runtime
        self.transport = transport
        let queue = self.queue
        self.consumeTask = Task {
            guard let reassembler = BossRustBleReassembler(runtime: runtime) else {
                queue.pushOtherError()
                return
            }
            do {
                for try await frame in transport.incomingFrames {
                    if let packetData = try reassembler.push(frame) {
                        queue.pushPacket(packetData)
                    }
                }
                queue.pushStreamEnded()
            } catch let error as BossAppleLinkError where error == .unexpectedStreamTermination {
                queue.pushUnexpectedStreamTermination()
            } catch {
                queue.pushOtherError()
            }
        }
    }

    func shutdown() {
        consumeTask?.cancel()
        consumeTask = nil
    }

    deinit {
        shutdown()
    }

    func send(packetBytes: UnsafePointer<UInt8>?, len: Int) -> BossFfiLinkStatus {
        guard let packetBytes, len > 0 else {
            return BOSS_FFI_LINK_STATUS_OTHER
        }

        let packetData = Data(bytes: packetBytes, count: len)
        let frames: [Data]
        do {
            frames = try segment(packetData, mtu: transport.attMTU)
        } catch {
            return BOSS_FFI_LINK_STATUS_OTHER
        }

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = BossRustFfiSendResultBox()
        Task {
            do {
                for frame in frames {
                    try await transport.send(frame)
                }
                resultBox.set(BOSS_FFI_LINK_STATUS_OK)
            } catch let error as BossAppleLinkError where error == .unexpectedStreamTermination {
                resultBox.set(BOSS_FFI_LINK_STATUS_UNEXPECTED_STREAM_TERMINATION)
            } catch {
                resultBox.set(BOSS_FFI_LINK_STATUS_OTHER)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return resultBox.get()
    }

    func nextPacket(timeoutMilliseconds: UInt64, outPacket: UnsafeMutablePointer<BossBuffer>?) -> BossFfiLinkStatus {
        guard let outPacket else {
            return BOSS_FFI_LINK_STATUS_OTHER
        }

        let timeout = Duration.milliseconds(Int64(timeoutMilliseconds))
        guard let event = queue.nextPacketEvent(timeout: timeout) else {
            return BOSS_FFI_LINK_STATUS_TIMED_OUT
        }

        switch event {
        case .packet(let packetData):
            let rustBuffer = packetData.withUnsafeBytes { bytes -> BossBuffer in
                runtime.bossCopyBytes(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
            }
            outPacket.pointee = rustBuffer
            return BOSS_FFI_LINK_STATUS_OK
        case .streamEnded:
            return BOSS_FFI_LINK_STATUS_STREAM_ENDED
        case .unexpectedStreamTermination:
            return BOSS_FFI_LINK_STATUS_UNEXPECTED_STREAM_TERMINATION
        case .otherError:
            return BOSS_FFI_LINK_STATUS_OTHER
        }
    }

    private func segment(_ packetData: Data, mtu: Int) throws -> [Data] {
        var frames = BossBufferList(data: nil, len: 0)
        var operationError = emptyRustTransportError()
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
            throw rustTransportError(from: operationError)
        }
        defer { runtime.bossBufferListFree(frames) }
        let buffers = UnsafeBufferPointer(start: frames.data, count: frames.len)
        return buffers.map { buffer in
            Data(bytes: buffer.data!, count: buffer.len)
        }
    }
}

private func emptyRustTransportError() -> BossFfiError {
    BossFfiError(
        code: BOSS_FFI_ERROR_NONE,
        message: BossBuffer(data: nil, len: 0),
        has_bmap_error_code: false,
        bmap_error_code: 0
    )
}

private func rustTransportError(from ffiError: BossFfiError) -> BossAppleControlError {
    let message: String
    if let data = ffiError.message.data, ffiError.message.len > 0 {
        let bytes = UnsafeBufferPointer(start: data, count: ffiError.message.len)
        message = String(decoding: bytes, as: UTF8.self)
    } else {
        message = ""
    }

    switch ffiError.code {
    case BOSS_FFI_ERROR_INVALID_ARGUMENT, BOSS_FFI_ERROR_UNSUPPORTED_OPERATION:
        return .unsupportedOperation(message.isEmpty ? "Rust transport FFI reported an unsupported operation" : message)
    default:
        return .unsupportedOperation(message.isEmpty ? "Rust transport FFI error code \(ffiError.code)" : message)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

let bossRustSendPacketBytes: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int) -> BossFfiLinkStatus = {
    context, packetData, packetLen in
    guard let context else {
        return BOSS_FFI_LINK_STATUS_OTHER
    }
    let bridge = Unmanaged<AnyObject>.fromOpaque(context).takeUnretainedValue() as? BossRustPacketByteBridge
    guard let bridge else {
        return BOSS_FFI_LINK_STATUS_OTHER
    }
    return bridge.send(packetBytes: packetData, len: packetLen)
}

let bossRustNextPacketBytes: @convention(c) (UnsafeMutableRawPointer?, UInt64, UnsafeMutablePointer<BossBuffer>?) -> BossFfiLinkStatus = {
    context, timeoutMillis, outPacket in
    guard let context else {
        return BOSS_FFI_LINK_STATUS_OTHER
    }
    let bridge = Unmanaged<AnyObject>.fromOpaque(context).takeUnretainedValue() as? BossRustPacketByteBridge
    guard let bridge else {
        return BOSS_FFI_LINK_STATUS_OTHER
    }
    return bridge.nextPacket(timeoutMilliseconds: timeoutMillis, outPacket: outPacket)
}

let bossRustReleaseContext: @convention(c) (UnsafeMutableRawPointer?) -> Void = { context in
    guard let context else {
        return
    }
    Unmanaged<AnyObject>.fromOpaque(context).release()
}
