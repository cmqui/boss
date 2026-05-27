use crate::{BossTransportKind, FunctionBlockSet, ProductDefinition};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BossFeatureSupport {
    Supported,
    Unsupported,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BossFeatureAccess {
    ReadOnly,
    ReadWrite,
    Unsupported,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BossProtocolSupport {
    pub function_blocks: FunctionBlockSet,
    pub transport_kind: BossTransportKind,
    pub default_device_id: i32,
    pub default_port: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BossSettingsCapabilities {
    pub standby_timer: BossFeatureAccess,
    pub wear_detection: BossFeatureAccess,
    pub auto_aware: BossFeatureAccess,
    pub auto_play_pause: BossFeatureAccess,
    pub auto_answer: BossFeatureAccess,
    pub volume_control: BossFeatureAccess,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BossAudioModeCapabilities {
    pub modes: BossFeatureSupport,
    pub current_mode: BossFeatureAccess,
    pub settings_config: BossFeatureAccess,
    pub favorites: BossFeatureAccess,
    pub custom_profiles: BossFeatureAccess,
    pub supported_prompts: BossFeatureSupport,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BossSoundCapabilities {
    pub equalizer: BossFeatureAccess,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BossDeviceCapabilities {
    pub settings: BossSettingsCapabilities,
    pub audio_modes: BossAudioModeCapabilities,
    pub sound: BossSoundCapabilities,
}

impl BossDeviceCapabilities {
    pub fn resolve(
        product: Option<&ProductDefinition>,
        protocol_support: &BossProtocolSupport,
    ) -> Self {
        let settings_access = if protocol_support
            .function_blocks
            .contains(crate::BmapFunctionBlock::Settings)
        {
            BossFeatureAccess::ReadWrite
        } else {
            BossFeatureAccess::Unsupported
        };

        let audio_modes_supported = if protocol_support
            .function_blocks
            .contains(crate::BmapFunctionBlock::AudioModes)
        {
            BossFeatureSupport::Supported
        } else {
            BossFeatureSupport::Unsupported
        };
        let audio_modes_access = match audio_modes_supported {
            BossFeatureSupport::Supported => BossFeatureAccess::ReadWrite,
            BossFeatureSupport::Unsupported => BossFeatureAccess::Unsupported,
            BossFeatureSupport::Unknown => BossFeatureAccess::Unknown,
        };

        let equalizer_access = if protocol_support
            .function_blocks
            .contains(crate::BmapFunctionBlock::Settings)
            && matches!(
                product.map(|product| product.family),
                Some(crate::BossProductFamily::QCUltra2)
            )
        {
            BossFeatureAccess::ReadWrite
        } else if protocol_support
            .function_blocks
            .contains(crate::BmapFunctionBlock::Settings)
        {
            BossFeatureAccess::Unknown
        } else {
            BossFeatureAccess::Unsupported
        };

        Self {
            settings: BossSettingsCapabilities {
                standby_timer: settings_access,
                wear_detection: settings_access,
                auto_aware: settings_access,
                auto_play_pause: settings_access,
                auto_answer: settings_access,
                volume_control: settings_access,
            },
            audio_modes: BossAudioModeCapabilities {
                modes: audio_modes_supported,
                current_mode: audio_modes_access,
                settings_config: audio_modes_access,
                favorites: audio_modes_access,
                custom_profiles: audio_modes_access,
                supported_prompts: audio_modes_supported,
            },
            sound: BossSoundCapabilities {
                equalizer: equalizer_access,
            },
        }
    }
}
