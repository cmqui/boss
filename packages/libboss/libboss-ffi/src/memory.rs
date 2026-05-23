use std::ptr;

use crate::{BossBuffer, BossBufferList, BossFfiBmapPacket, BossFfiError};

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
pub extern "C" fn boss_copy_bytes(data: *const u8, len: usize) -> BossBuffer {
    if data.is_null() || len == 0 {
        return BossBuffer {
            data: ptr::null_mut(),
            len: 0,
        };
    }
    let input = unsafe { std::slice::from_raw_parts(data, len) };
    crate::buffer_from_vec(input.to_vec())
}
