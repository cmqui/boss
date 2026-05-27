use std::ptr;

use libboss_core::{BleSegmentReassembler, BleSegmentation};

use crate::{
    buffer_from_vec, buffer_list_from_vec, invalid_argument_error, other_error, write_error,
    BossBuffer, BossBufferList, BossFfiError,
};

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
