import CBossRustFFI
import Darwin
import Dispatch
import Foundation

final class BossRustSessionBridge: @unchecked Sendable {
    fileprivate let runtime: BossRustFfiRuntime

    fileprivate init(runtime: BossRustFfiRuntime) {
        self.runtime = runtime
    }

    static let shared = BossRustFfiRuntime.shared.map(BossRustSessionBridge.init(runtime:))

    private func sessionCallbacks(for transport: AppleBleBossTransport) -> BossFfiSessionCallbacks {
        let bridge = transport.sharedRustPacketBridge(runtime: runtime)
        let retained = Unmanaged.passRetained(bridge)
        return BossFfiSessionCallbacks(
            context: retained.toOpaque(),
            transport_kind: 0,
            send_packet_bytes: bossRustSendPacketBytes,
            next_packet_bytes: bossRustNextPacketBytes,
            release_context: bossRustReleaseContext
        )
    }

    private func withSessionHandle<T>(
        on transport: AppleBleBossTransport,
        _ operation: (UnsafeMutableRawPointer?) throws -> T
    ) throws -> T {
        var createError = emptyError()
        guard let handle = runtime.bossSessionCreate(sessionCallbacks(for: transport), &createError) else {
            defer { runtime.bossErrorFree(createError) }
            throw map(error: createError)
        }
        defer { runtime.bossSessionFree(handle) }
        return try operation(handle)
    }

    private func withUpdateStreamHandle<T>(
        on transport: AppleBleBossTransport,
        kind: BossFfiUpdateStreamKind,
        _ operation: (UnsafeMutableRawPointer?) throws -> T
    ) throws -> T {
        var createError = emptyError()
        guard let handle = runtime.bossUpdateStreamCreate(sessionCallbacks(for: transport), kind, &createError) else {
            defer { runtime.bossErrorFree(createError) }
            throw map(error: createError)
        }
        defer { runtime.bossUpdateStreamFree(handle) }
        return try operation(handle)
    }

    func bootstrap(on transport: AppleBleBossTransport) async throws -> BossAppleBootstrappedDevice {
        BossRustLogger.log("using Rust bridge for bootstrap")
        var device = BossFfiBootstrappedDevice()
        var operationError = emptyError()
        let success = runtime.bossBootstrapSession(sessionCallbacks(for: transport), &device, &operationError)
        guard success else {
            defer { runtime.bossErrorFree(operationError) }
            throw map(error: operationError)
        }
        return Self.swiftBootstrappedDevice(from: device)
    }

    func currentAudioModeUpdateStream(on transport: AppleBleBossTransport) -> AsyncThrowingStream<Int, Error> {
        updateStream(on: transport, kind: BOSS_FFI_UPDATE_STREAM_KIND_CURRENT_AUDIO_MODE) { handle in
            var modeIndex: Int32 = 0
            var operationError = self.emptyError()
            let success = self.runtime.bossUpdateStreamNextCurrentAudioMode(handle, 60_000, &modeIndex, &operationError)
            guard success else {
                defer { self.runtime.bossErrorFree(operationError) }
                throw self.map(error: operationError)
            }
            return Int(modeIndex)
        }
    }

    func audioModeSettingsUpdateStream(on transport: AppleBleBossTransport) -> AsyncThrowingStream<BossAppleAudioModeSettingsConfig, Error> {
        updateStream(on: transport, kind: BOSS_FFI_UPDATE_STREAM_KIND_AUDIO_MODE_SETTINGS) { handle in
            var config = BossFfiAudioModeSettingsConfig()
            var operationError = self.emptyError()
            let success = self.runtime.bossUpdateStreamNextAudioModeSettings(handle, 60_000, &config, &operationError)
            guard success else {
                defer { self.runtime.bossErrorFree(operationError) }
                throw self.map(error: operationError)
            }
            return try Self.swiftConfig(from: config)
        }
    }

