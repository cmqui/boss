use std::collections::BTreeMap;

use libboss_rs_core::{
    BmapFunction, BmapFunctionBlock, BmapOperator, BmapOperatorType, BmapPacket, BossAudioModeConfig,
    BossAudioModePrompt, BossAudioModeSettingsConfig, BossAudioModesCapabilities, BossAudioModesCodec, BossEqualizerBand,
    BossEqualizerSettings, BossOnHeadDetectionValue, BossSettingsCodec, BossSettingsSnapshot,
    BossVolumeControlStatus, BossVolumeControlValue, FirmwareVersionInfo, ProductInfoCommands,
    ProductInfoParser, UnexpectedOperatorError,
};

use crate::{duration_seconds, hex_string, link_error_to_session_error, BmapResponseError, BossLink, BossSessionError};

pub struct PacketSession<L: BossLink> {
    link: L,
}

impl<L: BossLink> PacketSession<L> {
    pub fn new(link: L) -> Self {
        Self { link }
    }

    pub fn transport_kind(&self) -> libboss_rs_core::BossTransportKind {
        self.link.transport_kind()
    }

    pub async fn send_packet(&self, packet: &BmapPacket) -> Result<(), crate::BossLinkError> {
        self.link.send_packet(packet).await
    }

    pub async fn first_packet_matching<F>(
        &self,
        predicate: F,
        timeout_millis: u64,
    ) -> Result<BmapPacket, BossSessionError>
    where
        F: Fn(&BmapPacket) -> bool + Send + Sync,
    {
        loop {
            match self.link.next_packet(timeout_millis).await {
                Ok(Some(packet)) if predicate(&packet) => return Ok(packet),
                Ok(Some(_)) => continue,
                Ok(None) => return Err(BossSessionError::ResponseStreamEnded),
                Err(crate::BossLinkError::TimedOut) => {
                    return Err(BossSessionError::ResponseTimedOut {
                        seconds: duration_seconds(timeout_millis),
                    })
                }
                Err(crate::BossLinkError::UnexpectedStreamTermination) => {
                    return Err(BossSessionError::ResponseStreamEnded)
                }
                Err(crate::BossLinkError::Other(message)) => {
                    return Err(BossSessionError::UnsupportedOperation(message))
                }
            }
        }
    }

    pub async fn send_and_await<F>(
        &self,
        packet: &BmapPacket,
        predicate: F,
        timeout_millis: u64,
    ) -> Result<BmapPacket, BossSessionError>
    where
        F: Fn(&BmapPacket) -> bool + Send + Sync,
    {
        self.send_packet(packet)
            .await
            .map_err(link_error_to_session_error)?;
        self.first_packet_matching(predicate, timeout_millis).await
    }

    pub async fn response_packet(
        &self,
        packet: &BmapPacket,
        timeout_millis: u64,
    ) -> Result<BmapPacket, BossSessionError> {
        let response = self
            .send_and_await(
                packet,
                |incoming| {
                    incoming.function_block == packet.function_block
                        && incoming.function == packet.function
                        && incoming.operator.operator_type() == BmapOperatorType::Response
                },
                timeout_millis,
            )
            .await?;
        if response.operator == BmapOperator::Error {
            return Err(BossSessionError::BmapErrorResponse(BmapResponseError {
                context: format!(
                    "{}.{}",
                    packet.function_block.display_name(),
                    packet.function.name()
                ),
                payload_hex: hex_string(&response.payload),
            }));
        }
        Ok(response)
    }

    pub async fn response_packet_for_function(
        &self,
        packet: &BmapPacket,
        function: &BmapFunction,
        timeout_millis: u64,
    ) -> Result<BmapPacket, BossSessionError> {
        let response = self
            .send_and_await(
                packet,
                |incoming| {
                    &incoming.function == function
                        && incoming.operator.operator_type() == BmapOperatorType::Response
                },
                timeout_millis,
            )
            .await?;
        if response.operator != BmapOperator::Status {
            return Err(BossSessionError::UnexpectedOperator(UnexpectedOperatorError {
                expected: BmapOperator::Status,
                actual: response.operator,
            }));
        }
        Ok(response)
    }

