use libboss_core::{
    BmapCodec, BmapOperator, BmapPacket, BossAudioModesCodec, BossSettingsCodec,
};

use crate::conversions::*;
use crate::{
    buffer_from_i32_slice, buffer_from_struct_slice, buffer_from_vec, invalid_argument_error,
    other_error, prompt_from_bytes, write_error, BossBuffer, BossFfiAudioModeConfig,
    BossFfiAudioModeSettingsConfig,
    BossFfiAudioModesCapabilities, BossFfiBmapPacket, BossFfiEqualizerSettings, BossFfiError,
    BossFfiOnHeadDetectionValue, BossFfiStandbyTimerValue, BossFfiVolumeControlStatus,
};

fn write_packet(
    out_packet: *mut BossFfiBmapPacket,
    packet: BmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    if out_packet.is_null() {
        write_error(out_error, invalid_argument_error("out_packet was null"));
        return false;
    }
    unsafe { *out_packet = ffi_packet_from_core(packet) };
    true
}

fn with_packet<T>(
    packet: *const BossFfiBmapPacket,
    out_error: *mut BossFfiError,
    f: impl FnOnce(&BmapPacket) -> Result<T, crate::BossFfiError>,
) -> Result<T, bool> {
    let Some(packet) = (unsafe { packet.as_ref() }) else {
        write_error(out_error, invalid_argument_error("packet was null"));
        return Err(false);
    };
    let packet = core_packet_from_ffi(packet);
    f(&packet).map_err(|error| {
        write_error(out_error, error);
        false
    })
}

