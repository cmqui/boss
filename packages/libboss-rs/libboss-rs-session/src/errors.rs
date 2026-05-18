use libboss_rs_core::{
    BmapErrorCode, BossAudioModesCodecError, BossSettingsCodecError, ProductInfoParseError,
    UnexpectedOperatorError,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BossLinkError {
    TimedOut,
    UnexpectedStreamTermination,
    Other(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BootstrapTimeoutError {
    BmapVersion { timeout_milliseconds: u64 },
    Packet { function: String, timeout_milliseconds: u64 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BmapResponseError {
    pub context: String,
    pub payload_hex: String,
}

impl BmapResponseError {
    pub fn code(&self) -> Option<BmapErrorCode> {
        if self.payload_hex.len() != 2 {
            return None;
        }
        u8::from_str_radix(&self.payload_hex, 16)
            .ok()
            .and_then(BmapErrorCode::from_raw)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BossSessionError {
    ResponseStreamEnded,
    ResponseTimedOut { seconds: i64 },
    BmapErrorResponse(BmapResponseError),
    UnexpectedOperator(UnexpectedOperatorError),
    ModeChangeNotObserved { target_index: i32, observed_index: i32 },
    EqualizerNotObserved { expected: String, observed: String },
    SettingsConfigNotObserved { expected: String, observed: String },
    ProductInfo(ProductInfoParseError),
    SettingsCodec(BossSettingsCodecError),
    AudioModesCodec(BossAudioModesCodecError),
    UnsupportedOperation(String),
}

impl From<ProductInfoParseError> for BossSessionError {
    fn from(value: ProductInfoParseError) -> Self {
        Self::ProductInfo(value)
    }
}

impl From<BossSettingsCodecError> for BossSessionError {
    fn from(value: BossSettingsCodecError) -> Self {
        Self::SettingsCodec(value)
    }
}

impl From<BossAudioModesCodecError> for BossSessionError {
    fn from(value: BossAudioModesCodecError) -> Self {
        Self::AudioModesCodec(value)
    }
}

impl BossSessionError {
    pub fn bmap_error_code(&self) -> Option<BmapErrorCode> {
        match self {
            Self::BmapErrorResponse(error) => error.code(),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BossSettingSource {
    Snapshot,
    CompositeSnapshot,
    DirectGet,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BossSettingUnavailableReason {
    MissingFromSnapshot,
    TimedOut,
    ResponseStreamEnded,
    FunctionUnsupported,
    OperatorUnsupported,
    DataUnavailable,
    InsecureTransport,
    UnexpectedStreamTermination,
    BmapError(Option<BmapErrorCode>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BootstrapSessionError {
    Timeout(BootstrapTimeoutError),
    Session(BossSessionError),
    ProductInfo(ProductInfoParseError),
}

impl BootstrapSessionError {
    pub(crate) fn from_session_error_with_timeout(
        error: BossSessionError,
        timeout: BootstrapTimeoutError,
    ) -> Self {
        match error {
            BossSessionError::ResponseTimedOut { .. } => Self::Timeout(timeout),
            other => Self::Session(other),
        }
    }
}

impl From<ProductInfoParseError> for BootstrapSessionError {
    fn from(value: ProductInfoParseError) -> Self {
        Self::ProductInfo(value)
    }
}

pub(crate) fn duration_seconds(timeout_millis: u64) -> i64 {
    (timeout_millis / 1000) as i64
}

pub(crate) fn link_error_to_session_error(error: BossLinkError) -> BossSessionError {
    match error {
        BossLinkError::TimedOut => BossSessionError::ResponseTimedOut { seconds: 0 },
        BossLinkError::UnexpectedStreamTermination => BossSessionError::ResponseStreamEnded,
        BossLinkError::Other(message) => BossSessionError::UnsupportedOperation(message),
    }
}

pub(crate) fn hex_string(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02X}")).collect()
}
