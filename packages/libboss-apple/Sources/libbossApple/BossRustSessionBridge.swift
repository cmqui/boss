import CBossRustFFI
import Darwin
import Dispatch
import Foundation
import libboss

fileprivate final class BossRustFfiRuntime: @unchecked Sendable {
    typealias BufferFreeFn = @convention(c) (BossBuffer) -> Void
    typealias ErrorFreeFn = @convention(c) (BossFfiError) -> Void
    typealias CopyBytesFn = @convention(c) (UnsafePointer<UInt8>?, Int) -> BossBuffer
    typealias SessionCreateFn = @convention(c) (BossFfiSessionCallbacks, UnsafeMutablePointer<BossFfiError>?) -> UnsafeMutableRawPointer?
    typealias SessionFreeFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias SetCurrentAudioModeFn = @convention(c) (
        UnsafeMutableRawPointer?,
        Int32,
        Bool,
        UnsafeMutablePointer<BossFfiCurrentAudioModeWriteResult>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias SetAudioModeSettingsFn = @convention(c) (
        UnsafeMutableRawPointer?,
        BossFfiAudioModeSettingsConfigPatch,
        UnsafeMutablePointer<BossFfiAudioModeSettingsWriteResult>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool

    let handle: UnsafeMutableRawPointer
    let bossBufferFree: BufferFreeFn
    let bossErrorFree: ErrorFreeFn
    let bossCopyBytes: CopyBytesFn
    let bossSessionCreate: SessionCreateFn
    let bossSessionFree: SessionFreeFn
    let bossSessionSetCurrentAudioMode: SetCurrentAudioModeFn
    let bossSessionSetAudioModeSettings: SetAudioModeSettingsFn

    private init?(_ handle: UnsafeMutableRawPointer) {
        func load<T>(_ symbol: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, symbol) else {
                return nil
            }
            return unsafeBitCast(pointer, to: type)
        }

        guard
            let bossBufferFree = load("boss_buffer_free", as: BufferFreeFn.self),
            let bossErrorFree = load("boss_error_free", as: ErrorFreeFn.self),
            let bossCopyBytes = load("boss_copy_bytes", as: CopyBytesFn.self),
            let bossSessionCreate = load("boss_session_create", as: SessionCreateFn.self),
            let bossSessionFree = load("boss_session_free", as: SessionFreeFn.self),
            let bossSessionSetCurrentAudioMode = load("boss_session_set_current_audio_mode", as: SetCurrentAudioModeFn.self),
            let bossSessionSetAudioModeSettings = load("boss_session_set_audio_mode_settings", as: SetAudioModeSettingsFn.self)
        else {
            dlclose(handle)
            return nil
        }

        self.handle = handle
        self.bossBufferFree = bossBufferFree
        self.bossErrorFree = bossErrorFree
        self.bossCopyBytes = bossCopyBytes
        self.bossSessionCreate = bossSessionCreate
        self.bossSessionFree = bossSessionFree
        self.bossSessionSetCurrentAudioMode = bossSessionSetCurrentAudioMode
        self.bossSessionSetAudioModeSettings = bossSessionSetAudioModeSettings
    }

    deinit {
        dlclose(handle)
    }

    static let shared: BossRustFfiRuntime? = {
        for candidate in candidateLibraryPaths() {
            guard let loaded = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) else {
                continue
            }
            if let runtime = BossRustFfiRuntime(loaded) {
                return runtime
            }
            dlclose(loaded)
        }
        return nil
    }()

    private static func candidateLibraryPaths() -> [String] {
        var paths: [String] = []
        if let explicit = ProcessInfo.processInfo.environment["LIBBOSS_RS_FFI_DYLIB"], !explicit.isEmpty {
            paths.append(explicit)
        }

        let cwd = FileManager.default.currentDirectoryPath
        paths.append("\(cwd)/../libboss-rs/target/debug/liblibboss_rs_ffi.dylib")
        paths.append("\(cwd)/packages/libboss-rs/target/debug/liblibboss_rs_ffi.dylib")
        paths.append("\(cwd)/target/debug/liblibboss_rs_ffi.dylib")

        var deduped: [String] = []
        var seen = Set<String>()
        for path in paths where seen.insert(path).inserted {
            deduped.append(path)
        }
        return deduped
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

private final class BossRustLinkBridge: @unchecked Sendable {
    private final class SendResultBox: @unchecked Sendable {
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

    private let runtime: BossRustFfiRuntime
    private let link: any BossLink
    private let queue = BossRustPacketQueue()
    private var consumeTask: Task<Void, Never>?

    init(runtime: BossRustFfiRuntime, link: any BossLink) {
        self.runtime = runtime
        self.link = link
        let queue = self.queue
        self.consumeTask = Task {
            do {
                for try await packet in link.packets {
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
        let resultBox = SendResultBox()
        Task {
            do {
                try await link.send(packet: packet)
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

final class BossRustSessionBridge: @unchecked Sendable {
    fileprivate let runtime: BossRustFfiRuntime

    fileprivate init(runtime: BossRustFfiRuntime) {
        self.runtime = runtime
    }

    static let shared = BossRustFfiRuntime.shared.map(BossRustSessionBridge.init(runtime:))

    func setCurrentAudioMode(
        on link: any BossLink,
        targetIndex: Int,
        playVoicePrompt: Bool
    ) async throws -> BossAppleCurrentAudioModeWriteResult {
        let bridge = BossRustLinkBridge(runtime: runtime, link: link)
        let retained = Unmanaged.passRetained(bridge)
        let callbacks = BossFfiSessionCallbacks(
            context: retained.toOpaque(),
            transport_kind: link.transportKind == .ble ? 0 : 1,
            send_packet_bytes: bossRustSendPacketBytes,
            next_packet_bytes: bossRustNextPacketBytes,
            release_context: bossRustReleaseContext
        )

        var createError = BossFfiError(
            code: BOSS_FFI_ERROR_NONE,
            message: BossBuffer(data: nil, len: 0),
            has_bmap_error_code: false,
            bmap_error_code: 0
        )
        guard let handle = runtime.bossSessionCreate(callbacks, &createError) else {
            defer { runtime.bossErrorFree(createError) }
            throw map(error: createError)
        }
        defer { runtime.bossSessionFree(handle) }

        var result = BossFfiCurrentAudioModeWriteResult(
            disposition: BOSS_FFI_WRITE_DISPOSITION_UNCHANGED,
            mode_index: 0,
            target_index: 0
        )
        var operationError = BossFfiError(
            code: BOSS_FFI_ERROR_NONE,
            message: BossBuffer(data: nil, len: 0),
            has_bmap_error_code: false,
            bmap_error_code: 0
        )
        let success = runtime.bossSessionSetCurrentAudioMode(
            handle,
            Int32(targetIndex),
            playVoicePrompt,
            &result,
            &operationError
        )
        guard success else {
            defer { runtime.bossErrorFree(operationError) }
            throw map(error: operationError)
        }

        switch result.disposition {
        case BOSS_FFI_WRITE_DISPOSITION_UNCHANGED:
            return .unchanged(Int(result.mode_index))
        case BOSS_FFI_WRITE_DISPOSITION_UPDATED:
            return .updated(Int(result.mode_index))
        case BOSS_FFI_WRITE_DISPOSITION_VERIFICATION_INCONCLUSIVE:
            return .verificationInconclusive(targetIndex: Int(result.target_index))
        default:
            throw BossAppleControlError.unsupportedOperation("Rust FFI returned unknown current-audio-mode write disposition \(result.disposition)")
        }
    }

    func setAudioModeSettings(
        on link: any BossLink,
        update: BossAudioModeSettingsConfigPatch
    ) async throws -> BossAppleAudioModeSettingsWriteResult {
        let bridge = BossRustLinkBridge(runtime: runtime, link: link)
        let retained = Unmanaged.passRetained(bridge)
        let callbacks = BossFfiSessionCallbacks(
            context: retained.toOpaque(),
            transport_kind: link.transportKind == .ble ? 0 : 1,
            send_packet_bytes: bossRustSendPacketBytes,
            next_packet_bytes: bossRustNextPacketBytes,
            release_context: bossRustReleaseContext
        )

        var createError = BossFfiError(
            code: BOSS_FFI_ERROR_NONE,
            message: BossBuffer(data: nil, len: 0),
            has_bmap_error_code: false,
            bmap_error_code: 0
        )
        guard let handle = runtime.bossSessionCreate(callbacks, &createError) else {
            defer { runtime.bossErrorFree(createError) }
            throw map(error: createError)
        }
        defer { runtime.bossSessionFree(handle) }

        var result = BossFfiAudioModeSettingsWriteResult(
            disposition: BOSS_FFI_WRITE_DISPOSITION_UNCHANGED,
            config: Self.ffiConfig(from: BossAudioModeSettingsConfig(
                cncLevel: 0,
                autoCNCEnabled: false,
                spatialAudioMode: .off,
                windBlockEnabled: false,
                ancToggleEnabled: false
            ))
        )
        var operationError = BossFfiError(
            code: BOSS_FFI_ERROR_NONE,
            message: BossBuffer(data: nil, len: 0),
            has_bmap_error_code: false,
            bmap_error_code: 0
        )
        let success = runtime.bossSessionSetAudioModeSettings(
            handle,
            Self.ffiPatch(from: update),
            &result,
            &operationError
        )
        guard success else {
            defer { runtime.bossErrorFree(operationError) }
            throw map(error: operationError)
        }

        let config = try Self.swiftConfig(from: result.config)
        switch result.disposition {
        case BOSS_FFI_WRITE_DISPOSITION_UNCHANGED:
            return .unchanged(config)
        case BOSS_FFI_WRITE_DISPOSITION_UPDATED:
            return .updated(config)
        case BOSS_FFI_WRITE_DISPOSITION_VERIFICATION_INCONCLUSIVE:
            return .verificationInconclusive(config)
        default:
            throw BossAppleControlError.unsupportedOperation("Rust FFI returned unknown audio-mode-settings write disposition \(result.disposition)")
        }
    }

    private func map(error ffiError: BossFfiError) -> BossAppleControlError {
        let message = read(buffer: ffiError.message)
        switch ffiError.code {
        case BOSS_FFI_ERROR_INVALID_ARGUMENT, BOSS_FFI_ERROR_UNSUPPORTED_OPERATION:
            return .unsupportedOperation(message.isEmpty ? "Rust FFI reported an unsupported operation" : message)
        case BOSS_FFI_ERROR_RESPONSE_STREAM_ENDED:
            return .responseStreamEnded
        case BOSS_FFI_ERROR_RESPONSE_TIMED_OUT:
            return .responseTimedOut(seconds: 5)
        case BOSS_FFI_ERROR_BMAP_ERROR_RESPONSE:
            let payloadHex = ffiError.has_bmap_error_code ? String(format: "%02X", ffiError.bmap_error_code) : ""
            return .bmapErrorResponse(context: "libboss-rs", payloadHex: payloadHex)
        default:
            return .unsupportedOperation(message.isEmpty ? "Rust FFI error code \(ffiError.code)" : message)
        }
    }

    private func read(buffer: BossBuffer) -> String {
        guard let data = buffer.data, buffer.len > 0 else {
            return ""
        }
        let bytes = UnsafeBufferPointer(start: data, count: buffer.len)
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func ffiConfig(from config: BossAudioModeSettingsConfig) -> BossFfiAudioModeSettingsConfig {
        BossFfiAudioModeSettingsConfig(
            cnc_level: Int32(config.cncLevel),
            auto_cnc_enabled: config.autoCNCEnabled,
            spatial_audio_mode: config.spatialAudioMode.rawValue,
            wind_block_enabled: config.windBlockEnabled,
            anc_toggle_enabled: config.ancToggleEnabled
        )
    }

    private static func ffiPatch(from patch: BossAudioModeSettingsConfigPatch) -> BossFfiAudioModeSettingsConfigPatch {
        BossFfiAudioModeSettingsConfigPatch(
            has_cnc_level: patch.cncLevel != nil,
            cnc_level: Int32(patch.cncLevel ?? 0),
            has_auto_cnc_enabled: patch.autoCNCEnabled != nil,
            auto_cnc_enabled: patch.autoCNCEnabled ?? false,
            has_spatial_audio_mode: patch.spatialAudioMode != nil,
            spatial_audio_mode: patch.spatialAudioMode?.rawValue ?? BossSpatialAudioMode.off.rawValue,
            has_wind_block_enabled: patch.windBlockEnabled != nil,
            wind_block_enabled: patch.windBlockEnabled ?? false,
            has_anc_toggle_enabled: patch.ancToggleEnabled != nil,
            anc_toggle_enabled: patch.ancToggleEnabled ?? false
        )
    }

    private static func swiftConfig(from ffi: BossFfiAudioModeSettingsConfig) throws -> BossAudioModeSettingsConfig {
        guard let spatialAudioMode = BossSpatialAudioMode(rawValue: ffi.spatial_audio_mode) else {
            throw BossAppleControlError.unsupportedOperation(
                "Rust FFI returned unknown spatial audio mode \(ffi.spatial_audio_mode)"
            )
        }
        return BossAudioModeSettingsConfig(
            cncLevel: Int(ffi.cnc_level),
            autoCNCEnabled: ffi.auto_cnc_enabled,
            spatialAudioMode: spatialAudioMode,
            windBlockEnabled: ffi.wind_block_enabled,
            ancToggleEnabled: ffi.anc_toggle_enabled
        )
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

private let bossRustSendPacketBytes: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int) -> BossFfiLinkStatus = {
    context, packetData, packetLen in
    guard let context else {
        return BOSS_FFI_LINK_STATUS_OTHER
    }
    let bridge = Unmanaged<BossRustLinkBridge>.fromOpaque(context).takeUnretainedValue()
    return bridge.send(packetBytes: packetData, len: packetLen)
}

private let bossRustNextPacketBytes: @convention(c) (UnsafeMutableRawPointer?, UInt64, UnsafeMutablePointer<BossBuffer>?) -> BossFfiLinkStatus = {
    context, timeoutMillis, outPacket in
    guard let context else {
        return BOSS_FFI_LINK_STATUS_OTHER
    }
    let bridge = Unmanaged<BossRustLinkBridge>.fromOpaque(context).takeUnretainedValue()
    return bridge.nextPacket(timeoutMilliseconds: timeoutMillis, outPacket: outPacket)
}

private let bossRustReleaseContext: @convention(c) (UnsafeMutableRawPointer?) -> Void = { context in
    guard let context else {
        return
    }
    Unmanaged<BossRustLinkBridge>.fromOpaque(context).release()
}
