use libboss_rs_core::{
    BmapVersionInfo, BossOnHeadDetectionValue, BossTransportKind, BossVolumeControlStatus,
    FunctionBlockSet, ProductIdVariant,
};

use crate::{BossSettingSource, BossSettingUnavailableReason};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BossObservedSetting<T> {
    pub value: Option<T>,
    pub source: Option<BossSettingSource>,
    pub unavailable_reason: Option<BossSettingUnavailableReason>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BossDeviceSettingsReport {
    pub wear_detection: BossObservedSetting<BossOnHeadDetectionValue>,
    pub auto_aware_enabled: BossObservedSetting<bool>,
    pub auto_play_pause_enabled: BossObservedSetting<bool>,
    pub auto_answer_enabled: BossObservedSetting<bool>,
    pub volume_control: BossObservedSetting<BossVolumeControlStatus>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BootstrappedDevice {
    pub bmap_version: BmapVersionInfo,
    pub product_id: u16,
    pub product_name: String,
    pub product_variant: ProductIdVariant,
    pub supported_function_blocks: FunctionBlockSet,
    pub transport_kind: BossTransportKind,
    pub default_device_id: i32,
    pub default_port: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionConfiguration {
    pub default_device_id: i32,
    pub default_port: i32,
    pub first_version_timeout_millis: u64,
    pub retry_version_timeout_millis: u64,
    pub request_timeout_millis: u64,
}

impl Default for SessionConfiguration {
    fn default() -> Self {
        Self {
            default_device_id: 0,
            default_port: 0,
            first_version_timeout_millis: 2_000,
            retry_version_timeout_millis: 50_000,
            request_timeout_millis: 5_000,
        }
    }
}
