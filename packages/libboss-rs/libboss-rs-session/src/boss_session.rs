use std::collections::{BTreeMap, BTreeSet};

use libboss_rs_core::{
    BmapFunctionBlock, BmapPacket, BossAudioModeConfig, BossAudioModePrompt, BossAudioModeSettingsConfig,
    BossAudioModeSettingsConfigPatch, BossAudioModesCodec, BossEqualizerBand, BossEqualizerSettings,
    BossEqualizerSettingsPatch, BossOnHeadDetectionValue, BossSettingsCodec, BossVolumeControlStatus,
    BossVolumeControlValue, FirmwareVersionInfo,
};

use crate::{BossLink, BossObservedSetting, BossSettingSource, BossSessionError, BossDeviceSettingsReport, PacketSession};

pub struct BossSession<L: BossLink> {
    packet_session: PacketSession<L>,
}

impl<L: BossLink> BossSession<L> {
    pub fn new(packet_session: PacketSession<L>) -> Self {
        Self { packet_session }
    }

    pub async fn firmware_version(&self, port: i32, device_id: i32, timeout_millis: u64) -> Result<FirmwareVersionInfo, BossSessionError> {
        self.packet_session.firmware_version(port, device_id, timeout_millis).await
    }

    pub async fn current_audio_mode(&self, timeout_millis: u64) -> Result<i32, BossSessionError> {
        self.packet_session.current_audio_mode(timeout_millis).await
    }

    pub async fn supported_audio_mode_prompts(&self, timeout_millis: u64) -> Result<Vec<BossAudioModePrompt>, BossSessionError> {
        self.packet_session.supported_audio_mode_prompts(timeout_millis).await
    }

    pub async fn audio_mode_configs(&self, timeout_millis: u64) -> Result<Vec<BossAudioModeConfig>, BossSessionError> {
        self.packet_session.audio_mode_configs(timeout_millis).await
    }

    pub async fn audio_mode_settings_config(&self, timeout_millis: u64) -> Result<BossAudioModeSettingsConfig, BossSessionError> {
        self.packet_session.audio_mode_settings_config(timeout_millis).await
    }

    pub async fn favorite_audio_mode_indices(&self, timeout_millis: u64) -> Result<Vec<i32>, BossSessionError> {
        self.packet_session.favorite_audio_mode_indices(timeout_millis).await
    }

    pub async fn set_favorite_audio_mode_indices(
        &self,
        number_of_modes: i32,
        favorite_mode_indices: &[i32],
        timeout_millis: u64,
    ) -> Result<Vec<i32>, BossSessionError> {
        self.packet_session
            .set_favorite_audio_mode_indices(number_of_modes, favorite_mode_indices, timeout_millis)
            .await
    }

    pub async fn equalizer_settings(&self, timeout_millis: u64) -> Result<BossEqualizerSettings, BossSessionError> {
        self.packet_session.equalizer_settings(timeout_millis).await
    }

    pub async fn set_equalizer(
        &self,
        requests: &[(BossEqualizerBand, i32)],
        timeout_millis: u64,
    ) -> Result<BossEqualizerSettings, BossSessionError> {
        self.packet_session.set_equalizer(requests, timeout_millis).await
    }

    pub async fn on_head_detection(&self, timeout_millis: u64) -> Result<BossOnHeadDetectionValue, BossSessionError> {
        self.packet_session.on_head_detection(timeout_millis).await
    }

    pub async fn enabled_setting(&self, function_raw: u8, timeout_millis: u64) -> Result<bool, BossSessionError> {
        self.packet_session.enabled_setting(function_raw, timeout_millis).await
    }

    pub async fn set_enabled_setting(
        &self,
        function_raw: u8,
        enabled: bool,
        timeout_millis: u64,
    ) -> Result<bool, BossSessionError> {
        self.packet_session.set_enabled_setting(function_raw, enabled, timeout_millis).await
    }

    pub async fn set_on_head_detection(
        &self,
        value: &BossOnHeadDetectionValue,
        timeout_millis: u64,
    ) -> Result<BossOnHeadDetectionValue, BossSessionError> {
        self.packet_session.set_on_head_detection(value, timeout_millis).await
    }

