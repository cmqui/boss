use std::collections::VecDeque;
use std::sync::Mutex;

use libboss_rs_core::{BmapFunction, BmapFunctionBlock, BmapOperator};

use crate::*;

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

fn read_i32_buffer(buffer: &BossBuffer) -> Vec<i32> {
    if buffer.data.is_null() || buffer.len == 0 {
        return vec![];
    }
    let byte_count = buffer.len;
    assert_eq!(byte_count % std::mem::size_of::<i32>(), 0);
    unsafe {
        std::slice::from_raw_parts(buffer.data as *const i32, byte_count / std::mem::size_of::<i32>())
            .iter()
            .map(|value| i32::from_le(*value))
            .collect()
    }
}

fn read_bytes(buffer: &BossBuffer) -> Vec<u8> {
    if buffer.data.is_null() || buffer.len == 0 {
        return vec![];
    }
    unsafe { std::slice::from_raw_parts(buffer.data, buffer.len).to_vec() }
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

#[test]
fn ffi_session_audio_mode_capabilities_returns_counts() {
    let context = Box::new(HostContext {
        incoming_packets: Mutex::new(VecDeque::from(vec![packet_bytes(BmapPacket::new(
            BmapFunctionBlock::AudioModes,
            BmapFunction::Unknown {
                block: BmapFunctionBlock::AudioModes,
                raw_value: libboss_rs_core::BossAudioModesCodec::CAPABILITIES_FUNCTION_RAW,
            },
            0,
            0,
            BmapOperator::Status,
            vec![0x03, 0x02],
        ))])),
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

    let mut capabilities = BossFfiAudioModesCapabilities::default();
    assert!(boss_session_audio_mode_capabilities(
        handle,
        &mut capabilities,
        ptr::null_mut(),
    ));
    assert_eq!(capabilities.bose_modes, 3);
    assert_eq!(capabilities.user_modes, 2);

    boss_session_free(handle);
}

#[test]
fn ffi_session_set_favorite_audio_mode_indices_returns_updated_values() {
    let context = Box::new(HostContext {
        incoming_packets: Mutex::new(VecDeque::from(vec![packet_bytes(BmapPacket::new(
            BmapFunctionBlock::AudioModes,
            BmapFunction::Unknown {
                block: BmapFunctionBlock::AudioModes,
                raw_value: libboss_rs_core::BossAudioModesCodec::FAVORITES_FUNCTION_RAW,
            },
            0,
            0,
            BmapOperator::Status,
            vec![0x03, 0x03],
        ))])),
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

    let requested = [0i32, 1i32];
    let mut indices = BossBuffer {
        data: ptr::null_mut(),
        len: 0,
    };
    assert!(boss_session_set_favorite_audio_mode_indices(
        handle,
        3,
        requested.as_ptr(),
        requested.len(),
        &mut indices,
        ptr::null_mut(),
    ));
    assert_eq!(read_i32_buffer(&indices), vec![0, 1]);
    boss_buffer_free(indices);

    boss_session_free(handle);
}

#[test]
fn ffi_ble_segment_packet_returns_expected_frames() {
    let packet = vec![1, 2, 3, 4, 5, 6];
    let mut frames = BossBufferList {
        data: ptr::null_mut(),
        len: 0,
    };

    assert!(boss_ble_segment_packet(
        packet.as_ptr(),
        packet.len(),
        7,
        &mut frames,
        ptr::null_mut(),
    ));

    let frame_slice = unsafe { std::slice::from_raw_parts(frames.data, frames.len) };
    let decoded: Vec<Vec<u8>> = frame_slice
        .iter()
        .map(read_bytes)
        .collect();
    assert_eq!(decoded, vec![vec![0x10, 1, 2, 3], vec![0x11, 4, 5, 6]]);

    boss_buffer_list_free(frames);
}

#[test]
fn ffi_ble_reassembler_push_round_trips_frames() {
    let handle = boss_ble_reassembler_create();
    let frames = [vec![0x10, 1, 2, 3], vec![0x11, 4, 5, 6]];

    let mut packet = BossBuffer {
        data: ptr::null_mut(),
        len: 0,
    };
    let mut has_packet = false;
    assert!(boss_ble_reassembler_push(
        handle,
        frames[0].as_ptr(),
        frames[0].len(),
        &mut packet,
        &mut has_packet,
        ptr::null_mut(),
    ));
    assert!(!has_packet);
    assert!(packet.data.is_null());

    assert!(boss_ble_reassembler_push(
        handle,
        frames[1].as_ptr(),
        frames[1].len(),
        &mut packet,
        &mut has_packet,
        ptr::null_mut(),
    ));
    assert!(has_packet);
    assert_eq!(read_bytes(&packet), vec![1, 2, 3, 4, 5, 6]);
    boss_buffer_free(packet);
    boss_ble_reassembler_free(handle);
}

#[test]
fn ffi_bootstrap_session_returns_device() {
    let context = Box::new(HostContext {
        incoming_packets: Mutex::new(VecDeque::from(vec![
            packet_bytes(BmapPacket::new(
                BmapFunctionBlock::ProductInfo,
                BmapFunction::ProductInfoBmapVersion,
                0,
                0,
                BmapOperator::Status,
                b"1.2.3".to_vec(),
            )),
            packet_bytes(BmapPacket::new(
                BmapFunctionBlock::ProductInfo,
                BmapFunction::ProductInfoProductIdVariants,
                0,
                0,
                BmapOperator::Status,
                vec![0x40, 0x82, 0x01],
            )),
            packet_bytes(BmapPacket::new(
                BmapFunctionBlock::ProductInfo,
                BmapFunction::ProductInfoAllFblocks,
                0,
                0,
                BmapOperator::Status,
                vec![0x20],
            )),
        ])),
        sent_packets: Mutex::new(Vec::new()),
    });
    let context = Box::into_raw(context);
    let mut device = BossFfiBootstrappedDevice::default();
    assert!(boss_bootstrap_session(
        BossFfiSessionCallbacks {
            context: context as *mut c_void,
            transport_kind: 0,
            send_packet_bytes: Some(test_send_packet_bytes),
            next_packet_bytes: Some(test_next_packet_bytes),
            release_context: None,
        },
        &mut device,
        ptr::null_mut(),
    ));

    assert_eq!(device.product_id, 0x4082);
    assert_eq!(device.variant, 0x01);
    assert_eq!(device.transport_kind, 0);
    assert_eq!(
        &device.bmap_version_bytes[..device.bmap_version_len],
        b"1.2.3"
    );
    assert_eq!(
        &device.product_name_bytes[..device.product_name_len],
        b"Bose QC Ultra 2 HP"
    );

    unsafe {
        drop(Box::from_raw(context));
    }
}