    func equalizerUpdateStream(on transport: AppleBleBossTransport) -> AsyncThrowingStream<BossAppleEqualizerSettings, Error> {
        updateStream(on: transport, kind: BOSS_FFI_UPDATE_STREAM_KIND_EQUALIZER) { handle in
            var settings = BossFfiEqualizerSettings()
            var operationError = self.emptyError()
            let success = self.runtime.bossUpdateStreamNextEqualizer(handle, 60_000, &settings, &operationError)
            guard success else {
                defer { self.runtime.bossErrorFree(operationError) }
                throw self.map(error: operationError)
            }
            return Self.swiftEqualizerSettings(from: settings)
        }
    }

    func deviceSettingsUpdateStream(on transport: AppleBleBossTransport) -> AsyncThrowingStream<BossAppleDeviceSettingsReport, Error> {
        updateStream(on: transport, kind: BOSS_FFI_UPDATE_STREAM_KIND_DEVICE_SETTINGS) { handle in
            var report = BossFfiDeviceSettingsReport()
            var operationError = self.emptyError()
            let success = self.runtime.bossUpdateStreamNextDeviceSettings(handle, 60_000, &report, &operationError)
            guard success else {
                defer { self.runtime.bossErrorFree(operationError) }
                throw self.map(error: operationError)
            }
            return Self.swiftDeviceSettingsReport(from: report)
        }
    }

    func audioModeCatalogUpdateStream(on transport: AppleBleBossTransport) -> AsyncThrowingStream<[BossAppleAudioModeConfig], Error> {
        updateStream(on: transport, kind: BOSS_FFI_UPDATE_STREAM_KIND_AUDIO_MODE_CATALOG) { handle in
            var buffer = BossBuffer(data: nil, len: 0)
            var operationError = self.emptyError()
            let success = self.runtime.bossUpdateStreamNextAudioModeCatalog(handle, 60_000, &buffer, &operationError)
            guard success else {
                defer { self.runtime.bossErrorFree(operationError) }
                throw self.map(error: operationError)
            }
            defer { self.runtime.bossBufferFree(buffer) }
            return try Self.decodeStructBuffer(buffer, as: BossFfiAudioModeConfig.self).map(Self.swiftAudioModeConfig)
        }
    }