    pub async fn volume_control_status(&self, timeout_millis: u64) -> Result<BossVolumeControlStatus, BossSessionError> {
        self.packet_session.volume_control_status(timeout_millis).await
    }

    pub async fn set_volume_control(
        &self,
        value: BossVolumeControlValue,
        timeout_millis: u64,
    ) -> Result<BossVolumeControlStatus, BossSessionError> {
        self.packet_session.set_volume_control(value, timeout_millis).await
    }

    pub async fn set_current_audio_mode(
        &self,
        target_index: i32,
        play_voice_prompt: bool,
    ) -> Result<BossCurrentAudioModeWriteResult, BossSessionError> {
        if let Some(current_index) = self.current_audio_mode_if_available(2_000).await? {
            if current_index == target_index {
                return Ok(BossCurrentAudioModeWriteResult::Unchanged(current_index));
            }
        }

        match self
            .packet_session
            .start_current_audio_mode_change(target_index, play_voice_prompt, 5_000)
            .await
        {
            Ok(response) => {
                if response.operator == libboss_rs_core::BmapOperator::Result {
                    if let Some(response_mode_index) = response.payload.first() {
                        return Ok(BossCurrentAudioModeWriteResult::Updated(*response_mode_index as i32));
                    }
                    let verified = self.verify_current_audio_mode(target_index, 2_000, 3).await?;
                    return Ok(BossCurrentAudioModeWriteResult::Updated(verified));
                }
                Ok(BossCurrentAudioModeWriteResult::Updated(
                    BossAudioModesCodec::parse_current_mode(&response)?,
                ))
            }
            Err(error) => {
                if !Self::should_fallback_for_audio_mode_write(&error) {
                    return Err(error);
                }
                match self.verify_current_audio_mode(target_index, 3_000, 4).await {
                    Ok(verified) => Ok(BossCurrentAudioModeWriteResult::Updated(verified)),
                    Err(_) => Ok(BossCurrentAudioModeWriteResult::VerificationInconclusive {
                        target_index,
                    }),
                }
            }
        }
    }

    pub async fn set_audio_mode_settings(
        &self,
        update: BossAudioModeSettingsConfigPatch,
    ) -> Result<BossAudioModeSettingsWriteResult, BossSessionError> {
        let current = self.read_audio_mode_settings_config(2, 5_000).await?;
        let target = update.merged_with(&current);
        if target == current {
            return Ok(BossAudioModeSettingsWriteResult::Unchanged(current));
        }

        let write_result = match self
            .packet_session
            .set_audio_mode_settings_config(&target, 5_000)
            .await
        {
            Ok(updated) => {
                if !update.matches(&updated) {
                    Err(BossSessionError::SettingsConfigNotObserved {
                        expected: Self::describe_config(&target),
                        observed: Self::describe_config(&updated),
                    })
                } else {
                    Ok(updated)
                }
            }
            Err(error) => Err(error),
        };

        match write_result {
            Ok(updated) => Ok(BossAudioModeSettingsWriteResult::Updated(updated)),
            Err(error) => {
                if !Self::is_recoverable_audio_mode_settings_config_error(&error) {
                    return Err(error);
                }
                let verified = self.read_audio_mode_settings_config(2, 5_000).await?;
                if update.matches(&verified) {
                    return Ok(BossAudioModeSettingsWriteResult::Updated(verified));
                }
                Ok(BossAudioModeSettingsWriteResult::VerificationInconclusive(target))
            }
        }
    }

