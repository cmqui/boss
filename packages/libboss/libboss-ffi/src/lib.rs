use futures::executor::block_on;
use libboss_core::{
    BleSegmentReassembler, BleSegmentation, BmapCodec, BmapFunctionBlock, BmapOperator, BmapPacket,
    BossAudioModeSettingsConfig, BossAudioModesCodec, BossSettingsCodec, BossVolumeControlValue,
};
use libboss_session::{
    BootstrapSession, BossAudioModeSettingsWriteResult, BossCurrentAudioModeWriteResult,
    BossEqualizerWriteResult, BossLink, BossSession, BossSessionError, PacketSession,
    SessionConfiguration,
};
use std::ptr;

mod conversions;
mod ffi_types;
mod host_link;
#[cfg(test)]
mod tests;

use conversions::*;
use host_link::*;

pub use ffi_types::*;

pub(crate) fn buffer_from_vec(mut owned: Vec<u8>) -> BossBuffer {
    let buffer = BossBuffer {
        data: owned.as_mut_ptr(),
        len: owned.len(),
    };
    std::mem::forget(owned);
    buffer
}

fn buffer_list_from_vec(mut owned: Vec<BossBuffer>) -> BossBufferList {
    let list = BossBufferList {
        data: owned.as_mut_ptr(),
        len: owned.len(),
    };
    std::mem::forget(owned);
    list
}

pub(crate) fn buffer_from_string(message: impl Into<String>) -> BossBuffer {
    buffer_from_vec(message.into().into_bytes())
}

fn buffer_from_i32_slice(values: &[i32]) -> BossBuffer {
    let mut bytes = Vec::with_capacity(values.len() * std::mem::size_of::<i32>());
    for value in values {
        bytes.extend_from_slice(&value.to_le_bytes());
    }
    buffer_from_vec(bytes)
}

fn buffer_from_struct_slice<T: Copy>(values: &[T]) -> BossBuffer {
    let byte_len = std::mem::size_of_val(values);
    let mut bytes = vec![0u8; byte_len];
    unsafe {
        ptr::copy_nonoverlapping(values.as_ptr() as *const u8, bytes.as_mut_ptr(), byte_len);
    }
    buffer_from_vec(bytes)
}

pub(crate) fn write_error(out_error: *mut BossFfiError, error: BossFfiError) {
    if out_error.is_null() {
        return;
    }
    unsafe {
        *out_error = error;
    }
}

pub(crate) fn invalid_argument_error(message: impl Into<String>) -> BossFfiError {
    BossFfiError {
        code: BossFfiErrorCode::InvalidArgument,
        message: buffer_from_string(message),
        has_bmap_error_code: false,
        bmap_error_code: 0,
    }
}

fn other_error(message: impl Into<String>) -> BossFfiError {
    BossFfiError {
        code: BossFfiErrorCode::None,
        message: buffer_from_string(message),
        has_bmap_error_code: false,
        bmap_error_code: 0,
    }
}

fn prompt_from_bytes(byte1: u8, byte2: u8) -> libboss_core::BossAudioModePrompt {
    libboss_core::BossAudioModePrompt::ALL_KNOWN
        .into_iter()
        .find(|prompt| prompt.byte1 == byte1 && prompt.byte2 == byte2)
        .unwrap_or(libboss_core::BossAudioModePrompt::NONE)
}

impl Default for BossFfiWriteDisposition {
    fn default() -> Self {
        Self::Unchanged
    }
}

#[no_mangle]
pub extern "C" fn boss_buffer_free(buffer: BossBuffer) {
    if buffer.data.is_null() || buffer.len == 0 {
        return;
    }
    unsafe {
        let _ = Vec::from_raw_parts(buffer.data, buffer.len, buffer.len);
    }
}

#[no_mangle]
pub extern "C" fn boss_buffer_list_free(list: BossBufferList) {
    if list.data.is_null() || list.len == 0 {
        return;
    }
    unsafe {
        let buffers = Vec::from_raw_parts(list.data, list.len, list.len);
        for buffer in buffers {
            boss_buffer_free(buffer);
        }
    }
}

#[no_mangle]
pub extern "C" fn boss_error_free(error: BossFfiError) {
    boss_buffer_free(error.message);
}