#[no_mangle]
pub extern "C" fn boss_packet_encode(
    packet: BossFfiBmapPacket,
    out_bytes: *mut BossBuffer,
    out_error: *mut BossFfiError,
) -> bool {
    if out_bytes.is_null() {
        write_error(out_error, invalid_argument_error("out_bytes was null"));
        return false;
    }
    match BmapCodec::encode(&core_packet_from_ffi(&packet)) {
        Ok(bytes) => {
            unsafe { *out_bytes = buffer_from_vec(bytes.to_vec()) };
            true
        }
        Err(error) => {
            write_error(out_error, other_error(format!("{error:?}")));
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn boss_packet_decode(
    packet_data: *const u8,
    packet_len: usize,
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    if packet_data.is_null() {
        write_error(out_error, invalid_argument_error("packet_data was null"));
        return false;
    }
    if out_packet.is_null() {
        write_error(out_error, invalid_argument_error("out_packet was null"));
        return false;
    }
    let packet_data = unsafe { std::slice::from_raw_parts(packet_data, packet_len) };
    match BmapCodec::decode(packet_data) {
        Ok(packet) => {
            unsafe { *out_packet = ffi_packet_from_core(packet) };
            true
        }
        Err(error) => {
            write_error(out_error, other_error(format!("{error:?}")));
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn boss_bmap_decode_frame_size(
    frame_data: *const u8,
    frame_len: usize,
    out_payload_len: *mut usize,
) -> bool {
    if frame_data.is_null() || out_payload_len.is_null() {
        return false;
    }
    let frame = unsafe { std::slice::from_raw_parts(frame_data, frame_len) };
    match BmapCodec::decode(frame) {
        Ok(packet) => {
            unsafe { *out_payload_len = packet.payload.len() };
            true
        }
        Err(_) => false,
    }
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_names_supported_get_packet(
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    write_packet(
        out_packet,
        BossAudioModesCodec::names_supported_get_packet(),
        out_error,
    )
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_current_mode_get_packet(
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    write_packet(
        out_packet,
        BossAudioModesCodec::current_mode_get_packet(),
        out_error,
    )
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_current_mode_start_packet(
    mode_index: i32,
    play_voice_prompt: bool,
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    write_packet(
        out_packet,
        BossAudioModesCodec::current_mode_start_packet(mode_index, play_voice_prompt),
        out_error,
    )
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_capabilities_get_packet(
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    write_packet(
        out_packet,
        BossAudioModesCodec::capabilities_get_packet(),
        out_error,
    )
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_favorites_get_packet(
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    write_packet(
        out_packet,
        BossAudioModesCodec::favorites_get_packet(),
        out_error,
    )
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_settings_config_get_packet(
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    write_packet(
        out_packet,
        BossAudioModesCodec::settings_config_get_packet(),
        out_error,
    )
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_mode_config_start_packet(
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    write_packet(
        out_packet,
        BossAudioModesCodec::mode_config_start_packet(),
        out_error,
    )
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_settings_config_set_get_packet(
    config: BossFfiAudioModeSettingsConfig,
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    match BossAudioModesCodec::settings_config_set_get_packet(&core_config_from_ffi(config)) {
        Ok(packet) => write_packet(out_packet, packet, out_error),
        Err(error) => {
            write_error(out_error, other_error(format!("{error:?}")));
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_mode_config_set_get_packet(
    mode_index: i32,
    prompt_byte1: u8,
    prompt_byte2: u8,
    name_bytes: *const u8,
    name_len: usize,
    settings: BossFfiAudioModeSettingsConfig,
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    let name = if name_bytes.is_null() || name_len == 0 {
        String::new()
    } else {
        String::from_utf8_lossy(unsafe { std::slice::from_raw_parts(name_bytes, name_len) })
            .into_owned()
    };
    let prompt = prompt_from_bytes(prompt_byte1, prompt_byte2);
    match BossAudioModesCodec::mode_config_set_get_packet(
        mode_index,
        prompt,
        &name,
        &core_config_from_ffi(settings),
    ) {
        Ok(packet) => write_packet(out_packet, packet, out_error),
        Err(error) => {
            write_error(out_error, other_error(format!("{error:?}")));
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_favorites_set_get_packet(
    number_of_modes: i32,
    favorite_mode_indices: *const i32,
    favorite_mode_indices_len: usize,
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    let indices = if favorite_mode_indices.is_null() || favorite_mode_indices_len == 0 {
        &[][..]
    } else {
        unsafe { std::slice::from_raw_parts(favorite_mode_indices, favorite_mode_indices_len) }
    };
    match BossAudioModesCodec::encode_favorites(number_of_modes, indices) {
        Ok(payload) => write_packet(
            out_packet,
            BossAudioModesCodec::packet(
                BossAudioModesCodec::FAVORITES_FUNCTION_RAW,
                BmapOperator::SetGet,
                payload,
            ),
            out_error,
        ),
        Err(error) => {
            write_error(out_error, other_error(format!("{error:?}")));
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn boss_settings_get_all_start_packet(
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    write_packet(
        out_packet,
        BossSettingsCodec::settings_packet(
            BossSettingsCodec::SETTINGS_GET_ALL_FUNCTION_RAW,
            BmapOperator::Start,
            Vec::new(),
        ),
        out_error,
    )
}

#[no_mangle]
pub extern "C" fn boss_settings_standby_timer_get_packet(
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    write_packet(
        out_packet,
        BossSettingsCodec::settings_packet(
            BossSettingsCodec::STANDBY_TIMER_FUNCTION_RAW,
            BmapOperator::Get,
            Vec::new(),
        ),
        out_error,
    )
}

#[no_mangle]
pub extern "C" fn boss_settings_standby_timer_set_get_packet(
    minutes: i32,
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    match BossSettingsCodec::standby_timer_set_get_packet(minutes) {
        Ok(packet) => write_packet(out_packet, packet, out_error),
        Err(error) => {
            write_error(out_error, other_error(format!("{error:?}")));
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn boss_settings_on_head_detection_get_packet(
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    write_packet(
        out_packet,
        BossSettingsCodec::settings_packet(
            BossSettingsCodec::ON_HEAD_DETECTION_FUNCTION_RAW,
            BmapOperator::Get,
            Vec::new(),
        ),
        out_error,
    )
}

#[no_mangle]
pub extern "C" fn boss_settings_on_head_detection_set_get_packet(
    value: BossFfiOnHeadDetectionValue,
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    write_packet(
        out_packet,
        BossSettingsCodec::on_head_detection_set_get_packet(&core_on_head_detection_from_ffi(
            value,
        )),
        out_error,
    )
}

#[no_mangle]
pub extern "C" fn boss_settings_enabled_setting_get_packet(
    function_raw: u8,
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    write_packet(
        out_packet,
        BossSettingsCodec::settings_packet(function_raw, BmapOperator::Get, Vec::new()),
        out_error,
    )
}

#[no_mangle]
pub extern "C" fn boss_settings_enabled_setting_set_get_packet(
    function_raw: u8,
    enabled: bool,
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    write_packet(
        out_packet,
        BossSettingsCodec::settings_packet(
            function_raw,
            BmapOperator::SetGet,
            vec![if enabled { 0x01 } else { 0x00 }],
        ),
        out_error,
    )
}

#[no_mangle]
pub extern "C" fn boss_settings_equalizer_get_packet(
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    write_packet(
        out_packet,
        BossSettingsCodec::settings_packet(
            BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW,
            BmapOperator::Get,
            Vec::new(),
        ),
        out_error,
    )
}

#[no_mangle]
pub extern "C" fn boss_settings_equalizer_set_get_packet(
    target_level: i32,
    band_raw: u8,
    out_packet: *mut BossFfiBmapPacket,
    out_error: *mut BossFfiError,
) -> bool {
    match BossSettingsCodec::equalizer_set_get_packet(
        target_level,
        libboss_core::BossEqualizerBand::from_raw(band_raw),
    ) {
        Ok(packet) => write_packet(out_packet, packet, out_error),
        Err(error) => {
            write_error(out_error, other_error(format!("{error:?}")));
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_parse_supported_prompts(
    packet: *const BossFfiBmapPacket,
    out_prompts: *mut BossBuffer,
    out_error: *mut BossFfiError,
) -> bool {
    if out_prompts.is_null() {
        write_error(out_error, invalid_argument_error("out_prompts was null"));
        return false;
    }
    let Ok(prompts) = with_packet(packet, out_error, |packet| {
        BossAudioModesCodec::parse_supported_prompts(packet)
            .map(|prompts| {
                prompts
                    .into_iter()
                    .map(ffi_audio_mode_prompt_from_core)
                    .collect::<Vec<_>>()
            })
            .map_err(|error| other_error(format!("{error:?}")))
    }) else {
        return false;
    };
    unsafe { *out_prompts = buffer_from_struct_slice(&prompts) };
    true
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_parse_current_mode(
    packet: *const BossFfiBmapPacket,
    out_mode_index: *mut i32,
    out_error: *mut BossFfiError,
) -> bool {
    if out_mode_index.is_null() {
        write_error(out_error, invalid_argument_error("out_mode_index was null"));
        return false;
    }
    let Ok(mode_index) = with_packet(packet, out_error, |packet| {
        BossAudioModesCodec::parse_current_mode(packet)
            .map_err(|error| other_error(format!("{error:?}")))
    }) else {
        return false;
    };
    unsafe { *out_mode_index = mode_index };
    true
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_parse_capabilities(
    packet: *const BossFfiBmapPacket,
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
    let Ok(capabilities) = with_packet(packet, out_error, |packet| {
        BossAudioModesCodec::parse_capabilities(packet)
            .map(ffi_audio_modes_capabilities_from_core)
            .map_err(|error| other_error(format!("{error:?}")))
    }) else {
        return false;
    };
    unsafe { *out_capabilities = capabilities };
    true
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_parse_favorites(
    packet: *const BossFfiBmapPacket,
    out_favorites: *mut BossBuffer,
    out_error: *mut BossFfiError,
) -> bool {
    if out_favorites.is_null() {
        write_error(out_error, invalid_argument_error("out_favorites was null"));
        return false;
    }
    let Ok(favorites) = with_packet(packet, out_error, |packet| {
        BossAudioModesCodec::parse_favorites(packet)
            .map_err(|error| other_error(format!("{error:?}")))
    }) else {
        return false;
    };
    unsafe { *out_favorites = buffer_from_i32_slice(&favorites) };
    true
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_parse_settings_config(
    packet: *const BossFfiBmapPacket,
    out_config: *mut BossFfiAudioModeSettingsConfig,
    out_error: *mut BossFfiError,
) -> bool {
    if out_config.is_null() {
        write_error(out_error, invalid_argument_error("out_config was null"));
        return false;
    }
    let Ok(config) = with_packet(packet, out_error, |packet| {
        BossAudioModesCodec::parse_settings_config(packet)
            .map(ffi_config_from_core)
            .map_err(|error| other_error(format!("{error:?}")))
    }) else {
        return false;
    };
    unsafe { *out_config = config };
    true
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_parse_mode_config_detail(
    packet: *const BossFfiBmapPacket,
    out_config: *mut BossFfiAudioModeConfig,
    out_error: *mut BossFfiError,
) -> bool {
    if out_config.is_null() {
        write_error(out_error, invalid_argument_error("out_config was null"));
        return false;
    }
    let Ok(config) = with_packet(packet, out_error, |packet| {
        BossAudioModesCodec::parse_mode_config_detail(packet)
            .map(ffi_audio_mode_config_from_core)
            .map_err(|error| other_error(format!("{error:?}")))
    }) else {
        return false;
    };
    unsafe { *out_config = config };
    true
}

#[no_mangle]
pub extern "C" fn boss_audio_modes_parse_volume_control_status(
    packet: *const BossFfiBmapPacket,
    out_status: *mut BossFfiVolumeControlStatus,
    out_error: *mut BossFfiError,
) -> bool {
    if out_status.is_null() {
        write_error(out_error, invalid_argument_error("out_status was null"));
        return false;
    }
    let Ok(status) = with_packet(packet, out_error, |packet| {
        BossAudioModesCodec::parse_volume_control_status(packet)
            .map(ffi_volume_control_status_from_core)
            .map_err(|error| other_error(format!("{error:?}")))
    }) else {
        return false;
    };
    unsafe { *out_status = status };
    true
}

#[no_mangle]
pub extern "C" fn boss_settings_parse_equalizer(
    packet: *const BossFfiBmapPacket,
    out_settings: *mut BossFfiEqualizerSettings,
    out_error: *mut BossFfiError,
) -> bool {
    if out_settings.is_null() {
        write_error(out_error, invalid_argument_error("out_settings was null"));
        return false;
    }
    let Ok(settings) = with_packet(packet, out_error, |packet| {
        BossSettingsCodec::parse_equalizer(packet)
            .map(ffi_equalizer_from_core)
            .map_err(|error| other_error(format!("{error:?}")))
    }) else {
        return false;
    };
    unsafe { *out_settings = settings };
    true
}

#[no_mangle]
pub extern "C" fn boss_settings_parse_standby_timer(
    packet: *const BossFfiBmapPacket,
    out_value: *mut BossFfiStandbyTimerValue,
    out_error: *mut BossFfiError,
) -> bool {
    if out_value.is_null() {
        write_error(out_error, invalid_argument_error("out_value was null"));
        return false;
    }
    let Ok(value) = with_packet(packet, out_error, |packet| {
        BossSettingsCodec::parse_standby_timer(packet)
            .map(ffi_standby_timer_from_core)
            .map_err(|error| other_error(format!("{error:?}")))
    }) else {
        return false;
    };
    unsafe { *out_value = value };
    true
}

#[no_mangle]
pub extern "C" fn boss_settings_parse_enabled_flag(
    packet: *const BossFfiBmapPacket,
    out_enabled: *mut bool,
    out_error: *mut BossFfiError,
) -> bool {
    if out_enabled.is_null() {
        write_error(out_error, invalid_argument_error("out_enabled was null"));
        return false;
    }
    let Ok(enabled) = with_packet(packet, out_error, |packet| {
        BossSettingsCodec::parse_enabled_flag(packet)
            .map_err(|error| other_error(format!("{error:?}")))
    }) else {
        return false;
    };
    unsafe { *out_enabled = enabled };
    true
}

#[no_mangle]
pub extern "C" fn boss_settings_parse_on_head_detection(
    packet: *const BossFfiBmapPacket,
    out_value: *mut BossFfiOnHeadDetectionValue,
    out_error: *mut BossFfiError,
) -> bool {
    if out_value.is_null() {
        write_error(out_error, invalid_argument_error("out_value was null"));
        return false;
    }
    let Ok(value) = with_packet(packet, out_error, |packet| {
        BossSettingsCodec::parse_on_head_detection(packet)
            .map(ffi_on_head_detection_from_core)
            .map_err(|error| other_error(format!("{error:?}")))
    }) else {
        return false;
    };
    unsafe { *out_value = value };
    true
}