    pub async fn set_equalizer_verified(
        &self,
        update: BossEqualizerSettingsPatch,
    ) -> Result<BossEqualizerWriteResult, BossSessionError> {
        let current = self.packet_session.equalizer_settings(5_000).await?;
        if update.is_empty() {
            return Ok(BossEqualizerWriteResult::Unchanged(current));
        }
        let requested = Self::validated_equalizer_requests(&update, &current)?;
        let mut changed = false;
        let target = BossEqualizerSettings::new(
            current
                .ranges
                .iter()
                .cloned()
                .map(|range| {
                    if let Some((_, requested_level)) = requested.iter().find(|(band, _)| *band == range.band) {
                        if range.current_level != *requested_level {
                            changed = true;
                        }
                        libboss_rs_core::BossEqualizerRangeLevel {
                            band: range.band,
                            current_level: *requested_level,
                            min_level: range.min_level,
                            max_level: range.max_level,
                        }
                    } else {
                        range
                    }
                })
                .collect(),
        );
        if !changed {
            return Ok(BossEqualizerWriteResult::Unchanged(current));
        }

        let write_result = match self.packet_session.set_equalizer(&requested, 5_000).await {
            Ok(updated) => {
                if !update.matches(&updated) {
                    Err(BossSessionError::EqualizerNotObserved {
                        expected: Self::describe_equalizer_patch(&update),
                        observed: Self::describe_equalizer(&updated),
                    })
                } else {
                    Ok(updated)
                }
            }
            Err(error) => Err(error),
        };

        match write_result {
            Ok(updated) => Ok(BossEqualizerWriteResult::Updated(updated)),
            Err(error) => {
                if !Self::is_recoverable_equalizer_error(&error) {
                    return Err(error);
                }
                let verified = self.packet_session.equalizer_settings(5_000).await.unwrap_or(target.clone());
                if update.matches(&verified) {
                    return Ok(BossEqualizerWriteResult::Updated(verified));
                }
                Ok(BossEqualizerWriteResult::VerificationInconclusive(target))
            }
        }
    }

