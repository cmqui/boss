use std::collections::BTreeSet;

use libboss_core::{
    BmapOperator, BossAudioModeConfig, BossAudioModePrompt, BossAudioModeSettingsConfig,
    BossAudioModeSettingsConfigPatch, BossAudioModesCapabilities, BossAudioModesCodec,
    FirmwareVersionInfo, ProductInfoCommands, ProductInfoParser,
};

use crate::{
    BossAudioModeSettingsWriteResult, BossCurrentAudioModeWriteResult, BossLink, BossSession,
    BossSessionError,
};

impl<L: BossLink> BossSession<L> {
    pub async fn firmware_version(
        &self,
        port: i32,
        device_id: i32,
        timeout_millis: u64,
    ) -> Result<FirmwareVersionInfo, BossSessionError> {
        let response = self
            .packet_session
            .response_packet(
                &ProductInfoCommands::firmware_version(port, device_id),
                timeout_millis,
            )
            .await?;
        Ok(ProductInfoParser::parse_firmware_version(&response)?)
    }

    pub async fn current_audio_mode(&self, timeout_millis: u64) -> Result<i32, BossSessionError> {
        self.packet_session.current_audio_mode(timeout_millis).await
    }

    pub async fn supported_audio_mode_prompts(
        &self,
        timeout_millis: u64,
    ) -> Result<Vec<BossAudioModePrompt>, BossSessionError> {
        self.packet_session
            .supported_audio_mode_prompts(timeout_millis)
            .await
    }

    pub async fn audio_mode_capabilities(
        &self,
        timeout_millis: u64,
    ) -> Result<BossAudioModesCapabilities, BossSessionError> {
        self.packet_session
            .audio_mode_capabilities(timeout_millis)
            .await
    }

    pub async fn audio_mode_configs(
        &self,
        timeout_millis: u64,
    ) -> Result<Vec<BossAudioModeConfig>, BossSessionError> {
        self.packet_session.audio_mode_configs(timeout_millis).await
    }

    pub async fn audio_mode_settings_config(
        &self,
        timeout_millis: u64,
    ) -> Result<BossAudioModeSettingsConfig, BossSessionError> {
        self.packet_session
            .audio_mode_settings_config(timeout_millis)
            .await
    }

