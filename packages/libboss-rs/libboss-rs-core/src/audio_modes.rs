use crate::{BmapFunction, BmapFunctionBlock, BmapOperator, BmapPacket, Bytes};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BossVolumeControlValue {
    Disabled,
    Button,
    CapTouch,
    Imu,
}

impl BossVolumeControlValue {
    pub fn from_raw(raw: u8) -> Option<Self> {
        Some(match raw {
            0 => Self::Disabled,
            1 => Self::Button,
            2 => Self::CapTouch,
            3 => Self::Imu,
            _ => return None,
        })
    }

    pub fn raw_value(&self) -> u8 {
        match self {
            Self::Disabled => 0,
            Self::Button => 1,
            Self::CapTouch => 2,
            Self::Imu => 3,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BossVolumeControlStatus {
    pub value: BossVolumeControlValue,
    pub supported_values: Option<Vec<BossVolumeControlValue>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BossAudioModesCapabilities {
    pub bose_modes: i32,
    pub user_modes: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BossAudioModeInfo {
    pub mode_index: i32,
    pub name: String,
    pub favorite: bool,
    pub user_configurable: bool,
    pub user_configured: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BossAudioModePrompt {
    pub byte1: u8,
    pub byte2: u8,
    pub name: &'static str,
}

impl BossAudioModePrompt {
    pub const NONE: Self = Self { byte1: 0, byte2: 0, name: "None" };
    pub const QUIET: Self = Self { byte1: 0, byte2: 1, name: "Quiet" };
    pub const AWARE: Self = Self { byte1: 0, byte2: 2, name: "Aware" };
    pub const TRANSPARENT: Self = Self { byte1: 0, byte2: 3, name: "Transparent" };
    pub const TRANSPARENCY: Self = Self { byte1: 0, byte2: 4, name: "Transparency" };
    pub const MASKING: Self = Self { byte1: 0, byte2: 5, name: "Masking" };
    pub const COMFORT: Self = Self { byte1: 0, byte2: 6, name: "Comfort" };
    pub const COMMUTE: Self = Self { byte1: 0, byte2: 7, name: "Commute" };
    pub const OUTDOOR: Self = Self { byte1: 0, byte2: 8, name: "Outdoor" };
    pub const WORKOUT: Self = Self { byte1: 0, byte2: 9, name: "Workout" };
    pub const HOME: Self = Self { byte1: 0, byte2: 10, name: "Home" };
    pub const WORK: Self = Self { byte1: 0, byte2: 11, name: "Work" };
    pub const MUSIC: Self = Self { byte1: 0, byte2: 12, name: "Music" };
    pub const FOCUS: Self = Self { byte1: 0, byte2: 13, name: "Focus" };
    pub const RELAX: Self = Self { byte1: 0, byte2: 14, name: "Relax" };
    pub const FLIGHT: Self = Self { byte1: 0, byte2: 15, name: "Flight" };
    pub const AIRPORT: Self = Self { byte1: 0, byte2: 16, name: "Airport" };
    pub const DRIVING: Self = Self { byte1: 0, byte2: 17, name: "Driving" };
    pub const TRAINING: Self = Self { byte1: 0, byte2: 18, name: "Training" };
    pub const GYM: Self = Self { byte1: 0, byte2: 19, name: "Gym" };
    pub const RUN: Self = Self { byte1: 0, byte2: 20, name: "Run" };
    pub const WALK: Self = Self { byte1: 0, byte2: 21, name: "Walk" };
    pub const HIKE: Self = Self { byte1: 0, byte2: 22, name: "Hike" };
    pub const TALK: Self = Self { byte1: 0, byte2: 23, name: "Talk" };
    pub const CALL: Self = Self { byte1: 0, byte2: 24, name: "Call" };
    pub const WHISPER: Self = Self { byte1: 0, byte2: 25, name: "Whisper" };
    pub const HEARING: Self = Self { byte1: 0, byte2: 26, name: "Hearing" };
    pub const LEARN: Self = Self { byte1: 0, byte2: 27, name: "Learn" };
    pub const PODCAST: Self = Self { byte1: 0, byte2: 28, name: "Podcast" };
    pub const AUDIOBOOK: Self = Self { byte1: 0, byte2: 29, name: "Audiobook" };
    pub const CALM: Self = Self { byte1: 0, byte2: 30, name: "Calm" };
    pub const SLEEP: Self = Self { byte1: 0, byte2: 31, name: "Sleep" };
    pub const MEDITATE: Self = Self { byte1: 0, byte2: 32, name: "Meditate" };
    pub const YOGA: Self = Self { byte1: 0, byte2: 33, name: "Yoga" };
    pub const IMMERSION: Self = Self { byte1: 0, byte2: 34, name: "Immersion" };
    pub const STEREO: Self = Self { byte1: 0, byte2: 35, name: "Stereo" };
    pub const CINEMA: Self = Self { byte1: 0, byte2: 36, name: "Cinema" };

    pub const ALL_KNOWN: [Self; 37] = [
        Self::NONE, Self::QUIET, Self::AWARE, Self::TRANSPARENT, Self::TRANSPARENCY, Self::MASKING, Self::COMFORT,
        Self::COMMUTE, Self::OUTDOOR, Self::WORKOUT, Self::HOME, Self::WORK, Self::MUSIC, Self::FOCUS, Self::RELAX,
        Self::FLIGHT, Self::AIRPORT, Self::DRIVING, Self::TRAINING, Self::GYM, Self::RUN, Self::WALK, Self::HIKE,
        Self::TALK, Self::CALL, Self::WHISPER, Self::HEARING, Self::LEARN, Self::PODCAST, Self::AUDIOBOOK, Self::CALM,
        Self::SLEEP, Self::MEDITATE, Self::YOGA, Self::IMMERSION, Self::STEREO, Self::CINEMA,
    ];

    pub fn known(byte1: u8, byte2: u8) -> Self {
        Self::ALL_KNOWN
            .iter()
            .copied()
            .find(|prompt| prompt.byte1 == byte1 && prompt.byte2 == byte2)
            .unwrap_or(Self { byte1, byte2, name: "Unknown" })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BossSpatialAudioMode {
    Off,
    Room,
    Head,
}

impl BossSpatialAudioMode {
    pub fn from_raw(raw: u8) -> Option<Self> {
        Some(match raw {
            0 => Self::Off,
            1 => Self::Room,
            2 => Self::Head,
            _ => return None,
        })
    }

    pub fn raw_value(&self) -> u8 {
        match self {
            Self::Off => 0,
            Self::Room => 1,
            Self::Head => 2,
        }
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Off => "off",
            Self::Room => "room",
            Self::Head => "head",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BossAudioModeSettingsConfig {
    pub cnc_level: i32,
    pub auto_cnc_enabled: bool,
    pub spatial_audio_mode: BossSpatialAudioMode,
    pub wind_block_enabled: bool,
    pub anc_toggle_enabled: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BossAudioModeConfig {
    pub mode_index: i32,
    pub prompt: BossAudioModePrompt,
    pub name: String,
    pub favorite: bool,
    pub user_configurable: bool,
    pub user_configured: bool,
    pub settings: BossAudioModeSettingsConfig,
}

impl BossAudioModeConfig {
    pub fn info(&self) -> BossAudioModeInfo {
        BossAudioModeInfo {
            mode_index: self.mode_index,
            name: self.name.clone(),
            favorite: self.favorite,
            user_configurable: self.user_configurable,
            user_configured: self.user_configured,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct BossAudioModeSettingsConfigPatch {
    pub cnc_level: Option<i32>,
    pub auto_cnc_enabled: Option<bool>,
    pub spatial_audio_mode: Option<BossSpatialAudioMode>,
    pub wind_block_enabled: Option<bool>,
    pub anc_toggle_enabled: Option<bool>,
}

impl BossAudioModeSettingsConfigPatch {
    pub fn is_empty(&self) -> bool {
        self.cnc_level.is_none()
            && self.auto_cnc_enabled.is_none()
            && self.spatial_audio_mode.is_none()
            && self.wind_block_enabled.is_none()
            && self.anc_toggle_enabled.is_none()
    }

    pub fn merged_with(&self, current: &BossAudioModeSettingsConfig) -> BossAudioModeSettingsConfig {
        BossAudioModeSettingsConfig {
            cnc_level: self.cnc_level.unwrap_or(current.cnc_level),
            auto_cnc_enabled: self.auto_cnc_enabled.unwrap_or(current.auto_cnc_enabled),
            spatial_audio_mode: self.spatial_audio_mode.unwrap_or(current.spatial_audio_mode),
            wind_block_enabled: self.wind_block_enabled.unwrap_or(current.wind_block_enabled),
            anc_toggle_enabled: self.anc_toggle_enabled.unwrap_or(current.anc_toggle_enabled),
        }
    }

    pub fn matches(&self, config: &BossAudioModeSettingsConfig) -> bool {
        if let Some(value) = self.cnc_level {
            if config.cnc_level != value {
                return false;
            }
        }
        if let Some(value) = self.auto_cnc_enabled {
            if config.auto_cnc_enabled != value {
                return false;
            }
        }
        if let Some(value) = self.spatial_audio_mode {
            if config.spatial_audio_mode != value {
                return false;
            }
        }
        if let Some(value) = self.wind_block_enabled {
            if config.wind_block_enabled != value {
                return false;
            }
        }
        if let Some(value) = self.anc_toggle_enabled {
            if config.anc_toggle_enabled != value {
                return false;
            }
        }
        true
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BossAudioModesCodecError {
    UnexpectedOperator { expected: BmapOperator, actual: BmapOperator },
    InvalidPayload(String),
}

pub struct BossAudioModesCodec;

impl BossAudioModesCodec {
    pub const CAPABILITIES_FUNCTION_RAW: u8 = 0x02;
    pub const CURRENT_MODE_FUNCTION_RAW: u8 = 0x03;
    pub const MODE_CONFIG_FUNCTION_RAW: u8 = 0x06;
    pub const FAVORITES_FUNCTION_RAW: u8 = 0x08;
    pub const SETTINGS_CONFIG_FUNCTION_RAW: u8 = 0x0A;
    pub const NAMES_SUPPORTED_FUNCTION_RAW: u8 = 0x0B;

    pub fn packet(function_raw: u8, operator: BmapOperator, payload: Bytes) -> BmapPacket {
        let block = BmapFunctionBlock::AudioModes;
        BmapPacket::new(block, BmapFunction::from_raw(block, function_raw), 0, 0, operator, payload)
    }

    pub fn names_supported_get_packet() -> BmapPacket {
        Self::packet(Self::NAMES_SUPPORTED_FUNCTION_RAW, BmapOperator::Get, vec![])
    }

    pub fn current_mode_get_packet() -> BmapPacket {
        Self::packet(Self::CURRENT_MODE_FUNCTION_RAW, BmapOperator::Get, vec![])
    }

    pub fn current_mode_start_packet(mode_index: i32, play_voice_prompt: bool) -> BmapPacket {
        Self::packet(
            Self::CURRENT_MODE_FUNCTION_RAW,
            BmapOperator::Start,
            vec![mode_index as u8, if play_voice_prompt { 0x01 } else { 0x00 }],
        )
    }

    pub fn capabilities_get_packet() -> BmapPacket {
        Self::packet(Self::CAPABILITIES_FUNCTION_RAW, BmapOperator::Get, vec![])
    }

    pub fn mode_config_get_packet(mode_index: i32) -> BmapPacket {
        Self::packet(Self::MODE_CONFIG_FUNCTION_RAW, BmapOperator::Get, vec![mode_index as u8])
    }

    pub fn mode_config_start_packet() -> BmapPacket {
        Self::packet(Self::MODE_CONFIG_FUNCTION_RAW, BmapOperator::Start, vec![])
    }

    pub fn favorites_get_packet() -> BmapPacket {
        Self::packet(Self::FAVORITES_FUNCTION_RAW, BmapOperator::Get, vec![])
    }

    pub fn settings_config_get_packet() -> BmapPacket {
        Self::packet(Self::SETTINGS_CONFIG_FUNCTION_RAW, BmapOperator::Get, vec![])
    }

    pub fn settings_config_set_get_packet(config: &BossAudioModeSettingsConfig) -> Result<BmapPacket, BossAudioModesCodecError> {
        Ok(Self::packet(
            Self::SETTINGS_CONFIG_FUNCTION_RAW,
            BmapOperator::SetGet,
            Self::encode_settings_config(config)?,
        ))
    }

    pub fn mode_config_set_get_packet(
        mode_index: i32,
        prompt: BossAudioModePrompt,
        name: &str,
        settings: &BossAudioModeSettingsConfig,
    ) -> Result<BmapPacket, BossAudioModesCodecError> {
        Ok(Self::packet(
            Self::MODE_CONFIG_FUNCTION_RAW,
            BmapOperator::SetGet,
            Self::encode_mode_config_set_get_payload(mode_index, prompt, name, settings)?,
        ))
    }

    pub fn parse_capabilities(packet: &BmapPacket) -> Result<BossAudioModesCapabilities, BossAudioModesCodecError> {
        Self::require_status(packet)?;
        if packet.payload.len() < 2 {
            return Err(BossAudioModesCodecError::InvalidPayload("Expected at least two payload bytes for audio mode capabilities".into()));
        }
        Ok(BossAudioModesCapabilities {
            bose_modes: packet.payload[0] as i32,
            user_modes: packet.payload[1] as i32,
        })
    }

    pub fn parse_current_mode(packet: &BmapPacket) -> Result<i32, BossAudioModesCodecError> {
        Self::require_status(packet)?;
        let Some(first) = packet.payload.first().copied() else {
            return Err(BossAudioModesCodecError::InvalidPayload("Expected at least one payload byte for current audio mode".into()));
        };
        Ok(first as i32)
    }

    pub fn parse_settings_config(packet: &BmapPacket) -> Result<BossAudioModeSettingsConfig, BossAudioModesCodecError> {
        Self::require_status(packet)?;
        if packet.payload.len() < 5 {
            return Err(BossAudioModesCodecError::InvalidPayload("Expected at least five payload bytes for audio mode settings config".into()));
        }
        let Some(spatial_audio_mode) = BossSpatialAudioMode::from_raw(packet.payload[2]) else {
            return Err(BossAudioModesCodecError::InvalidPayload(format!("Unknown spatial audio mode: {}", packet.payload[2])));
        };
        Ok(BossAudioModeSettingsConfig {
            cnc_level: packet.payload[0] as i32,
            auto_cnc_enabled: packet.payload[1] != 0,
            spatial_audio_mode,
            wind_block_enabled: packet.payload[3] != 0,
            anc_toggle_enabled: packet.payload[4] != 0,
        })
    }

    pub fn parse_mode_config(packet: &BmapPacket) -> Result<BossAudioModeInfo, BossAudioModesCodecError> {
        Ok(Self::parse_mode_config_detail(packet)?.info())
    }

    pub fn parse_mode_config_detail(packet: &BmapPacket) -> Result<BossAudioModeConfig, BossAudioModesCodecError> {
        Self::require_status(packet)?;
        let payload = &packet.payload;
        if payload.len() >= 45 {
            let Some(spatial_audio_mode) = BossSpatialAudioMode::from_raw(payload[44]) else {
                return Err(BossAudioModesCodecError::InvalidPayload(format!("Unknown spatial audio mode: {}", payload[44])));
            };
            return Ok(BossAudioModeConfig {
                mode_index: payload[0] as i32,
                prompt: BossAudioModePrompt::known(payload[1], payload[2]),
                name: Self::parse_mode_name(payload, 6..38),
                favorite: payload[5] == 1,
                user_configurable: payload[3] == 1,
                user_configured: payload[4] == 1,
                settings: BossAudioModeSettingsConfig {
                    cnc_level: payload[42] as i32,
                    auto_cnc_enabled: payload[43] != 0,
                    spatial_audio_mode,
                    wind_block_enabled: if payload.len() >= 47 { payload[46] != 0 } else { false },
                    anc_toggle_enabled: if payload.len() >= 48 { payload[47] != 0 } else { false },
                },
            });
        }
        if payload.len() >= 40 {
            let Some(spatial_audio_mode) = BossSpatialAudioMode::from_raw(payload[37]) else {
                return Err(BossAudioModesCodecError::InvalidPayload(format!("Unknown spatial audio mode: {}", payload[37])));
            };
            return Ok(BossAudioModeConfig {
                mode_index: payload[0] as i32,
                prompt: BossAudioModePrompt::known(payload[1], payload[2]),
                name: Self::parse_mode_name(payload, 3..35),
                favorite: false,
                user_configurable: true,
                user_configured: true,
                settings: BossAudioModeSettingsConfig {
                    cnc_level: payload[35] as i32,
                    auto_cnc_enabled: payload[36] != 0,
                    spatial_audio_mode,
                    wind_block_enabled: payload[38] != 0,
                    anc_toggle_enabled: payload[39] != 0,
                },
            });
        }
        Err(BossAudioModesCodecError::InvalidPayload("Expected at least 40 payload bytes for audio mode config".into()))
    }

    pub fn encode_settings_config(config: &BossAudioModeSettingsConfig) -> Result<Bytes, BossAudioModesCodecError> {
        if !(0..=10).contains(&config.cnc_level) {
            return Err(BossAudioModesCodecError::InvalidPayload("CNC level must be in range 0...10".into()));
        }
        Ok(vec![
            config.cnc_level as u8,
            if config.auto_cnc_enabled { 0x01 } else { 0x00 },
            config.spatial_audio_mode.raw_value(),
            if config.wind_block_enabled { 0x01 } else { 0x00 },
            if config.anc_toggle_enabled { 0x01 } else { 0x00 },
        ])
    }

    pub fn encode_mode_config_set_get_payload(
        mode_index: i32,
        prompt: BossAudioModePrompt,
        name: &str,
        settings: &BossAudioModeSettingsConfig,
    ) -> Result<Bytes, BossAudioModesCodecError> {
        if !(0..=255).contains(&mode_index) {
            return Err(BossAudioModesCodecError::InvalidPayload("Mode index must be in range 0...255".into()));
        }
        let mut payload = Vec::with_capacity(40);
        payload.push(mode_index as u8);
        payload.push(prompt.byte1);
        payload.push(prompt.byte2);
        payload.extend_from_slice(&Self::encode_mode_name(name));
        payload.extend_from_slice(&Self::encode_settings_config(settings)?);
        Ok(payload)
    }

    pub fn parse_supported_prompts(packet: &BmapPacket) -> Result<Vec<BossAudioModePrompt>, BossAudioModesCodecError> {
        Self::require_status(packet)?;
        let mut prompts = Vec::new();
        for (byte_index, byte) in packet.payload.iter().copied().take(5).enumerate() {
            let max_bit = if byte_index == 4 { 4 } else { 7 };
            for bit_index in 0..=max_bit {
                if ((byte >> bit_index) & 1) == 1 {
                    prompts.push(BossAudioModePrompt::known(0, (byte_index * 8 + bit_index) as u8));
                }
            }
        }
        Ok(prompts)
    }

    pub fn parse_favorites(packet: &BmapPacket) -> Result<Vec<i32>, BossAudioModesCodecError> {
        Self::require_status(packet)?;
        let Some(number_of_modes) = packet.payload.first().copied() else {
            return Err(BossAudioModesCodecError::InvalidPayload("Expected at least one payload byte for audio mode favorites".into()));
        };
        let number_of_modes = number_of_modes as usize;
        let bitmask_byte_count = number_of_modes.div_ceil(8);
        if packet.payload.len() < bitmask_byte_count + 1 {
            return Err(BossAudioModesCodecError::InvalidPayload(format!(
                "Expected {} payload bytes for audio mode favorites",
                bitmask_byte_count + 1
            )));
        }
        let mut favorites = Vec::new();
        for payload_index in (1..=bitmask_byte_count).rev() {
            let byte = packet.payload[payload_index];
            for bit_index in 0..8 {
                if ((byte >> bit_index) & 1) == 1 {
                    let mode_index = (bitmask_byte_count - payload_index) * 8 + bit_index as usize;
                    if mode_index < number_of_modes {
                        favorites.push(mode_index as i32);
                    }
                }
            }
        }
        Ok(favorites)
    }

    pub fn encode_favorites(number_of_modes: i32, favorite_mode_indices: &[i32]) -> Result<Bytes, BossAudioModesCodecError> {
        if !(0..=255).contains(&number_of_modes) {
            return Err(BossAudioModesCodecError::InvalidPayload("Number of audio modes must be in range 0...255".into()));
        }
        let number_of_modes = number_of_modes as usize;
        let mut unique = favorite_mode_indices.to_vec();
        unique.sort();
        unique.dedup();
        if !unique.iter().all(|index| *index >= 0 && (*index as usize) < number_of_modes) {
            return Err(BossAudioModesCodecError::InvalidPayload(format!(
                "Favorite mode indices must be in range 0..<{}",
                number_of_modes
            )));
        }
        let bitmask_byte_count = number_of_modes.div_ceil(8);
        let mut payload = vec![0u8; bitmask_byte_count + 1];
        payload[0] = number_of_modes as u8;
        for favorite_mode_index in unique {
            let favorite_mode_index = favorite_mode_index as usize;
            let bitmask_offset = bitmask_byte_count - (favorite_mode_index / 8);
            payload[bitmask_offset] |= 1 << (favorite_mode_index % 8);
        }
        Ok(payload)
    }

    pub fn parse_volume_control_status(packet: &BmapPacket) -> Result<BossVolumeControlStatus, BossAudioModesCodecError> {
        Self::require_status(packet)?;
        let Some(first) = packet.payload.first().copied() else {
            return Err(BossAudioModesCodecError::InvalidPayload("Expected at least one payload byte for volume control".into()));
        };
        let value = BossVolumeControlValue::from_raw(first).unwrap_or(BossVolumeControlValue::Disabled);
        let supported_values = if packet.payload.len() > 1 {
            let bitmask = packet.payload[1];
            Some(
                [
                    if (bitmask & 0x01) == 0x01 { Some(BossVolumeControlValue::Button) } else { None },
                    if (bitmask & 0x02) == 0x02 { Some(BossVolumeControlValue::CapTouch) } else { None },
                    if (bitmask & 0x04) == 0x04 { Some(BossVolumeControlValue::Imu) } else { None },
                ]
                .into_iter()
                .flatten()
                .collect(),
            )
        } else {
            None
        };
        Ok(BossVolumeControlStatus { value, supported_values })
    }

    fn require_status(packet: &BmapPacket) -> Result<(), BossAudioModesCodecError> {
        if packet.operator != BmapOperator::Status {
            return Err(BossAudioModesCodecError::UnexpectedOperator { expected: BmapOperator::Status, actual: packet.operator });
        }
        Ok(())
    }

    fn parse_mode_name(payload: &[u8], range: std::ops::Range<usize>) -> String {
        let name_field = &payload[range];
        let zero_index = name_field.iter().position(|byte| *byte == 0).unwrap_or(name_field.len());
        String::from_utf8_lossy(&name_field[..zero_index]).to_string()
    }

    fn encode_mode_name(name: &str) -> Bytes {
        let bytes = name.as_bytes();
        let bytes = &bytes[..usize::min(bytes.len(), 31)];
        let mut data = vec![0u8; 32];
        data[..bytes.len()].copy_from_slice(bytes);
        data
    }
}
