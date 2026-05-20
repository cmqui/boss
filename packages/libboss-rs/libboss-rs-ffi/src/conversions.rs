use libboss_rs_core::{
    BossAudioModeConfig, BossAudioModePrompt, BossAudioModeSettingsConfig,
    BossAudioModeSettingsConfigPatch, BossEqualizerBand, BossEqualizerSettings,
    BossEqualizerSettingsPatch, BossOnHeadDetectionValue, BossStandbyTimerValue, BossTransportKind,
    BossVolumeControlStatus, BossVolumeControlValue, FirmwareVersionInfo,
};
use libboss_rs_session::{
    BootstrapSessionError, BootstrappedDevice, BossDeviceSettingsReport, BossLinkError,
    BossObservedSetting, BossSessionError, BossSettingSource, BossSettingUnavailableReason,
};

use crate::{
    buffer_from_string, BossFfiAudioModeConfig, BossFfiAudioModePrompt,
    BossFfiAudioModeSettingsConfig, BossFfiAudioModeSettingsConfigPatch, BossFfiBootstrappedDevice,
    BossFfiDeviceSettingsReport, BossFfiEqualizerPatch, BossFfiEqualizerRange,
    BossFfiEqualizerSettings, BossFfiError, BossFfiErrorCode, BossFfiFirmwareVersionInfo,
    BossFfiObservedBool, BossFfiObservedOnHeadDetection, BossFfiObservedVolumeControlStatus,
    BossFfiOnHeadDetectionValue, BossFfiStandbyTimerValue, BossFfiVolumeControlStatus,
};

pub(crate) fn session_error_to_ffi(error: BossSessionError) -> BossFfiError {
    let code = match error {
        BossSessionError::ResponseStreamEnded => BossFfiErrorCode::ResponseStreamEnded,
        BossSessionError::ResponseTimedOut { .. } => BossFfiErrorCode::ResponseTimedOut,
        BossSessionError::BmapErrorResponse(_) => BossFfiErrorCode::BmapErrorResponse,
        BossSessionError::UnexpectedOperator(_) => BossFfiErrorCode::UnexpectedOperator,
        BossSessionError::ModeChangeNotObserved { .. } => BossFfiErrorCode::ModeChangeNotObserved,
        BossSessionError::EqualizerNotObserved { .. } => BossFfiErrorCode::EqualizerNotObserved,
        BossSessionError::SettingsConfigNotObserved { .. } => {
            BossFfiErrorCode::SettingsConfigNotObserved
        }
        BossSessionError::NoFreeCustomAudioModeSlot => BossFfiErrorCode::NoFreeCustomAudioModeSlot,
        BossSessionError::CustomAudioModeSlotNotEditable(_) => {
            BossFfiErrorCode::CustomAudioModeSlotNotEditable
        }
        BossSessionError::CustomAudioModeSlotNotFound(_) => {
            BossFfiErrorCode::CustomAudioModeSlotNotFound
        }
        BossSessionError::ProductInfo(_) => BossFfiErrorCode::ProductInfo,
        BossSessionError::SettingsCodec(_) => BossFfiErrorCode::SettingsCodec,
        BossSessionError::AudioModesCodec(_) => BossFfiErrorCode::AudioModesCodec,
        BossSessionError::UnsupportedOperation(_) => BossFfiErrorCode::UnsupportedOperation,
    };
    let bmap_error_code = error.bmap_error_code().map(|code| code as u8);
    BossFfiError {
        code,
        message: buffer_from_string(format!("{error:?}")),
        has_bmap_error_code: bmap_error_code.is_some(),
        bmap_error_code: bmap_error_code.unwrap_or(0),
    }
}

pub(crate) fn bootstrap_error_to_ffi(error: BootstrapSessionError) -> BossFfiError {
    match error {
        BootstrapSessionError::Timeout(timeout) => BossFfiError {
            code: BossFfiErrorCode::ResponseTimedOut,
            message: buffer_from_string(format!("{timeout:?}")),
            has_bmap_error_code: false,
            bmap_error_code: 0,
        },
        BootstrapSessionError::Session(error) => session_error_to_ffi(error),
        BootstrapSessionError::ProductInfo(error) => BossFfiError {
            code: BossFfiErrorCode::ProductInfo,
            message: buffer_from_string(format!("{error:?}")),
            has_bmap_error_code: false,
            bmap_error_code: 0,
        },
    }
}

