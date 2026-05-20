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
    typealias BootstrapFn = @convention(c) (
        BossFfiSessionCallbacks,
        UnsafeMutablePointer<BossFfiBootstrappedDevice>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias UpdateStreamCreateFn = @convention(c) (
        BossFfiSessionCallbacks,
        BossFfiUpdateStreamKind,
        UnsafeMutablePointer<BossFfiError>?
    ) -> UnsafeMutableRawPointer?
    typealias UpdateStreamFreeFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias UpdateStreamCurrentAudioModeNextFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt64,
        UnsafeMutablePointer<Int32>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias UpdateStreamAudioModeSettingsNextFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt64,
        UnsafeMutablePointer<BossFfiAudioModeSettingsConfig>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias UpdateStreamEqualizerNextFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt64,
        UnsafeMutablePointer<BossFfiEqualizerSettings>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias UpdateStreamDeviceSettingsNextFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt64,
        UnsafeMutablePointer<BossFfiDeviceSettingsReport>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias UpdateStreamAudioModeCatalogNextFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt64,
        UnsafeMutablePointer<BossBuffer>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
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
    typealias SetEqualizerFn = @convention(c) (
        UnsafeMutableRawPointer?,
        BossFfiEqualizerPatch,
        UnsafeMutablePointer<BossFfiEqualizerWriteResult>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias SetEnabledSettingFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt8,
        Bool,
        UnsafeMutablePointer<Bool>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias EnabledSettingFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt8,
        UnsafeMutablePointer<Bool>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias CurrentAudioModeFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<Int32>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias SupportedAudioModePromptsFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<BossBuffer>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias AudioModeConfigsFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<BossBuffer>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias AudioModeSettingsConfigFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<BossFfiAudioModeSettingsConfig>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias FirmwareVersionFn = @convention(c) (
        UnsafeMutableRawPointer?,
        Int32,
        Int32,
        UnsafeMutablePointer<BossFfiFirmwareVersionInfo>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias StandbyTimerFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<BossFfiStandbyTimerValue>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias SettingsSnapshotFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<BossBuffer>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias EqualizerSettingsFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<BossFfiEqualizerSettings>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias FavoriteAudioModeIndicesFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<BossBuffer>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias OnHeadDetectionFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<BossFfiOnHeadDetectionValue>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias SetOnHeadDetectionFn = @convention(c) (
        UnsafeMutableRawPointer?,
        BossFfiOnHeadDetectionValue,
        UnsafeMutablePointer<BossFfiOnHeadDetectionValue>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias VolumeControlStatusFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<BossFfiVolumeControlStatus>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias SetVolumeControlFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt8,
        UnsafeMutablePointer<BossFfiVolumeControlStatus>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias SetStandbyTimerFn = @convention(c) (
        UnsafeMutableRawPointer?,
        Int32,
        UnsafeMutablePointer<BossFfiStandbyTimerValue>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias SetAudioModeFavoriteFn = @convention(c) (
        UnsafeMutableRawPointer?,
        Int32,
        Bool,
        UnsafeMutablePointer<BossBuffer>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias SaveCustomAudioModeFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<UInt8>?,
        Int,
        BossFfiAudioModeSettingsConfig,
        UInt8,
        UInt8,
        Bool,
        Int32,
        UnsafeMutablePointer<BossFfiAudioModeConfig>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias DeleteCustomAudioModeFn = @convention(c) (
        UnsafeMutableRawPointer?,
        Int32,
        UnsafeMutablePointer<BossFfiAudioModeConfig>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool

    let handle: UnsafeMutableRawPointer?
    let bossBufferFree: BufferFreeFn
    let bossErrorFree: ErrorFreeFn
    let bossCopyBytes: CopyBytesFn
    let bossSessionCreate: SessionCreateFn
    let bossSessionFree: SessionFreeFn
    let bossBootstrapSession: BootstrapFn
    let bossUpdateStreamCreate: UpdateStreamCreateFn
    let bossUpdateStreamFree: UpdateStreamFreeFn
    let bossUpdateStreamNextCurrentAudioMode: UpdateStreamCurrentAudioModeNextFn
    let bossUpdateStreamNextAudioModeSettings: UpdateStreamAudioModeSettingsNextFn
    let bossUpdateStreamNextEqualizer: UpdateStreamEqualizerNextFn
    let bossUpdateStreamNextDeviceSettings: UpdateStreamDeviceSettingsNextFn
    let bossUpdateStreamNextAudioModeCatalog: UpdateStreamAudioModeCatalogNextFn
    let bossSessionSetCurrentAudioMode: SetCurrentAudioModeFn
    let bossSessionSetAudioModeSettings: SetAudioModeSettingsFn
    let bossSessionSetEqualizer: SetEqualizerFn
    let bossSessionSetEnabledSetting: SetEnabledSettingFn
    let bossSessionEnabledSetting: EnabledSettingFn
    let bossSessionCurrentAudioMode: CurrentAudioModeFn
    let bossSessionSupportedAudioModePrompts: SupportedAudioModePromptsFn
    let bossSessionAudioModeConfigs: AudioModeConfigsFn
    let bossSessionAudioModeSettingsConfig: AudioModeSettingsConfigFn
    let bossSessionFirmwareVersion: FirmwareVersionFn
    let bossSessionStandbyTimer: StandbyTimerFn
    let bossSessionSettingsSnapshot: SettingsSnapshotFn
    let bossSessionEqualizerSettings: EqualizerSettingsFn
    let bossSessionFavoriteAudioModeIndices: FavoriteAudioModeIndicesFn
    let bossSessionOnHeadDetection: OnHeadDetectionFn
    let bossSessionSetOnHeadDetection: SetOnHeadDetectionFn
    let bossSessionVolumeControlStatus: VolumeControlStatusFn
    let bossSessionSetVolumeControl: SetVolumeControlFn
    let bossSessionSetStandbyTimer: SetStandbyTimerFn
    let bossSessionSetAudioModeFavorite: SetAudioModeFavoriteFn
    let bossSessionSaveCustomAudioMode: SaveCustomAudioModeFn
    let bossSessionDeleteCustomAudioMode: DeleteCustomAudioModeFn
    private let ownsHandle: Bool

    private init?(_ handle: UnsafeMutableRawPointer, ownsHandle: Bool) {
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
            let bossBootstrapSession = load("boss_bootstrap_session", as: BootstrapFn.self),
            let bossUpdateStreamCreate = load("boss_update_stream_create", as: UpdateStreamCreateFn.self),
            let bossUpdateStreamFree = load("boss_update_stream_free", as: UpdateStreamFreeFn.self),
            let bossUpdateStreamNextCurrentAudioMode = load("boss_update_stream_next_current_audio_mode", as: UpdateStreamCurrentAudioModeNextFn.self),
            let bossUpdateStreamNextAudioModeSettings = load("boss_update_stream_next_audio_mode_settings", as: UpdateStreamAudioModeSettingsNextFn.self),
            let bossUpdateStreamNextEqualizer = load("boss_update_stream_next_equalizer", as: UpdateStreamEqualizerNextFn.self),
            let bossUpdateStreamNextDeviceSettings = load("boss_update_stream_next_device_settings", as: UpdateStreamDeviceSettingsNextFn.self),
            let bossUpdateStreamNextAudioModeCatalog = load("boss_update_stream_next_audio_mode_catalog", as: UpdateStreamAudioModeCatalogNextFn.self),
            let bossSessionSetCurrentAudioMode = load("boss_session_set_current_audio_mode", as: SetCurrentAudioModeFn.self),
            let bossSessionSetAudioModeSettings = load("boss_session_set_audio_mode_settings", as: SetAudioModeSettingsFn.self),
            let bossSessionSetEqualizer = load("boss_session_set_equalizer", as: SetEqualizerFn.self),
            let bossSessionSetEnabledSetting = load("boss_session_set_enabled_setting", as: SetEnabledSettingFn.self),
            let bossSessionEnabledSetting = load("boss_session_enabled_setting", as: EnabledSettingFn.self),
            let bossSessionCurrentAudioMode = load("boss_session_current_audio_mode", as: CurrentAudioModeFn.self),
            let bossSessionSupportedAudioModePrompts = load("boss_session_supported_audio_mode_prompts", as: SupportedAudioModePromptsFn.self),
            let bossSessionAudioModeConfigs = load("boss_session_audio_mode_configs", as: AudioModeConfigsFn.self),
            let bossSessionAudioModeSettingsConfig = load("boss_session_audio_mode_settings_config", as: AudioModeSettingsConfigFn.self),
            let bossSessionFirmwareVersion = load("boss_session_firmware_version", as: FirmwareVersionFn.self),
            let bossSessionStandbyTimer = load("boss_session_standby_timer", as: StandbyTimerFn.self),
            let bossSessionSettingsSnapshot = load("boss_session_settings_snapshot", as: SettingsSnapshotFn.self),
            let bossSessionEqualizerSettings = load("boss_session_equalizer_settings", as: EqualizerSettingsFn.self),
            let bossSessionFavoriteAudioModeIndices = load("boss_session_favorite_audio_mode_indices", as: FavoriteAudioModeIndicesFn.self),
            let bossSessionOnHeadDetection = load("boss_session_on_head_detection", as: OnHeadDetectionFn.self),
            let bossSessionSetOnHeadDetection = load("boss_session_set_on_head_detection", as: SetOnHeadDetectionFn.self),
            let bossSessionVolumeControlStatus = load("boss_session_volume_control_status", as: VolumeControlStatusFn.self),
            let bossSessionSetVolumeControl = load("boss_session_set_volume_control", as: SetVolumeControlFn.self),
            let bossSessionSetStandbyTimer = load("boss_session_set_standby_timer", as: SetStandbyTimerFn.self),
            let bossSessionSetAudioModeFavorite = load("boss_session_set_audio_mode_favorite", as: SetAudioModeFavoriteFn.self),
            let bossSessionSaveCustomAudioMode = load("boss_session_save_custom_audio_mode", as: SaveCustomAudioModeFn.self),
            let bossSessionDeleteCustomAudioMode = load("boss_session_delete_custom_audio_mode", as: DeleteCustomAudioModeFn.self)
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
        self.bossBootstrapSession = bossBootstrapSession
        self.bossUpdateStreamCreate = bossUpdateStreamCreate
        self.bossUpdateStreamFree = bossUpdateStreamFree
        self.bossUpdateStreamNextCurrentAudioMode = bossUpdateStreamNextCurrentAudioMode
        self.bossUpdateStreamNextAudioModeSettings = bossUpdateStreamNextAudioModeSettings
        self.bossUpdateStreamNextEqualizer = bossUpdateStreamNextEqualizer
        self.bossUpdateStreamNextDeviceSettings = bossUpdateStreamNextDeviceSettings
        self.bossUpdateStreamNextAudioModeCatalog = bossUpdateStreamNextAudioModeCatalog
        self.bossSessionSetCurrentAudioMode = bossSessionSetCurrentAudioMode
        self.bossSessionSetAudioModeSettings = bossSessionSetAudioModeSettings
        self.bossSessionSetEqualizer = bossSessionSetEqualizer
        self.bossSessionSetEnabledSetting = bossSessionSetEnabledSetting
        self.bossSessionEnabledSetting = bossSessionEnabledSetting
        self.bossSessionCurrentAudioMode = bossSessionCurrentAudioMode
        self.bossSessionSupportedAudioModePrompts = bossSessionSupportedAudioModePrompts
        self.bossSessionAudioModeConfigs = bossSessionAudioModeConfigs
        self.bossSessionAudioModeSettingsConfig = bossSessionAudioModeSettingsConfig
        self.bossSessionFirmwareVersion = bossSessionFirmwareVersion
        self.bossSessionStandbyTimer = bossSessionStandbyTimer
        self.bossSessionSettingsSnapshot = bossSessionSettingsSnapshot
        self.bossSessionEqualizerSettings = bossSessionEqualizerSettings
        self.bossSessionFavoriteAudioModeIndices = bossSessionFavoriteAudioModeIndices
        self.bossSessionOnHeadDetection = bossSessionOnHeadDetection
        self.bossSessionSetOnHeadDetection = bossSessionSetOnHeadDetection
        self.bossSessionVolumeControlStatus = bossSessionVolumeControlStatus
        self.bossSessionSetVolumeControl = bossSessionSetVolumeControl
        self.bossSessionSetStandbyTimer = bossSessionSetStandbyTimer
        self.bossSessionSetAudioModeFavorite = bossSessionSetAudioModeFavorite
        self.bossSessionSaveCustomAudioMode = bossSessionSaveCustomAudioMode
        self.bossSessionDeleteCustomAudioMode = bossSessionDeleteCustomAudioMode
        self.ownsHandle = ownsHandle
    }

    #if os(macOS) && DEBUG && LIBBOSS_RS_STATIC_LINKED
    private init(linked: Void) {
        self.handle = nil
        self.bossBufferFree = boss_buffer_free
        self.bossErrorFree = boss_error_free
        self.bossCopyBytes = boss_copy_bytes
        self.bossSessionCreate = { callbacks, outError in
            UnsafeMutableRawPointer(boss_session_create(callbacks, outError))
        }
        self.bossSessionFree = { handle in
            boss_session_free(handle.map(OpaquePointer.init))
        }
        self.bossBootstrapSession = { callbacks, outDevice, outError in
            boss_bootstrap_session(callbacks, outDevice, outError)
        }
        self.bossUpdateStreamCreate = { callbacks, kind, outError in
            UnsafeMutableRawPointer(boss_update_stream_create(callbacks, kind, outError))
        }
        self.bossUpdateStreamFree = { handle in
            boss_update_stream_free(handle.map(OpaquePointer.init))
        }
        self.bossUpdateStreamNextCurrentAudioMode = { handle, timeoutMillis, outModeIndex, outError in
            boss_update_stream_next_current_audio_mode(handle.map(OpaquePointer.init), timeoutMillis, outModeIndex, outError)
        }
        self.bossUpdateStreamNextAudioModeSettings = { handle, timeoutMillis, outConfig, outError in
            boss_update_stream_next_audio_mode_settings(handle.map(OpaquePointer.init), timeoutMillis, outConfig, outError)
        }
        self.bossUpdateStreamNextEqualizer = { handle, timeoutMillis, outSettings, outError in
            boss_update_stream_next_equalizer(handle.map(OpaquePointer.init), timeoutMillis, outSettings, outError)
        }
        self.bossUpdateStreamNextDeviceSettings = { handle, timeoutMillis, outReport, outError in
            boss_update_stream_next_device_settings(handle.map(OpaquePointer.init), timeoutMillis, outReport, outError)
        }
        self.bossUpdateStreamNextAudioModeCatalog = { handle, timeoutMillis, outCatalog, outError in
            boss_update_stream_next_audio_mode_catalog(handle.map(OpaquePointer.init), timeoutMillis, outCatalog, outError)
        }
        self.bossSessionSetCurrentAudioMode = { handle, targetIndex, playVoicePrompt, outResult, outError in
            boss_session_set_current_audio_mode(handle.map(OpaquePointer.init), targetIndex, playVoicePrompt, outResult, outError)
        }
        self.bossSessionSetAudioModeSettings = { handle, patch, outResult, outError in
            boss_session_set_audio_mode_settings(handle.map(OpaquePointer.init), patch, outResult, outError)
        }
        self.bossSessionSetEqualizer = { handle, patch, outResult, outError in
            boss_session_set_equalizer(handle.map(OpaquePointer.init), patch, outResult, outError)
        }
        self.bossSessionSetEnabledSetting = { handle, functionRaw, enabled, outEnabled, outError in
            boss_session_set_enabled_setting(handle.map(OpaquePointer.init), functionRaw, enabled, outEnabled, outError)
        }
        self.bossSessionEnabledSetting = { handle, functionRaw, outEnabled, outError in
            boss_session_enabled_setting(handle.map(OpaquePointer.init), functionRaw, outEnabled, outError)
        }
        self.bossSessionCurrentAudioMode = { handle, outModeIndex, outError in
            boss_session_current_audio_mode(handle.map(OpaquePointer.init), outModeIndex, outError)
        }
        self.bossSessionSupportedAudioModePrompts = { handle, outPrompts, outError in
            boss_session_supported_audio_mode_prompts(handle.map(OpaquePointer.init), outPrompts, outError)
        }
        self.bossSessionAudioModeConfigs = { handle, outConfigs, outError in
            boss_session_audio_mode_configs(handle.map(OpaquePointer.init), outConfigs, outError)
        }
        self.bossSessionAudioModeSettingsConfig = { handle, outConfig, outError in
            boss_session_audio_mode_settings_config(handle.map(OpaquePointer.init), outConfig, outError)
        }
        self.bossSessionFirmwareVersion = { handle, port, deviceID, outInfo, outError in
            boss_session_firmware_version(handle.map(OpaquePointer.init), port, deviceID, outInfo, outError)
        }
        self.bossSessionStandbyTimer = { handle, outValue, outError in
            boss_session_standby_timer(handle.map(OpaquePointer.init), outValue, outError)
        }
        self.bossSessionSettingsSnapshot = { handle, outPackets, outError in
            boss_session_settings_snapshot(handle.map(OpaquePointer.init), outPackets, outError)
        }
        self.bossSessionEqualizerSettings = { handle, outSettings, outError in
            boss_session_equalizer_settings(handle.map(OpaquePointer.init), outSettings, outError)
        }
        self.bossSessionFavoriteAudioModeIndices = { handle, outIndices, outError in
            boss_session_favorite_audio_mode_indices(handle.map(OpaquePointer.init), outIndices, outError)
        }
        self.bossSessionOnHeadDetection = { handle, outValue, outError in
            boss_session_on_head_detection(handle.map(OpaquePointer.init), outValue, outError)
        }
        self.bossSessionSetOnHeadDetection = { handle, value, outValue, outError in
            boss_session_set_on_head_detection(handle.map(OpaquePointer.init), value, outValue, outError)
        }
        self.bossSessionVolumeControlStatus = { handle, outStatus, outError in
            boss_session_volume_control_status(handle.map(OpaquePointer.init), outStatus, outError)
        }
        self.bossSessionSetVolumeControl = { handle, value, outStatus, outError in
            boss_session_set_volume_control(handle.map(OpaquePointer.init), value, outStatus, outError)
        }
        self.bossSessionSetStandbyTimer = { handle, minutes, outValue, outError in
            boss_session_set_standby_timer(handle.map(OpaquePointer.init), minutes, outValue, outError)
        }
        self.bossSessionSetAudioModeFavorite = { handle, index, isFavorite, outIndices, outError in
            boss_session_set_audio_mode_favorite(handle.map(OpaquePointer.init), index, isFavorite, outIndices, outError)
        }
        self.bossSessionSaveCustomAudioMode = { handle, nameData, nameLen, settings, promptByte1, promptByte2, hasRequestedSlot, requestedSlot, outConfig, outError in
            boss_session_save_custom_audio_mode(
                handle.map(OpaquePointer.init),
                nameData,
                nameLen,
                settings,
                promptByte1,
                promptByte2,
                hasRequestedSlot,
                requestedSlot,
                outConfig,
                outError
            )
        }
        self.bossSessionDeleteCustomAudioMode = { handle, slot, outConfig, outError in
            boss_session_delete_custom_audio_mode(handle.map(OpaquePointer.init), slot, outConfig, outError)
        }
        self.ownsHandle = false
    }
    #endif

    deinit {
        if ownsHandle, let handle {
            dlclose(handle)
        }
    }

    static let shared: BossRustFfiRuntime? = {
        #if os(macOS) && DEBUG && LIBBOSS_RS_STATIC_LINKED
        BossRustLogger.log("using directly linked libboss-rs ffi symbols")
        return BossRustFfiRuntime(linked: ())
        #else
        if let processHandle = dlopen(nil, RTLD_NOW | RTLD_LOCAL) {
            if let runtime = BossRustFfiRuntime(processHandle, ownsHandle: false) {
                BossRustLogger.log("using linked libboss-rs ffi symbols from current process")
                return runtime
            }
        }

        for candidate in candidateLibraryPaths() {
            guard let loaded = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) else {
                continue
            }
            if let runtime = BossRustFfiRuntime(loaded, ownsHandle: true) {
                BossRustLogger.log("loaded libboss-rs ffi from \(candidate)")
                return runtime
            }
            dlclose(loaded)
        }
        BossRustLogger.log("libboss-rs ffi not loaded; falling back to Swift libboss implementation")
        return nil
        #endif
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

private enum BossRustLogger {
    static var isEnabled: Bool {
        let value = ProcessInfo.processInfo.environment["LIBBOSS_RS_FFI_LOG"]?.lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    static func log(_ message: String) {
        guard isEnabled else {
            return
        }
        fputs("[libboss-rs] \(message)\n", stderr)
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

private protocol BossRustPacketByteBridge: AnyObject, Sendable {
    func send(packetBytes: UnsafePointer<UInt8>?, len: Int) -> BossFfiLinkStatus
    func nextPacket(timeoutMilliseconds: UInt64, outPacket: UnsafeMutablePointer<BossBuffer>?) -> BossFfiLinkStatus
}

private final class BossRustPacketSessionBridge: BossRustPacketByteBridge, @unchecked Sendable {
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
        let resultBox = SendResultBox()
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

private final class BossRustBleTransportBridge: BossRustPacketByteBridge, @unchecked Sendable {
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
        let resultBox = SendResultBox()
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

final class BossRustSessionBridge: @unchecked Sendable {
    fileprivate let runtime: BossRustFfiRuntime

    fileprivate init(runtime: BossRustFfiRuntime) {
        self.runtime = runtime
    }

    static let shared = BossRustFfiRuntime.shared.map(BossRustSessionBridge.init(runtime:))

    private func sessionCallbacks(for packetSession: BossPacketSession) -> BossFfiSessionCallbacks {
        let bridge = BossRustPacketSessionBridge(runtime: runtime, packetSession: packetSession)
        let retained = Unmanaged.passRetained(bridge)
        return BossFfiSessionCallbacks(
            context: retained.toOpaque(),
            transport_kind: packetSession.transportKind == .ble ? 0 : 1,
            send_packet_bytes: bossRustSendPacketBytes,
            next_packet_bytes: bossRustNextPacketBytes,
            release_context: bossRustReleaseContext
        )
    }

    private func sessionCallbacks(for transport: AppleBleBossTransport) -> BossFfiSessionCallbacks {
        let bridge = BossRustBleTransportBridge(runtime: runtime, transport: transport)
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
        on packetSession: BossPacketSession,
        _ operation: (UnsafeMutableRawPointer?) throws -> T
    ) throws -> T {
        var createError = emptyError()
        guard let handle = runtime.bossSessionCreate(sessionCallbacks(for: packetSession), &createError) else {
            defer { runtime.bossErrorFree(createError) }
            throw map(error: createError)
        }
        defer { runtime.bossSessionFree(handle) }
        return try operation(handle)
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

    func bootstrap(on transport: AppleBleBossTransport) async throws -> BootstrappedDevice {
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

    func audioModeSettingsUpdateStream(on transport: AppleBleBossTransport) -> AsyncThrowingStream<BossAudioModeSettingsConfig, Error> {
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

    func equalizerUpdateStream(on transport: AppleBleBossTransport) -> AsyncThrowingStream<BossEqualizerSettings, Error> {
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

    func audioModeCatalogUpdateStream(on transport: AppleBleBossTransport) -> AsyncThrowingStream<[BossAudioModeConfig], Error> {
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

    func standbyTimer(on transport: AppleBleBossTransport) async throws -> BossStandbyTimerValue {
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

    func settingsSnapshot(on transport: AppleBleBossTransport) async throws -> BossSettingsSnapshot {
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

    func supportedAudioModePrompts(on transport: AppleBleBossTransport) async throws -> [BossAudioModePrompt] {
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

    func audioModeConfigs(on transport: AppleBleBossTransport) async throws -> [BossAudioModeConfig] {
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

    func audioModeSettingsConfig(on transport: AppleBleBossTransport) async throws -> BossAudioModeSettingsConfig {
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
    ) async throws -> FirmwareVersionInfo {
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

    func equalizerSettingsIfAvailable(on transport: AppleBleBossTransport) async throws -> BossEqualizerSettings? {
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
        let wearDetection: BossAppleObservedSetting<BossOnHeadDetectionValue> = try directObservedSetting {
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
                BossSettingsCodec.autoAwareFunctionRaw,
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
                BossSettingsCodec.autoPlayPauseFunctionRaw,
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
                    BossSettingsCodec.autoAnswerFunctionRaw,
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

        let volumeControl: BossAppleObservedSetting<BossVolumeControlStatus> = try directObservedSetting {
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
        update: BossAudioModeSettingsConfigPatch
    ) async throws -> BossAppleAudioModeSettingsWriteResult {
        BossRustLogger.log("using Rust bridge for setAudioModeSettings")
        let result = try withSessionHandle(on: transport) { handle in
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
        update: BossEqualizerSettingsPatch
    ) async throws -> BossAppleEqualizerWriteResult {
        BossRustLogger.log("using Rust bridge for setEqualizer")
        let result = try withSessionHandle(on: transport) { handle in
            var result = BossFfiEqualizerWriteResult(
                disposition: BOSS_FFI_WRITE_DISPOSITION_UNCHANGED,
                settings: Self.ffiEqualizerSettings(from: BossEqualizerSettings(ranges: []))
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
    ) async throws -> BossOnHeadDetectionValue {
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
        value: BossOnHeadDetectionValue
    ) async throws -> BossOnHeadDetectionValue {
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
        value: BossVolumeControlValue
    ) async throws -> BossVolumeControlStatus {
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
    ) async throws -> BossStandbyTimerValue {
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
        settings: BossAudioModeSettingsConfig,
        prompt: BossAudioModePrompt,
        requestedSlot: Int?
    ) async throws -> BossAudioModeConfig {
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
    ) async throws -> BossAudioModeConfig {
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

    private static func unavailableReason(for error: BossAppleControlError) -> BossAppleSettingUnavailableReason? {
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

    private static func readData(_ buffer: BossBuffer) -> Data {
        guard let data = buffer.data, buffer.len > 0 else {
            return Data()
        }
        return Data(bytes: data, count: buffer.len)
    }

    private func read(buffer: BossBuffer) -> String {
        guard let data = buffer.data, buffer.len > 0 else {
            return ""
        }
        let bytes = UnsafeBufferPointer(start: data, count: buffer.len)
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func readI32Buffer(_ buffer: BossBuffer) -> [Int] {
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

    private static func decodeStructBuffer<T>(_ buffer: BossBuffer, as _: T.Type) -> [T] {
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

    private func emptyError() -> BossFfiError {
        BossFfiError(
            code: BOSS_FFI_ERROR_NONE,
            message: BossBuffer(data: nil, len: 0),
            has_bmap_error_code: false,
            bmap_error_code: 0
        )
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

    private static func swiftAudioModePrompt(from ffi: BossFfiAudioModePrompt) -> BossAudioModePrompt {
        let name = withUnsafeBytes(of: ffi.name_bytes) { rawBuffer in
            String(decoding: rawBuffer.prefix(ffi.name_len), as: UTF8.self)
        }
        return BossAudioModePrompt(byte1: ffi.byte1, byte2: ffi.byte2, name: name)
    }

    private static func swiftAudioModeConfig(from ffi: BossFfiAudioModeConfig) throws -> BossAudioModeConfig {
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

    private static func swiftFirmwareVersion(from ffi: BossFfiFirmwareVersionInfo) -> FirmwareVersionInfo {
        let version = withUnsafeBytes(of: ffi.version_bytes) { rawBuffer in
            String(decoding: rawBuffer.prefix(ffi.version_len), as: UTF8.self)
        }
        return FirmwareVersionInfo(version: version, port: Int(ffi.port))
    }

    private static func swiftStandbyTimer(from ffi: BossFfiStandbyTimerValue) -> BossStandbyTimerValue {
        BossStandbyTimerValue(
            minutes: Int(ffi.minutes),
            supportsTwoByteMinutes: ffi.supports_two_byte_minutes
        )
    }

    private static func swiftSettingsSnapshot(from buffer: BossBuffer) throws -> BossSettingsSnapshot {
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

    private static func swiftBootstrappedDevice(from ffi: BossFfiBootstrappedDevice) -> BootstrappedDevice {
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

    private static func swiftDeviceSettingsReport(from ffi: BossFfiDeviceSettingsReport) -> BossAppleDeviceSettingsReport {
        BossAppleDeviceSettingsReport(
            wearDetection: swiftObservedOnHeadDetection(from: ffi.wear_detection),
            autoAwareEnabled: swiftObservedBool(from: ffi.auto_aware_enabled),
            autoPlayPauseEnabled: swiftObservedBool(from: ffi.auto_play_pause_enabled),
            autoAnswerEnabled: swiftObservedBool(from: ffi.auto_answer_enabled),
            volumeControl: swiftObservedVolumeControl(from: ffi.volume_control)
        )
    }

    private static func swiftObservedBool(from ffi: BossFfiObservedBool) -> BossAppleObservedSetting<Bool> {
        BossAppleObservedSetting(
            value: ffi.has_value ? ffi.value : nil,
            source: ffi.has_source ? swiftSettingSource(raw: ffi.source) : nil,
            unavailableReason: ffi.has_unavailable_reason ? swiftUnavailableReason(raw: ffi.unavailable_reason) : nil
        )
    }

    private static func swiftObservedOnHeadDetection(from ffi: BossFfiObservedOnHeadDetection) -> BossAppleObservedSetting<BossOnHeadDetectionValue> {
        BossAppleObservedSetting(
            value: ffi.has_value ? swiftOnHeadDetection(from: ffi.value) : nil,
            source: ffi.has_source ? swiftSettingSource(raw: ffi.source) : nil,
            unavailableReason: ffi.has_unavailable_reason ? swiftUnavailableReason(raw: ffi.unavailable_reason) : nil
        )
    }

    private static func swiftObservedVolumeControl(from ffi: BossFfiObservedVolumeControlStatus) -> BossAppleObservedSetting<BossVolumeControlStatus> {
        BossAppleObservedSetting(
            value: ffi.has_value ? (try? swiftVolumeControlStatus(from: ffi.value)) : nil,
            source: ffi.has_source ? swiftSettingSource(raw: ffi.source) : nil,
            unavailableReason: ffi.has_unavailable_reason ? swiftUnavailableReason(raw: ffi.unavailable_reason) : nil
        )
    }

    private static func swiftSettingSource(raw: UInt8) -> BossAppleSettingSource? {
        switch raw {
        case 0: return .snapshot
        case 1: return .compositeSnapshot
        case 2: return .directGet
        default: return nil
        }
    }

    private static func swiftUnavailableReason(raw: UInt8) -> BossAppleSettingUnavailableReason? {
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

    private static func ffiEqualizerPatch(from patch: BossEqualizerSettingsPatch) -> BossFfiEqualizerPatch {
        BossFfiEqualizerPatch(
            has_bass: patch.bass != nil,
            bass: Int32(patch.bass ?? 0),
            has_mid: patch.mid != nil,
            mid: Int32(patch.mid ?? 0),
            has_treble: patch.treble != nil,
            treble: Int32(patch.treble ?? 0)
        )
    }

    private static func ffiEqualizerRange(from range: BossEqualizerRangeLevel?) -> BossFfiEqualizerRange {
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

    private static func ffiEqualizerSettings(from settings: BossEqualizerSettings) -> BossFfiEqualizerSettings {
        BossFfiEqualizerSettings(
            bass: ffiEqualizerRange(from: settings.range(for: .bass)),
            mid: ffiEqualizerRange(from: settings.range(for: .mid)),
            treble: ffiEqualizerRange(from: settings.range(for: .treble))
        )
    }

    private static func ffiOnHeadDetection(from value: BossOnHeadDetectionValue) -> BossFfiOnHeadDetectionValue {
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

    private static func swiftEqualizerSettings(from ffi: BossFfiEqualizerSettings) -> BossEqualizerSettings {
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

    private static func swiftOnHeadDetection(from ffi: BossFfiOnHeadDetectionValue) -> BossOnHeadDetectionValue {
        BossOnHeadDetectionValue(
            isEnabled: ffi.is_enabled,
            isAutoPlayEnabled: ffi.has_auto_play_enabled ? ffi.auto_play_enabled : nil,
            isAutoAnswerEnabled: ffi.has_auto_answer_enabled ? ffi.auto_answer_enabled : nil,
            isAutoTransparencyEnabled: ffi.has_auto_transparency_enabled ? ffi.auto_transparency_enabled : nil
        )
    }

    private static func swiftVolumeControlStatus(from ffi: BossFfiVolumeControlStatus) throws -> BossVolumeControlStatus {
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
    let bridge = Unmanaged<AnyObject>.fromOpaque(context).takeUnretainedValue() as? BossRustPacketByteBridge
    guard let bridge else {
        return BOSS_FFI_LINK_STATUS_OTHER
    }
    return bridge.send(packetBytes: packetData, len: packetLen)
}

private let bossRustNextPacketBytes: @convention(c) (UnsafeMutableRawPointer?, UInt64, UnsafeMutablePointer<BossBuffer>?) -> BossFfiLinkStatus = {
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

private let bossRustReleaseContext: @convention(c) (UnsafeMutableRawPointer?) -> Void = { context in
    guard let context else {
        return
    }
    Unmanaged<AnyObject>.fromOpaque(context).release()
}
