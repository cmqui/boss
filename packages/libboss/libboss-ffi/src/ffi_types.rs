use std::ffi::c_void;

#[repr(C)]
pub struct BossBuffer {
    pub data: *mut u8,
    pub len: usize,
}

#[repr(C)]
pub struct BossBufferList {
    pub data: *mut BossBuffer,
    pub len: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BossFfiLinkStatus {
    Ok = 0,
    TimedOut = 1,
    StreamEnded = 2,
    UnexpectedStreamTermination = 3,
    Other = 4,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BossFfiErrorCode {
    None = 0,
    InvalidArgument = 1,
    ResponseStreamEnded = 2,
    ResponseTimedOut = 3,
    BmapErrorResponse = 4,
    UnexpectedOperator = 5,
    ModeChangeNotObserved = 6,
    EqualizerNotObserved = 7,
    SettingsConfigNotObserved = 8,
    ProductInfo = 9,
    SettingsCodec = 10,
    AudioModesCodec = 11,
    UnsupportedOperation = 12,
    NoFreeCustomAudioModeSlot = 13,
    CustomAudioModeSlotNotEditable = 14,
    CustomAudioModeSlotNotFound = 15,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BossFfiWriteDisposition {
    Unchanged = 0,
    Updated = 1,
    VerificationInconclusive = 2,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BossFfiUpdateStreamKind {
    CurrentAudioMode = 0,
    AudioModeSettings = 1,
    Equalizer = 2,
    DeviceSettings = 3,
    AudioModeCatalog = 4,
    RawPacket = 5,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct BossFfiSessionCallbacks {
    pub context: *mut c_void,
    pub transport_kind: u8,
    pub send_packet_bytes: Option<
        extern "C" fn(
            context: *mut c_void,
            packet_data: *const u8,
            packet_len: usize,
        ) -> BossFfiLinkStatus,
    >,
    pub next_packet_bytes: Option<
        extern "C" fn(
            context: *mut c_void,
            timeout_millis: u64,
            out_packet: *mut BossBuffer,
        ) -> BossFfiLinkStatus,
    >,
    pub release_context: Option<extern "C" fn(context: *mut c_void)>,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiAudioModesCapabilities {
    pub bose_modes: i32,
    pub user_modes: i32,
}

#[repr(C)]
pub struct BossFfiBmapPacket {
    pub function_block_raw: u8,
    pub function_raw: u8,
    pub device_id: u8,
    pub port: u8,
    pub operator_raw: u8,
    pub payload: BossBuffer,
}

impl Default for BossFfiBmapPacket {
    fn default() -> Self {
        Self {
            function_block_raw: 0,
            function_raw: 0,
            device_id: 0,
            port: 0,
            operator_raw: 0,
            payload: BossBuffer {
                data: std::ptr::null_mut(),
                len: 0,
            },
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiAudioModeSettingsConfig {
    pub cnc_level: i32,
    pub auto_cnc_enabled: bool,
    pub spatial_audio_mode: u8,
    pub wind_block_enabled: bool,
    pub anc_toggle_enabled: bool,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiAudioModeSettingsConfigPatch {
    pub has_cnc_level: bool,
    pub cnc_level: i32,
    pub has_auto_cnc_enabled: bool,
    pub auto_cnc_enabled: bool,
    pub has_spatial_audio_mode: bool,
    pub spatial_audio_mode: u8,
    pub has_wind_block_enabled: bool,
    pub wind_block_enabled: bool,
    pub has_anc_toggle_enabled: bool,
    pub anc_toggle_enabled: bool,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiEqualizerPatch {
    pub has_bass: bool,
    pub bass: i32,
    pub has_mid: bool,
    pub mid: i32,
    pub has_treble: bool,
    pub treble: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiEqualizerRange {
    pub available: bool,
    pub current_level: i32,
    pub min_level: i32,
    pub max_level: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiEqualizerSettings {
    pub bass: BossFfiEqualizerRange,
    pub mid: BossFfiEqualizerRange,
    pub treble: BossFfiEqualizerRange,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiCurrentAudioModeWriteResult {
    pub disposition: BossFfiWriteDisposition,
    pub mode_index: i32,
    pub target_index: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiAudioModeSettingsWriteResult {
    pub disposition: BossFfiWriteDisposition,
    pub config: BossFfiAudioModeSettingsConfig,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BossFfiAudioModeConfig {
    pub mode_index: i32,
    pub prompt_byte1: u8,
    pub prompt_byte2: u8,
    pub name_len: usize,
    pub name_bytes: [u8; 32],
    pub favorite: bool,
    pub user_configurable: bool,
    pub user_configured: bool,
    pub settings: BossFfiAudioModeSettingsConfig,
}

impl Default for BossFfiAudioModeConfig {
    fn default() -> Self {
        Self {
            mode_index: 0,
            prompt_byte1: 0,
            prompt_byte2: 0,
            name_len: 0,
            name_bytes: [0; 32],
            favorite: false,
            user_configurable: false,
            user_configured: false,
            settings: BossFfiAudioModeSettingsConfig::default(),
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BossFfiAudioModePrompt {
    pub byte1: u8,
    pub byte2: u8,
    pub name_len: usize,
    pub name_bytes: [u8; 32],
}

impl Default for BossFfiAudioModePrompt {
    fn default() -> Self {
        Self {
            byte1: 0,
            byte2: 0,
            name_len: 0,
            name_bytes: [0; 32],
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiEqualizerWriteResult {
    pub disposition: BossFfiWriteDisposition,
    pub settings: BossFfiEqualizerSettings,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiOnHeadDetectionValue {
    pub is_enabled: bool,
    pub has_auto_play_enabled: bool,
    pub auto_play_enabled: bool,
    pub has_auto_answer_enabled: bool,
    pub auto_answer_enabled: bool,
    pub has_auto_transparency_enabled: bool,
    pub auto_transparency_enabled: bool,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiVolumeControlStatus {
    pub value: u8,
    pub has_supported_values_mask: bool,
    pub supported_values_mask: u8,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiStandbyTimerValue {
    pub minutes: i32,
    pub supports_two_byte_minutes: bool,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiObservedBool {
    pub has_value: bool,
    pub value: bool,
    pub has_source: bool,
    pub source: u8,
    pub has_unavailable_reason: bool,
    pub unavailable_reason: u8,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiObservedOnHeadDetection {
    pub has_value: bool,
    pub value: BossFfiOnHeadDetectionValue,
    pub has_source: bool,
    pub source: u8,
    pub has_unavailable_reason: bool,
    pub unavailable_reason: u8,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiObservedVolumeControlStatus {
    pub has_value: bool,
    pub value: BossFfiVolumeControlStatus,
    pub has_source: bool,
    pub source: u8,
    pub has_unavailable_reason: bool,
    pub unavailable_reason: u8,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiDeviceSettingsReport {
    pub wear_detection: BossFfiObservedOnHeadDetection,
    pub auto_aware_enabled: BossFfiObservedBool,
    pub auto_play_pause_enabled: BossFfiObservedBool,
    pub auto_answer_enabled: BossFfiObservedBool,
    pub volume_control: BossFfiObservedVolumeControlStatus,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BossFfiFirmwareVersionInfo {
    pub port: i32,
    pub version_len: usize,
    pub version_bytes: [u8; 64],
}

impl Default for BossFfiFirmwareVersionInfo {
    fn default() -> Self {
        Self {
            port: 0,
            version_len: 0,
            version_bytes: [0; 64],
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BossFfiBootstrappedDevice {
    pub bmap_version_len: usize,
    pub bmap_version_bytes: [u8; 64],
    pub product_id: u16,
    pub variant: u8,
    pub product_name_len: usize,
    pub product_name_bytes: [u8; 64],
    pub function_blocks_len: usize,
    pub function_blocks_bytes: [u8; 32],
    pub transport_kind: u8,
    pub default_device_id: i32,
    pub default_port: i32,
}

impl Default for BossFfiBootstrappedDevice {
    fn default() -> Self {
        Self {
            bmap_version_len: 0,
            bmap_version_bytes: [0; 64],
            product_id: 0,
            variant: 0,
            product_name_len: 0,
            product_name_bytes: [0; 64],
            function_blocks_len: 0,
            function_blocks_bytes: [0; 32],
            transport_kind: 0,
            default_device_id: 0,
            default_port: 0,
        }
    }
}

#[repr(C)]
pub struct BossFfiError {
    pub code: BossFfiErrorCode,
    pub message: BossBuffer,
    pub has_bmap_error_code: bool,
    pub bmap_error_code: u8,
}