pub(crate) fn ffi_link_error_to_session_error(error: BossLinkError) -> BossSessionError {
    match error {
        BossLinkError::TimedOut => BossSessionError::ResponseTimedOut { seconds: 0 },
        BossLinkError::UnexpectedStreamTermination => BossSessionError::ResponseStreamEnded,
        BossLinkError::Other(message) => BossSessionError::UnsupportedOperation(message),
    }
}

pub(crate) fn ffi_config_from_core(
    config: BossAudioModeSettingsConfig,
) -> BossFfiAudioModeSettingsConfig {
    BossFfiAudioModeSettingsConfig {
        cnc_level: config.cnc_level,
        auto_cnc_enabled: config.auto_cnc_enabled,
        spatial_audio_mode: config.spatial_audio_mode.raw_value(),
        wind_block_enabled: config.wind_block_enabled,
        anc_toggle_enabled: config.anc_toggle_enabled,
    }
}

pub(crate) fn ffi_audio_mode_config_from_core(
    config: BossAudioModeConfig,
) -> BossFfiAudioModeConfig {
    let (name_len, name_bytes) = fixed_bytes::<32>(&config.name);
    BossFfiAudioModeConfig {
        mode_index: config.mode_index,
        prompt_byte1: config.prompt.byte1,
        prompt_byte2: config.prompt.byte2,
        name_len,
        name_bytes,
        favorite: config.favorite,
        user_configurable: config.user_configurable,
        user_configured: config.user_configured,
        settings: ffi_config_from_core(config.settings),
    }
}

pub(crate) fn ffi_audio_mode_prompt_from_core(
    prompt: BossAudioModePrompt,
) -> BossFfiAudioModePrompt {
    let (name_len, name_bytes) = fixed_bytes::<32>(&prompt.name);
    BossFfiAudioModePrompt {
        byte1: prompt.byte1,
        byte2: prompt.byte2,
        name_len,
        name_bytes,
    }
}

pub(crate) fn ffi_firmware_version_from_core(
    info: FirmwareVersionInfo,
) -> BossFfiFirmwareVersionInfo {
    let (version_len, version_bytes) = fixed_bytes::<64>(&info.version);
    BossFfiFirmwareVersionInfo {
        port: info.port,
        version_len,
        version_bytes,
    }
}

pub(crate) fn core_patch_from_ffi(
    patch: BossFfiAudioModeSettingsConfigPatch,
) -> BossAudioModeSettingsConfigPatch {
    BossAudioModeSettingsConfigPatch {
        cnc_level: patch.has_cnc_level.then_some(patch.cnc_level),
        auto_cnc_enabled: patch.has_auto_cnc_enabled.then_some(patch.auto_cnc_enabled),
        spatial_audio_mode: patch
            .has_spatial_audio_mode
            .then(|| libboss_rs_core::BossSpatialAudioMode::from_raw(patch.spatial_audio_mode))
            .flatten(),
        wind_block_enabled: patch
            .has_wind_block_enabled
            .then_some(patch.wind_block_enabled),
        anc_toggle_enabled: patch
            .has_anc_toggle_enabled
            .then_some(patch.anc_toggle_enabled),
    }
}

pub(crate) fn core_equalizer_patch_from_ffi(
    patch: BossFfiEqualizerPatch,
) -> BossEqualizerSettingsPatch {
    BossEqualizerSettingsPatch {
        bass: patch.has_bass.then_some(patch.bass),
        mid: patch.has_mid.then_some(patch.mid),
        treble: patch.has_treble.then_some(patch.treble),
    }
}

fn ffi_range(settings: &BossEqualizerSettings, band: BossEqualizerBand) -> BossFfiEqualizerRange {
    if let Some(range) = settings.range(&band) {
        BossFfiEqualizerRange {
            available: true,
            current_level: range.current_level,
            min_level: range.min_level,
            max_level: range.max_level,
        }
    } else {
        BossFfiEqualizerRange::default()
    }
}