    pub async fn favorite_audio_mode_indices(
        &self,
        timeout_millis: u64,
    ) -> Result<Vec<i32>, BossSessionError> {
        self.packet_session
            .favorite_audio_mode_indices(timeout_millis)
            .await
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

    pub async fn set_audio_mode_favorite(
        &self,
        index: i32,
        is_favorite: bool,
        timeout_millis: u64,
    ) -> Result<Vec<i32>, BossSessionError> {
        let capabilities = self.audio_mode_capabilities(timeout_millis).await?;
        let number_of_modes = capabilities.bose_modes + capabilities.user_modes;
        let mut favorites: BTreeSet<i32> = self
            .favorite_audio_mode_indices(timeout_millis)
            .await?
            .into_iter()
            .collect();
        if is_favorite {
            favorites.insert(index);
        } else {
            favorites.remove(&index);
        }
        let requested: Vec<i32> = favorites.into_iter().collect();
        self.set_favorite_audio_mode_indices(number_of_modes, &requested, timeout_millis)
            .await
    }

    pub async fn favorite_audio_mode(
        &self,
        index: i32,
        timeout_millis: u64,
    ) -> Result<Vec<i32>, BossSessionError> {
        self.set_audio_mode_favorite(index, true, timeout_millis)
            .await
    }

    pub async fn unfavorite_audio_mode(
        &self,
        index: i32,
        timeout_millis: u64,
    ) -> Result<Vec<i32>, BossSessionError> {
        self.set_audio_mode_favorite(index, false, timeout_millis)
            .await
    }

    pub async fn save_custom_audio_mode(
        &self,
        name: &str,
        settings: &BossAudioModeSettingsConfig,
        prompt: BossAudioModePrompt,
        requested_slot: Option<i32>,
        timeout_millis: u64,
    ) -> Result<BossAudioModeConfig, BossSessionError> {
        let configs = self.audio_mode_configs(timeout_millis).await?;
        let slot = if let Some(requested_slot) = requested_slot {
            if configs
                .iter()
                .find(|config| config.mode_index == requested_slot)
                .map(|config| config.user_configurable)
                != Some(true)
            {
                return Err(BossSessionError::CustomAudioModeSlotNotEditable(
                    requested_slot,
                ));
            }
            requested_slot
        } else {
            Self::first_free_custom_audio_mode_slot(&configs)
                .ok_or(BossSessionError::NoFreeCustomAudioModeSlot)?
        };

        self.write_custom_audio_mode(slot, name, settings, prompt, timeout_millis)
            .await
    }

    pub async fn delete_custom_audio_mode(
        &self,
        slot: i32,
        timeout_millis: u64,
    ) -> Result<BossAudioModeConfig, BossSessionError> {
        let configs = self.audio_mode_configs(timeout_millis).await?;
        let Some(existing) = configs.iter().find(|config| config.mode_index == slot) else {
            return Err(BossSessionError::CustomAudioModeSlotNotFound(slot));
        };
        if !existing.user_configurable {
            return Err(BossSessionError::CustomAudioModeSlotNotEditable(slot));
        }

        if existing.favorite {
            let _ = self.unfavorite_audio_mode(slot, timeout_millis).await?;
        }

        self.write_custom_audio_mode(
            slot,
            "",
            &existing.deleted_settings_baseline(),
            BossAudioModePrompt::NONE,
            timeout_millis,
        )
        .await
    }

    pub async fn set_current_audio_mode(
        &self,
        target_index: i32,
        play_voice_prompt: bool,
    ) -> Result<BossCurrentAudioModeWriteResult, BossSessionError> {
        match self
            .packet_session
            .start_current_audio_mode_change(target_index, play_voice_prompt, 5_000)
            .await
        {
            Ok(response) => {
                if response.operator == BmapOperator::Result {
                    if let Some(response_mode_index) = response.payload.first() {
                        return Ok(BossCurrentAudioModeWriteResult::Updated(
                            *response_mode_index as i32,
                        ));
                    }
                    let verified = self
                        .verify_current_audio_mode(target_index, 2_000, 3)
                        .await?;
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
                Ok(BossAudioModeSettingsWriteResult::VerificationInconclusive(
                    target,
                ))
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
        let mut last_error = BossSessionError::ResponseTimedOut {
            seconds: (timeout_per_attempt / 1000) as i64,
        };
        for _ in 0..attempts {
            match self
                .packet_session
                .current_audio_mode(timeout_per_attempt)
                .await
            {
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
        let mut last_error = BossSessionError::ResponseTimedOut {
            seconds: (timeout_per_attempt / 1000) as i64,
        };
        for attempt in 0..attempts {
            match self
                .packet_session
                .audio_mode_settings_config(timeout_per_attempt)
                .await
            {
                Ok(config) => return Ok(config),
                Err(error) => {
                    if !Self::is_recoverable_audio_mode_settings_config_error(&error)
                        || attempt == attempts - 1
                    {
                        return Err(error);
                    }
                    last_error = error;
                }
            }
        }
        Err(last_error)
    }

    pub(crate) fn should_fallback_for_audio_mode_write(error: &BossSessionError) -> bool {
        matches!(
            error,
            BossSessionError::ResponseTimedOut { .. } | BossSessionError::ResponseStreamEnded
        )
    }

    fn is_recoverable_audio_mode_settings_config_error(error: &BossSessionError) -> bool {
        if Self::should_fallback_for_audio_mode_write(error) {
            return true;
        }
        match error {
            BossSessionError::SettingsConfigNotObserved { .. } => true,
            BossSessionError::BmapErrorResponse(_) => matches!(
                error.bmap_error_code(),
                Some(libboss_core::BmapErrorCode::InsecureTransport)
                    | Some(libboss_core::BmapErrorCode::Timeout)
                    | Some(libboss_core::BmapErrorCode::Busy)
            ),
            _ => false,
        }
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

    async fn write_custom_audio_mode(
        &self,
        slot: i32,
        name: &str,
        settings: &BossAudioModeSettingsConfig,
        prompt: BossAudioModePrompt,
        timeout_millis: u64,
    ) -> Result<BossAudioModeConfig, BossSessionError> {
        self.packet_session
            .set_audio_mode_config(slot, prompt, name, settings, timeout_millis)
            .await
    }

    pub(crate) fn first_free_custom_audio_mode_slot(
        configs: &[BossAudioModeConfig],
    ) -> Option<i32> {
        configs
            .iter()
            .find(|config| config.user_configurable && config.name.is_empty())
            .map(|config| config.mode_index)
    }
}
