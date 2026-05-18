use std::collections::BTreeMap;

use libboss_rs_core::*;

#[test]
fn packet_codec_encodes_and_decodes() {
    let packet = BmapPacket::new(
        BmapFunctionBlock::ProductInfo,
        BmapFunction::ProductInfoBmapVersion,
        2,
        1,
        BmapOperator::Get,
        vec![0xAA, 0xBB],
    );

    let encoded = BmapCodec::encode(&packet).unwrap();
    assert_eq!(encoded, vec![0x00, 0x01, 0x91, 0x02, 0xAA, 0xBB]);
    let decoded = BmapCodec::decode(&encoded).unwrap();
    assert_eq!(decoded, packet);
}

#[test]
fn packet_decode_preserves_unknown_values() {
    let decoded = BmapCodec::decode(&[0x7E, 0x55, 0xF9, 0x00]).unwrap();
    assert_eq!(decoded.function_block, BmapFunctionBlock::Unknown(0x7E));
    assert_eq!(
        decoded.function,
        BmapFunction::Unknown {
            block: BmapFunctionBlock::Unknown(0x7E),
            raw_value: 0x55
        }
    );
    assert_eq!(decoded.operator, BmapOperator::Unknown(0x09));
    assert_eq!(decoded.device_id, 3);
    assert_eq!(decoded.port, 3);
}

#[test]
fn ble_segmentation_and_reassembly_round_trip() {
    let payload: Vec<u8> = (0..40).collect();
    let frames = BleSegmentation::encode(&payload, 23).unwrap();
    assert_eq!(frames.len(), 3);
    let mut reassembler = BleSegmentReassembler::default();
    assert!(reassembler.push(&frames[0]).unwrap().is_none());
    assert!(reassembler.push(&frames[1]).unwrap().is_none());
    assert_eq!(reassembler.push(&frames[2]).unwrap(), Some(payload));
}

#[test]
fn stream_decoder_handles_multiple_packets_and_leftovers() {
    let first = BmapCodec::encode(&ProductInfoCommands::bmap_version(0, 0)).unwrap();
    let second = BmapCodec::encode(&ProductInfoCommands::product_id_variant(0, 0)).unwrap();
    let mut combined = first.clone();
    combined.extend_from_slice(&second);

    let mut decoder = BmapFrameStreamDecoder::default();
    let partial = decoder.push(&combined[..5]).unwrap();
    assert_eq!(partial.len(), 1);
    let remainder = decoder.push(&combined[5..]).unwrap();
    assert_eq!(remainder.len(), 1);
    assert_eq!(remainder[0].function, BmapFunction::ProductInfoProductIdVariants);
}

#[test]
fn function_block_set_honors_implicit_product_info() {
    let set = FunctionBlockSet::from_bytes(&[0x00, 0x06]);
    assert!(set.contains(BmapFunctionBlock::ProductInfo));
    assert!(set.contains(BmapFunctionBlock::Settings));
    assert!(set.contains(BmapFunctionBlock::Status));
}

#[test]
fn product_info_parsing_matches_swift_behavior() {
    let version = ProductInfoParser::parse_bmap_version(&BmapPacket::new(
        BmapFunctionBlock::ProductInfo,
        BmapFunction::ProductInfoBmapVersion,
        0,
        0,
        BmapOperator::Status,
        b"1.2.3".to_vec(),
    ))
    .unwrap();
    assert_eq!(version.version, "1.2.3");

    let black = ProductInfoParser::parse_product_id_variant(&BmapPacket::new(
        BmapFunctionBlock::ProductInfo,
        BmapFunction::ProductInfoProductIdVariants,
        0,
        0,
        BmapOperator::Status,
        vec![0x40, 0x82, 0x01],
    ))
    .unwrap();
    assert_eq!(black.product_id, 0x4082);
    assert_eq!(black.product.unwrap().display_name, "Bose QC Ultra 2 HP");
    assert_eq!(black.variant_name, Some("WolverineBlack"));
}

#[test]
fn standby_timer_and_on_head_detection_codecs_match() {
    let packet = BossSettingsCodec::standby_timer_set_get_packet(300).unwrap();
    assert_eq!(packet.payload, vec![0x2C, 0x01]);

    let packet = BossSettingsCodec::on_head_detection_set_get_packet(&BossOnHeadDetectionValue {
        is_enabled: true,
        is_auto_play_enabled: Some(true),
        is_auto_answer_enabled: Some(false),
        is_auto_transparency_enabled: Some(true),
    });
    assert_eq!(packet.payload, vec![0x01, 0x05]);
}