pub(crate) fn ffi_equalizer_from_core(settings: BossEqualizerSettings) -> BossFfiEqualizerSettings {
    BossFfiEqualizerSettings {
        bass: ffi_range(&settings, BossEqualizerBand::Bass),
        mid: ffi_range(&settings, BossEqualizerBand::Mid),
        treble: ffi_range(&settings, BossEqualizerBand::Treble),
    }
}

pub(crate) fn ffi_on_head_detection_from_core(
    value: BossOnHeadDetectionValue,
) -> BossFfiOnHeadDetectionValue {
    BossFfiOnHeadDetectionValue {
        is_enabled: value.is_enabled,
        has_auto_play_enabled: value.is_auto_play_enabled.is_some(),
        auto_play_enabled: value.is_auto_play_enabled.unwrap_or(false),
        has_auto_answer_enabled: value.is_auto_answer_enabled.is_some(),
        auto_answer_enabled: value.is_auto_answer_enabled.unwrap_or(false),
        has_auto_transparency_enabled: value.is_auto_transparency_enabled.is_some(),
        auto_transparency_enabled: value.is_auto_transparency_enabled.unwrap_or(false),
    }
}

pub(crate) fn core_on_head_detection_from_ffi(
    value: BossFfiOnHeadDetectionValue,
) -> BossOnHeadDetectionValue {
    BossOnHeadDetectionValue {
        is_enabled: value.is_enabled,
        is_auto_play_enabled: value
            .has_auto_play_enabled
            .then_some(value.auto_play_enabled),
        is_auto_answer_enabled: value
            .has_auto_answer_enabled
            .then_some(value.auto_answer_enabled),
        is_auto_transparency_enabled: value
            .has_auto_transparency_enabled
            .then_some(value.auto_transparency_enabled),
    }
}

pub(crate) fn ffi_volume_control_status_from_core(
    status: BossVolumeControlStatus,
) -> BossFfiVolumeControlStatus {
    let supported_values_mask = status.supported_values.as_ref().map(|values| {
        values.iter().fold(0u8, |mask, value| {
            mask | match value {
                BossVolumeControlValue::Disabled => 0x08,
                BossVolumeControlValue::Button => 0x01,
                BossVolumeControlValue::CapTouch => 0x02,
                BossVolumeControlValue::Imu => 0x04,
            }
        })
    });
    BossFfiVolumeControlStatus {
        value: status.value.raw_value(),
        has_supported_values_mask: supported_values_mask.is_some(),
        supported_values_mask: supported_values_mask.unwrap_or(0),
    }
}

pub(crate) fn ffi_standby_timer_from_core(
    value: BossStandbyTimerValue,
) -> BossFfiStandbyTimerValue {
    BossFfiStandbyTimerValue {
        minutes: value.minutes,
        supports_two_byte_minutes: value.supports_two_byte_minutes,
    }
}

fn ffi_setting_source(source: &BossSettingSource) -> u8 {
    match source {
        BossSettingSource::Snapshot => 0,
        BossSettingSource::CompositeSnapshot => 1,
        BossSettingSource::DirectGet => 2,
    }
}

fn ffi_setting_unavailable_reason(reason: &BossSettingUnavailableReason) -> u8 {
    match reason {
        BossSettingUnavailableReason::MissingFromSnapshot => 0,
        BossSettingUnavailableReason::TimedOut => 1,
        BossSettingUnavailableReason::ResponseStreamEnded => 2,
        BossSettingUnavailableReason::FunctionUnsupported => 3,
        BossSettingUnavailableReason::OperatorUnsupported => 4,
        BossSettingUnavailableReason::DataUnavailable => 5,
        BossSettingUnavailableReason::InsecureTransport => 6,
        BossSettingUnavailableReason::UnexpectedStreamTermination => 7,
        BossSettingUnavailableReason::BmapError(_) => 8,
    }
}

