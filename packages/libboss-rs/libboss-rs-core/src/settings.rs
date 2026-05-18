use std::collections::BTreeMap;

use crate::{
    BmapFunction, BmapFunctionBlock, BmapOperator, BmapPacket, BossAudioModesCodec,
    BossAudioModesCodecError, BossVolumeControlStatus, Bytes,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BossStandbyTimerValue {
    pub minutes: i32,
    pub supports_two_byte_minutes: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BossOnHeadDetectionValue {
    pub is_enabled: bool,
    pub is_auto_play_enabled: Option<bool>,
    pub is_auto_answer_enabled: Option<bool>,
    pub is_auto_transparency_enabled: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct BossOnHeadDetectionPatch {
    pub is_enabled: Option<bool>,
    pub is_auto_play_enabled: Option<bool>,
    pub is_auto_answer_enabled: Option<bool>,
    pub is_auto_transparency_enabled: Option<bool>,
}

impl BossOnHeadDetectionPatch {
    pub fn is_empty(&self) -> bool {
        self.is_enabled.is_none()
            && self.is_auto_play_enabled.is_none()
            && self.is_auto_answer_enabled.is_none()
            && self.is_auto_transparency_enabled.is_none()
    }

    pub fn merged_with(&self, current: &BossOnHeadDetectionValue) -> BossOnHeadDetectionValue {
        BossOnHeadDetectionValue {
            is_enabled: self.is_enabled.unwrap_or(current.is_enabled),
            is_auto_play_enabled: self.is_auto_play_enabled.or(current.is_auto_play_enabled),
            is_auto_answer_enabled: self.is_auto_answer_enabled.or(current.is_auto_answer_enabled),
            is_auto_transparency_enabled: self.is_auto_transparency_enabled.or(current.is_auto_transparency_enabled),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BossDeviceSettings {
    pub wear_detection: Option<BossOnHeadDetectionValue>,
    pub auto_aware_enabled: Option<bool>,
    pub auto_play_pause_enabled: Option<bool>,
    pub auto_answer_enabled: Option<bool>,
    pub volume_control: Option<BossVolumeControlStatus>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BossSettingsCodecError {
    UnexpectedOperator { expected: BmapOperator, actual: BmapOperator },
    InvalidPayload(String),
}

pub struct BossSettingsCodec;

impl BossSettingsCodec {
    pub const SETTINGS_GET_ALL_FUNCTION_RAW: u8 = 0x01;
    pub const STANDBY_TIMER_FUNCTION_RAW: u8 = 0x04;
    pub const ON_HEAD_DETECTION_FUNCTION_RAW: u8 = 0x10;
    pub const AUTO_PLAY_PAUSE_FUNCTION_RAW: u8 = 0x18;
    pub const AUTO_ANSWER_FUNCTION_RAW: u8 = 0x1B;
    pub const VOLUME_CONTROL_FUNCTION_RAW: u8 = 0x1C;
    pub const AUTO_AWARE_FUNCTION_RAW: u8 = 0x1D;
    pub const RANGE_CONTROL_FUNCTION_RAW: u8 = 0x07;

    pub fn settings_packet(function_raw: u8, operator: BmapOperator, payload: Bytes) -> BmapPacket {
        let block = BmapFunctionBlock::Settings;
        BmapPacket::new(block, BmapFunction::from_raw(block, function_raw), 0, 0, operator, payload)
    }

    pub fn standby_timer_set_get_packet(minutes: i32) -> Result<BmapPacket, BossSettingsCodecError> {
        Self::validate_standby_timer_minutes(minutes)?;
        Ok(Self::settings_packet(
            Self::STANDBY_TIMER_FUNCTION_RAW,
            BmapOperator::SetGet,
            Self::encode_standby_timer_minutes(minutes),
        ))
    }

    pub fn on_head_detection_set_get_packet(value: &BossOnHeadDetectionValue) -> BmapPacket {
        Self::settings_packet(
            Self::ON_HEAD_DETECTION_FUNCTION_RAW,
            BmapOperator::SetGet,
            Self::encode_on_head_detection(value),
        )
    }

    pub fn equalizer_set_get_packet(target_level: i32, band: BossEqualizerBand) -> Result<BmapPacket, BossSettingsCodecError> {
        if !(-128..=127).contains(&target_level) {
            return Err(BossSettingsCodecError::InvalidPayload(
                "Equalizer target level must be in range -128...127".into(),
            ));
        }
        Ok(Self::settings_packet(
            Self::RANGE_CONTROL_FUNCTION_RAW,
            BmapOperator::SetGet,
            vec![(target_level as i8) as u8, band.raw_value()],
        ))
    }

    pub fn encode_standby_timer_minutes(minutes: i32) -> Bytes {
        if minutes <= 0xFF {
            return vec![minutes as u8];
        }
        vec![(minutes & 0xFF) as u8, ((minutes >> 8) & 0xFF) as u8]
    }

    pub fn parse_standby_timer(packet: &BmapPacket) -> Result<BossStandbyTimerValue, BossSettingsCodecError> {
        Self::require_status(packet)?;
        if packet.payload.is_empty() {
            return Err(BossSettingsCodecError::InvalidPayload("Standby timer payload was empty".into()));
        }
        if packet.payload.len() < 3 {
            return Ok(BossStandbyTimerValue { minutes: packet.payload[0] as i32, supports_two_byte_minutes: false });
        }
        let minutes = ((packet.payload[2] as i32) << 8) | packet.payload[0] as i32;
        Ok(BossStandbyTimerValue { minutes, supports_two_byte_minutes: true })
    }

    pub fn parse_enabled_flag(packet: &BmapPacket) -> Result<bool, BossSettingsCodecError> {
        Self::require_status(packet)?;
        let Some(first) = packet.payload.first().copied() else {
            return Err(BossSettingsCodecError::InvalidPayload("Expected at least one payload byte".into()));
        };
        Ok((first & 0x01) == 0x01)
    }

    pub fn parse_on_head_detection(packet: &BmapPacket) -> Result<BossOnHeadDetectionValue, BossSettingsCodecError> {
        Self::require_status(packet)?;
        if packet.payload.len() < 2 {
            return Err(BossSettingsCodecError::InvalidPayload("Expected at least two payload bytes for on-head detection".into()));
        }
        let flags = packet.payload[0];
        let values = packet.payload[1];
        Ok(BossOnHeadDetectionValue {
            is_enabled: (flags & 0x01) == 0x01,
            is_auto_play_enabled: if (flags & 0x02) == 0x02 { Some((values & 0x01) == 0x01) } else { None },
            is_auto_answer_enabled: if (flags & 0x04) == 0x04 { Some((values & 0x02) == 0x02) } else { None },
            is_auto_transparency_enabled: if (flags & 0x08) == 0x08 { Some((values & 0x04) == 0x04) } else { None },
        })
    }

    pub fn encode_on_head_detection(value: &BossOnHeadDetectionValue) -> Bytes {
        vec![
            if value.is_enabled { 0x01 } else { 0x00 },
            (if value.is_auto_play_enabled == Some(true) { 0x01 } else { 0x00 })
                | (if value.is_auto_answer_enabled == Some(true) { 0x02 } else { 0x00 })
                | (if value.is_auto_transparency_enabled == Some(true) { 0x04 } else { 0x00 }),
        ]
    }

    pub fn parse_equalizer(packet: &BmapPacket) -> Result<BossEqualizerSettings, BossSettingsCodecError> {
        Self::require_status(packet)?;
        if packet.payload.len() % 4 != 0 {
            return Err(BossSettingsCodecError::InvalidPayload(
                "Expected range-control payload length to be a multiple of four bytes".into(),
            ));
        }
        let mut ranges = Vec::new();
        for chunk in packet.payload.chunks_exact(4) {
            ranges.push(BossEqualizerRangeLevel {
                band: BossEqualizerBand::from_raw(chunk[3]),
                current_level: (chunk[2] as i8) as i32,
                min_level: (chunk[0] as i8) as i32,
                max_level: (chunk[1] as i8) as i32,
            });
        }
        Ok(BossEqualizerSettings::new(ranges))
    }

    fn validate_standby_timer_minutes(minutes: i32) -> Result<(), BossSettingsCodecError> {
        if !(0..=0xFFFF).contains(&minutes) {
            return Err(BossSettingsCodecError::InvalidPayload(
                "Standby timer minutes must be in range 0...65535".into(),
            ));
        }
        Ok(())
    }

    fn require_status(packet: &BmapPacket) -> Result<(), BossSettingsCodecError> {
        if packet.operator != BmapOperator::Status {
            return Err(BossSettingsCodecError::UnexpectedOperator { expected: BmapOperator::Status, actual: packet.operator });
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BossSettingsSnapshot {
    packets_by_function_raw: BTreeMap<u8, BmapPacket>,
}

impl BossSettingsSnapshot {
    pub fn new(packets_by_function_raw: BTreeMap<u8, BmapPacket>) -> Self {
        Self { packets_by_function_raw }
    }

    pub fn packet(&self, function_raw: u8) -> Option<&BmapPacket> {
        self.packets_by_function_raw.get(&function_raw)
    }

    pub fn standby_timer(&self) -> Result<Option<BossStandbyTimerValue>, BossSettingsCodecError> {
        self.packet(BossSettingsCodec::STANDBY_TIMER_FUNCTION_RAW)
            .map(BossSettingsCodec::parse_standby_timer)
            .transpose()
    }

    pub fn auto_aware(&self) -> Result<Option<bool>, BossSettingsCodecError> {
        self.packet(BossSettingsCodec::AUTO_AWARE_FUNCTION_RAW)
            .map(BossSettingsCodec::parse_enabled_flag)
            .transpose()
    }

    pub fn on_head_detection(&self) -> Result<Option<BossOnHeadDetectionValue>, BossSettingsCodecError> {
        self.packet(BossSettingsCodec::ON_HEAD_DETECTION_FUNCTION_RAW)
            .map(BossSettingsCodec::parse_on_head_detection)
            .transpose()
    }

    pub fn auto_play_pause(&self) -> Result<Option<bool>, BossSettingsCodecError> {
        self.packet(BossSettingsCodec::AUTO_PLAY_PAUSE_FUNCTION_RAW)
            .map(BossSettingsCodec::parse_enabled_flag)
            .transpose()
    }

    pub fn auto_answer(&self) -> Result<Option<bool>, BossSettingsCodecError> {
        if let Some(packet) = self.packet(BossSettingsCodec::AUTO_ANSWER_FUNCTION_RAW) {
            return BossSettingsCodec::parse_enabled_flag(packet).map(Some);
        }
        Ok(self.on_head_detection()?.and_then(|value| value.is_auto_answer_enabled))
    }

    pub fn volume_control(&self) -> Result<Option<BossVolumeControlStatus>, BossAudioModesCodecError> {
        self.packet(BossSettingsCodec::VOLUME_CONTROL_FUNCTION_RAW)
            .map(BossAudioModesCodec::parse_volume_control_status)
            .transpose()
    }

    pub fn device_settings(&self) -> Result<BossDeviceSettings, BossSettingsCodecError> {
        Ok(BossDeviceSettings {
            wear_detection: self.on_head_detection()?,
            auto_aware_enabled: self.auto_aware()?,
            auto_play_pause_enabled: self.auto_play_pause()?,
            auto_answer_enabled: self.auto_answer()?,
            volume_control: None,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum BossEqualizerBand {
    Bass,
    Mid,
    Treble,
    Unknown(u8),
}

impl BossEqualizerBand {
    pub fn from_raw(raw: u8) -> Self {
        match raw {
            0 => Self::Bass,
            1 => Self::Mid,
            2 => Self::Treble,
            value => Self::Unknown(value),
        }
    }

    pub fn raw_value(&self) -> u8 {
        match self {
            Self::Bass => 0,
            Self::Mid => 1,
            Self::Treble => 2,
            Self::Unknown(value) => *value,
        }
    }

    pub fn display_name(&self) -> String {
        match self {
            Self::Bass => "bass".into(),
            Self::Mid => "mid".into(),
            Self::Treble => "treble".into(),
            Self::Unknown(value) => format!("unknown({value})"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BossEqualizerRangeLevel {
    pub band: BossEqualizerBand,
    pub current_level: i32,
    pub min_level: i32,
    pub max_level: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BossEqualizerSettings {
    pub ranges: Vec<BossEqualizerRangeLevel>,
}

impl BossEqualizerSettings {
    pub fn new(mut ranges: Vec<BossEqualizerRangeLevel>) -> Self {
        ranges.sort_by_key(|range| range.band.raw_value());
        Self { ranges }
    }

    pub fn range(&self, band: &BossEqualizerBand) -> Option<&BossEqualizerRangeLevel> {
        self.ranges.iter().find(|range| &range.band == band)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct BossEqualizerSettingsPatch {
    pub bass: Option<i32>,
    pub mid: Option<i32>,
    pub treble: Option<i32>,
}

impl BossEqualizerSettingsPatch {
    pub fn is_empty(&self) -> bool {
        self.bass.is_none() && self.mid.is_none() && self.treble.is_none()
    }

    pub fn requested_levels(&self) -> Vec<(BossEqualizerBand, i32)> {
        let mut values = Vec::new();
        if let Some(bass) = self.bass {
            values.push((BossEqualizerBand::Bass, bass));
        }
        if let Some(mid) = self.mid {
            values.push((BossEqualizerBand::Mid, mid));
        }
        if let Some(treble) = self.treble {
            values.push((BossEqualizerBand::Treble, treble));
        }
        values
    }

    pub fn matches(&self, settings: &BossEqualizerSettings) -> bool {
        for (band, level) in self.requested_levels() {
            if settings.range(&band).map(|range| range.current_level) != Some(level) {
                return false;
            }
        }
        true
    }
}
