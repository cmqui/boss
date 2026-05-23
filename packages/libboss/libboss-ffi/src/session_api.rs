use futures::executor::block_on;
use libboss_core::{BmapCodec, BossAudioModeSettingsConfig, BossVolumeControlValue};
use libboss_session::{
    BootstrapSession, BossAudioModeSettingsWriteResult, BossCurrentAudioModeWriteResult,
    BossEqualizerWriteResult, BossSession, PacketSession, SessionConfiguration,
};

use crate::conversions::*;
use crate::host_link::{
    ffi_link_from_callbacks, with_session, BossFfiSessionHandle,
};
use crate::{
    buffer_from_i32_slice, buffer_from_struct_slice, buffer_from_vec, invalid_argument_error,
    write_error, BossBuffer, BossFfiAudioModeConfig, BossFfiAudioModeSettingsConfig,
    BossFfiAudioModeSettingsWriteResult, BossFfiAudioModesCapabilities,
    BossFfiBootstrappedDevice, BossFfiCurrentAudioModeWriteResult, BossFfiEqualizerSettings,
    BossFfiEqualizerWriteResult, BossFfiError, BossFfiFirmwareVersionInfo,
    BossFfiOnHeadDetectionValue, BossFfiSessionCallbacks, BossFfiStandbyTimerValue,
    BossFfiVolumeControlStatus, BossFfiWriteDisposition,
};

#[no_mangle]
pub extern "C" fn boss_session_create(
    callbacks: BossFfiSessionCallbacks,
    out_error: *mut BossFfiError,
) -> *mut BossFfiSessionHandle {
    let Some(link) = ffi_link_from_callbacks(callbacks, out_error) else {
        return std::ptr::null_mut();
    };
    let handle = BossFfiSessionHandle {
        session: BossSession::new(PacketSession::new(link)),
    };
    Box::into_raw(Box::new(handle))
}