fn ffi_observed_bool(value: &BossObservedSetting<bool>) -> BossFfiObservedBool {
    BossFfiObservedBool {
        has_value: value.value.is_some(),
        value: value.value.unwrap_or(false),
        has_source: value.source.is_some(),
        source: value.source.as_ref().map(ffi_setting_source).unwrap_or(0),
        has_unavailable_reason: value.unavailable_reason.is_some(),
        unavailable_reason: value
            .unavailable_reason
            .as_ref()
            .map(ffi_setting_unavailable_reason)
            .unwrap_or(0),
    }
}

fn ffi_observed_on_head_detection(
    value: &BossObservedSetting<BossOnHeadDetectionValue>,
) -> BossFfiObservedOnHeadDetection {
    BossFfiObservedOnHeadDetection {
        has_value: value.value.is_some(),
        value: value
            .value
            .clone()
            .map(ffi_on_head_detection_from_core)
            .unwrap_or_default(),
        has_source: value.source.is_some(),
        source: value.source.as_ref().map(ffi_setting_source).unwrap_or(0),
        has_unavailable_reason: value.unavailable_reason.is_some(),
        unavailable_reason: value
            .unavailable_reason
            .as_ref()
            .map(ffi_setting_unavailable_reason)
            .unwrap_or(0),
    }
}

fn ffi_observed_volume_control_status(
    value: &BossObservedSetting<BossVolumeControlStatus>,
) -> BossFfiObservedVolumeControlStatus {
    BossFfiObservedVolumeControlStatus {
        has_value: value.value.is_some(),
        value: value
            .value
            .clone()
            .map(ffi_volume_control_status_from_core)
            .unwrap_or_default(),
        has_source: value.source.is_some(),
        source: value.source.as_ref().map(ffi_setting_source).unwrap_or(0),
        has_unavailable_reason: value.unavailable_reason.is_some(),
        unavailable_reason: value
            .unavailable_reason
            .as_ref()
            .map(ffi_setting_unavailable_reason)
            .unwrap_or(0),
    }
}

pub(crate) fn ffi_device_settings_report_from_core(
    report: &BossDeviceSettingsReport,
) -> BossFfiDeviceSettingsReport {
    BossFfiDeviceSettingsReport {
        wear_detection: ffi_observed_on_head_detection(&report.wear_detection),
        auto_aware_enabled: ffi_observed_bool(&report.auto_aware_enabled),
        auto_play_pause_enabled: ffi_observed_bool(&report.auto_play_pause_enabled),
        auto_answer_enabled: ffi_observed_bool(&report.auto_answer_enabled),
        volume_control: ffi_observed_volume_control_status(&report.volume_control),
    }
}

pub(crate) fn fixed_bytes<const N: usize>(value: &str) -> (usize, [u8; N]) {
    let bytes = value.as_bytes();
    let clipped_len = bytes.len().min(N);
    let mut fixed = [0u8; N];
    fixed[..clipped_len].copy_from_slice(&bytes[..clipped_len]);
    (clipped_len, fixed)
}

pub(crate) fn ffi_bootstrapped_device_from_core(
    device: BootstrappedDevice,
) -> BossFfiBootstrappedDevice {
    let (bmap_version_len, bmap_version_bytes) = fixed_bytes::<64>(&device.bmap_version.version);
    let (product_name_len, product_name_bytes) = fixed_bytes::<64>(&device.product_name);
    let function_blocks = device.supported_function_blocks.encoded();
    let function_blocks_len = function_blocks.len().min(32);
    let mut function_blocks_bytes = [0u8; 32];
    function_blocks_bytes[..function_blocks_len]
        .copy_from_slice(&function_blocks[..function_blocks_len]);
    BossFfiBootstrappedDevice {
        bmap_version_len,
        bmap_version_bytes,
        product_id: device.product_id,
        variant: device.product_variant.variant,
        product_name_len,
        product_name_bytes,
        function_blocks_len,
        function_blocks_bytes,
        transport_kind: match device.transport_kind {
            BossTransportKind::Ble => 0,
            BossTransportKind::Stream => 1,
        },
        default_device_id: device.default_device_id,
        default_port: device.default_port,
    }
}
