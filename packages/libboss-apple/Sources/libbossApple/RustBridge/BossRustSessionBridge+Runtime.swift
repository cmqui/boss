import CBossRustFFI
import Darwin
import Foundation

final class BossRustFfiRuntime: @unchecked Sendable {
    typealias BufferFreeFn = @convention(c) (BossBuffer) -> Void
    typealias BufferListFreeFn = @convention(c) (BossBufferList) -> Void
    typealias ErrorFreeFn = @convention(c) (BossFfiError) -> Void
    typealias CopyBytesFn = @convention(c) (UnsafePointer<UInt8>?, Int) -> BossBuffer
    typealias BleReassemblerCreateFn = @convention(c) () -> UnsafeMutableRawPointer?
    typealias BleReassemblerFreeFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias BleSegmentPacketFn = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        Int,
        UnsafeMutablePointer<BossBufferList>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
    typealias BleReassemblerPushFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<BossBuffer>?,
        UnsafeMutablePointer<Bool>?,
        UnsafeMutablePointer<BossFfiError>?
    ) -> Bool
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
    typealias AudioModeCapabilitiesFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<BossFfiAudioModesCapabilities>?,
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
    typealias SetFavoriteAudioModeIndicesFn = @convention(c) (
        UnsafeMutableRawPointer?,
        Int32,
        UnsafePointer<Int32>?,
        Int,
        UnsafeMutablePointer<BossBuffer>?,
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
    let bossBufferListFree: BufferListFreeFn
    let bossErrorFree: ErrorFreeFn
    let bossCopyBytes: CopyBytesFn
    let bossBleReassemblerCreate: BleReassemblerCreateFn
    let bossBleReassemblerFree: BleReassemblerFreeFn
    let bossBleSegmentPacket: BleSegmentPacketFn
    let bossBleReassemblerPush: BleReassemblerPushFn
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
    let bossSessionAudioModeCapabilities: AudioModeCapabilitiesFn
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
    let bossSessionSetFavoriteAudioModeIndices: SetFavoriteAudioModeIndicesFn
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
            let bossBufferListFree = load("boss_buffer_list_free", as: BufferListFreeFn.self),
            let bossErrorFree = load("boss_error_free", as: ErrorFreeFn.self),
            let bossCopyBytes = load("boss_copy_bytes", as: CopyBytesFn.self),
            let bossBleReassemblerCreate = load("boss_ble_reassembler_create", as: BleReassemblerCreateFn.self),
            let bossBleReassemblerFree = load("boss_ble_reassembler_free", as: BleReassemblerFreeFn.self),
            let bossBleSegmentPacket = load("boss_ble_segment_packet", as: BleSegmentPacketFn.self),
            let bossBleReassemblerPush = load("boss_ble_reassembler_push", as: BleReassemblerPushFn.self),
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
            let bossSessionAudioModeCapabilities = load("boss_session_audio_mode_capabilities", as: AudioModeCapabilitiesFn.self),
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
            let bossSessionSetFavoriteAudioModeIndices = load("boss_session_set_favorite_audio_mode_indices", as: SetFavoriteAudioModeIndicesFn.self),
            let bossSessionSetAudioModeFavorite = load("boss_session_set_audio_mode_favorite", as: SetAudioModeFavoriteFn.self),
            let bossSessionSaveCustomAudioMode = load("boss_session_save_custom_audio_mode", as: SaveCustomAudioModeFn.self),
            let bossSessionDeleteCustomAudioMode = load("boss_session_delete_custom_audio_mode", as: DeleteCustomAudioModeFn.self)
        else {
            dlclose(handle)
            return nil
        }

        self.handle = handle
        self.bossBufferFree = bossBufferFree
        self.bossBufferListFree = bossBufferListFree
        self.bossErrorFree = bossErrorFree
        self.bossCopyBytes = bossCopyBytes
        self.bossBleReassemblerCreate = bossBleReassemblerCreate
        self.bossBleReassemblerFree = bossBleReassemblerFree
        self.bossBleSegmentPacket = bossBleSegmentPacket
        self.bossBleReassemblerPush = bossBleReassemblerPush
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
        self.bossSessionAudioModeCapabilities = bossSessionAudioModeCapabilities
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
        self.bossSessionSetFavoriteAudioModeIndices = bossSessionSetFavoriteAudioModeIndices
        self.bossSessionSetAudioModeFavorite = bossSessionSetAudioModeFavorite
        self.bossSessionSaveCustomAudioMode = bossSessionSaveCustomAudioMode
        self.bossSessionDeleteCustomAudioMode = bossSessionDeleteCustomAudioMode
        self.ownsHandle = ownsHandle
    }

    #if LIBBOSS_STATIC_LINKED
    private init(linked: Void) {
        self.handle = nil
        self.bossBufferFree = boss_buffer_free
        self.bossBufferListFree = boss_buffer_list_free
        self.bossErrorFree = boss_error_free
        self.bossCopyBytes = boss_copy_bytes
        self.bossBleReassemblerCreate = {
            UnsafeMutableRawPointer(boss_ble_reassembler_create())
        }
        self.bossBleReassemblerFree = { handle in
            boss_ble_reassembler_free(handle.map(OpaquePointer.init))
        }
        self.bossBleSegmentPacket = { packetData, packetLen, mtu, outFrames, outError in
            boss_ble_segment_packet(packetData, packetLen, mtu, outFrames, outError)
        }
        self.bossBleReassemblerPush = { handle, segmentData, segmentLen, outPacket, outHasPacket, outError in
            boss_ble_reassembler_push(handle.map(OpaquePointer.init), segmentData, segmentLen, outPacket, outHasPacket, outError)
        }
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
        self.bossSessionAudioModeCapabilities = { handle, outCapabilities, outError in
            boss_session_audio_mode_capabilities(handle.map(OpaquePointer.init), outCapabilities, outError)
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
        self.bossSessionSetFavoriteAudioModeIndices = { handle, numberOfModes, favoriteIndicesData, favoriteIndicesLen, outIndices, outError in
            boss_session_set_favorite_audio_mode_indices(
                handle.map(OpaquePointer.init),
                numberOfModes,
                favoriteIndicesData,
                favoriteIndicesLen,
                outIndices,
                outError
            )
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
        #if LIBBOSS_STATIC_LINKED
        BossRustLogger.log("using directly linked libboss ffi symbols")
        return BossRustFfiRuntime(linked: ())
        #else
        if let processHandle = dlopen(nil, RTLD_NOW | RTLD_LOCAL) {
            if let runtime = BossRustFfiRuntime(processHandle, ownsHandle: false) {
                BossRustLogger.log("using linked libboss ffi symbols from current process")
                return runtime
            }
        }

        for candidate in candidateLibraryPaths() {
            guard let loaded = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) else {
                continue
            }
            if let runtime = BossRustFfiRuntime(loaded, ownsHandle: true) {
                BossRustLogger.log("loaded libboss ffi from \(candidate)")
                return runtime
            }
            dlclose(loaded)
        }
        BossRustLogger.log("libboss ffi not loaded; no supported runtime is available")
        return nil
        #endif
    }()

    private static func candidateLibraryPaths() -> [String] {
        var paths: [String] = []
        if let explicit = ProcessInfo.processInfo.environment["LIBBOSS_FFI_DYLIB"], !explicit.isEmpty {
            paths.append(explicit)
        } else if let legacyExplicit = ProcessInfo.processInfo.environment["LIBBOSS_RS_FFI_DYLIB"], !legacyExplicit.isEmpty {
            paths.append(legacyExplicit)
        }

        let dylibName = "liblibboss_ffi.dylib"
        let profiles = ffiBuildProfiles()

        if let embedded = Bundle.main.path(forResource: "liblibboss_ffi", ofType: "dylib", inDirectory: "Frameworks") {
            paths.append(embedded)
        }
        if let frameworksURL = Bundle.main.privateFrameworksURL {
            paths.append(frameworksURL.appendingPathComponent(dylibName).path)
        }
        if let executableURL = Bundle.main.executableURL {
            let frameworksURL = executableURL
                .deletingLastPathComponent()
                .appendingPathComponent("../Frameworks/\(dylibName)")
            paths.append(frameworksURL.standardizedFileURL.path)
        }

        for profile in profiles {
            for base in repositorySearchRoots() {
                paths.append(base.appendingPathComponent("libboss/target/\(profile)/\(dylibName)").path)
                paths.append(base.appendingPathComponent("packages/libboss/target/\(profile)/\(dylibName)").path)
            }
        }

        let cwd = FileManager.default.currentDirectoryPath
        for profile in profiles {
            paths.append("\(cwd)/../libboss/target/\(profile)/\(dylibName)")
            paths.append("\(cwd)/packages/libboss/target/\(profile)/\(dylibName)")
            paths.append("\(cwd)/target/\(profile)/\(dylibName)")
        }

        var deduped: [String] = []
        var seen = Set<String>()
        for path in paths where seen.insert(path).inserted {
            deduped.append(path)
        }
        return deduped
    }

    private static func ffiBuildProfiles() -> [String] {
        #if DEBUG
        return ["debug", "release"]
        #else
        return ["release", "debug"]
        #endif
    }

    private static func repositorySearchRoots() -> [URL] {
        var roots: [URL] = []
        var seen = Set<String>()

        func appendAncestors(of url: URL?) {
            guard var directory = url?.standardizedFileURL else { return }
            for _ in 0..<12 {
                let path = directory.path
                guard seen.insert(path).inserted else { break }
                roots.append(directory)
                let parent = directory.deletingLastPathComponent()
                if parent.path == directory.path {
                    break
                }
                directory = parent
            }
        }

        appendAncestors(of: Bundle.main.bundleURL)
        appendAncestors(of: Bundle.main.executableURL?.deletingLastPathComponent())
        appendAncestors(of: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))

        return roots
    }
}

