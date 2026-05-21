import CBossRustFFI
import Dispatch
import Foundation
import libboss

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

final class BossRustPacketSessionBridge: BossRustPacketByteBridge, @unchecked Sendable {
    private let runtime: BossRustFfiRuntime
    private let packetSession: BossPacketSession
    private let queue = BossRustPacketQueue()
    private var consumeTask: Task<Void, Never>?

    init(runtime: BossRustFfiRuntime, packetSession: BossPacketSession) {
        self.runtime = runtime
        self.packetSession = packetSession
        let queue = self.queue
        self.consumeTask = Task {
            do {
                for try await packet in packetSession.packetStream(matching: { _ in true }) {
                    queue.pushPacket(try BmapCodec.encode(packet))
                }
                queue.pushStreamEnded()
            } catch let error as BossLinkError where error == .unexpectedStreamTermination {
                queue.pushUnexpectedStreamTermination()
            } catch {
                queue.pushOtherError()
            }
        }
    }

    deinit {
        consumeTask?.cancel()
    }

    func send(packetBytes: UnsafePointer<UInt8>?, len: Int) -> BossFfiLinkStatus {
        guard let packetBytes, len > 0 else {
            return BOSS_FFI_LINK_STATUS_OTHER
        }

        let packetData = Data(bytes: packetBytes, count: len)
        let packet: BmapPacket
        do {
            packet = try BmapCodec.decode(packetData)
        } catch {
            return BOSS_FFI_LINK_STATUS_OTHER
        }

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = BossRustFfiSendResultBox()
        Task {
            do {
                try await packetSession.send(packet: packet)
                resultBox.set(BOSS_FFI_LINK_STATUS_OK)
            } catch let error as BossLinkError where error == .unexpectedStreamTermination {
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
            var reassembler = BleSegmentReassembler()
            do {
                for try await frame in transport.incomingFrames {
                    if let packetData = try reassembler.push(frame) {
                        queue.pushPacket(packetData)
                    }
                }
                queue.pushStreamEnded()
            } catch let error as BossLinkError where error == .unexpectedStreamTermination {
                queue.pushUnexpectedStreamTermination()
            } catch {
                queue.pushOtherError()
            }
        }
    }

    deinit {
        consumeTask?.cancel()
    }

    func send(packetBytes: UnsafePointer<UInt8>?, len: Int) -> BossFfiLinkStatus {
        guard let packetBytes, len > 0 else {
            return BOSS_FFI_LINK_STATUS_OTHER
        }

        let packetData = Data(bytes: packetBytes, count: len)
        let frames: [Data]
        do {
            frames = try BleSegmentation.encode(packetBytes: packetData, mtu: transport.attMTU)
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
            } catch let error as BossLinkError where error == .unexpectedStreamTermination {
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