    private func updateStream<Element: Sendable>(
        on transport: AppleBleBossTransport,
        kind: BossFfiUpdateStreamKind,
        next: @escaping @Sendable (UnsafeMutableRawPointer?) throws -> Element
    ) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try self.withUpdateStreamHandle(on: transport, kind: kind) { handle in
                        while !Task.isCancelled {
                            do {
                                continuation.yield(try next(handle))
                            } catch let error as BossAppleControlError {
                                if case .responseTimedOut = error {
                                    continue
                                }
                                throw error
                            }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func directObservedSetting<Value: Sendable & Equatable>(
        initialUnavailableReason: BossAppleSettingUnavailableReason = .dataUnavailable,
        _ read: () throws -> Value
    ) throws -> BossAppleObservedSetting<Value> {
        do {
            return BossAppleObservedSetting(value: try read(), source: .directGet)
        } catch let error as BossAppleControlError {
            if let reason = Self.unavailableReason(for: error) {
                return BossAppleObservedSetting(value: nil, unavailableReason: reason)
            }
            throw error
        }
    }

    private func directOptionalSetting<Value>(
        _ read: () throws -> Value
    ) throws -> Value? {
        do {
            return try read()
        } catch let error as BossAppleControlError {
            if Self.unavailableReason(for: error) != nil {
                return nil
            }
            throw error
        }
    }

    func currentAudioMode(on transport: AppleBleBossTransport) async throws -> Int {
        BossRustLogger.log("using Rust bridge for currentAudioMode")
        return try withSessionHandle(on: transport) { handle in
            var modeIndex: Int32 = 0
            var operationError = emptyError()
            let success = runtime.bossSessionCurrentAudioMode(handle, &modeIndex, &operationError)
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return Int(modeIndex)
        }
    }

    func standbyTimer(on transport: AppleBleBossTransport) async throws -> BossAppleStandbyTimerValue {
        BossRustLogger.log("using Rust bridge for standbyTimer")
        return try withSessionHandle(on: transport) { handle in
            var value = BossFfiStandbyTimerValue()
            var operationError = emptyError()
            let success = runtime.bossSessionStandbyTimer(handle, &value, &operationError)
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return Self.swiftStandbyTimer(from: value)
        }
    }

    func settingsSnapshot(on transport: AppleBleBossTransport) async throws -> BossAppleSettingsSnapshot {
        BossRustLogger.log("using Rust bridge for settingsSnapshot")
        return try withSessionHandle(on: transport) { handle in
            var buffer = BossBuffer(data: nil, len: 0)
            var operationError = emptyError()
            let success = runtime.bossSessionSettingsSnapshot(handle, &buffer, &operationError)
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            defer { runtime.bossBufferFree(buffer) }
            return try Self.swiftSettingsSnapshot(from: buffer)
        }
    }

    func supportedAudioModePrompts(on transport: AppleBleBossTransport) async throws -> [BossAppleAudioModePrompt] {
        BossRustLogger.log("using Rust bridge for supportedAudioModePrompts")
        return try withSessionHandle(on: transport) { handle in
            var buffer = BossBuffer(data: nil, len: 0)
            var operationError = emptyError()
            let success = runtime.bossSessionSupportedAudioModePrompts(handle, &buffer, &operationError)
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            defer { runtime.bossBufferFree(buffer) }
            return Self.decodeStructBuffer(buffer, as: BossFfiAudioModePrompt.self).map(Self.swiftAudioModePrompt)
        }
    }

    func audioModeConfigs(on transport: AppleBleBossTransport) async throws -> [BossAppleAudioModeConfig] {
        BossRustLogger.log("using Rust bridge for audioModeConfigs")
        return try withSessionHandle(on: transport) { handle in
            var buffer = BossBuffer(data: nil, len: 0)
            var operationError = emptyError()
            let success = runtime.bossSessionAudioModeConfigs(handle, &buffer, &operationError)
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            defer { runtime.bossBufferFree(buffer) }
            return try Self.decodeStructBuffer(buffer, as: BossFfiAudioModeConfig.self).map(Self.swiftAudioModeConfig)
        }
    }

    func audioModeCapabilities(on transport: AppleBleBossTransport) async throws -> BossAppleAudioModesCapabilities {
        BossRustLogger.log("using Rust bridge for audioModeCapabilities")
        return try withSessionHandle(on: transport) { handle in
            var capabilities = BossFfiAudioModesCapabilities()
            var operationError = emptyError()
            let success = runtime.bossSessionAudioModeCapabilities(handle, &capabilities, &operationError)
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return Self.swiftAudioModeCapabilities(from: capabilities)
        }
    }

    func audioModeSettingsConfig(on transport: AppleBleBossTransport) async throws -> BossAppleAudioModeSettingsConfig {
        BossRustLogger.log("using Rust bridge for audioModeSettingsConfig")
        return try withSessionHandle(on: transport) { handle in
            var config = BossFfiAudioModeSettingsConfig()
            var operationError = emptyError()
            let success = runtime.bossSessionAudioModeSettingsConfig(handle, &config, &operationError)
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return try Self.swiftConfig(from: config)
        }
    }

    func firmwareVersion(
        on transport: AppleBleBossTransport,
        port: Int,
        deviceID: Int
    ) async throws -> BossAppleFirmwareVersionInfo {
        BossRustLogger.log("using Rust bridge for firmwareVersion(port: \(port), deviceID: \(deviceID))")
        return try withSessionHandle(on: transport) { handle in
            var info = BossFfiFirmwareVersionInfo()
            var operationError = emptyError()
            let success = runtime.bossSessionFirmwareVersion(handle, Int32(port), Int32(deviceID), &info, &operationError)
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return Self.swiftFirmwareVersion(from: info)
        }
    }

    func equalizerSettingsIfAvailable(on transport: AppleBleBossTransport) async throws -> BossAppleEqualizerSettings? {
        BossRustLogger.log("using Rust bridge for equalizerSettingsIfAvailable")
        return try withSessionHandle(on: transport) { handle in
            try directOptionalSetting {
                var settings = BossFfiEqualizerSettings()
                var operationError = emptyError()
                let success = runtime.bossSessionEqualizerSettings(handle, &settings, &operationError)
                guard success else {
                    defer { runtime.bossErrorFree(operationError) }
                    throw map(error: operationError)
                }
                return Self.swiftEqualizerSettings(from: settings)
            }
        }
    }

    func favoriteAudioModeIndices(on transport: AppleBleBossTransport) async throws -> [Int] {
        BossRustLogger.log("using Rust bridge for favoriteAudioModeIndices")
        return try withSessionHandle(on: transport) { handle in
            var buffer = BossBuffer(data: nil, len: 0)
            var operationError = emptyError()
            let success = runtime.bossSessionFavoriteAudioModeIndices(handle, &buffer, &operationError)
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            defer { runtime.bossBufferFree(buffer) }
            return Self.readI32Buffer(buffer)
        }
    }

    func setFavoriteAudioModeIndices(
        on transport: AppleBleBossTransport,
        indices: [Int],
        numberOfModes: Int
    ) async throws -> [Int] {
        BossRustLogger.log("using Rust bridge for setFavoriteAudioModeIndices")
        return try withSessionHandle(on: transport) { handle in
            let ffiIndices = indices.map(Int32.init)
            var buffer = BossBuffer(data: nil, len: 0)
            var operationError = emptyError()
            let success = ffiIndices.withUnsafeBufferPointer { pointer in
                runtime.bossSessionSetFavoriteAudioModeIndices(
                    handle,
                    Int32(numberOfModes),
                    pointer.baseAddress,
                    pointer.count,
                    &buffer,
                    &operationError
                )
            }
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            defer { runtime.bossBufferFree(buffer) }
            return Self.readI32Buffer(buffer)
        }
    }

    func deviceSettingsReport(on transport: AppleBleBossTransport) async throws -> BossAppleDeviceSettingsReport {
        BossRustLogger.log("using Rust bridge for deviceSettingsReport")
        return try withSessionHandle(on: transport, deviceSettingsReport(handle:))
    }

    func refreshModeWorkspaceSnapshot(on transport: AppleBleBossTransport) async throws -> BossAppleModeWorkspaceSnapshot {
        BossRustLogger.log("using Rust bridge for refreshModeWorkspaceSnapshot")
        return try withSessionHandle(on: transport) { handle in
            var modeIndex: Int32 = 0
            var currentError = emptyError()
            guard runtime.bossSessionCurrentAudioMode(handle, &modeIndex, &currentError) else {
                defer { runtime.bossErrorFree(currentError) }
                throw map(error: currentError)
            }

            var settingsFfi = BossFfiAudioModeSettingsConfig()
            var settingsError = emptyError()
            guard runtime.bossSessionAudioModeSettingsConfig(handle, &settingsFfi, &settingsError) else {
                defer { runtime.bossErrorFree(settingsError) }
                throw map(error: settingsError)
            }

            let equalizer = try directOptionalSetting {
                var settings = BossFfiEqualizerSettings()
                var operationError = emptyError()
                let success = runtime.bossSessionEqualizerSettings(handle, &settings, &operationError)
                guard success else {
                    defer { runtime.bossErrorFree(operationError) }
                    throw map(error: operationError)
                }
                return Self.swiftEqualizerSettings(from: settings)
            }

            let deviceSettings = try deviceSettingsReport(handle: handle)

            return BossAppleModeWorkspaceSnapshot(
                currentAudioModeIndex: Int(modeIndex),
                settings: try Self.swiftConfig(from: settingsFfi),
                equalizer: equalizer,
                deviceSettings: deviceSettings
            )
        }
    }

    private func deviceSettingsReport(handle: UnsafeMutableRawPointer?) throws -> BossAppleDeviceSettingsReport {
        let wearDetection: BossAppleObservedSetting<BossAppleOnHeadDetectionValue> = try directObservedSetting {
            var value = BossFfiOnHeadDetectionValue()
            var operationError = emptyError()
            let success = runtime.bossSessionOnHeadDetection(handle, &value, &operationError)
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return Self.swiftOnHeadDetection(from: value)
        }

        let autoAwareEnabled: BossAppleObservedSetting<Bool> = try directObservedSetting {
                var enabled = false
                var operationError = emptyError()
                let success = runtime.bossSessionEnabledSetting(
                    handle,
                    BossAppleSettingsProtocol.autoAwareFunctionRaw,
                    &enabled,
                    &operationError
                )
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return enabled
        }

        let autoPlayPauseEnabled: BossAppleObservedSetting<Bool> = try directObservedSetting {
                var enabled = false
                var operationError = emptyError()
                let success = runtime.bossSessionEnabledSetting(
                    handle,
                    BossAppleSettingsProtocol.autoPlayPauseFunctionRaw,
                    &enabled,
                    &operationError
                )
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return enabled
        }

        let autoAnswerEnabled: BossAppleObservedSetting<Bool>
        if let derived = wearDetection.value?.isAutoAnswerEnabled {
            autoAnswerEnabled = BossAppleObservedSetting(value: derived, source: .directGet)
        } else {
            autoAnswerEnabled = try directObservedSetting {
                var enabled = false
                var operationError = emptyError()
                let success = runtime.bossSessionEnabledSetting(
                    handle,
                    BossAppleSettingsProtocol.autoAnswerFunctionRaw,
                    &enabled,
                    &operationError
                )
                guard success else {
                    defer { runtime.bossErrorFree(operationError) }
                    throw map(error: operationError)
                }
                return enabled
            }
        }

        let volumeControl: BossAppleObservedSetting<BossAppleVolumeControlStatus> = try directObservedSetting {
            var status = BossFfiVolumeControlStatus()
            var operationError = emptyError()
            let success = runtime.bossSessionVolumeControlStatus(handle, &status, &operationError)
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return try Self.swiftVolumeControlStatus(from: status)
        }

        return BossAppleDeviceSettingsReport(
            wearDetection: wearDetection,
            autoAwareEnabled: autoAwareEnabled,
            autoPlayPauseEnabled: autoPlayPauseEnabled,
            autoAnswerEnabled: autoAnswerEnabled,
            volumeControl: volumeControl
        )
    }

    func setCurrentAudioMode(
        on transport: AppleBleBossTransport,
        targetIndex: Int,
        playVoicePrompt: Bool
    ) async throws -> BossAppleCurrentAudioModeWriteResult {
        BossRustLogger.log("using Rust bridge for setCurrentAudioMode(targetIndex: \(targetIndex), playVoicePrompt: \(playVoicePrompt))")
        let result = try withSessionHandle(on: transport) { handle in
            var result = BossFfiCurrentAudioModeWriteResult(
                disposition: BOSS_FFI_WRITE_DISPOSITION_UNCHANGED,
                mode_index: 0,
                target_index: 0
            )
            var operationError = emptyError()
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
            return result
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
        on transport: AppleBleBossTransport,
        update: BossAppleAudioModeSettingsConfigPatch
    ) async throws -> BossAppleAudioModeSettingsWriteResult {
        BossRustLogger.log("using Rust bridge for setAudioModeSettings")
        let result = try withSessionHandle(on: transport) { handle in
            var result = BossFfiAudioModeSettingsWriteResult(
                disposition: BOSS_FFI_WRITE_DISPOSITION_UNCHANGED,
                config: Self.ffiConfig(from: BossAppleAudioModeSettingsConfig(
                    cncLevel: 0,
                    autoCNCEnabled: false,
                    spatialAudioMode: .off,
                    windBlockEnabled: false,
                    ancToggleEnabled: false
                ))
            )
            var operationError = emptyError()
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
            return result
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

    func setEqualizer(
        on transport: AppleBleBossTransport,
        update: BossAppleEqualizerSettingsPatch
    ) async throws -> BossAppleEqualizerWriteResult {
        BossRustLogger.log("using Rust bridge for setEqualizer")
        let result = try withSessionHandle(on: transport) { handle in
            var result = BossFfiEqualizerWriteResult(
                disposition: BOSS_FFI_WRITE_DISPOSITION_UNCHANGED,
                settings: Self.ffiEqualizerSettings(from: BossAppleEqualizerSettings(ranges: []))
            )
            var operationError = emptyError()
            let success = runtime.bossSessionSetEqualizer(
                handle,
                Self.ffiEqualizerPatch(from: update),
                &result,
                &operationError
            )
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return result
        }

        let settings = Self.swiftEqualizerSettings(from: result.settings)
        switch result.disposition {
        case BOSS_FFI_WRITE_DISPOSITION_UNCHANGED:
            return .unchanged(settings)
        case BOSS_FFI_WRITE_DISPOSITION_UPDATED:
            return .updated(settings)
        case BOSS_FFI_WRITE_DISPOSITION_VERIFICATION_INCONCLUSIVE:
            return .verificationInconclusive(settings)
        default:
            throw BossAppleControlError.unsupportedOperation("Rust FFI returned unknown equalizer write disposition \(result.disposition)")
        }
    }

    func setEnabledSetting(
        on transport: AppleBleBossTransport,
        functionRaw: UInt8,
        enabled: Bool
    ) async throws -> Bool {
        BossRustLogger.log("using Rust bridge for setEnabledSetting(functionRaw: \(functionRaw), enabled: \(enabled))")
        return try withSessionHandle(on: transport) { handle in
            var updated = false
            var operationError = emptyError()
            let success = runtime.bossSessionSetEnabledSetting(
                handle,
                functionRaw,
                enabled,
                &updated,
                &operationError
            )
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return updated
        }
    }

    func setWearDetectionEnabled(
        on transport: AppleBleBossTransport,
        enabled: Bool
    ) async throws -> BossAppleOnHeadDetectionValue {
        BossRustLogger.log("using Rust bridge for setWearDetectionEnabled(enabled: \(enabled))")
        return try withSessionHandle(on: transport) { handle in
            var current = BossFfiOnHeadDetectionValue()
            var operationError = emptyError()
            let readSuccess = runtime.bossSessionOnHeadDetection(handle, &current, &operationError)
            guard readSuccess else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }

            current.is_enabled = enabled
            var updated = BossFfiOnHeadDetectionValue()
            var writeError = emptyError()
            let writeSuccess = runtime.bossSessionSetOnHeadDetection(handle, current, &updated, &writeError)
            guard writeSuccess else {
                defer { runtime.bossErrorFree(writeError) }
                throw map(error: writeError)
            }
            return Self.swiftOnHeadDetection(from: updated)
        }
    }

    func setWearDetection(
        on transport: AppleBleBossTransport,
        value: BossAppleOnHeadDetectionValue
    ) async throws -> BossAppleOnHeadDetectionValue {
        BossRustLogger.log("using Rust bridge for setWearDetection")
        return try withSessionHandle(on: transport) { handle in
            var updated = BossFfiOnHeadDetectionValue()
            var operationError = emptyError()
            let success = runtime.bossSessionSetOnHeadDetection(
                handle,
                Self.ffiOnHeadDetection(from: value),
                &updated,
                &operationError
            )
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return Self.swiftOnHeadDetection(from: updated)
        }
    }

    func setVolumeControl(
        on transport: AppleBleBossTransport,
        value: BossAppleVolumeControlValue
    ) async throws -> BossAppleVolumeControlStatus {
        BossRustLogger.log("using Rust bridge for setVolumeControl(value: \(value.displayName))")
        return try withSessionHandle(on: transport) { handle in
            var status = BossFfiVolumeControlStatus()
            var operationError = emptyError()
            let success = runtime.bossSessionSetVolumeControl(handle, value.rawValue, &status, &operationError)
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return try Self.swiftVolumeControlStatus(from: status)
        }
    }

    func setStandbyTimer(
        on transport: AppleBleBossTransport,
        minutes: Int
    ) async throws -> BossAppleStandbyTimerValue {
        BossRustLogger.log("using Rust bridge for setStandbyTimer(minutes: \(minutes))")
        return try withSessionHandle(on: transport) { handle in
            var value = BossFfiStandbyTimerValue()
            var operationError = emptyError()
            let success = runtime.bossSessionSetStandbyTimer(handle, Int32(minutes), &value, &operationError)
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return Self.swiftStandbyTimer(from: value)
        }
    }

    func setAudioModeFavorite(
        on transport: AppleBleBossTransport,
        index: Int,
        isFavorite: Bool
    ) async throws -> [Int] {
        BossRustLogger.log("using Rust bridge for setAudioModeFavorite(index: \(index), isFavorite: \(isFavorite))")
        return try withSessionHandle(on: transport) { handle in
            var buffer = BossBuffer(data: nil, len: 0)
            var operationError = emptyError()
            let success = runtime.bossSessionSetAudioModeFavorite(
                handle,
                Int32(index),
                isFavorite,
                &buffer,
                &operationError
            )
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            defer { runtime.bossBufferFree(buffer) }
            return Self.readI32Buffer(buffer)
        }
    }

    func saveCustomAudioMode(
        on transport: AppleBleBossTransport,
        name: String,
        settings: BossAppleAudioModeSettingsConfig,
        prompt: BossAppleAudioModePrompt,
        requestedSlot: Int?
    ) async throws -> BossAppleAudioModeConfig {
        BossRustLogger.log("using Rust bridge for saveCustomAudioMode(slot: \(requestedSlot.map(String.init) ?? "auto"))")
        return try withSessionHandle(on: transport) { handle in
            var result = BossFfiAudioModeConfig()
            var operationError = emptyError()
            let success = name.utf8CString.withUnsafeBufferPointer { nameBuffer in
                runtime.bossSessionSaveCustomAudioMode(
                    handle,
                    UnsafeRawPointer(nameBuffer.baseAddress)?.assumingMemoryBound(to: UInt8.self),
                    max(0, nameBuffer.count - 1),
                    Self.ffiConfig(from: settings),
                    prompt.byte1,
                    prompt.byte2,
                    requestedSlot != nil,
                    Int32(requestedSlot ?? 0),
                    &result,
                    &operationError
                )
            }
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return try Self.swiftAudioModeConfig(from: result)
        }
    }

    func deleteCustomAudioMode(
        on transport: AppleBleBossTransport,
        slot: Int
    ) async throws -> BossAppleAudioModeConfig {
        BossRustLogger.log("using Rust bridge for deleteCustomAudioMode(slot: \(slot))")
        return try withSessionHandle(on: transport) { handle in
            var result = BossFfiAudioModeConfig()
            var operationError = emptyError()
            let success = runtime.bossSessionDeleteCustomAudioMode(
                handle,
                Int32(slot),
                &result,
                &operationError
            )
            guard success else {
                defer { runtime.bossErrorFree(operationError) }
                throw map(error: operationError)
            }
            return try Self.swiftAudioModeConfig(from: result)
        }
    }

}