#[test]
fn equalizer_parser_reads_signed_range_levels() {
    let packet = BmapPacket::new(
        BmapFunctionBlock::Settings,
        BmapFunction::Unknown { block: BmapFunctionBlock::Settings, raw_value: BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW },
        0,
        0,
        BmapOperator::Status,
        vec![0xF6, 0x0A, 0x03, 0x00, 0xF6, 0x0A, 0xFE, 0x01, 0xF6, 0x0A, 0x05, 0x02],
    );
    let equalizer = BossSettingsCodec::parse_equalizer(&packet).unwrap();
    assert_eq!(equalizer.range(&BossEqualizerBand::Bass).unwrap().current_level, 3);
    assert_eq!(equalizer.range(&BossEqualizerBand::Mid).unwrap().current_level, -2);
    assert_eq!(equalizer.range(&BossEqualizerBand::Treble).unwrap().current_level, 5);
}

#[test]
fn audio_mode_codecs_match_supported_prompt_and_favorites_logic() {
    let packet = BmapPacket::new(
        BmapFunctionBlock::AudioModes,
        BmapFunction::Unknown { block: BmapFunctionBlock::AudioModes, raw_value: BossAudioModesCodec::NAMES_SUPPORTED_FUNCTION_RAW },
        0,
        0,
        BmapOperator::Status,
        vec![0b0000_0111, 0, 0, 0, 0],
    );
    let prompts = BossAudioModesCodec::parse_supported_prompts(&packet).unwrap();
    assert_eq!(prompts[0].name, "None");
    assert_eq!(prompts[1].name, "Quiet");
    assert_eq!(prompts[2].name, "Aware");

    let payload = BossAudioModesCodec::encode_favorites(10, &[0, 1, 9]).unwrap();
    let favorites = BossAudioModesCodec::parse_favorites(&BmapPacket::new(
        BmapFunctionBlock::AudioModes,
        BmapFunction::Unknown { block: BmapFunctionBlock::AudioModes, raw_value: BossAudioModesCodec::FAVORITES_FUNCTION_RAW },
        0,
        0,
        BmapOperator::Status,
        payload,
    ))
    .unwrap();
    assert_eq!(favorites, vec![0, 1, 9]);
}

#[test]
fn audio_mode_config_parser_reads_index_name_and_flags() {
    let mut payload = vec![0u8; 48];
    payload[0] = 0x02;
    payload[1] = 0x00;
    payload[2] = 0x22;
    payload[3] = 0x01;
    payload[4] = 0x00;
    payload[5] = 0x01;
    payload[41] = 0x1D;
    payload[42] = 0x05;
    payload[44] = 0x02;
    payload[45] = 0x7F;
    payload[46] = 0x01;
    payload[47] = 0x01;
    let name = b"Immersion";
    payload[6..(6 + name.len())].copy_from_slice(name);

    let packet = BmapPacket::new(
        BmapFunctionBlock::AudioModes,
        BmapFunction::Unknown { block: BmapFunctionBlock::AudioModes, raw_value: BossAudioModesCodec::MODE_CONFIG_FUNCTION_RAW },
        0,
        0,
        BmapOperator::Status,
        payload,
    );
    let config = BossAudioModesCodec::parse_mode_config_detail(&packet).unwrap();
    assert_eq!(config.mode_index, 2);
    assert_eq!(config.prompt.name, "Immersion");
    assert_eq!(config.name, "Immersion");
    assert!(config.favorite);
    assert!(config.user_configurable);
    assert!(!config.user_configured);
    assert_eq!(config.settings.cnc_level, 5);
    assert_eq!(config.settings.spatial_audio_mode, BossSpatialAudioMode::Head);
    assert!(config.settings.wind_block_enabled);
    assert!(config.settings.anc_toggle_enabled);
}

#[test]
fn settings_snapshot_falls_back_to_composite_auto_answer() {
    let mut packets = BTreeMap::new();
    packets.insert(
        BossSettingsCodec::ON_HEAD_DETECTION_FUNCTION_RAW,
        BmapPacket::new(
            BmapFunctionBlock::Settings,
            BmapFunction::Unknown { block: BmapFunctionBlock::Settings, raw_value: BossSettingsCodec::ON_HEAD_DETECTION_FUNCTION_RAW },
            0,
            0,
            BmapOperator::Status,
            vec![0x05, 0x00],
        ),
    );
    let snapshot = BossSettingsSnapshot::new(packets);
    assert_eq!(snapshot.auto_answer().unwrap(), Some(false));
}