#[no_mangle]
pub extern "C" fn boss_bootstrap_session(
    callbacks: BossFfiSessionCallbacks,
    out_device: *mut BossFfiBootstrappedDevice,
    out_error: *mut BossFfiError,
) -> bool {
    if out_device.is_null() {
        write_error(out_error, invalid_argument_error("out_device was null"));
        return false;
    }
    let Some(link) = ffi_link_from_callbacks(callbacks, out_error) else {
        return false;
    };
    match block_on(BootstrapSession::new(link, SessionConfiguration::default()).bootstrap()) {
        Ok(device) => {
            unsafe {
                *out_device = ffi_bootstrapped_device_from_core(device);
            }
            true
        }
        Err(error) => {
            write_error(out_error, bootstrap_error_to_ffi(error));
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn boss_session_free(handle: *mut BossFfiSessionHandle) {
    if handle.is_null() {
        return;
    }
    unsafe {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub extern "C" fn boss_session_set_current_audio_mode(
    handle: *mut BossFfiSessionHandle,
    target_index: i32,
    play_voice_prompt: bool,
    out_result: *mut BossFfiCurrentAudioModeWriteResult,
    out_error: *mut BossFfiError,
) -> bool {
    if out_result.is_null() {
        write_error(out_error, invalid_argument_error("out_result was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(
            handle
                .session
                .set_current_audio_mode(target_index, play_voice_prompt),
        )
    }) else {
        return false;
    };

    let ffi_result = match result {
        BossCurrentAudioModeWriteResult::Unchanged(mode_index) => {
            BossFfiCurrentAudioModeWriteResult {
                disposition: BossFfiWriteDisposition::Unchanged,
                mode_index,
                target_index: mode_index,
            }
        }
        BossCurrentAudioModeWriteResult::Updated(mode_index) => {
            BossFfiCurrentAudioModeWriteResult {
                disposition: BossFfiWriteDisposition::Updated,
                mode_index,
                target_index: mode_index,
            }
        }
        BossCurrentAudioModeWriteResult::VerificationInconclusive { target_index } => {
            BossFfiCurrentAudioModeWriteResult {
                disposition: BossFfiWriteDisposition::VerificationInconclusive,
                mode_index: target_index,
                target_index,
            }
        }
    };
    unsafe {
        *out_result = ffi_result;
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_set_audio_mode_settings(
    handle: *mut BossFfiSessionHandle,
    patch: crate::BossFfiAudioModeSettingsConfigPatch,
    out_result: *mut BossFfiAudioModeSettingsWriteResult,
    out_error: *mut BossFfiError,
) -> bool {
    if out_result.is_null() {
        write_error(out_error, invalid_argument_error("out_result was null"));
        return false;
    }
    if patch.has_spatial_audio_mode
        && libboss_core::BossSpatialAudioMode::from_raw(patch.spatial_audio_mode).is_none()
    {
        write_error(
            out_error,
            invalid_argument_error("spatial_audio_mode was not recognized"),
        );
        return false;
    }

    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(
            handle
                .session
                .set_audio_mode_settings(core_patch_from_ffi(patch)),
        )
    }) else {
        return false;
    };

    let ffi_result = match result {
        BossAudioModeSettingsWriteResult::Unchanged(config) => {
            BossFfiAudioModeSettingsWriteResult {
                disposition: BossFfiWriteDisposition::Unchanged,
                config: ffi_config_from_core(config),
            }
        }
        BossAudioModeSettingsWriteResult::Updated(config) => BossFfiAudioModeSettingsWriteResult {
            disposition: BossFfiWriteDisposition::Updated,
            config: ffi_config_from_core(config),
        },
        BossAudioModeSettingsWriteResult::VerificationInconclusive(config) => {
            BossFfiAudioModeSettingsWriteResult {
                disposition: BossFfiWriteDisposition::VerificationInconclusive,
                config: ffi_config_from_core(config),
            }
        }
    };
    unsafe {
        *out_result = ffi_result;
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_set_equalizer(
    handle: *mut BossFfiSessionHandle,
    patch: crate::BossFfiEqualizerPatch,
    out_result: *mut BossFfiEqualizerWriteResult,
    out_error: *mut BossFfiError,
) -> bool {
    if out_result.is_null() {
        write_error(out_error, invalid_argument_error("out_result was null"));
        return false;
    }

    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(
            handle
                .session
                .set_equalizer_verified(core_equalizer_patch_from_ffi(patch)),
        )
    }) else {
        return false;
    };

    let ffi_result = match result {
        BossEqualizerWriteResult::Unchanged(settings) => BossFfiEqualizerWriteResult {
            disposition: BossFfiWriteDisposition::Unchanged,
            settings: ffi_equalizer_from_core(settings),
        },
        BossEqualizerWriteResult::Updated(settings) => BossFfiEqualizerWriteResult {
            disposition: BossFfiWriteDisposition::Updated,
            settings: ffi_equalizer_from_core(settings),
        },
        BossEqualizerWriteResult::VerificationInconclusive(settings) => {
            BossFfiEqualizerWriteResult {
                disposition: BossFfiWriteDisposition::VerificationInconclusive,
                settings: ffi_equalizer_from_core(settings),
            }
        }
    };
    unsafe {
        *out_result = ffi_result;
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_set_enabled_setting(
    handle: *mut BossFfiSessionHandle,
    function_raw: u8,
    enabled: bool,
    out_enabled: *mut bool,
    out_error: *mut BossFfiError,
) -> bool {
    if out_enabled.is_null() {
        write_error(out_error, invalid_argument_error("out_enabled was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(
            handle
                .session
                .set_enabled_setting(function_raw, enabled, 5_000),
        )
    }) else {
        return false;
    };
    unsafe {
        *out_enabled = result;
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_enabled_setting(
    handle: *mut BossFfiSessionHandle,
    function_raw: u8,
    out_enabled: *mut bool,
    out_error: *mut BossFfiError,
) -> bool {
    if out_enabled.is_null() {
        write_error(out_error, invalid_argument_error("out_enabled was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.enabled_setting(function_raw, 5_000))
    }) else {
        return false;
    };
    unsafe {
        *out_enabled = result;
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_current_audio_mode(
    handle: *mut BossFfiSessionHandle,
    out_mode_index: *mut i32,
    out_error: *mut BossFfiError,
) -> bool {
    if out_mode_index.is_null() {
        write_error(out_error, invalid_argument_error("out_mode_index was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.current_audio_mode(5_000))
    }) else {
        return false;
    };
    unsafe {
        *out_mode_index = result;
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_standby_timer(
    handle: *mut BossFfiSessionHandle,
    out_value: *mut BossFfiStandbyTimerValue,
    out_error: *mut BossFfiError,
) -> bool {
    if out_value.is_null() {
        write_error(out_error, invalid_argument_error("out_value was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.standby_timer(5_000))
    }) else {
        return false;
    };
    unsafe {
        *out_value = ffi_standby_timer_from_core(result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_settings_snapshot(
    handle: *mut BossFfiSessionHandle,
    out_packets: *mut BossBuffer,
    out_error: *mut BossFfiError,
) -> bool {
    if out_packets.is_null() {
        write_error(out_error, invalid_argument_error("out_packets was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.settings_snapshot(5_000))
    }) else {
        return false;
    };
    let mut bytes = Vec::new();
    for packet in [
        result.packet(libboss_core::BossSettingsCodec::STANDBY_TIMER_FUNCTION_RAW),
        result.packet(libboss_core::BossSettingsCodec::AUTO_AWARE_FUNCTION_RAW),
        result.packet(libboss_core::BossSettingsCodec::ON_HEAD_DETECTION_FUNCTION_RAW),
        result.packet(libboss_core::BossSettingsCodec::AUTO_PLAY_PAUSE_FUNCTION_RAW),
        result.packet(libboss_core::BossSettingsCodec::AUTO_ANSWER_FUNCTION_RAW),
        result.packet(libboss_core::BossSettingsCodec::VOLUME_CONTROL_FUNCTION_RAW),
        result.packet(libboss_core::BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW),
    ]
    .into_iter()
    .flatten()
    {
        let encoded = match BmapCodec::encode(packet) {
            Ok(encoded) => encoded,
            Err(error) => {
                write_error(
                    out_error,
                    invalid_argument_error(format!(
                        "failed to encode settings snapshot packet: {error:?}"
                    )),
                );
                return false;
            }
        };
        let len = encoded.len() as u32;
        bytes.extend_from_slice(&len.to_le_bytes());
        bytes.extend_from_slice(&encoded);
    }
    unsafe {
        *out_packets = buffer_from_vec(bytes);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_supported_audio_mode_prompts(
    handle: *mut BossFfiSessionHandle,
    out_prompts: *mut BossBuffer,
    out_error: *mut BossFfiError,
) -> bool {
    if out_prompts.is_null() {
        write_error(out_error, invalid_argument_error("out_prompts was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.supported_audio_mode_prompts(5_000))
    }) else {
        return false;
    };
    let prompts: Vec<crate::BossFfiAudioModePrompt> = result
        .into_iter()
        .map(ffi_audio_mode_prompt_from_core)
        .collect();
    unsafe {
        *out_prompts = buffer_from_struct_slice(&prompts);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_audio_mode_configs(
    handle: *mut BossFfiSessionHandle,
    out_configs: *mut BossBuffer,
    out_error: *mut BossFfiError,
) -> bool {
    if out_configs.is_null() {
        write_error(out_error, invalid_argument_error("out_configs was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.audio_mode_configs(30_000))
    }) else {
        return false;
    };
    let configs: Vec<BossFfiAudioModeConfig> = result
        .into_iter()
        .map(ffi_audio_mode_config_from_core)
        .collect();
    unsafe {
        *out_configs = buffer_from_struct_slice(&configs);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_audio_mode_capabilities(
    handle: *mut BossFfiSessionHandle,
    out_capabilities: *mut BossFfiAudioModesCapabilities,
    out_error: *mut BossFfiError,
) -> bool {
    if out_capabilities.is_null() {
        write_error(
            out_error,
            invalid_argument_error("out_capabilities was null"),
        );
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.audio_mode_capabilities(5_000))
    }) else {
        return false;
    };
    unsafe {
        *out_capabilities = ffi_audio_modes_capabilities_from_core(result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_audio_mode_settings_config(
    handle: *mut BossFfiSessionHandle,
    out_config: *mut BossFfiAudioModeSettingsConfig,
    out_error: *mut BossFfiError,
) -> bool {
    if out_config.is_null() {
        write_error(out_error, invalid_argument_error("out_config was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.audio_mode_settings_config(5_000))
    }) else {
        return false;
    };
    unsafe {
        *out_config = ffi_config_from_core(result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_firmware_version(
    handle: *mut BossFfiSessionHandle,
    port: i32,
    device_id: i32,
    out_info: *mut BossFfiFirmwareVersionInfo,
    out_error: *mut BossFfiError,
) -> bool {
    if out_info.is_null() {
        write_error(out_error, invalid_argument_error("out_info was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.firmware_version(port, device_id, 5_000))
    }) else {
        return false;
    };
    unsafe {
        *out_info = ffi_firmware_version_from_core(result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_equalizer_settings(
    handle: *mut BossFfiSessionHandle,
    out_settings: *mut BossFfiEqualizerSettings,
    out_error: *mut BossFfiError,
) -> bool {
    if out_settings.is_null() {
        write_error(out_error, invalid_argument_error("out_settings was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.equalizer_settings(5_000))
    }) else {
        return false;
    };
    unsafe {
        *out_settings = ffi_equalizer_from_core(result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_favorite_audio_mode_indices(
    handle: *mut BossFfiSessionHandle,
    out_indices: *mut BossBuffer,
    out_error: *mut BossFfiError,
) -> bool {
    if out_indices.is_null() {
        write_error(out_error, invalid_argument_error("out_indices was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.favorite_audio_mode_indices(5_000))
    }) else {
        return false;
    };
    unsafe {
        *out_indices = buffer_from_i32_slice(&result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_on_head_detection(
    handle: *mut BossFfiSessionHandle,
    out_value: *mut BossFfiOnHeadDetectionValue,
    out_error: *mut BossFfiError,
) -> bool {
    if out_value.is_null() {
        write_error(out_error, invalid_argument_error("out_value was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.on_head_detection(5_000))
    }) else {
        return false;
    };
    unsafe {
        *out_value = ffi_on_head_detection_from_core(result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_set_on_head_detection(
    handle: *mut BossFfiSessionHandle,
    value: BossFfiOnHeadDetectionValue,
    out_value: *mut BossFfiOnHeadDetectionValue,
    out_error: *mut BossFfiError,
) -> bool {
    if out_value.is_null() {
        write_error(out_error, invalid_argument_error("out_value was null"));
        return false;
    }
    let core_value = core_on_head_detection_from_ffi(value);
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.set_on_head_detection(&core_value, 5_000))
    }) else {
        return false;
    };
    unsafe {
        *out_value = ffi_on_head_detection_from_core(result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_volume_control_status(
    handle: *mut BossFfiSessionHandle,
    out_status: *mut BossFfiVolumeControlStatus,
    out_error: *mut BossFfiError,
) -> bool {
    if out_status.is_null() {
        write_error(out_error, invalid_argument_error("out_status was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.volume_control_status(5_000))
    }) else {
        return false;
    };
    unsafe {
        *out_status = ffi_volume_control_status_from_core(result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_set_volume_control(
    handle: *mut BossFfiSessionHandle,
    value: u8,
    out_status: *mut BossFfiVolumeControlStatus,
    out_error: *mut BossFfiError,
) -> bool {
    if out_status.is_null() {
        write_error(out_error, invalid_argument_error("out_status was null"));
        return false;
    }
    let Some(value) = BossVolumeControlValue::from_raw(value) else {
        write_error(
            out_error,
            invalid_argument_error("volume control value was not recognized"),
        );
        return false;
    };
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.set_volume_control(value, 5_000))
    }) else {
        return false;
    };
    unsafe {
        *out_status = ffi_volume_control_status_from_core(result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_set_standby_timer(
    handle: *mut BossFfiSessionHandle,
    minutes: i32,
    out_value: *mut BossFfiStandbyTimerValue,
    out_error: *mut BossFfiError,
) -> bool {
    if out_value.is_null() {
        write_error(out_error, invalid_argument_error("out_value was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.set_standby_timer(minutes, 5_000))
    }) else {
        return false;
    };
    unsafe {
        *out_value = ffi_standby_timer_from_core(result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_set_favorite_audio_mode_indices(
    handle: *mut BossFfiSessionHandle,
    number_of_modes: i32,
    favorite_indices_data: *const i32,
    favorite_indices_len: usize,
    out_indices: *mut BossBuffer,
    out_error: *mut BossFfiError,
) -> bool {
    if out_indices.is_null() {
        write_error(out_error, invalid_argument_error("out_indices was null"));
        return false;
    }
    let favorite_indices = if favorite_indices_data.is_null() || favorite_indices_len == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(favorite_indices_data, favorite_indices_len) }
    };
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.set_favorite_audio_mode_indices(
            number_of_modes,
            favorite_indices,
            5_000,
        ))
    }) else {
        return false;
    };
    unsafe {
        *out_indices = buffer_from_i32_slice(&result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_set_audio_mode_favorite(
    handle: *mut BossFfiSessionHandle,
    index: i32,
    is_favorite: bool,
    out_indices: *mut BossBuffer,
    out_error: *mut BossFfiError,
) -> bool {
    if out_indices.is_null() {
        write_error(out_error, invalid_argument_error("out_indices was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(
            handle
                .session
                .set_audio_mode_favorite(index, is_favorite, 5_000),
        )
    }) else {
        return false;
    };
    unsafe {
        *out_indices = buffer_from_i32_slice(&result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_save_custom_audio_mode(
    handle: *mut BossFfiSessionHandle,
    name_data: *const u8,
    name_len: usize,
    settings: BossFfiAudioModeSettingsConfig,
    prompt_byte1: u8,
    prompt_byte2: u8,
    has_requested_slot: bool,
    requested_slot: i32,
    out_config: *mut BossFfiAudioModeConfig,
    out_error: *mut BossFfiError,
) -> bool {
    if out_config.is_null() {
        write_error(out_error, invalid_argument_error("out_config was null"));
        return false;
    }
    let name = if name_data.is_null() || name_len == 0 {
        ""
    } else {
        let bytes = unsafe { std::slice::from_raw_parts(name_data, name_len) };
        match std::str::from_utf8(bytes) {
            Ok(value) => value,
            Err(_) => {
                write_error(
                    out_error,
                    invalid_argument_error("name was not valid UTF-8"),
                );
                return false;
            }
        }
    };
    let Some(spatial_audio_mode) =
        libboss_core::BossSpatialAudioMode::from_raw(settings.spatial_audio_mode)
    else {
        write_error(
            out_error,
            invalid_argument_error("spatial_audio_mode was not recognized"),
        );
        return false;
    };
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.save_custom_audio_mode(
            name,
            &BossAudioModeSettingsConfig {
                cnc_level: settings.cnc_level,
                auto_cnc_enabled: settings.auto_cnc_enabled,
                spatial_audio_mode,
                wind_block_enabled: settings.wind_block_enabled,
                anc_toggle_enabled: settings.anc_toggle_enabled,
            },
            libboss_core::BossAudioModePrompt::known(prompt_byte1, prompt_byte2),
            has_requested_slot.then_some(requested_slot),
            5_000,
        ))
    }) else {
        return false;
    };
    unsafe {
        *out_config = ffi_audio_mode_config_from_core(result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_session_delete_custom_audio_mode(
    handle: *mut BossFfiSessionHandle,
    slot: i32,
    out_config: *mut BossFfiAudioModeConfig,
    out_error: *mut BossFfiError,
) -> bool {
    if out_config.is_null() {
        write_error(out_error, invalid_argument_error("out_config was null"));
        return false;
    }
    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.delete_custom_audio_mode(slot, 5_000))
    }) else {
        return false;
    };
    unsafe {
        *out_config = ffi_audio_mode_config_from_core(result);
    }
    true
}
