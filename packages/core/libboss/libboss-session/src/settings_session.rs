use libboss_core::{
    BossOnHeadDetectionValue, BossSettingsCodec, BossSettingsSnapshot, BossStandbyTimerValue,
    BossVolumeControlStatus, BossVolumeControlValue,
};

use crate::{
    BossDeviceSettingsReport, BossLink, BossObservedSetting, BossSession, BossSessionError,
    BossSettingSource,
};

impl<L: BossLink> BossSession<L> {
    pub async fn standby_timer(
        &self,
        timeout_millis: u64,
    ) -> Result<BossStandbyTimerValue, BossSessionError> {
        self.packet_session.standby_timer(timeout_millis).await
    }

    pub async fn settings_snapshot(
        &self,
        timeout_millis: u64,
    ) -> Result<BossSettingsSnapshot, BossSessionError> {
        self.packet_session.settings_snapshot(timeout_millis).await
    }

    pub async fn set_standby_timer(
        &self,
        minutes: i32,
        timeout_millis: u64,
    ) -> Result<BossStandbyTimerValue, BossSessionError> {
        self.packet_session
            .set_standby_timer(minutes, timeout_millis)
            .await
    }

    pub async fn on_head_detection(
        &self,
        timeout_millis: u64,
    ) -> Result<BossOnHeadDetectionValue, BossSessionError> {
        self.packet_session.on_head_detection(timeout_millis).await
    }

    pub async fn enabled_setting(
        &self,
        function_raw: u8,
        timeout_millis: u64,
    ) -> Result<bool, BossSessionError> {
        self.packet_session
            .enabled_setting(function_raw, timeout_millis)
            .await
    }

    pub async fn set_enabled_setting(
        &self,
        function_raw: u8,
        enabled: bool,
        timeout_millis: u64,
    ) -> Result<bool, BossSessionError> {
        self.packet_session
            .set_enabled_setting(function_raw, enabled, timeout_millis)
            .await
    }

    pub async fn set_on_head_detection(
        &self,
        value: &BossOnHeadDetectionValue,
        timeout_millis: u64,
    ) -> Result<BossOnHeadDetectionValue, BossSessionError> {
        self.packet_session
            .set_on_head_detection(value, timeout_millis)
            .await
    }

    pub async fn volume_control_status(
        &self,
        timeout_millis: u64,
    ) -> Result<BossVolumeControlStatus, BossSessionError> {
        self.packet_session
            .volume_control_status(timeout_millis)
            .await
    }

    pub async fn refresh_device_settings_report(
        &self,
        timeout_millis: u64,
    ) -> Result<BossDeviceSettingsReport, BossSessionError> {
        let wear_detection = self
            .observe_direct_setting(|| async { self.on_head_detection(timeout_millis).await })
            .await?;
        let auto_aware_enabled = self
            .observe_direct_setting(|| async {
                self.enabled_setting(BossSettingsCodec::AUTO_AWARE_FUNCTION_RAW, timeout_millis)
                    .await
            })
            .await?;
        let auto_play_pause_enabled = self
            .observe_direct_setting(|| async {
                self.enabled_setting(
                    BossSettingsCodec::AUTO_PLAY_PAUSE_FUNCTION_RAW,
                    timeout_millis,
                )
                .await
            })
            .await?;
        let auto_answer_enabled = if let Some(derived) = wear_detection
            .value
            .as_ref()
            .and_then(|value| value.is_auto_answer_enabled)
        {
            BossObservedSetting {
                value: Some(derived),
                source: Some(BossSettingSource::DirectGet),
                unavailable_reason: None,
            }
        } else {
            self.observe_direct_setting(|| async {
                self.enabled_setting(BossSettingsCodec::AUTO_ANSWER_FUNCTION_RAW, timeout_millis)
                    .await
            })
            .await?
        };
        let volume_control = self
            .observe_direct_setting(|| async { self.volume_control_status(timeout_millis).await })
            .await?;

        Ok(BossDeviceSettingsReport {
            wear_detection,
            auto_aware_enabled,
            auto_play_pause_enabled,
            auto_answer_enabled,
            volume_control,
        })
    }

    pub async fn set_volume_control(
        &self,
        value: BossVolumeControlValue,
        timeout_millis: u64,
    ) -> Result<BossVolumeControlStatus, BossSessionError> {
        self.packet_session
            .set_volume_control(value, timeout_millis)
            .await
    }

    fn unavailable_reason_for_error(
        error: &BossSessionError,
    ) -> Option<crate::BossSettingUnavailableReason> {
        match error {
            BossSessionError::ResponseTimedOut { .. } => {
                Some(crate::BossSettingUnavailableReason::TimedOut)
            }
            BossSessionError::ResponseStreamEnded => {
                Some(crate::BossSettingUnavailableReason::ResponseStreamEnded)
            }
            BossSessionError::BmapErrorResponse(response) => match response.code() {
                Some(libboss_core::BmapErrorCode::FblockNotSupp)
                | Some(libboss_core::BmapErrorCode::FuncNotSupp) => {
                    Some(crate::BossSettingUnavailableReason::FunctionUnsupported)
                }
                Some(libboss_core::BmapErrorCode::OpNotSupp) => {
                    Some(crate::BossSettingUnavailableReason::OperatorUnsupported)
                }
                Some(libboss_core::BmapErrorCode::DataUnavailable) => {
                    Some(crate::BossSettingUnavailableReason::DataUnavailable)
                }
                Some(libboss_core::BmapErrorCode::InsecureTransport) => {
                    Some(crate::BossSettingUnavailableReason::InsecureTransport)
                }
                code => Some(crate::BossSettingUnavailableReason::BmapError(code)),
            },
            _ => None,
        }
    }

    async fn observe_direct_setting<T, F, Fut>(
        &self,
        read: F,
    ) -> Result<BossObservedSetting<T>, BossSessionError>
    where
        T: Clone,
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<T, BossSessionError>>,
    {
        match read().await {
            Ok(value) => Ok(BossObservedSetting {
                value: Some(value),
                source: Some(BossSettingSource::DirectGet),
                unavailable_reason: None,
            }),
            Err(error) => {
                if let Some(reason) = Self::unavailable_reason_for_error(&error) {
                    Ok(BossObservedSetting {
                        value: None,
                        source: None,
                        unavailable_reason: Some(reason),
                    })
                } else {
                    Err(error)
                }
            }
        }
    }
}
