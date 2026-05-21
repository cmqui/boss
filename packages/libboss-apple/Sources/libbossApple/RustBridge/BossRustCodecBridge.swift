import CBossRustFFI
import Foundation

enum BossRustCodecBridge {
    typealias PacketEncodeFn = @convention(c) (BossFfiBmapPacket, UnsafeMutablePointer<BossBuffer>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias PacketDecodeFn = @convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias PacketFreeFn = @convention(c) (BossFfiBmapPacket) -> Void
    typealias BuildPacketFn = @convention(c) (UnsafeMutablePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias CurrentModeStartPacketFn = @convention(c) (Int32, Bool, UnsafeMutablePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias SettingsConfigSetGetPacketFn = @convention(c) (BossFfiAudioModeSettingsConfig, UnsafeMutablePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias ModeConfigSetGetPacketFn = @convention(c) (Int32, UInt8, UInt8, UnsafePointer<UInt8>?, Int, BossFfiAudioModeSettingsConfig, UnsafeMutablePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias FavoritesSetGetPacketFn = @convention(c) (Int32, UnsafePointer<Int32>?, Int, UnsafeMutablePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias StandbyTimerSetGetPacketFn = @convention(c) (Int32, UnsafeMutablePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias OnHeadDetectionSetGetPacketFn = @convention(c) (BossFfiOnHeadDetectionValue, UnsafeMutablePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias EnabledSettingPacketFn = @convention(c) (UInt8, UnsafeMutablePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias EnabledSettingSetPacketFn = @convention(c) (UInt8, Bool, UnsafeMutablePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias EqualizerSetGetPacketFn = @convention(c) (Int32, UInt8, UnsafeMutablePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias ParseCurrentModeFn = @convention(c) (UnsafePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias ParseCapabilitiesFn = @convention(c) (UnsafePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiAudioModesCapabilities>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias ParseFavoritesFn = @convention(c) (UnsafePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossBuffer>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias ParseConfigFn = @convention(c) (UnsafePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiAudioModeSettingsConfig>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias ParseModeConfigFn = @convention(c) (UnsafePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiAudioModeConfig>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias ParsePromptsFn = @convention(c) (UnsafePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossBuffer>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias ParseEqualizerFn = @convention(c) (UnsafePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiEqualizerSettings>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias ParseStandbyTimerFn = @convention(c) (UnsafePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiStandbyTimerValue>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias ParseEnabledFlagFn = @convention(c) (UnsafePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<Bool>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias ParseOnHeadDetectionFn = @convention(c) (UnsafePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiOnHeadDetectionValue>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    typealias ParseVolumeControlStatusFn = @convention(c) (UnsafePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiVolumeControlStatus>?, UnsafeMutablePointer<BossFfiError>?) -> Bool

    static func encode(_ packet: BossAppleBmapPacket, runtime: BossRustFfiRuntime) throws -> Data {
        guard let fn = runtime.loadCodecSymbol("boss_packet_encode", as: PacketEncodeFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust packet encoder symbol was unavailable")
        }
        var buffer = BossBuffer(data: nil, len: 0)
        var error = emptyError()
        let ffiPacket = ffiPacket(from: packet, runtime: runtime)
        defer {
            runtime.bossPacketFreeIfAvailable(ffiPacket)
        }
        let success = fn(ffiPacket, &buffer, &error)
        guard success else {
            defer { runtime.bossErrorFree(error) }
            throw map(error: error)
        }
        defer { runtime.bossBufferFree(buffer) }
        return BossRustSessionBridge.readData(buffer)
    }

    static func decode(_ packetData: Data, runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket {
        guard let fn = runtime.loadCodecSymbol("boss_packet_decode", as: PacketDecodeFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust packet decoder symbol was unavailable")
        }
        var ffiPacket = BossFfiBmapPacket()
        var error = emptyError()
        let success = packetData.withUnsafeBytes { bytes in
            fn(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &ffiPacket, &error)
        }
        guard success else {
            defer { runtime.bossErrorFree(error) }
            throw map(error: error)
        }
        defer { runtime.bossPacketFreeIfAvailable(ffiPacket) }
        return swiftPacket(from: ffiPacket)
    }

    static func settingsGetAllStartPacket(runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket {
        try buildPacket("boss_settings_get_all_start_packet", runtime: runtime)
    }

    static func namesSupportedGetPacket(runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket {
        try buildPacket("boss_audio_modes_names_supported_get_packet", runtime: runtime)
    }

    static func modeConfigStartPacket(runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket {
        try buildPacket("boss_audio_modes_mode_config_start_packet", runtime: runtime)
    }

    static func currentModeGetPacket(runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket {
        try buildPacket("boss_audio_modes_current_mode_get_packet", runtime: runtime)
    }

    static func currentModeStartPacket(modeIndex: Int, playVoicePrompt: Bool, runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket {
        guard let fn = runtime.loadCodecSymbol("boss_audio_modes_current_mode_start_packet", as: CurrentModeStartPacketFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust current-mode packet builder symbol was unavailable")
        }
        var packet = BossFfiBmapPacket()
        var error = emptyError()
        let success = fn(Int32(modeIndex), playVoicePrompt, &packet, &error)
        guard success else {
            defer { runtime.bossErrorFree(error) }
            throw map(error: error)
        }
        defer { runtime.bossPacketFreeIfAvailable(packet) }
        return swiftPacket(from: packet)
    }

    static func capabilitiesGetPacket(runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket { try buildPacket("boss_audio_modes_capabilities_get_packet", runtime: runtime) }
    static func favoritesGetPacket(runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket { try buildPacket("boss_audio_modes_favorites_get_packet", runtime: runtime) }
    static func settingsConfigGetPacket(runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket { try buildPacket("boss_audio_modes_settings_config_get_packet", runtime: runtime) }
    static func standbyTimerGetPacket(runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket { try buildPacket("boss_settings_standby_timer_get_packet", runtime: runtime) }
    static func onHeadDetectionGetPacket(runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket { try buildPacket("boss_settings_on_head_detection_get_packet", runtime: runtime) }
    static func equalizerGetPacket(runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket { try buildPacket("boss_settings_equalizer_get_packet", runtime: runtime) }

    static func standbyTimerSetGetPacket(minutes: Int, runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket {
        guard let fn = runtime.loadCodecSymbol("boss_settings_standby_timer_set_get_packet", as: StandbyTimerSetGetPacketFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust standby-timer packet builder symbol was unavailable")
        }
        return try invokePacketBuilder(runtime: runtime) { packet, error in
            fn(Int32(minutes), packet, error)
        }
    }

    static func settingsConfigSetGetPacket(_ config: BossAppleAudioModeSettingsConfig, runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket {
        guard let fn = runtime.loadCodecSymbol("boss_audio_modes_settings_config_set_get_packet", as: SettingsConfigSetGetPacketFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust settings-config packet builder symbol was unavailable")
        }
        return try invokePacketBuilder(runtime: runtime) { packet, error in
            fn(BossRustSessionBridge.ffiConfig(from: config), packet, error)
        }
    }

    static func modeConfigSetGetPacket(modeIndex: Int, prompt: BossAppleAudioModePrompt, name: String, settings: BossAppleAudioModeSettingsConfig, runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket {
        guard let fn = runtime.loadCodecSymbol("boss_audio_modes_mode_config_set_get_packet", as: ModeConfigSetGetPacketFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust mode-config packet builder symbol was unavailable")
        }
        let nameBytes = Array(name.utf8)
        return try nameBytes.withUnsafeBufferPointer { bytes in
            try invokePacketBuilder(runtime: runtime) { packet, error in
                fn(Int32(modeIndex), prompt.byte1, prompt.byte2, bytes.baseAddress, bytes.count, BossRustSessionBridge.ffiConfig(from: settings), packet, error)
            }
        }
    }

    static func favoritesSetGetPacket(numberOfModes: Int, favoriteModeIndices: [Int], runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket {
        guard let fn = runtime.loadCodecSymbol("boss_audio_modes_favorites_set_get_packet", as: FavoritesSetGetPacketFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust favorites packet builder symbol was unavailable")
        }
        let indices = favoriteModeIndices.map(Int32.init)
        return try indices.withUnsafeBufferPointer { values in
            try invokePacketBuilder(runtime: runtime) { packet, error in
                fn(Int32(numberOfModes), values.baseAddress, values.count, packet, error)
            }
        }
    }

    static func onHeadDetectionSetGetPacket(_ value: BossAppleOnHeadDetectionValue, runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket {
        guard let fn = runtime.loadCodecSymbol("boss_settings_on_head_detection_set_get_packet", as: OnHeadDetectionSetGetPacketFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust on-head-detection packet builder symbol was unavailable")
        }
        return try invokePacketBuilder(runtime: runtime) { packet, error in
            fn(BossRustSessionBridge.ffiOnHeadDetection(from: value), packet, error)
        }
    }

    static func enabledSettingGetPacket(functionRaw: UInt8, runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket {
        guard let fn = runtime.loadCodecSymbol("boss_settings_enabled_setting_get_packet", as: EnabledSettingPacketFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust enabled-setting get packet builder symbol was unavailable")
        }
        return try invokePacketBuilder(runtime: runtime) { packet, error in fn(functionRaw, packet, error) }
    }

    static func enabledSettingSetGetPacket(functionRaw: UInt8, enabled: Bool, runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket {
        guard let fn = runtime.loadCodecSymbol("boss_settings_enabled_setting_set_get_packet", as: EnabledSettingSetPacketFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust enabled-setting set packet builder symbol was unavailable")
        }
        return try invokePacketBuilder(runtime: runtime) { packet, error in fn(functionRaw, enabled, packet, error) }
    }

    static func equalizerSetGetPacket(targetLevel: Int, band: BossAppleEqualizerBand, runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket {
        guard let fn = runtime.loadCodecSymbol("boss_settings_equalizer_set_get_packet", as: EqualizerSetGetPacketFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust equalizer packet builder symbol was unavailable")
        }
        return try invokePacketBuilder(runtime: runtime) { packet, error in fn(Int32(targetLevel), band.rawValue, packet, error) }
    }

    static func parseSupportedPrompts(from packet: BossAppleBmapPacket, runtime: BossRustFfiRuntime) throws -> [BossAppleAudioModePrompt] {
        guard let fn = runtime.loadCodecSymbol("boss_audio_modes_parse_supported_prompts", as: ParsePromptsFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust supported-prompts parser symbol was unavailable")
        }
        var ffiPacket = ffiPacket(from: packet, runtime: runtime)
        defer { runtime.bossPacketFreeIfAvailable(ffiPacket) }
        var buffer = BossBuffer(data: nil, len: 0)
        var error = emptyError()
        let success = fn(&ffiPacket, &buffer, &error)
        guard success else {
            defer { runtime.bossErrorFree(error) }
            throw map(error: error)
        }
        defer { runtime.bossBufferFree(buffer) }
        return BossRustSessionBridge.decodeStructBuffer(buffer, as: BossFfiAudioModePrompt.self).map(BossRustSessionBridge.swiftAudioModePrompt)
    }

    static func parseCurrentMode(from packet: BossAppleBmapPacket, runtime: BossRustFfiRuntime) throws -> Int {
        guard let fn = runtime.loadCodecSymbol("boss_audio_modes_parse_current_mode", as: ParseCurrentModeFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust current-mode parser symbol was unavailable")
        }
        var ffiPacket = ffiPacket(from: packet, runtime: runtime)
        defer { runtime.bossPacketFreeIfAvailable(ffiPacket) }
        var value: Int32 = 0
        var error = emptyError()
        let success = fn(&ffiPacket, &value, &error)
        guard success else {
            defer { runtime.bossErrorFree(error) }
            throw map(error: error)
        }
        return Int(value)
    }

    static func parseCapabilities(from packet: BossAppleBmapPacket, runtime: BossRustFfiRuntime) throws -> BossAppleAudioModesCapabilities {
        guard let fn = runtime.loadCodecSymbol("boss_audio_modes_parse_capabilities", as: ParseCapabilitiesFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust capabilities parser symbol was unavailable")
        }
        return try parseValue(packet: packet, runtime: runtime, fn: fn, convert: BossRustSessionBridge.swiftAudioModeCapabilities)
    }

    static func parseFavorites(from packet: BossAppleBmapPacket, runtime: BossRustFfiRuntime) throws -> [Int] {
        guard let fn = runtime.loadCodecSymbol("boss_audio_modes_parse_favorites", as: ParseFavoritesFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust favorites parser symbol was unavailable")
        }
        var ffiPacket = ffiPacket(from: packet, runtime: runtime)
        defer { runtime.bossPacketFreeIfAvailable(ffiPacket) }
        var buffer = BossBuffer(data: nil, len: 0)
        var error = emptyError()
        let success = fn(&ffiPacket, &buffer, &error)
        guard success else {
            defer { runtime.bossErrorFree(error) }
            throw map(error: error)
        }
        defer { runtime.bossBufferFree(buffer) }
        let data = BossRustSessionBridge.readData(buffer)
        return stride(from: 0, to: data.count, by: MemoryLayout<Int32>.size).map {
            Int(Int32(littleEndian: data[$0..<$0 + 4].withUnsafeBytes { $0.load(as: Int32.self) }))
        }
    }

    static func parseSettingsConfig(from packet: BossAppleBmapPacket, runtime: BossRustFfiRuntime) throws -> BossAppleAudioModeSettingsConfig {
        guard let fn = runtime.loadCodecSymbol("boss_audio_modes_parse_settings_config", as: ParseConfigFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust settings-config parser symbol was unavailable")
        }
        return try parseValue(packet: packet, runtime: runtime, fn: fn, convert: BossRustSessionBridge.swiftConfig)
    }

    static func parseModeConfigDetail(from packet: BossAppleBmapPacket, runtime: BossRustFfiRuntime) throws -> BossAppleAudioModeConfig {
        guard let fn = runtime.loadCodecSymbol("boss_audio_modes_parse_mode_config_detail", as: ParseModeConfigFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust mode-config parser symbol was unavailable")
        }
        return try parseValue(packet: packet, runtime: runtime, fn: fn, convert: BossRustSessionBridge.swiftAudioModeConfig)
    }

    static func parseEqualizer(from packet: BossAppleBmapPacket, runtime: BossRustFfiRuntime) throws -> BossAppleEqualizerSettings {
        guard let fn = runtime.loadCodecSymbol("boss_settings_parse_equalizer", as: ParseEqualizerFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust equalizer parser symbol was unavailable")
        }
        return try parseValue(packet: packet, runtime: runtime, fn: fn, convert: BossRustSessionBridge.swiftEqualizerSettings)
    }

    static func parseStandbyTimer(from packet: BossAppleBmapPacket, runtime: BossRustFfiRuntime) throws -> BossAppleStandbyTimerValue {
        guard let fn = runtime.loadCodecSymbol("boss_settings_parse_standby_timer", as: ParseStandbyTimerFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust standby-timer parser symbol was unavailable")
        }
        return try parseValue(packet: packet, runtime: runtime, fn: fn, convert: BossRustSessionBridge.swiftStandbyTimer)
    }

    static func parseEnabledFlag(from packet: BossAppleBmapPacket, runtime: BossRustFfiRuntime) throws -> Bool {
        guard let fn = runtime.loadCodecSymbol("boss_settings_parse_enabled_flag", as: ParseEnabledFlagFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust enabled-flag parser symbol was unavailable")
        }
        return try parseValue(packet: packet, runtime: runtime, fn: fn, convert: { $0 })
    }

    static func parseOnHeadDetection(from packet: BossAppleBmapPacket, runtime: BossRustFfiRuntime) throws -> BossAppleOnHeadDetectionValue {
        guard let fn = runtime.loadCodecSymbol("boss_settings_parse_on_head_detection", as: ParseOnHeadDetectionFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust on-head-detection parser symbol was unavailable")
        }
        return try parseValue(packet: packet, runtime: runtime, fn: fn, convert: BossRustSessionBridge.swiftOnHeadDetection)
    }

    static func parseVolumeControlStatus(from packet: BossAppleBmapPacket, runtime: BossRustFfiRuntime) throws -> BossAppleVolumeControlStatus {
        guard let fn = runtime.loadCodecSymbol("boss_audio_modes_parse_volume_control_status", as: ParseVolumeControlStatusFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust volume-control parser symbol was unavailable")
        }
        return try parseValue(packet: packet, runtime: runtime, fn: fn, convert: BossRustSessionBridge.swiftVolumeControlStatus)
    }

    private static func buildPacket(_ symbol: String, runtime: BossRustFfiRuntime) throws -> BossAppleBmapPacket {
        guard let fn = runtime.loadCodecSymbol(symbol, as: BuildPacketFn.self) else {
            throw BossAppleControlError.unsupportedOperation("Rust packet builder symbol \(symbol) was unavailable")
        }
        return try invokePacketBuilder(runtime: runtime) { packet, error in fn(packet, error) }
    }

    private static func invokePacketBuilder(
        runtime: BossRustFfiRuntime,
        _ call: (UnsafeMutablePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<BossFfiError>?) -> Bool
    ) throws -> BossAppleBmapPacket {
        var packet = BossFfiBmapPacket()
        var error = emptyError()
        let success = call(&packet, &error)
        guard success else {
            defer { runtime.bossErrorFree(error) }
            throw map(error: error)
        }
        defer { runtime.bossPacketFreeIfAvailable(packet) }
        return swiftPacket(from: packet)
    }

    private static func parseValue<Raw, Value>(
        packet: BossAppleBmapPacket,
        runtime: BossRustFfiRuntime,
        fn: @escaping (UnsafePointer<BossFfiBmapPacket>?, UnsafeMutablePointer<Raw>?, UnsafeMutablePointer<BossFfiError>?) -> Bool,
        convert: (Raw) throws -> Value
    ) throws -> Value {
        var ffiPacket = ffiPacket(from: packet, runtime: runtime)
        defer { runtime.bossPacketFreeIfAvailable(ffiPacket) }
        let rawPtr = UnsafeMutablePointer<Raw>.allocate(capacity: 1)
        defer { rawPtr.deallocate() }
        var error = emptyError()
        let success = fn(&ffiPacket, rawPtr, &error)
        guard success else {
            defer { runtime.bossErrorFree(error) }
            throw map(error: error)
        }
        return try convert(rawPtr.move())
    }

    private static func ffiPacket(from packet: BossAppleBmapPacket, runtime: BossRustFfiRuntime) -> BossFfiBmapPacket {
        let payload = packet.payload.withUnsafeBytes { bytes in
            runtime.bossCopyBytes(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
        }
        return BossFfiBmapPacket(
            function_block_raw: packet.functionBlock.rawValue,
            function_raw: packet.function.rawValue,
            device_id: UInt8(packet.deviceID),
            port: UInt8(packet.port),
            operator_raw: packet.operator.rawValue,
            payload: payload
        )
    }

    private static func swiftPacket(from ffi: BossFfiBmapPacket) -> BossAppleBmapPacket {
        let payload = BossRustSessionBridge.readData(ffi.payload)
        let block = BmapFunctionBlock(rawValue: ffi.function_block_raw)
        return BmapPacket(
            functionBlock: block,
            function: BmapFunction(block: block, rawValue: ffi.function_raw),
            deviceID: Int(ffi.device_id),
            port: Int(ffi.port),
            operator: BmapOperator(rawValue: ffi.operator_raw),
            payload: payload
        )
    }

    private static func emptyError() -> BossFfiError {
        BossFfiError(code: BOSS_FFI_ERROR_NONE, message: BossBuffer(data: nil, len: 0), has_bmap_error_code: false, bmap_error_code: 0)
    }

    private static func map(error ffiError: BossFfiError) -> BossAppleControlError {
        let message = ffiError.message.data.map { String(decoding: UnsafeBufferPointer(start: $0, count: ffiError.message.len), as: UTF8.self) } ?? ""
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
        default:
            return .unsupportedOperation(message.isEmpty ? "Rust FFI error code \(ffiError.code)" : message)
        }
    }
}

private extension BossRustFfiRuntime {
    func bossPacketFreeIfAvailable(_ packet: BossFfiBmapPacket) {
        guard let fn = loadCodecSymbol("boss_packet_free", as: BossRustCodecBridge.PacketFreeFn.self) else {
            bossBufferFree(packet.payload)
            return
        }
        fn(packet)
    }
}