    pub async fn settings_snapshot(&self, timeout_millis: u64) -> Result<BossSettingsSnapshot, BossSessionError> {
        self.send_packet(&BossSettingsCodec::settings_packet(
            BossSettingsCodec::SETTINGS_GET_ALL_FUNCTION_RAW,
            BmapOperator::Start,
            vec![],
        ))
        .await
        .map_err(link_error_to_session_error)?;

        let mut snapshot = BTreeMap::new();
        loop {
            let packet = self
                .first_packet_matching(|packet| packet.function_block == BmapFunctionBlock::Settings, timeout_millis)
                .await?;
            let raw_function = packet.function.raw_value();
            if raw_function == BossSettingsCodec::SETTINGS_GET_ALL_FUNCTION_RAW && packet.operator == BmapOperator::Error {
                return Err(BossSessionError::BmapErrorResponse(BmapResponseError {
                    context: "settings.SettingsGetAll".into(),
                    payload_hex: hex_string(&packet.payload),
                }));
            }
            if raw_function == BossSettingsCodec::SETTINGS_GET_ALL_FUNCTION_RAW && packet.operator == BmapOperator::Result {
                return Ok(BossSettingsSnapshot::new(snapshot));
            }
            if packet.operator == BmapOperator::Status {
                snapshot.insert(raw_function, packet);
            }
        }
    }

    pub async fn firmware_version(
        &self,
        port: i32,
        device_id: i32,
        timeout_millis: u64,
    ) -> Result<FirmwareVersionInfo, BossSessionError> {
        let response = self
            .response_packet(&ProductInfoCommands::firmware_version(port, device_id), timeout_millis)
            .await?;
        Ok(ProductInfoParser::parse_firmware_version(&response)?)
    }

    pub async fn current_audio_mode(&self, timeout_millis: u64) -> Result<i32, BossSessionError> {
        let response = self
            .response_packet(&BossAudioModesCodec::current_mode_get_packet(), timeout_millis)
            .await?;
        Ok(BossAudioModesCodec::parse_current_mode(&response)?)
    }

    pub async fn supported_audio_mode_prompts(
        &self,
        timeout_millis: u64,
    ) -> Result<Vec<BossAudioModePrompt>, BossSessionError> {
        let response = self
            .response_packet(&BossAudioModesCodec::names_supported_get_packet(), timeout_millis)
            .await?;
        Ok(BossAudioModesCodec::parse_supported_prompts(&response)?)
    }

    pub async fn audio_mode_capabilities(
        &self,
        timeout_millis: u64,
    ) -> Result<BossAudioModesCapabilities, BossSessionError> {
        let response = self
            .response_packet(&BossAudioModesCodec::capabilities_get_packet(), timeout_millis)
            .await?;
        Ok(BossAudioModesCodec::parse_capabilities(&response)?)
    }

    pub async fn audio_mode_configs(&self, timeout_millis: u64) -> Result<Vec<BossAudioModeConfig>, BossSessionError> {
        self.send_packet(&BossAudioModesCodec::mode_config_start_packet())
            .await
            .map_err(link_error_to_session_error)?;

        let mut modes_by_index = BTreeMap::new();
        loop {
            let packet = self
                .first_packet_matching(
                    |packet| {
                        packet.function_block == BmapFunctionBlock::AudioModes
                            && packet.function.raw_value() == BossAudioModesCodec::MODE_CONFIG_FUNCTION_RAW
                    },
                    timeout_millis,
                )
                .await?;
            if packet.operator == BmapOperator::Error {
                return Err(BossSessionError::BmapErrorResponse(BmapResponseError {
                    context: format!("audioModes.{}", packet.function.name()),
                    payload_hex: hex_string(&packet.payload),
                }));
            }
            if packet.operator == BmapOperator::Result {
                return Ok(modes_by_index.into_values().collect());
            }
            if packet.operator == BmapOperator::Status {
                let mode = BossAudioModesCodec::parse_mode_config_detail(&packet)?;
                modes_by_index.insert(mode.mode_index, mode);
            }
        }
    }

    pub async fn audio_mode_settings_config(
        &self,
        timeout_millis: u64,
    ) -> Result<BossAudioModeSettingsConfig, BossSessionError> {
        let response = self
            .response_packet(&BossAudioModesCodec::settings_config_get_packet(), timeout_millis)
            .await?;
        Ok(BossAudioModesCodec::parse_settings_config(&response)?)
    }

    pub async fn set_audio_mode_settings_config(
        &self,
        config: &BossAudioModeSettingsConfig,
        timeout_millis: u64,
    ) -> Result<BossAudioModeSettingsConfig, BossSessionError> {
        let packet = BossAudioModesCodec::settings_config_set_get_packet(config)?;
        let response = self.response_packet(&packet, timeout_millis).await?;
        Ok(BossAudioModesCodec::parse_settings_config(&response)?)
    }

    pub async fn favorite_audio_mode_indices(&self, timeout_millis: u64) -> Result<Vec<i32>, BossSessionError> {
        let response = self
            .response_packet(&BossAudioModesCodec::favorites_get_packet(), timeout_millis)
            .await?;
        Ok(BossAudioModesCodec::parse_favorites(&response)?)
    }

