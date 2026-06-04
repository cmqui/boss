use crate::{BossLink, PacketSession};

pub struct BossSession<L: BossLink> {
    pub(crate) packet_session: PacketSession<L>,
}

impl<L: BossLink> BossSession<L> {
    pub fn new(packet_session: PacketSession<L>) -> Self {
        Self { packet_session }
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
    Unchanged(libboss_core::BossAudioModeSettingsConfig),
    Updated(libboss_core::BossAudioModeSettingsConfig),
    VerificationInconclusive(libboss_core::BossAudioModeSettingsConfig),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BossEqualizerWriteResult {
    Unchanged(libboss_core::BossEqualizerSettings),
    Updated(libboss_core::BossEqualizerSettings),
    VerificationInconclusive(libboss_core::BossEqualizerSettings),
}
