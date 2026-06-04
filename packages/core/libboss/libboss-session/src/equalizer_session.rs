use libboss_core::{BossEqualizerBand, BossEqualizerSettings, BossEqualizerSettingsPatch};

use crate::{BossEqualizerWriteResult, BossLink, BossSession, BossSessionError};

impl<L: BossLink> BossSession<L> {
    pub async fn equalizer_settings(
        &self,
        timeout_millis: u64,
    ) -> Result<BossEqualizerSettings, BossSessionError> {
        self.packet_session.equalizer_settings(timeout_millis).await
    }

    pub async fn set_equalizer(
        &self,
        requests: &[(BossEqualizerBand, i32)],
        timeout_millis: u64,
    ) -> Result<BossEqualizerSettings, BossSessionError> {
        self.packet_session
            .set_equalizer(requests, timeout_millis)
            .await
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
                    if let Some((_, requested_level)) =
                        requested.iter().find(|(band, _)| *band == range.band)
                    {
                        if range.current_level != *requested_level {
                            changed = true;
                        }
                        libboss_core::BossEqualizerRangeLevel {
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
                let verified = self
                    .packet_session
                    .equalizer_settings(5_000)
                    .await
                    .unwrap_or(target.clone());
                if update.matches(&verified) {
                    return Ok(BossEqualizerWriteResult::Updated(verified));
                }
                Ok(BossEqualizerWriteResult::VerificationInconclusive(target))
            }
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
                Some(libboss_core::BmapErrorCode::InsecureTransport)
                    | Some(libboss_core::BmapErrorCode::Timeout)
                    | Some(libboss_core::BmapErrorCode::Busy)
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
}
