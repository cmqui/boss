use std::ptr;
use std::sync::Arc;

use async_trait::async_trait;
use libboss_core::{BmapCodec, BmapPacket, BossAudioModeConfig, BossTransportKind};
use libboss_session::{
    BossDeviceSettingsReport, BossLink, BossLinkError, BossSession, BossSessionError,
};

use crate::{
    invalid_argument_error, session_error_to_ffi, write_error, BossBuffer, BossFfiError,
    BossFfiLinkStatus, BossFfiSessionCallbacks, BossFfiUpdateStreamKind,
};

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
pub(crate) struct FfiLink {
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
        let packet_bytes = BmapCodec::encode(packet)
            .map_err(|error| BossLinkError::Other(format!("{error:?}")))?;
        let Some(send_packet_bytes) = self.inner.callbacks.send_packet_bytes else {
            return Err(BossLinkError::Other(
                "missing send_packet_bytes callback".into(),
            ));
        };
        match send_packet_bytes(
            self.inner.callbacks.context,
            packet_bytes.as_ptr(),
            packet_bytes.len(),
        ) {
            BossFfiLinkStatus::Ok => Ok(()),
            BossFfiLinkStatus::TimedOut => Err(BossLinkError::TimedOut),
            BossFfiLinkStatus::StreamEnded => Err(BossLinkError::UnexpectedStreamTermination),
            BossFfiLinkStatus::UnexpectedStreamTermination => {
                Err(BossLinkError::UnexpectedStreamTermination)
            }
            BossFfiLinkStatus::Other => Err(BossLinkError::Other(
                "host send callback returned other".into(),
            )),
        }
    }

    async fn next_packet(&self, timeout_millis: u64) -> Result<Option<BmapPacket>, BossLinkError> {
        let Some(next_packet_bytes) = self.inner.callbacks.next_packet_bytes else {
            return Err(BossLinkError::Other(
                "missing next_packet_bytes callback".into(),
            ));
        };
        let mut buffer = BossBuffer {
            data: ptr::null_mut(),
            len: 0,
        };
        match next_packet_bytes(self.inner.callbacks.context, timeout_millis, &mut buffer) {
            BossFfiLinkStatus::Ok => {
                if buffer.data.is_null() || buffer.len == 0 {
                    return Err(BossLinkError::Other(
                        "host next_packet_bytes returned ok with empty packet".into(),
                    ));
                }
                let packet_bytes =
                    unsafe { std::slice::from_raw_parts(buffer.data, buffer.len) }.to_vec();
                free_buffer(buffer);
                BmapCodec::decode(&packet_bytes)
                    .map(Some)
                    .map_err(|error| BossLinkError::Other(format!("{error:?}")))
            }
            BossFfiLinkStatus::TimedOut => Err(BossLinkError::TimedOut),
            BossFfiLinkStatus::StreamEnded => Ok(None),
            BossFfiLinkStatus::UnexpectedStreamTermination => {
                Err(BossLinkError::UnexpectedStreamTermination)
            }
            BossFfiLinkStatus::Other => Err(BossLinkError::Other(
                "host next_packet_bytes callback returned other".into(),
            )),
        }
    }
}

pub struct BossFfiSessionHandle {
    pub(crate) session: BossSession<FfiLink>,
}

pub struct BossFfiUpdateStreamHandle {
    pub(crate) link: FfiLink,
    pub(crate) kind: BossFfiUpdateStreamKind,
    pub(crate) device_settings_report: Option<BossDeviceSettingsReport>,
    pub(crate) audio_mode_catalog: Option<Vec<BossAudioModeConfig>>,
}

pub(crate) fn ffi_link_from_callbacks(
    callbacks: BossFfiSessionCallbacks,
    out_error: *mut BossFfiError,
) -> Option<FfiLink> {
    if callbacks.send_packet_bytes.is_none() || callbacks.next_packet_bytes.is_none() {
        write_error(
            out_error,
            invalid_argument_error(
                "session callbacks must include send_packet_bytes and next_packet_bytes",
            ),
        );
        return None;
    }

    Some(FfiLink {
        inner: Arc::new(FfiLinkInner { callbacks }),
    })
}

pub(crate) fn with_session<T>(
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

pub(crate) fn with_update_stream<T>(
    handle: *mut BossFfiUpdateStreamHandle,
    out_error: *mut BossFfiError,
    f: impl FnOnce(&BossFfiUpdateStreamHandle) -> Result<T, BossSessionError>,
) -> Option<T> {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        write_error(
            out_error,
            invalid_argument_error("update stream handle was null"),
        );
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

pub(crate) fn with_update_stream_mut<T>(
    handle: *mut BossFfiUpdateStreamHandle,
    out_error: *mut BossFfiError,
    f: impl FnOnce(&mut BossFfiUpdateStreamHandle) -> Result<T, BossSessionError>,
) -> Option<T> {
    let Some(handle) = (unsafe { handle.as_mut() }) else {
        write_error(
            out_error,
            invalid_argument_error("update stream handle was null"),
        );
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

fn free_buffer(buffer: BossBuffer) {
    if buffer.data.is_null() || buffer.len == 0 {
        return;
    }
    unsafe {
        let _ = Vec::from_raw_parts(buffer.data, buffer.len, buffer.len);
    }
}
