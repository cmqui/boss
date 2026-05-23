use futures::executor::block_on;
use libboss_core::{BmapFunctionBlock, BmapPacket, BossAudioModesCodec, BossSettingsCodec};
use libboss_session::{BossLink, BossSession, BossSessionError, PacketSession};

use crate::conversions::*;
use crate::host_link::{
    with_update_stream, with_update_stream_mut, BossFfiUpdateStreamHandle, FfiLink,
};
use crate::{
    buffer_from_struct_slice, invalid_argument_error, write_error, BossBuffer,
    BossFfiAudioModeConfig, BossFfiAudioModeSettingsConfig, BossFfiDeviceSettingsReport,
    BossFfiEqualizerSettings, BossFfiError, BossFfiUpdateStreamKind,
};

async fn next_stream_packet(
    handle: &BossFfiUpdateStreamHandle,
    timeout_millis: u64,
) -> Result<BmapPacket, BossSessionError> {
    loop {
        let Some(packet) = handle
            .link
            .next_packet(timeout_millis)
            .await
            .map_err(ffi_link_error_to_session_error)?
        else {
            return Err(BossSessionError::ResponseStreamEnded);
        };
        let matches = match handle.kind {
            BossFfiUpdateStreamKind::CurrentAudioMode => {
                packet.function_block == BmapFunctionBlock::AudioModes
                    && packet.function.raw_value() == BossAudioModesCodec::CURRENT_MODE_FUNCTION_RAW
                    && packet.operator == libboss_core::BmapOperator::Status
            }
            BossFfiUpdateStreamKind::AudioModeSettings => {
                packet.function_block == BmapFunctionBlock::AudioModes
                    && packet.function.raw_value()
                        == BossAudioModesCodec::SETTINGS_CONFIG_FUNCTION_RAW
                    && packet.operator == libboss_core::BmapOperator::Status
            }
            BossFfiUpdateStreamKind::Equalizer => {
                packet.function_block == BmapFunctionBlock::Settings
                    && packet.function.raw_value() == BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW
                    && packet.operator == libboss_core::BmapOperator::Status
            }
            BossFfiUpdateStreamKind::DeviceSettings => {
                packet.function_block == BmapFunctionBlock::Settings
                    && packet.operator == libboss_core::BmapOperator::Status
            }
            BossFfiUpdateStreamKind::AudioModeCatalog => {
                packet.function_block == BmapFunctionBlock::AudioModes
                    && packet.operator == libboss_core::BmapOperator::Status
            }
        };
        if matches {
            return Ok(packet);
        }
    }
}

#[no_mangle]
pub extern "C" fn boss_update_stream_create(
    callbacks: crate::BossFfiSessionCallbacks,
    kind: BossFfiUpdateStreamKind,
    out_error: *mut BossFfiError,
) -> *mut BossFfiUpdateStreamHandle {
    let Some(link) = crate::host_link::ffi_link_from_callbacks(callbacks, out_error) else {
        return std::ptr::null_mut();
    };
    Box::into_raw(Box::new(BossFfiUpdateStreamHandle {
        link,
        kind,
        device_settings_report: None,
        audio_mode_catalog: None,
    }))
}

