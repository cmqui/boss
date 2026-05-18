#[cfg(test)]
mod tests {
    use futures::executor::block_on;
    use libboss_rs_core::{
        BmapErrorCode, BmapFunction, BmapFunctionBlock, BmapOperator, BmapPacket, BossAudioModeConfig,
        BossAudioModePrompt, BossAudioModeSettingsConfig, BossAudioModeSettingsConfigPatch, BossAudioModesCodec,
        BossEqualizerBand, BossEqualizerSettingsPatch, BossOnHeadDetectionValue, BossSettingsCodec,
        BossSpatialAudioMode, BossVolumeControlValue,
    };

    use crate::test_support::MockLink;
    use crate::{
        BossAudioModeSettingsWriteResult, BossCurrentAudioModeWriteResult, BossDeviceSettingsReport,
        BossEqualizerWriteResult, BossObservedSetting, BossSession, BossSessionError, BossSettingSource,
        BossSettingUnavailableReason, BootstrapSession, BootstrapSessionError, BootstrapTimeoutError, PacketSession,
        SessionConfiguration,
    };

    #[test]
    fn packet_session_awaits_matching_response() {
        block_on(async {
            let target_packet = BmapPacket::new(
                BmapFunctionBlock::ProductInfo,
                BmapFunction::ProductInfoProductIdVariants,
                0,
                0,
                BmapOperator::Status,
                vec![0x40, 0x82, 0x01],
            );
            let link = MockLink::new(vec![Ok(Some(target_packet.clone()))]);
            let session = PacketSession::new(link);

            let received = session
                .first_packet_matching(
                    |packet| packet.function == BmapFunction::ProductInfoProductIdVariants,
                    1_000,
                )
                .await
                .unwrap();

            assert_eq!(received, target_packet);
        });
    }

    #[test]
    fn packet_session_builds_settings_snapshot_from_status_packets() {
        block_on(async {
            let snapshot_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::AUTO_PLAY_PAUSE_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x01],
            );
            let result_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::SETTINGS_GET_ALL_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Result,
                vec![],
            );
            let link = MockLink::new(vec![Ok(Some(snapshot_packet)), Ok(Some(result_packet))]);
            let session = PacketSession::new(link);

