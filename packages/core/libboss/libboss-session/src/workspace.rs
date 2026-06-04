use std::collections::{BTreeMap, BTreeSet};

use libboss_core::{BmapFunctionBlock, BmapOperator, BmapPacket, BossAudioModeConfig};
use libboss_core::{BossAudioModesCodec, BossSettingsCodec};

use crate::{
    BossDeviceSettingsReport, BossLink, BossObservedSetting, BossSession, BossSessionError,
    BossSettingSource,
};

impl<L: BossLink> BossSession<L> {
    pub fn reduce_audio_mode_catalog(
        catalog: &[BossAudioModeConfig],
        packet: &BmapPacket,
    ) -> Result<Option<Vec<BossAudioModeConfig>>, BossSessionError> {
        if packet.function_block != BmapFunctionBlock::AudioModes
            || packet.operator != BmapOperator::Status
        {
            return Ok(None);
        }

        match packet.function.raw_value() {
            BossAudioModesCodec::MODE_CONFIG_FUNCTION_RAW => {
                let mode = BossAudioModesCodec::parse_mode_config_detail(packet)?;
                let mut updated: BTreeMap<i32, BossAudioModeConfig> = catalog
                    .iter()
                    .cloned()
                    .map(|mode| (mode.mode_index, mode))
                    .collect();
                updated.insert(mode.mode_index, mode);
                Ok(Some(updated.into_values().collect()))
            }
            BossAudioModesCodec::FAVORITES_FUNCTION_RAW => {
                let favorites = BossAudioModesCodec::parse_favorites(packet)?;
                let favorites: BTreeSet<i32> = favorites.into_iter().collect();
                Ok(Some(
                    catalog
                        .iter()
                        .cloned()
                        .map(|mode| BossAudioModeConfig {
                            favorite: favorites.contains(&mode.mode_index),
                            ..mode
                        })
                        .collect(),
                ))
            }
            _ => Ok(None),
        }
    }

    pub fn reduce_device_settings_report(
        report: &BossDeviceSettingsReport,
        packet: &BmapPacket,
    ) -> Result<Option<BossDeviceSettingsReport>, BossSessionError> {
        if packet.function_block != BmapFunctionBlock::Settings
            || packet.operator != BmapOperator::Status
        {
            return Ok(None);
        }

        match packet.function.raw_value() {
            BossSettingsCodec::ON_HEAD_DETECTION_FUNCTION_RAW => {
                let value = BossSettingsCodec::parse_on_head_detection(packet)?;
                let wear_detection = BossObservedSetting {
                    value: Some(value.clone()),
                    source: Some(BossSettingSource::Snapshot),
                    unavailable_reason: None,
                };
                let auto_answer_enabled =
                    if report.auto_answer_enabled.source == Some(BossSettingSource::Snapshot) {
                        report.auto_answer_enabled.clone()
                    } else if let Some(derived) = value.is_auto_answer_enabled {
                        BossObservedSetting {
                            value: Some(derived),
                            source: Some(BossSettingSource::CompositeSnapshot),
                            unavailable_reason: None,
                        }
                    } else {
                        report.auto_answer_enabled.clone()
                    };
                Ok(Some(BossDeviceSettingsReport {
                    wear_detection,
                    auto_aware_enabled: report.auto_aware_enabled.clone(),
                    auto_play_pause_enabled: report.auto_play_pause_enabled.clone(),
                    auto_answer_enabled,
                    volume_control: report.volume_control.clone(),
                }))
            }
            BossSettingsCodec::AUTO_AWARE_FUNCTION_RAW => Ok(Some(BossDeviceSettingsReport {
                wear_detection: report.wear_detection.clone(),
                auto_aware_enabled: BossObservedSetting {
                    value: Some(BossSettingsCodec::parse_enabled_flag(packet)?),
                    source: Some(BossSettingSource::Snapshot),
                    unavailable_reason: None,
                },
                auto_play_pause_enabled: report.auto_play_pause_enabled.clone(),
                auto_answer_enabled: report.auto_answer_enabled.clone(),
                volume_control: report.volume_control.clone(),
            })),
            BossSettingsCodec::AUTO_PLAY_PAUSE_FUNCTION_RAW => Ok(Some(BossDeviceSettingsReport {
                wear_detection: report.wear_detection.clone(),
                auto_aware_enabled: report.auto_aware_enabled.clone(),
                auto_play_pause_enabled: BossObservedSetting {
                    value: Some(BossSettingsCodec::parse_enabled_flag(packet)?),
                    source: Some(BossSettingSource::Snapshot),
                    unavailable_reason: None,
                },
                auto_answer_enabled: report.auto_answer_enabled.clone(),
                volume_control: report.volume_control.clone(),
            })),
            BossSettingsCodec::AUTO_ANSWER_FUNCTION_RAW => Ok(Some(BossDeviceSettingsReport {
                wear_detection: report.wear_detection.clone(),
                auto_aware_enabled: report.auto_aware_enabled.clone(),
                auto_play_pause_enabled: report.auto_play_pause_enabled.clone(),
                auto_answer_enabled: BossObservedSetting {
                    value: Some(BossSettingsCodec::parse_enabled_flag(packet)?),
                    source: Some(BossSettingSource::Snapshot),
                    unavailable_reason: None,
                },
                volume_control: report.volume_control.clone(),
            })),
            BossSettingsCodec::VOLUME_CONTROL_FUNCTION_RAW => Ok(Some(BossDeviceSettingsReport {
                wear_detection: report.wear_detection.clone(),
                auto_aware_enabled: report.auto_aware_enabled.clone(),
                auto_play_pause_enabled: report.auto_play_pause_enabled.clone(),
                auto_answer_enabled: report.auto_answer_enabled.clone(),
                volume_control: BossObservedSetting {
                    value: Some(BossAudioModesCodec::parse_volume_control_status(packet)?),
                    source: Some(BossSettingSource::Snapshot),
                    unavailable_reason: None,
                },
            })),
            _ => Ok(None),
        }
    }
}