extension BossRustFfiRuntime {
    func loadCodecSymbol<T>(_ symbol: String, as _: T.Type) -> T? {
        #if LIBBOSS_STATIC_LINKED
        if let symbol = Self.directlyLinkedCodecSymbol(symbol, as: T.self) {
            return symbol
        }
        #endif
        guard let handle else {
            return nil
        }
        guard let pointer = dlsym(handle, symbol) else {
            return nil
        }
        return unsafeBitCast(pointer, to: T.self)
    }

    #if LIBBOSS_STATIC_LINKED
    private static func directlyLinkedCodecSymbol<T>(_ symbol: String, as _: T.Type) -> T? {
        switch symbol {
        case "boss_packet_free":
            return unsafeBitCast(
                boss_packet_free as BossRustCodecBridge.PacketFreeFn,
                to: T.self
            )
        case "boss_packet_encode":
            return unsafeBitCast(
                boss_packet_encode as BossRustCodecBridge.PacketEncodeFn,
                to: T.self
            )
        case "boss_packet_decode":
            return unsafeBitCast(
                boss_packet_decode as BossRustCodecBridge.PacketDecodeFn,
                to: T.self
            )
        case "boss_audio_modes_names_supported_get_packet":
            return unsafeBitCast(
                boss_audio_modes_names_supported_get_packet as BossRustCodecBridge.BuildPacketFn,
                to: T.self
            )
        case "boss_audio_modes_current_mode_get_packet":
            return unsafeBitCast(
                boss_audio_modes_current_mode_get_packet as BossRustCodecBridge.BuildPacketFn,
                to: T.self
            )
        case "boss_audio_modes_current_mode_start_packet":
            return unsafeBitCast(
                boss_audio_modes_current_mode_start_packet as BossRustCodecBridge.CurrentModeStartPacketFn,
                to: T.self
            )
        case "boss_audio_modes_capabilities_get_packet":
            return unsafeBitCast(
                boss_audio_modes_capabilities_get_packet as BossRustCodecBridge.BuildPacketFn,
                to: T.self
            )
        case "boss_audio_modes_favorites_get_packet":
            return unsafeBitCast(
                boss_audio_modes_favorites_get_packet as BossRustCodecBridge.BuildPacketFn,
                to: T.self
            )
        case "boss_audio_modes_settings_config_get_packet":
            return unsafeBitCast(
                boss_audio_modes_settings_config_get_packet as BossRustCodecBridge.BuildPacketFn,
                to: T.self
            )
        case "boss_audio_modes_mode_config_start_packet":
            return unsafeBitCast(
                boss_audio_modes_mode_config_start_packet as BossRustCodecBridge.BuildPacketFn,
                to: T.self
            )
        case "boss_audio_modes_settings_config_set_get_packet":
            return unsafeBitCast(
                boss_audio_modes_settings_config_set_get_packet as BossRustCodecBridge.SettingsConfigSetGetPacketFn,
                to: T.self
            )
        case "boss_audio_modes_mode_config_set_get_packet":
            return unsafeBitCast(
                boss_audio_modes_mode_config_set_get_packet as BossRustCodecBridge.ModeConfigSetGetPacketFn,
                to: T.self
            )
        case "boss_audio_modes_favorites_set_get_packet":
            return unsafeBitCast(
                boss_audio_modes_favorites_set_get_packet as BossRustCodecBridge.FavoritesSetGetPacketFn,
                to: T.self
            )
        case "boss_settings_get_all_start_packet":
            return unsafeBitCast(
                boss_settings_get_all_start_packet as BossRustCodecBridge.BuildPacketFn,
                to: T.self
            )
        case "boss_settings_standby_timer_get_packet":
            return unsafeBitCast(
                boss_settings_standby_timer_get_packet as BossRustCodecBridge.BuildPacketFn,
                to: T.self
            )
        case "boss_settings_standby_timer_set_get_packet":
            return unsafeBitCast(
                boss_settings_standby_timer_set_get_packet as BossRustCodecBridge.StandbyTimerSetGetPacketFn,
                to: T.self
            )
        case "boss_settings_on_head_detection_get_packet":
            return unsafeBitCast(
                boss_settings_on_head_detection_get_packet as BossRustCodecBridge.BuildPacketFn,
                to: T.self
            )
        case "boss_settings_on_head_detection_set_get_packet":
            return unsafeBitCast(
                boss_settings_on_head_detection_set_get_packet as BossRustCodecBridge.OnHeadDetectionSetGetPacketFn,
                to: T.self
            )
        case "boss_settings_enabled_setting_get_packet":
            return unsafeBitCast(
                boss_settings_enabled_setting_get_packet as BossRustCodecBridge.EnabledSettingPacketFn,
                to: T.self
            )
        case "boss_settings_enabled_setting_set_get_packet":
            return unsafeBitCast(
                boss_settings_enabled_setting_set_get_packet as BossRustCodecBridge.EnabledSettingSetPacketFn,
                to: T.self
            )
        case "boss_settings_equalizer_get_packet":
            return unsafeBitCast(
                boss_settings_equalizer_get_packet as BossRustCodecBridge.BuildPacketFn,
                to: T.self
            )
        case "boss_settings_equalizer_set_get_packet":
            return unsafeBitCast(
                boss_settings_equalizer_set_get_packet as BossRustCodecBridge.EqualizerSetGetPacketFn,
                to: T.self
            )
        case "boss_audio_modes_parse_supported_prompts":
            return unsafeBitCast(
                boss_audio_modes_parse_supported_prompts as BossRustCodecBridge.ParsePromptsFn,
                to: T.self
            )
        case "boss_audio_modes_parse_current_mode":
            return unsafeBitCast(
                boss_audio_modes_parse_current_mode as BossRustCodecBridge.ParseCurrentModeFn,
                to: T.self
            )
        case "boss_audio_modes_parse_capabilities":
            return unsafeBitCast(
                boss_audio_modes_parse_capabilities as BossRustCodecBridge.ParseCapabilitiesFn,
                to: T.self
            )
        case "boss_audio_modes_parse_favorites":
            return unsafeBitCast(
                boss_audio_modes_parse_favorites as BossRustCodecBridge.ParseFavoritesFn,
                to: T.self
            )
        case "boss_audio_modes_parse_settings_config":
            return unsafeBitCast(
                boss_audio_modes_parse_settings_config as BossRustCodecBridge.ParseConfigFn,
                to: T.self
            )
        case "boss_audio_modes_parse_mode_config_detail":
            return unsafeBitCast(
                boss_audio_modes_parse_mode_config_detail as BossRustCodecBridge.ParseModeConfigFn,
                to: T.self
            )
        case "boss_audio_modes_parse_volume_control_status":
            return unsafeBitCast(
                boss_audio_modes_parse_volume_control_status as BossRustCodecBridge.ParseVolumeControlStatusFn,
                to: T.self
            )
        case "boss_settings_parse_equalizer":
            return unsafeBitCast(
                boss_settings_parse_equalizer as BossRustCodecBridge.ParseEqualizerFn,
                to: T.self
            )
        case "boss_settings_parse_standby_timer":
            return unsafeBitCast(
                boss_settings_parse_standby_timer as BossRustCodecBridge.ParseStandbyTimerFn,
                to: T.self
            )
        case "boss_settings_parse_enabled_flag":
            return unsafeBitCast(
                boss_settings_parse_enabled_flag as BossRustCodecBridge.ParseEnabledFlagFn,
                to: T.self
            )
        case "boss_settings_parse_on_head_detection":
            return unsafeBitCast(
                boss_settings_parse_on_head_detection as BossRustCodecBridge.ParseOnHeadDetectionFn,
                to: T.self
            )
        default:
            return nil
        }
    }
    #endif
}

enum BossRustLogger {
    static var isEnabled: Bool {
        let value = ProcessInfo.processInfo.environment["LIBBOSS_FFI_LOG"]?.lowercased()
            ?? ProcessInfo.processInfo.environment["LIBBOSS_RS_FFI_LOG"]?.lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    static func log(_ message: String) {
        guard isEnabled else {
            return
        }
        fputs("[libboss] \(message)\n", stderr)
    }
}
