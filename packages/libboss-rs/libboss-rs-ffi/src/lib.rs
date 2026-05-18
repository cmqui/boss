use std::ffi::c_void;
use std::ptr;
use std::sync::Arc;

use async_trait::async_trait;
use futures::executor::block_on;
use libboss_rs_core::{
    BmapCodec, BmapPacket, BossAudioModeSettingsConfig, BossAudioModeSettingsConfigPatch,
    BossEqualizerBand, BossEqualizerSettings, BossEqualizerSettingsPatch, BossTransportKind,
};
use libboss_rs_session::{
    BossAudioModeSettingsWriteResult, BossCurrentAudioModeWriteResult, BossEqualizerWriteResult, BossLink,
    BossLinkError, BossSession, BossSessionError, PacketSession,
};

#[repr(C)]
pub struct BossBuffer {
    pub data: *mut u8,
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
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BossFfiWriteDisposition {
    Unchanged = 0,
    Updated = 1,
    VerificationInconclusive = 2,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct BossFfiSessionCallbacks {
    pub context: *mut c_void,
    pub transport_kind: u8,
    pub send_packet_bytes:
        Option<extern "C" fn(context: *mut c_void, packet_data: *const u8, packet_len: usize) -> BossFfiLinkStatus>,
    pub next_packet_bytes:
        Option<extern "C" fn(context: *mut c_void, timeout_millis: u64, out_packet: *mut BossBuffer) -> BossFfiLinkStatus>,
    pub release_context: Option<extern "C" fn(context: *mut c_void)>,
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
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BossFfiEqualizerWriteResult {
    pub disposition: BossFfiWriteDisposition,
    pub settings: BossFfiEqualizerSettings,
}

#[repr(C)]
pub struct BossFfiError {
    pub code: BossFfiErrorCode,
    pub message: BossBuffer,
    pub has_bmap_error_code: bool,
    pub bmap_error_code: u8,
}

struct FfiLinkInner {
    callbacks: BossFfiSessionCallbacks,
}

impl Drop for FfiLinkInner {
    fn drop(&mut self) {
        if let Some(release_context) = self.callbacks.release_context {
            release_context(self.callbacks.context);
        }
    }
}

// SAFETY: the host is responsible for supplying a thread-safe context when using the shared handle.
unsafe impl Send for FfiLinkInner {}
// SAFETY: the host is responsible for supplying a thread-safe context when using the shared handle.
unsafe impl Sync for FfiLinkInner {}

#[derive(Clone)]
struct FfiLink {
    inner: Arc<FfiLinkInner>,
}

#[async_trait]
impl BossLink for FfiLink {
    fn transport_kind(&self) -> BossTransportKind {
        match self.inner.callbacks.transport_kind {
            0 => BossTransportKind::Ble,
            _ => BossTransportKind::Stream,
        }
    }

    async fn send_packet(&self, packet: &BmapPacket) -> Result<(), BossLinkError> {
        let packet_bytes = BmapCodec::encode(packet).map_err(|error| BossLinkError::Other(format!("{error:?}")))?;
        let Some(send_packet_bytes) = self.inner.callbacks.send_packet_bytes else {
            return Err(BossLinkError::Other("missing send_packet_bytes callback".into()));
        };
        match send_packet_bytes(
            self.inner.callbacks.context,
            packet_bytes.as_ptr(),
            packet_bytes.len(),
        ) {
            BossFfiLinkStatus::Ok => Ok(()),
            BossFfiLinkStatus::TimedOut => Err(BossLinkError::TimedOut),
            BossFfiLinkStatus::StreamEnded => Err(BossLinkError::UnexpectedStreamTermination),
            BossFfiLinkStatus::UnexpectedStreamTermination => Err(BossLinkError::UnexpectedStreamTermination),
            BossFfiLinkStatus::Other => Err(BossLinkError::Other("host send callback returned other".into())),
        }
    }

    async fn next_packet(&self, timeout_millis: u64) -> Result<Option<BmapPacket>, BossLinkError> {
        let Some(next_packet_bytes) = self.inner.callbacks.next_packet_bytes else {
            return Err(BossLinkError::Other("missing next_packet_bytes callback".into()));
        };
        let mut buffer = BossBuffer {
            data: ptr::null_mut(),
            len: 0,
        };
        match next_packet_bytes(self.inner.callbacks.context, timeout_millis, &mut buffer) {
            BossFfiLinkStatus::Ok => {
                if buffer.data.is_null() || buffer.len == 0 {
                    return Err(BossLinkError::Other("host next_packet_bytes returned ok with empty packet".into()));
                }
                let packet_bytes = unsafe { std::slice::from_raw_parts(buffer.data, buffer.len) }.to_vec();
                boss_buffer_free(buffer);
                BmapCodec::decode(&packet_bytes)
                    .map(Some)
                    .map_err(|error| BossLinkError::Other(format!("{error:?}")))
            }
            BossFfiLinkStatus::TimedOut => Err(BossLinkError::TimedOut),
            BossFfiLinkStatus::StreamEnded => Ok(None),
            BossFfiLinkStatus::UnexpectedStreamTermination => Err(BossLinkError::UnexpectedStreamTermination),
            BossFfiLinkStatus::Other => Err(BossLinkError::Other("host next_packet_bytes callback returned other".into())),
        }
    }
}

pub struct BossFfiSessionHandle {
    session: BossSession<FfiLink>,
}

fn buffer_from_vec(mut owned: Vec<u8>) -> BossBuffer {
    let buffer = BossBuffer {
        data: owned.as_mut_ptr(),
        len: owned.len(),
    };
    std::mem::forget(owned);
    buffer
}

fn buffer_from_string(message: impl Into<String>) -> BossBuffer {
    buffer_from_vec(message.into().into_bytes())
}

fn write_error(out_error: *mut BossFfiError, error: BossFfiError) {
    if out_error.is_null() {
        return;
    }
    unsafe {
        *out_error = error;
    }
}

fn invalid_argument_error(message: impl Into<String>) -> BossFfiError {
    BossFfiError {
        code: BossFfiErrorCode::InvalidArgument,
        message: buffer_from_string(message),
        has_bmap_error_code: false,
        bmap_error_code: 0,
    }
}

fn session_error_to_ffi(error: BossSessionError) -> BossFfiError {
    let code = match error {
        BossSessionError::ResponseStreamEnded => BossFfiErrorCode::ResponseStreamEnded,
        BossSessionError::ResponseTimedOut { .. } => BossFfiErrorCode::ResponseTimedOut,
        BossSessionError::BmapErrorResponse(_) => BossFfiErrorCode::BmapErrorResponse,
        BossSessionError::UnexpectedOperator(_) => BossFfiErrorCode::UnexpectedOperator,
        BossSessionError::ModeChangeNotObserved { .. } => BossFfiErrorCode::ModeChangeNotObserved,
        BossSessionError::EqualizerNotObserved { .. } => BossFfiErrorCode::EqualizerNotObserved,
        BossSessionError::SettingsConfigNotObserved { .. } => BossFfiErrorCode::SettingsConfigNotObserved,
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

fn with_session<T>(
    handle: *mut BossFfiSessionHandle,
    out_error: *mut BossFfiError,
    f: impl FnOnce(&BossFfiSessionHandle) -> Result<T, BossSessionError>,
) -> Option<T> {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        write_error(out_error, invalid_argument_error("session handle was null"));
        return None;
    };
    match f(handle) {
        Ok(value) => Some(value),
        Err(error) => {
            write_error(out_error, session_error_to_ffi(error));
            None
        }
    }
}

fn ffi_config_from_core(config: BossAudioModeSettingsConfig) -> BossFfiAudioModeSettingsConfig {
    BossFfiAudioModeSettingsConfig {
        cnc_level: config.cnc_level,
        auto_cnc_enabled: config.auto_cnc_enabled,
        spatial_audio_mode: config.spatial_audio_mode.raw_value(),
        wind_block_enabled: config.wind_block_enabled,
        anc_toggle_enabled: config.anc_toggle_enabled,
    }
}

fn core_patch_from_ffi(patch: BossFfiAudioModeSettingsConfigPatch) -> BossAudioModeSettingsConfigPatch {
    BossAudioModeSettingsConfigPatch {
        cnc_level: patch.has_cnc_level.then_some(patch.cnc_level),
        auto_cnc_enabled: patch.has_auto_cnc_enabled.then_some(patch.auto_cnc_enabled),
        spatial_audio_mode: patch
            .has_spatial_audio_mode
            .then(|| libboss_rs_core::BossSpatialAudioMode::from_raw(patch.spatial_audio_mode))
            .flatten(),
        wind_block_enabled: patch.has_wind_block_enabled.then_some(patch.wind_block_enabled),
        anc_toggle_enabled: patch.has_anc_toggle_enabled.then_some(patch.anc_toggle_enabled),
    }
}

fn core_equalizer_patch_from_ffi(patch: BossFfiEqualizerPatch) -> BossEqualizerSettingsPatch {
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

fn ffi_equalizer_from_core(settings: BossEqualizerSettings) -> BossFfiEqualizerSettings {
    BossFfiEqualizerSettings {
        bass: ffi_range(&settings, BossEqualizerBand::Bass),
        mid: ffi_range(&settings, BossEqualizerBand::Mid),
        treble: ffi_range(&settings, BossEqualizerBand::Treble),
    }
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
pub extern "C" fn boss_error_free(error: BossFfiError) {
    boss_buffer_free(error.message);
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

#[no_mangle]
pub extern "C" fn boss_session_create(
    callbacks: BossFfiSessionCallbacks,
    out_error: *mut BossFfiError,
) -> *mut BossFfiSessionHandle {
    if callbacks.send_packet_bytes.is_none() || callbacks.next_packet_bytes.is_none() {
        write_error(
            out_error,
            invalid_argument_error("session callbacks must include send_packet_bytes and next_packet_bytes"),
        );
        return ptr::null_mut();
    }

    let link = FfiLink {
        inner: Arc::new(FfiLinkInner { callbacks }),
    };
    let handle = BossFfiSessionHandle {
        session: BossSession::new(PacketSession::new(link)),
    };
    Box::into_raw(Box::new(handle))
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
        block_on(handle.session.set_current_audio_mode(target_index, play_voice_prompt))
    }) else {
        return false;
    };

    let ffi_result = match result {
        BossCurrentAudioModeWriteResult::Unchanged(mode_index) => BossFfiCurrentAudioModeWriteResult {
            disposition: BossFfiWriteDisposition::Unchanged,
            mode_index,
            target_index: mode_index,
        },
        BossCurrentAudioModeWriteResult::Updated(mode_index) => BossFfiCurrentAudioModeWriteResult {
            disposition: BossFfiWriteDisposition::Updated,
            mode_index,
            target_index: mode_index,
        },
        BossCurrentAudioModeWriteResult::VerificationInconclusive { target_index } => BossFfiCurrentAudioModeWriteResult {
            disposition: BossFfiWriteDisposition::VerificationInconclusive,
            mode_index: target_index,
            target_index,
        },
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
        && libboss_rs_core::BossSpatialAudioMode::from_raw(patch.spatial_audio_mode).is_none()
    {
        write_error(out_error, invalid_argument_error("spatial_audio_mode was not recognized"));
        return false;
    }

    let Some(result) = with_session(handle, out_error, |handle| {
        block_on(handle.session.set_audio_mode_settings(core_patch_from_ffi(patch)))
    }) else {
        return false;
    };

    let ffi_result = match result {
        BossAudioModeSettingsWriteResult::Unchanged(config) => BossFfiAudioModeSettingsWriteResult {
            disposition: BossFfiWriteDisposition::Unchanged,
            config: ffi_config_from_core(config),
        },
        BossAudioModeSettingsWriteResult::Updated(config) => BossFfiAudioModeSettingsWriteResult {
            disposition: BossFfiWriteDisposition::Updated,
            config: ffi_config_from_core(config),
        },
        BossAudioModeSettingsWriteResult::VerificationInconclusive(config) => BossFfiAudioModeSettingsWriteResult {
            disposition: BossFfiWriteDisposition::VerificationInconclusive,
            config: ffi_config_from_core(config),
        },
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
        block_on(handle.session.set_equalizer_verified(core_equalizer_patch_from_ffi(patch)))
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
        BossEqualizerWriteResult::VerificationInconclusive(settings) => BossFfiEqualizerWriteResult {
            disposition: BossFfiWriteDisposition::VerificationInconclusive,
            settings: ffi_equalizer_from_core(settings),
        },
    };
    unsafe {
        *out_result = ffi_result;
    }
    true
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::sync::Mutex;

    use libboss_rs_core::{BmapFunction, BmapFunctionBlock, BmapOperator};

    use super::*;

    struct HostContext {
        incoming_packets: Mutex<VecDeque<Vec<u8>>>,
        sent_packets: Mutex<Vec<Vec<u8>>>,
    }

    extern "C" fn test_send_packet_bytes(
        context: *mut c_void,
        packet_data: *const u8,
        packet_len: usize,
    ) -> BossFfiLinkStatus {
        let context = unsafe { &*(context as *mut HostContext) };
        let packet = unsafe { std::slice::from_raw_parts(packet_data, packet_len) }.to_vec();
        context.sent_packets.lock().unwrap().push(packet);
        BossFfiLinkStatus::Ok
    }

    extern "C" fn test_next_packet_bytes(
        context: *mut c_void,
        _timeout_millis: u64,
        out_packet: *mut BossBuffer,
    ) -> BossFfiLinkStatus {
        let context = unsafe { &*(context as *mut HostContext) };
        let Some(packet) = context.incoming_packets.lock().unwrap().pop_front() else {
            return BossFfiLinkStatus::StreamEnded;
        };
        unsafe {
            *out_packet = buffer_from_vec(packet);
        }
        BossFfiLinkStatus::Ok
    }

    extern "C" fn test_release_context(context: *mut c_void) {
        unsafe {
            drop(Box::from_raw(context as *mut HostContext));
        }
    }

    fn packet_bytes(packet: BmapPacket) -> Vec<u8> {
        BmapCodec::encode(&packet).unwrap()
    }

    #[test]
    fn ffi_session_set_current_audio_mode_returns_updated_result() {
        let context = Box::new(HostContext {
            incoming_packets: Mutex::new(VecDeque::from(vec![
                packet_bytes(BmapPacket::new(
                    BmapFunctionBlock::AudioModes,
                    BmapFunction::Unknown {
                        block: BmapFunctionBlock::AudioModes,
                        raw_value: libboss_rs_core::BossAudioModesCodec::CURRENT_MODE_FUNCTION_RAW,
                    },
                    0,
                    0,
                    BmapOperator::Status,
                    vec![0x01],
                )),
                packet_bytes(BmapPacket::new(
                    BmapFunctionBlock::AudioModes,
                    BmapFunction::Unknown {
                        block: BmapFunctionBlock::AudioModes,
                        raw_value: libboss_rs_core::BossAudioModesCodec::CURRENT_MODE_FUNCTION_RAW,
                    },
                    0,
                    0,
                    BmapOperator::Result,
                    vec![0x03],
                )),
            ])),
            sent_packets: Mutex::new(Vec::new()),
        });
        let handle = boss_session_create(
            BossFfiSessionCallbacks {
                context: Box::into_raw(context) as *mut c_void,
                transport_kind: 1,
                send_packet_bytes: Some(test_send_packet_bytes),
                next_packet_bytes: Some(test_next_packet_bytes),
                release_context: Some(test_release_context),
            },
            ptr::null_mut(),
        );

        let mut result = BossFfiCurrentAudioModeWriteResult::default();
        assert!(boss_session_set_current_audio_mode(
            handle,
            3,
            false,
            &mut result,
            ptr::null_mut(),
        ));
        assert_eq!(result.disposition, BossFfiWriteDisposition::Updated);
        assert_eq!(result.mode_index, 3);

        boss_session_free(handle);
    }
}
