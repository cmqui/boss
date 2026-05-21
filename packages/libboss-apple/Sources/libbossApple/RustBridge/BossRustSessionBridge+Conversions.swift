import CBossRustFFI
import Foundation
import libboss

extension BossRustSessionBridge {
    func map(error ffiError: BossFfiError) -> BossAppleControlError {
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
        case BOSS_FFI_ERROR_NO_FREE_CUSTOM_AUDIO_MODE_SLOT:
            return .noFreeCustomAudioModeSlot
        case BOSS_FFI_ERROR_CUSTOM_AUDIO_MODE_SLOT_NOT_EDITABLE:
            return .unsupportedOperation(message.isEmpty ? "Requested custom audio mode slot is not editable" : message)
        case BOSS_FFI_ERROR_CUSTOM_AUDIO_MODE_SLOT_NOT_FOUND:
            return .unsupportedOperation(message.isEmpty ? "Requested custom audio mode slot was not found" : message)
        default:
            return .unsupportedOperation(message.isEmpty ? "Rust FFI error code \(ffiError.code)" : message)
        }
    }

    static func unavailableReason(for error: BossAppleControlError) -> BossAppleSettingUnavailableReason? {
        switch error {
        case .responseTimedOut:
            return .timedOut
        case .responseStreamEnded:
            return .responseStreamEnded
        case .bmapErrorResponse(_, let payloadHex):
            let code = BossAppleController.bmapErrorCode(from: payloadHex)
            switch code {
            case .fblockNotSupp?, .funcNotSupp?:
                return .functionUnsupported
            case .opNotSupp?:
                return .operatorUnsupported
            case .dataUnavailable?:
                return .dataUnavailable
            case .insecureTransport?:
                return .insecureTransport
            case let code:
                return .bmapError(code)
            }
        default:
            return nil
        }
    }

    static func readData(_ buffer: BossBuffer) -> Data {
        guard let data = buffer.data, buffer.len > 0 else {
            return Data()
        }
        return Data(bytes: data, count: buffer.len)
    }

    func read(buffer: BossBuffer) -> String {
        guard let data = buffer.data, buffer.len > 0 else {
            return ""
        }
        let bytes = UnsafeBufferPointer(start: data, count: buffer.len)
        return String(decoding: bytes, as: UTF8.self)
    }

    static func readI32Buffer(_ buffer: BossBuffer) -> [Int] {
        guard let data = buffer.data, buffer.len > 0 else {
            return []
        }
        let byteCount = buffer.len
        guard byteCount % MemoryLayout<Int32>.size == 0 else {
            return []
        }
        let count = byteCount / MemoryLayout<Int32>.size
        let raw = UnsafeRawBufferPointer(start: data, count: byteCount)
        return raw.bindMemory(to: Int32.self).prefix(count).map { Int(Int32(littleEndian: $0)) }
    }

    static func decodeStructBuffer<T>(_ buffer: BossBuffer, as _: T.Type) -> [T] {
        guard let data = buffer.data, buffer.len > 0 else {
            return []
        }
        let stride = MemoryLayout<T>.stride
        guard stride > 0, buffer.len % stride == 0 else {
            return []
        }
        let raw = UnsafeRawBufferPointer(start: data, count: buffer.len)
        return Array(raw.bindMemory(to: T.self))
    }

    func emptyError() -> BossFfiError {
        BossFfiError(
            code: BOSS_FFI_ERROR_NONE,
            message: BossBuffer(data: nil, len: 0),
            has_bmap_error_code: false,
            bmap_error_code: 0
        )
    }

    static func ffiConfig(from config: BossAudioModeSettingsConfig) -> BossFfiAudioModeSettingsConfig {
        BossFfiAudioModeSettingsConfig(
            cnc_level: Int32(config.cncLevel),
            auto_cnc_enabled: config.autoCNCEnabled,
            spatial_audio_mode: config.spatialAudioMode.rawValue,
            wind_block_enabled: config.windBlockEnabled,
            anc_toggle_enabled: config.ancToggleEnabled
        )
    }

    static func ffiPatch(from patch: BossAudioModeSettingsConfigPatch) -> BossFfiAudioModeSettingsConfigPatch {
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

    static func swiftConfig(from ffi: BossFfiAudioModeSettingsConfig) throws -> BossAudioModeSettingsConfig {
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

    static func swiftAudioModePrompt(from ffi: BossFfiAudioModePrompt) -> BossAudioModePrompt {
        let name = withUnsafeBytes(of: ffi.name_bytes) { rawBuffer in
            String(decoding: rawBuffer.prefix(ffi.name_len), as: UTF8.self)
        }
        return BossAudioModePrompt(byte1: ffi.byte1, byte2: ffi.byte2, name: name)
    }

    static func swiftAudioModeConfig(from ffi: BossFfiAudioModeConfig) throws -> BossAudioModeConfig {
        let name = withUnsafeBytes(of: ffi.name_bytes) { rawBuffer in
            String(decoding: rawBuffer.prefix(ffi.name_len), as: UTF8.self)
        }
        return BossAudioModeConfig(
            modeIndex: Int(ffi.mode_index),
            prompt: BossAudioModePrompt.known(byte1: ffi.prompt_byte1, byte2: ffi.prompt_byte2),
            name: name,
            favorite: ffi.favorite,
            userConfigurable: ffi.user_configurable,
            userConfigured: ffi.user_configured,
            settings: try swiftConfig(from: ffi.settings)
        )
    }

    static func swiftFirmwareVersion(from ffi: BossFfiFirmwareVersionInfo) -> FirmwareVersionInfo {
        let version = withUnsafeBytes(of: ffi.version_bytes) { rawBuffer in
            String(decoding: rawBuffer.prefix(ffi.version_len), as: UTF8.self)
        }
        return FirmwareVersionInfo(version: version, port: Int(ffi.port))
    }

    static func swiftStandbyTimer(from ffi: BossFfiStandbyTimerValue) -> BossStandbyTimerValue {
        BossStandbyTimerValue(
            minutes: Int(ffi.minutes),
            supportsTwoByteMinutes: ffi.supports_two_byte_minutes
        )
    }

    static func swiftSettingsSnapshot(from buffer: BossBuffer) throws -> BossSettingsSnapshot {
        let bytes = readData(buffer)
        var offset = 0
        var packetsByFunctionRaw: [UInt8: BmapPacket] = [:]

        while offset < bytes.count {
            guard offset + 4 <= bytes.count else {
                throw BossAppleControlError.unsupportedOperation("Rust FFI returned truncated settings snapshot length prefix")
            }
            let length = bytes[offset..<(offset + 4)].withUnsafeBytes { rawBuffer in
                Int(UInt32(littleEndian: rawBuffer.load(as: UInt32.self)))
            }
            offset += 4
            guard length >= BmapPacket.headerSize, offset + length <= bytes.count else {
                throw BossAppleControlError.unsupportedOperation("Rust FFI returned invalid settings snapshot packet length")
            }
            let packetBytes = bytes[offset..<(offset + length)]
            let packet = try BmapCodec.decode(Data(packetBytes))
            packetsByFunctionRaw[packet.function.rawValue] = packet
            offset += length
        }

        return BossSettingsSnapshot(packetsByFunctionRaw: packetsByFunctionRaw)
    }

    static func swiftBootstrappedDevice(from ffi: BossFfiBootstrappedDevice) -> BootstrappedDevice {
        let bmapVersion = withUnsafeBytes(of: ffi.bmap_version_bytes) { rawBuffer in
            String(decoding: rawBuffer.prefix(ffi.bmap_version_len), as: UTF8.self)
        }
        let productName = withUnsafeBytes(of: ffi.product_name_bytes) { rawBuffer in
            String(decoding: rawBuffer.prefix(ffi.product_name_len), as: UTF8.self)
        }
        let functionBlockBytes = withUnsafeBytes(of: ffi.function_blocks_bytes) { rawBuffer in
            Data(rawBuffer.prefix(ffi.function_blocks_len))
        }
        let product = ProductMap.product(for: ffi.product_id)
        return BootstrappedDevice(
            bmapVersion: BmapVersionInfo(version: bmapVersion),
            productID: ffi.product_id,
            productName: productName,
            productVariant: ProductIDVariant(
                productID: ffi.product_id,
                variant: ffi.variant,
                product: product,
                variantName: product?.variants[ffi.variant]
            ),
            supportedFunctionBlocks: FunctionBlockSet(bytes: functionBlockBytes),
            transportKind: ffi.transport_kind == 0 ? .ble : .stream,
            defaultDeviceID: Int(ffi.default_device_id),
            defaultPort: Int(ffi.default_port)
        )
    }

    static func swiftDeviceSettingsReport(from ffi: BossFfiDeviceSettingsReport) -> BossAppleDeviceSettingsReport {
        BossAppleDeviceSettingsReport(
            wearDetection: swiftObservedOnHeadDetection(from: ffi.wear_detection),
            autoAwareEnabled: swiftObservedBool(from: ffi.auto_aware_enabled),
            autoPlayPauseEnabled: swiftObservedBool(from: ffi.auto_play_pause_enabled),
            autoAnswerEnabled: swiftObservedBool(from: ffi.auto_answer_enabled),
            volumeControl: swiftObservedVolumeControl(from: ffi.volume_control)
        )
    }

    static func swiftObservedBool(from ffi: BossFfiObservedBool) -> BossAppleObservedSetting<Bool> {
        BossAppleObservedSetting(
            value: ffi.has_value ? ffi.value : nil,
            source: ffi.has_source ? swiftSettingSource(raw: ffi.source) : nil,
            unavailableReason: ffi.has_unavailable_reason ? swiftUnavailableReason(raw: ffi.unavailable_reason) : nil
        )
    }

    static func swiftObservedOnHeadDetection(from ffi: BossFfiObservedOnHeadDetection) -> BossAppleObservedSetting<BossOnHeadDetectionValue> {
        BossAppleObservedSetting(
            value: ffi.has_value ? swiftOnHeadDetection(from: ffi.value) : nil,
            source: ffi.has_source ? swiftSettingSource(raw: ffi.source) : nil,
            unavailableReason: ffi.has_unavailable_reason ? swiftUnavailableReason(raw: ffi.unavailable_reason) : nil
        )
    }

    static func swiftObservedVolumeControl(from ffi: BossFfiObservedVolumeControlStatus) -> BossAppleObservedSetting<BossVolumeControlStatus> {
        BossAppleObservedSetting(
            value: ffi.has_value ? (try? swiftVolumeControlStatus(from: ffi.value)) : nil,
            source: ffi.has_source ? swiftSettingSource(raw: ffi.source) : nil,
            unavailableReason: ffi.has_unavailable_reason ? swiftUnavailableReason(raw: ffi.unavailable_reason) : nil
        )
    }

    static func swiftSettingSource(raw: UInt8) -> BossAppleSettingSource? {
        switch raw {
        case 0: return .snapshot
        case 1: return .compositeSnapshot
        case 2: return .directGet
        default: return nil
        }
    }

    static func swiftUnavailableReason(raw: UInt8) -> BossAppleSettingUnavailableReason? {
        switch raw {
        case 0: return .missingFromSnapshot
        case 1: return .timedOut
        case 2: return .responseStreamEnded
        case 3: return .functionUnsupported
        case 4: return .operatorUnsupported
        case 5: return .dataUnavailable
        case 6: return .insecureTransport
        case 7: return .unexpectedStreamTermination
        case 8: return .bmapError(nil)
        default: return nil
        }
    }

    static func ffiEqualizerPatch(from patch: BossEqualizerSettingsPatch) -> BossFfiEqualizerPatch {
        BossFfiEqualizerPatch(
            has_bass: patch.bass != nil,
            bass: Int32(patch.bass ?? 0),
            has_mid: patch.mid != nil,
            mid: Int32(patch.mid ?? 0),
            has_treble: patch.treble != nil,
            treble: Int32(patch.treble ?? 0)
        )
    }

    static func ffiEqualizerRange(from range: BossEqualizerRangeLevel?) -> BossFfiEqualizerRange {
        guard let range else {
            return BossFfiEqualizerRange(available: false, current_level: 0, min_level: 0, max_level: 0)
        }
        return BossFfiEqualizerRange(
            available: true,
            current_level: Int32(range.currentLevel),
            min_level: Int32(range.minLevel),
            max_level: Int32(range.maxLevel)
        )
    }

    static func ffiEqualizerSettings(from settings: BossEqualizerSettings) -> BossFfiEqualizerSettings {
        BossFfiEqualizerSettings(
            bass: ffiEqualizerRange(from: settings.range(for: .bass)),
            mid: ffiEqualizerRange(from: settings.range(for: .mid)),
            treble: ffiEqualizerRange(from: settings.range(for: .treble))
        )
    }

    static func ffiOnHeadDetection(from value: BossOnHeadDetectionValue) -> BossFfiOnHeadDetectionValue {
        BossFfiOnHeadDetectionValue(
            is_enabled: value.isEnabled,
            has_auto_play_enabled: value.isAutoPlayEnabled != nil,
            auto_play_enabled: value.isAutoPlayEnabled ?? false,
            has_auto_answer_enabled: value.isAutoAnswerEnabled != nil,
            auto_answer_enabled: value.isAutoAnswerEnabled ?? false,
            has_auto_transparency_enabled: value.isAutoTransparencyEnabled != nil,
            auto_transparency_enabled: value.isAutoTransparencyEnabled ?? false
        )
    }

    static func swiftEqualizerSettings(from ffi: BossFfiEqualizerSettings) -> BossEqualizerSettings {
        var ranges: [BossEqualizerRangeLevel] = []
        if ffi.bass.available {
            ranges.append(
                BossEqualizerRangeLevel(
                    band: .bass,
                    currentLevel: Int(ffi.bass.current_level),
                    minLevel: Int(ffi.bass.min_level),
                    maxLevel: Int(ffi.bass.max_level)
                )
            )
        }
        if ffi.mid.available {
            ranges.append(
                BossEqualizerRangeLevel(
                    band: .mid,
                    currentLevel: Int(ffi.mid.current_level),
                    minLevel: Int(ffi.mid.min_level),
                    maxLevel: Int(ffi.mid.max_level)
                )
            )
        }
        if ffi.treble.available {
            ranges.append(
                BossEqualizerRangeLevel(
                    band: .treble,
                    currentLevel: Int(ffi.treble.current_level),
                    minLevel: Int(ffi.treble.min_level),
                    maxLevel: Int(ffi.treble.max_level)
                )
            )
        }
        return BossEqualizerSettings(ranges: ranges)
    }

    static func swiftOnHeadDetection(from ffi: BossFfiOnHeadDetectionValue) -> BossOnHeadDetectionValue {
        BossOnHeadDetectionValue(
            isEnabled: ffi.is_enabled,
            isAutoPlayEnabled: ffi.has_auto_play_enabled ? ffi.auto_play_enabled : nil,
            isAutoAnswerEnabled: ffi.has_auto_answer_enabled ? ffi.auto_answer_enabled : nil,
            isAutoTransparencyEnabled: ffi.has_auto_transparency_enabled ? ffi.auto_transparency_enabled : nil
        )
    }

    static func swiftVolumeControlStatus(from ffi: BossFfiVolumeControlStatus) throws -> BossVolumeControlStatus {
        guard let value = BossVolumeControlValue(rawValue: ffi.value) else {
            throw BossAppleControlError.unsupportedOperation(
                "Rust FFI returned unknown volume control value \(ffi.value)"
            )
        }
        let supportedValues: [BossVolumeControlValue]? = ffi.has_supported_values_mask ? [
            (ffi.supported_values_mask & 0x08) == 0x08 ? .disabled : nil,
            (ffi.supported_values_mask & 0x01) == 0x01 ? .button : nil,
            (ffi.supported_values_mask & 0x02) == 0x02 ? .capTouch : nil,
            (ffi.supported_values_mask & 0x04) == 0x04 ? .imu : nil,
        ].compactMap { $0 } : nil

        return BossVolumeControlStatus(value: value, supportedValues: supportedValues)
    }
}