    pub async fn set_favorite_audio_mode_indices(
        &self,
        number_of_modes: i32,
        favorite_mode_indices: &[i32],
        timeout_millis: u64,
    ) -> Result<Vec<i32>, BossSessionError> {
        let packet = BossAudioModesCodec::packet(
            BossAudioModesCodec::FAVORITES_FUNCTION_RAW,
            BmapOperator::SetGet,
            BossAudioModesCodec::encode_favorites(number_of_modes, favorite_mode_indices)?,
        );
        let response = self.response_packet(&packet, timeout_millis).await?;
        Ok(BossAudioModesCodec::parse_favorites(&response)?)
    }

    pub async fn equalizer_settings(&self, timeout_millis: u64) -> Result<BossEqualizerSettings, BossSessionError> {
        let response = self
            .response_packet(
                &BossSettingsCodec::settings_packet(BossSettingsCodec::RANGE_CONTROL_FUNCTION_RAW, BmapOperator::Get, vec![]),
                timeout_millis,
            )
            .await?;
        Ok(BossSettingsCodec::parse_equalizer(&response)?)
    }

    pub async fn set_equalizer(
        &self,
        requests: &[(BossEqualizerBand, i32)],
        timeout_millis: u64,
    ) -> Result<BossEqualizerSettings, BossSessionError> {
        let mut last_settings = None;
        for (band, level) in requests {
            let packet = BossSettingsCodec::equalizer_set_get_packet(*level, band.clone())?;
            let response = self.response_packet(&packet, timeout_millis).await?;
            last_settings = Some(BossSettingsCodec::parse_equalizer(&response)?);
        }
        last_settings.ok_or_else(|| {
            BossSessionError::SettingsCodec(libboss_rs_core::BossSettingsCodecError::InvalidPayload(
                "At least one equalizer band update is required".into(),
            ))
        })
    }

    pub async fn on_head_detection(&self, timeout_millis: u64) -> Result<BossOnHeadDetectionValue, BossSessionError> {
        let response = self
            .response_packet(
                &BossSettingsCodec::settings_packet(BossSettingsCodec::ON_HEAD_DETECTION_FUNCTION_RAW, BmapOperator::Get, vec![]),
                timeout_millis,
            )
            .await?;
        Ok(BossSettingsCodec::parse_on_head_detection(&response)?)
    }

    pub async fn enabled_setting(&self, function_raw: u8, timeout_millis: u64) -> Result<bool, BossSessionError> {
        let response = self
            .response_packet(&BossSettingsCodec::settings_packet(function_raw, BmapOperator::Get, vec![]), timeout_millis)
            .await?;
        Ok(BossSettingsCodec::parse_enabled_flag(&response)?)
    }

    pub async fn set_enabled_setting(
        &self,
        function_raw: u8,
        enabled: bool,
        timeout_millis: u64,
    ) -> Result<bool, BossSessionError> {
        let response = self
            .response_packet(
                &BossSettingsCodec::settings_packet(function_raw, BmapOperator::SetGet, vec![if enabled { 0x01 } else { 0x00 }]),
                timeout_millis,
            )
            .await?;
        Ok(BossSettingsCodec::parse_enabled_flag(&response)?)
    }

    pub async fn set_on_head_detection(
        &self,
        value: &BossOnHeadDetectionValue,
        timeout_millis: u64,
    ) -> Result<BossOnHeadDetectionValue, BossSessionError> {
        let response = self
            .response_packet(&BossSettingsCodec::on_head_detection_set_get_packet(value), timeout_millis)
            .await?;
        Ok(BossSettingsCodec::parse_on_head_detection(&response)?)
    }

    pub async fn volume_control_status(&self, timeout_millis: u64) -> Result<BossVolumeControlStatus, BossSessionError> {
        let response = self
            .response_packet(
                &BossSettingsCodec::settings_packet(BossSettingsCodec::VOLUME_CONTROL_FUNCTION_RAW, BmapOperator::Get, vec![]),
                timeout_millis,
            )
            .await?;
        Ok(BossAudioModesCodec::parse_volume_control_status(&response)?)
    }

    pub async fn set_volume_control(
        &self,
        value: BossVolumeControlValue,
        timeout_millis: u64,
    ) -> Result<BossVolumeControlStatus, BossSessionError> {
        let response = self
            .response_packet(
                &BossSettingsCodec::settings_packet(
                    BossSettingsCodec::VOLUME_CONTROL_FUNCTION_RAW,
                    BmapOperator::SetGet,
                    vec![value.raw_value()],
                ),
                timeout_millis,
            )
            .await?;
        Ok(BossAudioModesCodec::parse_volume_control_status(&response)?)
    }

    pub async fn start_current_audio_mode_change(
        &self,
        mode_index: i32,
        play_voice_prompt: bool,
        timeout_millis: u64,
    ) -> Result<BmapPacket, BossSessionError> {
        self.response_packet(
            &BossAudioModesCodec::current_mode_start_packet(mode_index, play_voice_prompt),
            timeout_millis,
        )
        .await
    }
}