#[no_mangle]
pub extern "C" fn boss_packet_free(packet: BossFfiBmapPacket) {
    boss_buffer_free(packet.payload);
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
    f: impl FnOnce(&BmapPacket) -> Result<T, BossFfiError>,
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

#[no_mangle]
pub extern "C" fn boss_copy_bytes(data: *const u8, len: usize) -> BossBuffer {
    if data.is_null() || len == 0 {
        return BossBuffer {
            data: ptr::null_mut(),
            len: 0,
        };
    }
    let input = unsafe { std::slice::from_raw_parts(data, len) };
    buffer_from_vec(input.to_vec())
}

pub struct BossFfiBleReassemblerHandle {
    reassembler: BleSegmentReassembler,
}

#[no_mangle]
pub extern "C" fn boss_ble_reassembler_create() -> *mut BossFfiBleReassemblerHandle {
    Box::into_raw(Box::new(BossFfiBleReassemblerHandle {
        reassembler: BleSegmentReassembler::default(),
    }))
}

#[no_mangle]
pub extern "C" fn boss_ble_reassembler_free(handle: *mut BossFfiBleReassemblerHandle) {
    if handle.is_null() {
        return;
    }
    unsafe {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub extern "C" fn boss_ble_segment_packet(
    packet_data: *const u8,
    packet_len: usize,
    mtu: usize,
    out_frames: *mut BossBufferList,
    out_error: *mut BossFfiError,
) -> bool {
    if packet_data.is_null() {
        write_error(out_error, invalid_argument_error("packet_data was null"));
        return false;
    }
    if out_frames.is_null() {
        write_error(out_error, invalid_argument_error("out_frames was null"));
        return false;
    }

    let packet = unsafe { std::slice::from_raw_parts(packet_data, packet_len) };
    match BleSegmentation::encode(packet, mtu) {
        Ok(frames) => {
            let buffers = frames.into_iter().map(buffer_from_vec).collect();
            unsafe {
                *out_frames = buffer_list_from_vec(buffers);
            }
            true
        }
        Err(error) => {
            write_error(out_error, other_error(format!("{error:?}")));
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn boss_ble_reassembler_push(
    handle: *mut BossFfiBleReassemblerHandle,
    segment_data: *const u8,
    segment_len: usize,
    out_packet: *mut BossBuffer,
    out_has_packet: *mut bool,
    out_error: *mut BossFfiError,
) -> bool {
    let Some(handle) = (unsafe { handle.as_mut() }) else {
        write_error(
            out_error,
            invalid_argument_error("reassembler handle was null"),
        );
        return false;
    };
    if segment_data.is_null() {
        write_error(out_error, invalid_argument_error("segment_data was null"));
        return false;
    }
    if out_packet.is_null() {
        write_error(out_error, invalid_argument_error("out_packet was null"));
        return false;
    }
    if out_has_packet.is_null() {
        write_error(out_error, invalid_argument_error("out_has_packet was null"));
        return false;
    }

    let segment = unsafe { std::slice::from_raw_parts(segment_data, segment_len) };
    match handle.reassembler.push(segment) {
        Ok(Some(packet)) => {
            unsafe {
                *out_packet = buffer_from_vec(packet);
                *out_has_packet = true;
            }
            true
        }
        Ok(None) => {
            unsafe {
                *out_packet = BossBuffer {
                    data: ptr::null_mut(),
                    len: 0,
                };
                *out_has_packet = false;
            }
            true
        }
        Err(error) => {
            write_error(out_error, other_error(format!("{error:?}")));
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn boss_session_create(
    callbacks: BossFfiSessionCallbacks,
    out_error: *mut BossFfiError,
) -> *mut BossFfiSessionHandle {
    let Some(link) = ffi_link_from_callbacks(callbacks, out_error) else {
        return ptr::null_mut();
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
pub extern "C" fn boss_update_stream_create(
    callbacks: BossFfiSessionCallbacks,
    kind: BossFfiUpdateStreamKind,
    out_error: *mut BossFfiError,
) -> *mut BossFfiUpdateStreamHandle {
    let Some(link) = ffi_link_from_callbacks(callbacks, out_error) else {
        return ptr::null_mut();
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
                    handle
                        .audio_mode_catalog
                        .as_ref()
                        .expect("state initialized"),
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
    patch: BossFfiAudioModeSettingsConfigPatch,
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
    patch: BossFfiEqualizerPatch,
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
        result.packet(BossSettingsCodec::STANDBY_TIMER_FUNCTION_RAW),
        result.packet(BossSettingsCodec::AUTO_AWARE_FUNCTION_RAW),
        result.packet(BossSettingsCodec::ON_HEAD_DETECTION_FUNCTION_RAW),
        result.packet(BossSettingsCodec::AUTO_PLAY_PAUSE_FUNCTION_RAW),
        result.packet(BossSettingsCodec::AUTO_ANSWER_FUNCTION_RAW),
        result.packet(BossSettingsCodec::VOLUME_CONTROL_FUNCTION_RAW),
        result.packet(BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW),
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
    let prompts: Vec<BossFfiAudioModePrompt> = result
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