    pub fn reduce_audio_mode_catalog(
        catalog: &[BossAudioModeConfig],
        packet: &BmapPacket,
    ) -> Result<Option<Vec<BossAudioModeConfig>>, BossSessionError> {
        if packet.function_block != BmapFunctionBlock::AudioModes || packet.operator != libboss_rs_core::BmapOperator::Status {
            return Ok(None);
        }

        match packet.function.raw_value() {
            BossAudioModesCodec::MODE_CONFIG_FUNCTION_RAW => {
                let mode = BossAudioModesCodec::parse_mode_config_detail(packet)?;
                let mut updated: BTreeMap<i32, BossAudioModeConfig> =
                    catalog.iter().cloned().map(|mode| (mode.mode_index, mode)).collect();
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
        if packet.function_block != BmapFunctionBlock::Settings || packet.operator != libboss_rs_core::BmapOperator::Status {
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
                let auto_answer_enabled = if report.auto_answer_enabled.source == Some(BossSettingSource::Snapshot) {
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
            _ => Ok(None),
        }
    }

    async fn current_audio_mode_if_available(&self, timeout_millis: u64) -> Result<Option<i32>, BossSessionError> {
        match self.packet_session.current_audio_mode(timeout_millis).await {
            Ok(value) => Ok(Some(value)),
            Err(error) => {
                if Self::should_fallback_for_audio_mode_write(&error) {
                    Ok(None)
                } else {
                    Err(error)
                }
            }
        }
    }

    async fn verify_current_audio_mode(
        &self,
        target_index: i32,
        timeout_per_attempt: u64,
        attempts: usize,
    ) -> Result<i32, BossSessionError> {
        let mut last_observed_index = None;
        let mut last_error = BossSessionError::ResponseTimedOut { seconds: (timeout_per_attempt / 1000) as i64 };
        for _ in 0..attempts {
            match self.packet_session.current_audio_mode(timeout_per_attempt).await {
                Ok(current_index) => {
                    last_observed_index = Some(current_index);
                    if current_index == target_index {
                        return Ok(current_index);
                    }
                }
                Err(error) => last_error = error,
            }
        }
        if let Some(observed_index) = last_observed_index {
            return Err(BossSessionError::ModeChangeNotObserved {
                target_index,
                observed_index,
            });
        }
        Err(last_error)
    }

    async fn read_audio_mode_settings_config(
        &self,
        attempts: usize,
        timeout_per_attempt: u64,
    ) -> Result<BossAudioModeSettingsConfig, BossSessionError> {
        let mut last_error = BossSessionError::ResponseTimedOut { seconds: (timeout_per_attempt / 1000) as i64 };
        for attempt in 0..attempts {
            match self.packet_session.audio_mode_settings_config(timeout_per_attempt).await {
                Ok(config) => return Ok(config),
                Err(error) => {
                    if !Self::is_recoverable_audio_mode_settings_config_error(&error) || attempt == attempts - 1 {
                        return Err(error);
                    }
                    last_error = error;
                }
            }
        }
        Err(last_error)
    }

    fn should_fallback_for_audio_mode_write(error: &BossSessionError) -> bool {
        matches!(error, BossSessionError::ResponseTimedOut { .. } | BossSessionError::ResponseStreamEnded)
    }

    fn is_recoverable_audio_mode_settings_config_error(error: &BossSessionError) -> bool {
        if Self::should_fallback_for_audio_mode_write(error) {
            return true;
        }
        match error {
            BossSessionError::SettingsConfigNotObserved { .. } => true,
            BossSessionError::BmapErrorResponse(_) => matches!(
                error.bmap_error_code(),
                Some(libboss_rs_core::BmapErrorCode::InsecureTransport)
                    | Some(libboss_rs_core::BmapErrorCode::Timeout)
                    | Some(libboss_rs_core::BmapErrorCode::Busy)
            ),
            _ => false,
        }
    }

    fn is_recoverable_equalizer_error(error: &BossSessionError) -> bool {
        if Self::should_fallback_for_audio_mode_write(error) {
            return true;
        }
        match error {
            BossSessionError::EqualizerNotObserved { .. } => true,
            BossSessionError::BmapErrorResponse(_) => matches!(
                error.bmap_error_code(),
                Some(libboss_rs_core::BmapErrorCode::InsecureTransport)
                    | Some(libboss_rs_core::BmapErrorCode::Timeout)
                    | Some(libboss_rs_core::BmapErrorCode::Busy)
            ),
            _ => false,
        }
    }

    fn validated_equalizer_requests(
        update: &BossEqualizerSettingsPatch,
        current: &BossEqualizerSettings,
    ) -> Result<Vec<(BossEqualizerBand, i32)>, BossSessionError> {
        update
            .requested_levels()
            .into_iter()
            .map(|(band, level)| {
                let Some(range) = current.range(&band) else {
                    return Err(BossSessionError::UnsupportedOperation(format!(
                        "This device/session does not expose the {} equalizer band over BMAP",
                        band.display_name()
                    )));
                };
                if !(range.min_level..=range.max_level).contains(&level) {
                    return Err(BossSessionError::UnsupportedOperation(format!(
                        "Requested {} equalizer level {} is outside the supported range {}...{}",
                        band.display_name(),
                        level,
                        range.min_level,
                        range.max_level
                    )));
                }
                Ok((band, level))
            })
            .collect()
    }

    fn describe_equalizer_patch(update: &BossEqualizerSettingsPatch) -> String {
        update
            .requested_levels()
            .into_iter()
            .map(|(band, level)| format!("{}={}", band.display_name(), level))
            .collect::<Vec<_>>()
            .join(",")
    }

    fn describe_equalizer(settings: &BossEqualizerSettings) -> String {
        settings
            .ranges
            .iter()
            .map(|range| {
                format!(
                    "{}={}[{}...{}]",
                    range.band.display_name(),
                    range.current_level,
                    range.min_level,
                    range.max_level
                )
            })
            .collect::<Vec<_>>()
            .join(",")
    }

    fn describe_config(config: &BossAudioModeSettingsConfig) -> String {
        format!(
            "cnc={},autoCNC={},spatial={},wind={},anc={}",
            config.cnc_level,
            config.auto_cnc_enabled,
            config.spatial_audio_mode.display_name(),
            config.wind_block_enabled,
            config.anc_toggle_enabled
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BossCurrentAudioModeWriteResult {
    Unchanged(i32),
    Updated(i32),
    VerificationInconclusive { target_index: i32 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BossAudioModeSettingsWriteResult {
    Unchanged(BossAudioModeSettingsConfig),
    Updated(BossAudioModeSettingsConfig),
    VerificationInconclusive(BossAudioModeSettingsConfig),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BossEqualizerWriteResult {
    Unchanged(BossEqualizerSettings),
    Updated(BossEqualizerSettings),
    VerificationInconclusive(BossEqualizerSettings),
}