#[no_mangle]
pub extern "C" fn boss_update_stream_free(handle: *mut BossFfiUpdateStreamHandle) {
    if handle.is_null() {
        return;
    }
    unsafe {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub extern "C" fn boss_update_stream_next_current_audio_mode(
    handle: *mut BossFfiUpdateStreamHandle,
    timeout_millis: u64,
    out_mode_index: *mut i32,
    out_error: *mut BossFfiError,
) -> bool {
    if out_mode_index.is_null() {
        write_error(out_error, invalid_argument_error("out_mode_index was null"));
        return false;
    }
    let Some(result) = with_update_stream(handle, out_error, |handle| {
        if handle.kind != BossFfiUpdateStreamKind::CurrentAudioMode {
            return Err(BossSessionError::UnsupportedOperation(
                "update stream kind did not match current audio mode".into(),
            ));
        }
        block_on(async {
            let packet = next_stream_packet(handle, timeout_millis).await?;
            BossAudioModesCodec::parse_current_mode(&packet).map_err(Into::into)
        })
    }) else {
        return false;
    };
    unsafe {
        *out_mode_index = result;
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_update_stream_next_audio_mode_settings(
    handle: *mut BossFfiUpdateStreamHandle,
    timeout_millis: u64,
    out_config: *mut BossFfiAudioModeSettingsConfig,
    out_error: *mut BossFfiError,
) -> bool {
    if out_config.is_null() {
        write_error(out_error, invalid_argument_error("out_config was null"));
        return false;
    }
    let Some(result) = with_update_stream(handle, out_error, |handle| {
        if handle.kind != BossFfiUpdateStreamKind::AudioModeSettings {
            return Err(BossSessionError::UnsupportedOperation(
                "update stream kind did not match audio mode settings".into(),
            ));
        }
        block_on(async {
            let packet = next_stream_packet(handle, timeout_millis).await?;
            BossAudioModesCodec::parse_settings_config(&packet).map_err(Into::into)
        })
    }) else {
        return false;
    };
    unsafe {
        *out_config = ffi_config_from_core(result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_update_stream_next_equalizer(
    handle: *mut BossFfiUpdateStreamHandle,
    timeout_millis: u64,
    out_settings: *mut BossFfiEqualizerSettings,
    out_error: *mut BossFfiError,
) -> bool {
    if out_settings.is_null() {
        write_error(out_error, invalid_argument_error("out_settings was null"));
        return false;
    }
    let Some(result) = with_update_stream(handle, out_error, |handle| {
        if handle.kind != BossFfiUpdateStreamKind::Equalizer {
            return Err(BossSessionError::UnsupportedOperation(
                "update stream kind did not match equalizer".into(),
            ));
        }
        block_on(async {
            let packet = next_stream_packet(handle, timeout_millis).await?;
            BossSettingsCodec::parse_equalizer(&packet).map_err(Into::into)
        })
    }) else {
        return false;
    };
    unsafe {
        *out_settings = ffi_equalizer_from_core(result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_update_stream_next_device_settings(
    handle: *mut BossFfiUpdateStreamHandle,
    timeout_millis: u64,
    out_report: *mut BossFfiDeviceSettingsReport,
    out_error: *mut BossFfiError,
) -> bool {
    if out_report.is_null() {
        write_error(out_error, invalid_argument_error("out_report was null"));
        return false;
    }
    let Some(result) = with_update_stream_mut(handle, out_error, |handle| {
        if handle.kind != BossFfiUpdateStreamKind::DeviceSettings {
            return Err(BossSessionError::UnsupportedOperation(
                "update stream kind did not match device settings".into(),
            ));
        }
        let session = BossSession::new(PacketSession::new(handle.link.clone()));
        block_on(async {
            if handle.device_settings_report.is_none() {
                let initial = session.refresh_device_settings_report(5_000).await?;
                handle.device_settings_report = Some(initial.clone());
                return Ok(initial);
            }
            loop {
                let packet = next_stream_packet(handle, timeout_millis).await?;
                if let Some(updated) = BossSession::<FfiLink>::reduce_device_settings_report(
                    handle
                        .device_settings_report
                        .as_ref()
                        .expect("state initialized"),
                    &packet,
                )? {
                    handle.device_settings_report = Some(updated.clone());
                    return Ok(updated);
                }
            }
        })
    }) else {
        return false;
    };
    unsafe {
        *out_report = ffi_device_settings_report_from_core(&result);
    }
    true
}

#[no_mangle]
pub extern "C" fn boss_update_stream_next_audio_mode_catalog(
    handle: *mut BossFfiUpdateStreamHandle,
    timeout_millis: u64,
    out_catalog: *mut BossBuffer,
    out_error: *mut BossFfiError,
) -> bool {
    if out_catalog.is_null() {
        write_error(out_error, invalid_argument_error("out_catalog was null"));
        return false;
    }
    let Some(result) = with_update_stream_mut(handle, out_error, |handle| {
        if handle.kind != BossFfiUpdateStreamKind::AudioModeCatalog {
            return Err(BossSessionError::UnsupportedOperation(
                "update stream kind did not match audio mode catalog".into(),
            ));
        }
        let session = BossSession::new(PacketSession::new(handle.link.clone()));
        block_on(async {
            if handle.audio_mode_catalog.is_none() {
                let initial = session.audio_mode_configs(30_000).await?;
                handle.audio_mode_catalog = Some(initial.clone());
                return Ok(initial);
            }
            loop {
                let packet = next_stream_packet(handle, timeout_millis).await?;
                if let Some(updated) = BossSession::<FfiLink>::reduce_audio_mode_catalog(
                    handle.audio_mode_catalog.as_ref().expect("state initialized"),
                    &packet,
                )? {
                    handle.audio_mode_catalog = Some(updated.clone());
                    return Ok(updated);
                }
            }
        })
    }) else {
        return false;
    };
    let configs: Vec<BossFfiAudioModeConfig> = result
        .into_iter()
        .map(ffi_audio_mode_config_from_core)
        .collect();
    unsafe {
        *out_catalog = buffer_from_struct_slice(&configs);
    }
    true
}