            let snapshot = session.settings_snapshot(1_000).await.unwrap();
            assert_eq!(snapshot.auto_play_pause().unwrap(), Some(true));
        });
    }

    #[test]
    fn packet_session_surfaces_generic_bmap_response_error() {
        block_on(async {
            let error_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::CURRENT_MODE_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Error,
                vec![BmapErrorCode::Timeout as u8],
            );
            let link = MockLink::new(vec![Ok(Some(error_packet))]);
            let session = PacketSession::new(link);

            let error = session.current_audio_mode(1_000).await.unwrap_err();
            match error {
                BossSessionError::BmapErrorResponse(response) => {
                    assert_eq!(response.context, "audioModes.Unknown(31:3)");
                    assert_eq!(response.payload_hex, "09");
                    assert_eq!(response.code(), Some(BmapErrorCode::Timeout));
                }
                other => panic!("unexpected error: {other:?}"),
            }
        });
    }

    #[test]
    fn boss_session_reads_firmware_version() {
        block_on(async {
            let packet = BmapPacket::new(
                BmapFunctionBlock::ProductInfo,
                BmapFunction::ProductInfoFirmwareVersion,
                0,
                2,
                BmapOperator::Status,
                b"9.9.9".to_vec(),
            );
            let link = MockLink::new(vec![Ok(Some(packet))]);
            let session = BossSession::new(PacketSession::new(link));

            let firmware = session.firmware_version(2, 0, 1_000).await.unwrap();
            assert_eq!(firmware.version, "9.9.9");
            assert_eq!(firmware.port, 2);
        });
    }

    #[test]
    fn bootstrap_session_success() {
        block_on(async {
            let link = MockLink::new(vec![
                Ok(Some(BmapPacket::new(
                    BmapFunctionBlock::ProductInfo,
                    BmapFunction::ProductInfoBmapVersion,
                    0,
                    0,
                    BmapOperator::Status,
                    b"1.0.0".to_vec(),
                ))),
                Ok(Some(BmapPacket::new(
                    BmapFunctionBlock::ProductInfo,
                    BmapFunction::ProductInfoProductIdVariants,
                    0,
                    0,
                    BmapOperator::Status,
                    vec![0x40, 0x82, 0x02],
                ))),
                Ok(Some(BmapPacket::new(
                    BmapFunctionBlock::ProductInfo,
                    BmapFunction::ProductInfoAllFblocks,
                    0,
                    0,
                    BmapOperator::Status,
                    vec![0x00, 0x06],
                ))),
            ]);
            let session = BootstrapSession::new(
                link.clone(),
                SessionConfiguration {
                    first_version_timeout_millis: 50,
                    retry_version_timeout_millis: 100,
                    request_timeout_millis: 50,
                    ..Default::default()
                },
            );

            let device = session.bootstrap().await.unwrap();
            assert_eq!(device.bmap_version.version, "1.0.0");
            assert_eq!(device.product_id, 0x4082);
            assert_eq!(device.product_variant.variant_name, Some("WolverineWhiteSmoke"));
            assert!(device.supported_function_blocks.contains(BmapFunctionBlock::Settings));
            assert_eq!(device.transport_kind, libboss_rs_core::BossTransportKind::Stream);
            assert_eq!(link.sent_packets().len(), 3);
        });
    }

    #[test]
    fn bootstrap_session_retries_version_request() {
        block_on(async {
            let link = MockLink::new(vec![
                Err(crate::BossLinkError::TimedOut),
                Ok(Some(BmapPacket::new(
                    BmapFunctionBlock::ProductInfo,
                    BmapFunction::ProductInfoBmapVersion,
                    0,
                    0,
                    BmapOperator::Status,
                    b"1.0.1".to_vec(),
                ))),
                Ok(Some(BmapPacket::new(
                    BmapFunctionBlock::ProductInfo,
                    BmapFunction::ProductInfoProductIdVariants,
                    0,
                    0,
                    BmapOperator::Status,
                    vec![0x40, 0x82, 0x01],
                ))),
                Ok(Some(BmapPacket::new(
                    BmapFunctionBlock::ProductInfo,
                    BmapFunction::ProductInfoAllFblocks,
                    0,
                    0,
                    BmapOperator::Status,
                    vec![0x00],
                ))),
            ]);
            let session = BootstrapSession::new(
                link.clone(),
                SessionConfiguration {
                    first_version_timeout_millis: 5,
                    retry_version_timeout_millis: 100,
                    request_timeout_millis: 50,
                    ..Default::default()
                },
            );

            session.bootstrap().await.unwrap();
            let version_requests = link
                .sent_packets()
                .into_iter()
                .filter(|packet| packet.function == BmapFunction::ProductInfoBmapVersion)
                .count();
            assert_eq!(version_requests, 2);
        });
    }

    #[test]
    fn bootstrap_session_fails_on_unexpected_operator() {
        block_on(async {
            let link = MockLink::new(vec![Ok(Some(BmapPacket::new(
                BmapFunctionBlock::ProductInfo,
                BmapFunction::ProductInfoBmapVersion,
                0,
                0,
                BmapOperator::Error,
                vec![0x00],
            )))]);
            let session = BootstrapSession::new(
                link,
                SessionConfiguration {
                    first_version_timeout_millis: 50,
                    retry_version_timeout_millis: 50,
                    request_timeout_millis: 50,
                    ..Default::default()
                },
            );

            let error = session.bootstrap().await.unwrap_err();
            match error {
                BootstrapSessionError::Session(BossSessionError::UnexpectedOperator(actual)) => {
                    assert_eq!(actual.expected, BmapOperator::Status);
                    assert_eq!(actual.actual, BmapOperator::Error);
                }
                other => panic!("unexpected error: {other:?}"),
            }
        });
    }

    #[test]
    fn bootstrap_session_times_out() {
        block_on(async {
            let link = MockLink::new(vec![
                Err(crate::BossLinkError::TimedOut),
                Err(crate::BossLinkError::TimedOut),
            ]);
            let session = BootstrapSession::new(
                link,
                SessionConfiguration {
                    first_version_timeout_millis: 5,
                    retry_version_timeout_millis: 5,
                    request_timeout_millis: 5,
                    ..Default::default()
                },
            );

            let error = session.bootstrap().await.unwrap_err();
            assert_eq!(
                error,
                BootstrapSessionError::Timeout(BootstrapTimeoutError::BmapVersion {
                    timeout_milliseconds: 5,
                })
            );
        });
    }

    #[test]
    fn packet_session_reads_supported_audio_mode_prompts() {
        block_on(async {
            let packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::NAMES_SUPPORTED_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0b0000_0111, 0, 0, 0, 0],
            );
            let session = PacketSession::new(MockLink::new(vec![Ok(Some(packet))]));
            let prompts = session.supported_audio_mode_prompts(1_000).await.unwrap();
            assert_eq!(prompts.iter().map(|prompt| prompt.name).collect::<Vec<_>>(), vec!["None", "Quiet", "Aware"]);
        });
    }

    #[test]
    fn packet_session_reads_audio_mode_configs() {
        block_on(async {
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
            payload[46] = 0x01;
            payload[47] = 0x01;
            let name = b"Immersion";
            payload[6..(6 + name.len())].copy_from_slice(name);

            let status_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::MODE_CONFIG_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                payload,
            );
            let result_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::MODE_CONFIG_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Result,
                vec![],
            );
            let session = PacketSession::new(MockLink::new(vec![Ok(Some(status_packet)), Ok(Some(result_packet))]));
            let configs = session.audio_mode_configs(1_000).await.unwrap();
            assert_eq!(configs.len(), 1);
            assert_eq!(configs[0].name, "Immersion");
            assert_eq!(configs[0].settings.cnc_level, 5);
        });
    }

    #[test]
    fn packet_session_reads_audio_mode_settings_config() {
        block_on(async {
            let packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::SETTINGS_CONFIG_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x05, 0x01, 0x02, 0x01, 0x00],
            );
            let session = PacketSession::new(MockLink::new(vec![Ok(Some(packet))]));
            let config = session.audio_mode_settings_config(1_000).await.unwrap();
            assert_eq!(
                config,
                BossAudioModeSettingsConfig {
                    cnc_level: 5,
                    auto_cnc_enabled: true,
                    spatial_audio_mode: BossSpatialAudioMode::Head,
                    wind_block_enabled: true,
                    anc_toggle_enabled: false,
                }
            );
        });
    }

    #[test]
    fn boss_session_audio_mode_catalog_reducer_updates_favorites() {
        let initial = vec![
            BossAudioModeConfig {
                mode_index: 0,
                prompt: BossAudioModePrompt::NONE,
                name: "Quiet".into(),
                favorite: false,
                user_configurable: false,
                user_configured: false,
                settings: BossAudioModeSettingsConfig {
                    cnc_level: 5,
                    auto_cnc_enabled: false,
                    spatial_audio_mode: BossSpatialAudioMode::Off,
                    wind_block_enabled: false,
                    anc_toggle_enabled: false,
                },
            },
            BossAudioModeConfig {
                mode_index: 1,
                prompt: BossAudioModePrompt::NONE,
                name: "Aware".into(),
                favorite: false,
                user_configurable: false,
                user_configured: false,
                settings: BossAudioModeSettingsConfig {
                    cnc_level: 2,
                    auto_cnc_enabled: false,
                    spatial_audio_mode: BossSpatialAudioMode::Off,
                    wind_block_enabled: false,
                    anc_toggle_enabled: false,
                },
            },
        ];
        let packet = BmapPacket::new(
            BmapFunctionBlock::AudioModes,
            BmapFunction::Unknown {
                block: BmapFunctionBlock::AudioModes,
                raw_value: BossAudioModesCodec::FAVORITES_FUNCTION_RAW,
            },
            0,
            0,
            BmapOperator::Status,
            vec![0x02, 0x02],
        );

        let reduced = BossSession::<MockLink>::reduce_audio_mode_catalog(&initial, &packet)
            .unwrap()
            .unwrap();
        assert_eq!(reduced.iter().map(|mode| mode.favorite).collect::<Vec<_>>(), vec![false, true]);
    }

    #[test]
    fn boss_session_audio_mode_catalog_reducer_upserts_mode_config() {
        let initial = vec![BossAudioModeConfig {
            mode_index: 1,
            prompt: BossAudioModePrompt::NONE,
            name: "Aware".into(),
            favorite: false,
            user_configurable: false,
            user_configured: false,
            settings: BossAudioModeSettingsConfig {
                cnc_level: 2,
                auto_cnc_enabled: false,
                spatial_audio_mode: BossSpatialAudioMode::Off,
                wind_block_enabled: false,
                anc_toggle_enabled: false,
            },
        }];
        let mut payload = Vec::new();
        payload.extend_from_slice(&[0x03, 0x00, 0x00]);
        payload.extend_from_slice(b"Custom");
        payload.extend(std::iter::repeat(0x00).take(32 - 6));
        payload.extend_from_slice(&[0x06, 0x01, BossSpatialAudioMode::Head.raw_value(), 0x01, 0x01]);
        let packet = BmapPacket::new(
            BmapFunctionBlock::AudioModes,
            BmapFunction::Unknown {
                block: BmapFunctionBlock::AudioModes,
                raw_value: BossAudioModesCodec::MODE_CONFIG_FUNCTION_RAW,
            },
            0,
            0,
            BmapOperator::Status,
            payload,
        );

        let reduced = BossSession::<MockLink>::reduce_audio_mode_catalog(&initial, &packet)
            .unwrap()
            .unwrap();
        assert_eq!(reduced.iter().map(|mode| mode.mode_index).collect::<Vec<_>>(), vec![1, 3]);
        assert_eq!(reduced.last().unwrap().name, "Custom");
        assert_eq!(reduced.last().unwrap().settings.spatial_audio_mode, BossSpatialAudioMode::Head);
    }

    #[test]
    fn boss_session_device_settings_reducer_updates_standalone_flags() {
        let initial = BossDeviceSettingsReport {
            wear_detection: BossObservedSetting {
                value: None,
                source: None,
                unavailable_reason: Some(BossSettingUnavailableReason::MissingFromSnapshot),
            },
            auto_aware_enabled: BossObservedSetting {
                value: None,
                source: None,
                unavailable_reason: Some(BossSettingUnavailableReason::MissingFromSnapshot),
            },
            auto_play_pause_enabled: BossObservedSetting {
                value: None,
                source: None,
                unavailable_reason: Some(BossSettingUnavailableReason::MissingFromSnapshot),
            },
            auto_answer_enabled: BossObservedSetting {
                value: None,
                source: None,
                unavailable_reason: Some(BossSettingUnavailableReason::MissingFromSnapshot),
            },
            volume_control: BossObservedSetting {
                value: None,
                source: None,
                unavailable_reason: Some(BossSettingUnavailableReason::MissingFromSnapshot),
            },
        };
        let packet = BmapPacket::new(
            BmapFunctionBlock::Settings,
            BmapFunction::Unknown {
                block: BmapFunctionBlock::Settings,
                raw_value: BossSettingsCodec::AUTO_AWARE_FUNCTION_RAW,
            },
            0,
            0,
            BmapOperator::Status,
            vec![0x01],
        );
        let reduced = BossSession::<MockLink>::reduce_device_settings_report(&initial, &packet)
            .unwrap()
            .unwrap();
        assert_eq!(reduced.auto_aware_enabled.value, Some(true));
        assert_eq!(reduced.auto_aware_enabled.source, Some(BossSettingSource::Snapshot));
        assert_eq!(reduced.wear_detection, initial.wear_detection);
    }

    #[test]
    fn boss_session_device_settings_reducer_derives_auto_answer_from_on_head_detection() {
        let initial = BossDeviceSettingsReport {
            wear_detection: BossObservedSetting {
                value: None,
                source: None,
                unavailable_reason: Some(BossSettingUnavailableReason::MissingFromSnapshot),
            },
            auto_aware_enabled: BossObservedSetting {
                value: None,
                source: None,
                unavailable_reason: Some(BossSettingUnavailableReason::MissingFromSnapshot),
            },
            auto_play_pause_enabled: BossObservedSetting {
                value: None,
                source: None,
                unavailable_reason: Some(BossSettingUnavailableReason::MissingFromSnapshot),
            },
            auto_answer_enabled: BossObservedSetting {
                value: None,
                source: None,
                unavailable_reason: Some(BossSettingUnavailableReason::MissingFromSnapshot),
            },
            volume_control: BossObservedSetting {
                value: None,
                source: None,
                unavailable_reason: Some(BossSettingUnavailableReason::MissingFromSnapshot),
            },
        };
        let packet = BmapPacket::new(
            BmapFunctionBlock::Settings,
            BmapFunction::Unknown {
                block: BmapFunctionBlock::Settings,
                raw_value: BossSettingsCodec::ON_HEAD_DETECTION_FUNCTION_RAW,
            },
            0,
            0,
            BmapOperator::Status,
            vec![0x05, 0x02],
        );
        let reduced = BossSession::<MockLink>::reduce_device_settings_report(&initial, &packet)
            .unwrap()
            .unwrap();
        assert_eq!(
            reduced.wear_detection.value,
            Some(BossOnHeadDetectionValue {
                is_enabled: true,
                is_auto_play_enabled: None,
                is_auto_answer_enabled: Some(true),
                is_auto_transparency_enabled: None,
            })
        );
        assert_eq!(reduced.wear_detection.source, Some(BossSettingSource::Snapshot));
        assert_eq!(reduced.auto_answer_enabled.value, Some(true));
        assert_eq!(reduced.auto_answer_enabled.source, Some(BossSettingSource::CompositeSnapshot));
    }

    #[test]
    fn packet_session_reads_and_sets_favorites() {
        block_on(async {
            let get_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::FAVORITES_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x03, 0x05],
            );
            let set_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::FAVORITES_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x03, 0x03],
            );
            let link = MockLink::new(vec![Ok(Some(get_packet)), Ok(Some(set_packet))]);
            let session = PacketSession::new(link);

            let favorites = session.favorite_audio_mode_indices(1_000).await.unwrap();
            assert_eq!(favorites, vec![0, 2]);

            let updated = session
                .set_favorite_audio_mode_indices(3, &[0, 1], 1_000)
                .await
                .unwrap();
            assert_eq!(updated, vec![0, 1]);
        });
    }

    #[test]
    fn packet_session_reads_and_sets_enabled_setting() {
        block_on(async {
            let get_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::AUTO_AWARE_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x01],
            );
            let set_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::AUTO_AWARE_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x00],
            );
            let session = PacketSession::new(MockLink::new(vec![Ok(Some(get_packet)), Ok(Some(set_packet))]));
            assert!(session.enabled_setting(BossSettingsCodec::AUTO_AWARE_FUNCTION_RAW, 1_000).await.unwrap());
            assert!(!session
                .set_enabled_setting(BossSettingsCodec::AUTO_AWARE_FUNCTION_RAW, false, 1_000)
                .await
                .unwrap());
        });
    }

    #[test]
    fn packet_session_reads_and_sets_on_head_detection() {
        block_on(async {
            let get_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::ON_HEAD_DETECTION_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x05, 0x02],
            );
            let set_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::ON_HEAD_DETECTION_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x0F, 0x05],
            );
            let session = PacketSession::new(MockLink::new(vec![Ok(Some(get_packet)), Ok(Some(set_packet))]));
            let read = session.on_head_detection(1_000).await.unwrap();
            assert_eq!(read.is_auto_answer_enabled, Some(true));

            let updated = session
                .set_on_head_detection(
                    &BossOnHeadDetectionValue {
                        is_enabled: true,
                        is_auto_play_enabled: Some(true),
                        is_auto_answer_enabled: Some(false),
                        is_auto_transparency_enabled: Some(true),
                    },
                    1_000,
                )
                .await
                .unwrap();
            assert_eq!(updated.is_auto_play_enabled, Some(true));
            assert_eq!(updated.is_auto_answer_enabled, Some(false));
            assert_eq!(updated.is_auto_transparency_enabled, Some(true));
        });
    }

    #[test]
    fn packet_session_reads_and_sets_volume_control() {
        block_on(async {
            let get_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::VOLUME_CONTROL_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![BossVolumeControlValue::CapTouch.raw_value(), 0x03],
            );
            let set_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::VOLUME_CONTROL_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![BossVolumeControlValue::Button.raw_value(), 0x03],
            );
            let session = PacketSession::new(MockLink::new(vec![Ok(Some(get_packet)), Ok(Some(set_packet))]));
            let read = session.volume_control_status(1_000).await.unwrap();
            assert_eq!(read.value, BossVolumeControlValue::CapTouch);
            assert_eq!(read.supported_values.unwrap(), vec![BossVolumeControlValue::Button, BossVolumeControlValue::CapTouch]);

            let updated = session
                .set_volume_control(BossVolumeControlValue::Button, 1_000)
                .await
                .unwrap();
            assert_eq!(updated.value, BossVolumeControlValue::Button);
        });
    }

    #[test]
    fn packet_session_sets_equalizer_across_multiple_requests() {
        block_on(async {
            let response_one = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0xF6, 0x0A, 0x03, 0x00, 0xF6, 0x0A, 0x00, 0x01, 0xF6, 0x0A, 0x00, 0x02],
            );
            let response_two = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0xF6, 0x0A, 0x03, 0x00, 0xF6, 0x0A, 0xFD, 0x01, 0xF6, 0x0A, 0x00, 0x02],
            );
            let session = PacketSession::new(MockLink::new(vec![Ok(Some(response_one)), Ok(Some(response_two))]));
            let settings = session
                .set_equalizer(&[(BossEqualizerBand::Bass, 3), (BossEqualizerBand::Mid, -3)], 1_000)
                .await
                .unwrap();
            assert_eq!(settings.range(&BossEqualizerBand::Bass).unwrap().current_level, 3);
            assert_eq!(settings.range(&BossEqualizerBand::Mid).unwrap().current_level, -3);
        });
    }

    #[test]
    fn boss_session_set_current_audio_mode_returns_unchanged_when_already_selected() {
        block_on(async {
            let current_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::CURRENT_MODE_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x02],
            );
            let session = BossSession::new(PacketSession::new(MockLink::new(vec![Ok(Some(current_packet))])));

            let result = session.set_current_audio_mode(2, false).await.unwrap();
            assert_eq!(result, BossCurrentAudioModeWriteResult::Unchanged(2));
        });
    }

    #[test]
    fn boss_session_set_current_audio_mode_returns_updated_from_start_response() {
        block_on(async {
            let current_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::CURRENT_MODE_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x01],
            );
            let start_response = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::CURRENT_MODE_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Result,
                vec![0x03],
            );
            let session = BossSession::new(PacketSession::new(MockLink::new(vec![
                Ok(Some(current_packet)),
                Ok(Some(start_response)),
            ])));

            let result = session.set_current_audio_mode(3, true).await.unwrap();
            assert_eq!(result, BossCurrentAudioModeWriteResult::Updated(3));
        });
    }

    #[test]
    fn boss_session_set_current_audio_mode_verifies_after_recoverable_failure() {
        block_on(async {
            let initial_current = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::CURRENT_MODE_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x01],
            );
            let verified_current = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::CURRENT_MODE_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x03],
            );
            let session = BossSession::new(PacketSession::new(MockLink::new(vec![
                Ok(Some(initial_current)),
                Err(crate::BossLinkError::TimedOut),
                Ok(Some(verified_current)),
            ])));

            let result = session.set_current_audio_mode(3, false).await.unwrap();
            assert_eq!(result, BossCurrentAudioModeWriteResult::Updated(3));
        });
    }

    #[test]
    fn boss_session_set_audio_mode_settings_returns_unchanged_when_patch_is_noop() {
        block_on(async {
            let current_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::SETTINGS_CONFIG_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x05, 0x01, 0x02, 0x01, 0x00],
            );
            let session = BossSession::new(PacketSession::new(MockLink::new(vec![Ok(Some(current_packet))])));

            let result = session
                .set_audio_mode_settings(BossAudioModeSettingsConfigPatch {
                    cnc_level: Some(5),
                    auto_cnc_enabled: Some(true),
                    spatial_audio_mode: Some(BossSpatialAudioMode::Head),
                    wind_block_enabled: Some(true),
                    anc_toggle_enabled: Some(false),
                })
                .await
                .unwrap();

            assert_eq!(
                result,
                BossAudioModeSettingsWriteResult::Unchanged(BossAudioModeSettingsConfig {
                    cnc_level: 5,
                    auto_cnc_enabled: true,
                    spatial_audio_mode: BossSpatialAudioMode::Head,
                    wind_block_enabled: true,
                    anc_toggle_enabled: false,
                })
            );
        });
    }

    #[test]
    fn boss_session_set_audio_mode_settings_returns_updated_when_set_get_matches_patch() {
        block_on(async {
            let current_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::SETTINGS_CONFIG_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x05, 0x01, 0x02, 0x00, 0x00],
            );
            let updated_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::SETTINGS_CONFIG_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x07, 0x01, 0x02, 0x01, 0x00],
            );
            let session = BossSession::new(PacketSession::new(MockLink::new(vec![
                Ok(Some(current_packet)),
                Ok(Some(updated_packet)),
            ])));

            let result = session
                .set_audio_mode_settings(BossAudioModeSettingsConfigPatch {
                    cnc_level: Some(7),
                    wind_block_enabled: Some(true),
                    ..Default::default()
                })
                .await
                .unwrap();

            assert_eq!(
                result,
                BossAudioModeSettingsWriteResult::Updated(BossAudioModeSettingsConfig {
                    cnc_level: 7,
                    auto_cnc_enabled: true,
                    spatial_audio_mode: BossSpatialAudioMode::Head,
                    wind_block_enabled: true,
                    anc_toggle_enabled: false,
                })
            );
        });
    }

    #[test]
    fn boss_session_set_equalizer_returns_unchanged_when_patch_does_not_change_levels() {
        block_on(async {
            let current_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0xF6, 0x0A, 0x03, 0x00, 0xF6, 0x0A, 0xFD, 0x01, 0xF6, 0x0A, 0x00, 0x02],
            );
            let session = BossSession::new(PacketSession::new(MockLink::new(vec![Ok(Some(current_packet))])));

            let result = session
                .set_equalizer_verified(BossEqualizerSettingsPatch {
                    bass: Some(3),
                    mid: Some(-3),
                    treble: Some(0),
                })
                .await
                .unwrap();

            match result {
                BossEqualizerWriteResult::Unchanged(settings) => {
                    assert_eq!(settings.range(&BossEqualizerBand::Bass).unwrap().current_level, 3);
                    assert_eq!(settings.range(&BossEqualizerBand::Mid).unwrap().current_level, -3);
                    assert_eq!(settings.range(&BossEqualizerBand::Treble).unwrap().current_level, 0);
                }
                other => panic!("unexpected result: {other:?}"),
            }
        });
    }

    #[test]
    fn boss_session_set_equalizer_returns_updated_when_write_matches_patch() {
        block_on(async {
            let current_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0xF6, 0x0A, 0x00, 0x00, 0xF6, 0x0A, 0x00, 0x01, 0xF6, 0x0A, 0x00, 0x02],
            );
            let updated_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0xF6, 0x0A, 0x03, 0x00, 0xF6, 0x0A, 0xFD, 0x01, 0xF6, 0x0A, 0x00, 0x02],
            );
            let session = BossSession::new(PacketSession::new(MockLink::new(vec![
                Ok(Some(current_packet)),
                Ok(Some(updated_packet.clone())),
                Ok(Some(updated_packet)),
            ])));

            let result = session
                .set_equalizer_verified(BossEqualizerSettingsPatch {
                    bass: Some(3),
                    mid: Some(-3),
                    ..Default::default()
                })
                .await
                .unwrap();

            match result {
                BossEqualizerWriteResult::Updated(settings) => {
                    assert_eq!(settings.range(&BossEqualizerBand::Bass).unwrap().current_level, 3);
                    assert_eq!(settings.range(&BossEqualizerBand::Mid).unwrap().current_level, -3);
                }
                other => panic!("unexpected result: {other:?}"),
            }
        });
    }

    #[test]
    fn boss_session_set_current_audio_mode_returns_verification_inconclusive_when_target_is_not_observed() {
        block_on(async {
            let initial_current = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::CURRENT_MODE_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x01],
            );
            let observed_current = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::CURRENT_MODE_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x02],
            );
            let session = BossSession::new(PacketSession::new(MockLink::new(vec![
                Ok(Some(initial_current)),
                Err(crate::BossLinkError::TimedOut),
                Ok(Some(observed_current.clone())),
                Ok(Some(observed_current.clone())),
                Ok(Some(observed_current.clone())),
                Ok(Some(observed_current)),
            ])));

            let result = session.set_current_audio_mode(3, false).await.unwrap();
            assert_eq!(
                result,
                BossCurrentAudioModeWriteResult::VerificationInconclusive { target_index: 3 }
            );
        });
    }

    #[test]
    fn boss_session_set_audio_mode_settings_recovers_from_busy_bmap_error_via_reread() {
        block_on(async {
            let current_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::SETTINGS_CONFIG_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x05, 0x01, 0x02, 0x00, 0x00],
            );
            let busy_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::SETTINGS_CONFIG_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Error,
                vec![BmapErrorCode::Busy as u8],
            );
            let verified_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::SETTINGS_CONFIG_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x07, 0x01, 0x02, 0x01, 0x00],
            );
            let session = BossSession::new(PacketSession::new(MockLink::new(vec![
                Ok(Some(current_packet)),
                Ok(Some(busy_packet)),
                Ok(Some(verified_packet)),
            ])));

            let result = session
                .set_audio_mode_settings(BossAudioModeSettingsConfigPatch {
                    cnc_level: Some(7),
                    wind_block_enabled: Some(true),
                    ..Default::default()
                })
                .await
                .unwrap();

            assert_eq!(
                result,
                BossAudioModeSettingsWriteResult::Updated(BossAudioModeSettingsConfig {
                    cnc_level: 7,
                    auto_cnc_enabled: true,
                    spatial_audio_mode: BossSpatialAudioMode::Head,
                    wind_block_enabled: true,
                    anc_toggle_enabled: false,
                })
            );
        });
    }

    #[test]
    fn boss_session_set_audio_mode_settings_returns_verification_inconclusive_when_reread_does_not_match() {
        block_on(async {
            let current_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::SETTINGS_CONFIG_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x05, 0x01, 0x02, 0x00, 0x00],
            );
            let mismatched_updated_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::SETTINGS_CONFIG_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x07, 0x01, 0x02, 0x00, 0x00],
            );
            let verified_stale_packet = BmapPacket::new(
                BmapFunctionBlock::AudioModes,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::AudioModes,
                    raw_value: BossAudioModesCodec::SETTINGS_CONFIG_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0x05, 0x01, 0x02, 0x00, 0x00],
            );
            let session = BossSession::new(PacketSession::new(MockLink::new(vec![
                Ok(Some(current_packet)),
                Ok(Some(mismatched_updated_packet)),
                Ok(Some(verified_stale_packet.clone())),
                Ok(Some(verified_stale_packet)),
            ])));

            let result = session
                .set_audio_mode_settings(BossAudioModeSettingsConfigPatch {
                    cnc_level: Some(7),
                    wind_block_enabled: Some(true),
                    ..Default::default()
                })
                .await
                .unwrap();

            assert_eq!(
                result,
                BossAudioModeSettingsWriteResult::VerificationInconclusive(BossAudioModeSettingsConfig {
                    cnc_level: 7,
                    auto_cnc_enabled: true,
                    spatial_audio_mode: BossSpatialAudioMode::Head,
                    wind_block_enabled: true,
                    anc_toggle_enabled: false,
                })
            );
        });
    }

    #[test]
    fn boss_session_set_equalizer_recovers_from_busy_bmap_error_via_reread() {
        block_on(async {
            let current_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0xF6, 0x0A, 0x00, 0x00, 0xF6, 0x0A, 0x00, 0x01, 0xF6, 0x0A, 0x00, 0x02],
            );
            let busy_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Error,
                vec![BmapErrorCode::Busy as u8],
            );
            let verified_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0xF6, 0x0A, 0x03, 0x00, 0xF6, 0x0A, 0xFD, 0x01, 0xF6, 0x0A, 0x00, 0x02],
            );
            let session = BossSession::new(PacketSession::new(MockLink::new(vec![
                Ok(Some(current_packet)),
                Ok(Some(busy_packet)),
                Ok(Some(verified_packet)),
            ])));

            let result = session
                .set_equalizer_verified(BossEqualizerSettingsPatch {
                    bass: Some(3),
                    mid: Some(-3),
                    ..Default::default()
                })
                .await
                .unwrap();

            match result {
                BossEqualizerWriteResult::Updated(settings) => {
                    assert_eq!(settings.range(&BossEqualizerBand::Bass).unwrap().current_level, 3);
                    assert_eq!(settings.range(&BossEqualizerBand::Mid).unwrap().current_level, -3);
                }
                other => panic!("unexpected result: {other:?}"),
            }
        });
    }

    #[test]
    fn boss_session_set_equalizer_returns_verification_inconclusive_when_reread_does_not_match() {
        block_on(async {
            let current_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0xF6, 0x0A, 0x00, 0x00, 0xF6, 0x0A, 0x00, 0x01, 0xF6, 0x0A, 0x00, 0x02],
            );
            let mismatched_updated_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0xF6, 0x0A, 0x03, 0x00, 0xF6, 0x0A, 0x00, 0x01, 0xF6, 0x0A, 0x00, 0x02],
            );
            let verified_stale_packet = BmapPacket::new(
                BmapFunctionBlock::Settings,
                BmapFunction::Unknown {
                    block: BmapFunctionBlock::Settings,
                    raw_value: BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW,
                },
                0,
                0,
                BmapOperator::Status,
                vec![0xF6, 0x0A, 0x00, 0x00, 0xF6, 0x0A, 0x00, 0x01, 0xF6, 0x0A, 0x00, 0x02],
            );
            let session = BossSession::new(PacketSession::new(MockLink::new(vec![
                Ok(Some(current_packet)),
                Ok(Some(mismatched_updated_packet)),
                Ok(Some(verified_stale_packet.clone())),
                Ok(Some(verified_stale_packet)),
            ])));

            let result = session
                .set_equalizer_verified(BossEqualizerSettingsPatch {
                    bass: Some(3),
                    mid: Some(-3),
                    ..Default::default()
                })
                .await
                .unwrap();

            match result {
                BossEqualizerWriteResult::VerificationInconclusive(settings) => {
                    assert_eq!(settings.range(&BossEqualizerBand::Bass).unwrap().current_level, 3);
                    assert_eq!(settings.range(&BossEqualizerBand::Mid).unwrap().current_level, -3);
                }
                other => panic!("unexpected result: {other:?}"),
            }
        });
    }
}
