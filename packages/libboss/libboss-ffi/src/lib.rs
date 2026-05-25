use std::ptr;

mod ble;
mod conversions;
mod ffi_types;
mod host_link;
mod memory;
mod packets;
mod session_api;
#[cfg(test)]
mod tests;
mod update_broker;
mod update_stream;

pub use ble::*;
pub use ffi_types::*;
pub use memory::*;
pub use packets::*;
pub use session_api::*;
pub use update_stream::*;

pub(crate) fn buffer_from_vec(mut owned: Vec<u8>) -> BossBuffer {
    let buffer = BossBuffer {
        data: owned.as_mut_ptr(),
        len: owned.len(),
    };
    std::mem::forget(owned);
    buffer
}

pub(crate) fn buffer_list_from_vec(mut owned: Vec<BossBuffer>) -> BossBufferList {
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

pub(crate) fn buffer_from_i32_slice(values: &[i32]) -> BossBuffer {
    let mut bytes = Vec::with_capacity(values.len() * std::mem::size_of::<i32>());
    for value in values {
        bytes.extend_from_slice(&value.to_le_bytes());
    }
    buffer_from_vec(bytes)
}

pub(crate) fn buffer_from_struct_slice<T: Copy>(values: &[T]) -> BossBuffer {
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

pub(crate) fn other_error(message: impl Into<String>) -> BossFfiError {
    BossFfiError {
        code: BossFfiErrorCode::None,
        message: buffer_from_string(message),
        has_bmap_error_code: false,
        bmap_error_code: 0,
    }
}

pub(crate) fn prompt_from_bytes(byte1: u8, byte2: u8) -> libboss_core::BossAudioModePrompt {
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
