use crate::{Bytes, PacketDecodeError, PacketEncodeError};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum BmapFunctionBlock {
    ProductInfo,
    Settings,
    Status,
    FirmwareUpdate,
    DeviceManagement,
    AudioManagement,
    CallManagement,
    Control,
    Debug,
    Notification,
    ReservedBosebuild1,
    ReservedBosebuild2,
    HearingAssistance,
    DataCollection,
    HeartRate,
    PeerBud,
    Vpa,
    Wifi,
    Authentication,
    Experimental,
    Cloud,
    AugmentedReality,
    Print,
    AudioModes,
    Unknown(u8),
}

impl BmapFunctionBlock {
    pub fn from_raw(raw: u8) -> Self {
        match raw {
            0 => Self::ProductInfo,
            1 => Self::Settings,
            2 => Self::Status,
            3 => Self::FirmwareUpdate,
            4 => Self::DeviceManagement,
            5 => Self::AudioManagement,
            6 => Self::CallManagement,
            7 => Self::Control,
            8 => Self::Debug,
            9 => Self::Notification,
            10 => Self::ReservedBosebuild1,
            11 => Self::ReservedBosebuild2,
            12 => Self::HearingAssistance,
            13 => Self::DataCollection,
            14 => Self::HeartRate,
            15 => Self::PeerBud,
            16 => Self::Vpa,
            17 => Self::Wifi,
            18 => Self::Authentication,
            19 => Self::Experimental,
            20 => Self::Cloud,
            21 => Self::AugmentedReality,
            22 => Self::Print,
            31 => Self::AudioModes,
            value => Self::Unknown(value),
        }
    }

    pub fn raw_value(self) -> u8 {
        match self {
            Self::ProductInfo => 0,
            Self::Settings => 1,
            Self::Status => 2,
            Self::FirmwareUpdate => 3,
            Self::DeviceManagement => 4,
            Self::AudioManagement => 5,
            Self::CallManagement => 6,
            Self::Control => 7,
            Self::Debug => 8,
            Self::Notification => 9,
            Self::ReservedBosebuild1 => 10,
            Self::ReservedBosebuild2 => 11,
            Self::HearingAssistance => 12,
            Self::DataCollection => 13,
            Self::HeartRate => 14,
            Self::PeerBud => 15,
            Self::Vpa => 16,
            Self::Wifi => 17,
            Self::Authentication => 18,
            Self::Experimental => 19,
            Self::Cloud => 20,
            Self::AugmentedReality => 21,
            Self::Print => 22,
            Self::AudioModes => 31,
            Self::Unknown(value) => value,
        }
    }

    pub fn display_name(self) -> String {
        match self {
            Self::ProductInfo => "productInfo".into(),
            Self::Settings => "settings".into(),
            Self::Status => "status".into(),
            Self::FirmwareUpdate => "firmwareUpdate".into(),
            Self::DeviceManagement => "deviceManagement".into(),
            Self::AudioManagement => "audioManagement".into(),
            Self::CallManagement => "callManagement".into(),
            Self::Control => "control".into(),
            Self::Debug => "debug".into(),
            Self::Notification => "notification".into(),
            Self::ReservedBosebuild1 => "reservedBosebuild1".into(),
            Self::ReservedBosebuild2 => "reservedBosebuild2".into(),
            Self::HearingAssistance => "hearingAssistance".into(),
            Self::DataCollection => "dataCollection".into(),
            Self::HeartRate => "heartRate".into(),
            Self::PeerBud => "peerBud".into(),
            Self::Vpa => "vpa".into(),
            Self::Wifi => "wifi".into(),
            Self::Authentication => "authentication".into(),
            Self::Experimental => "experimental".into(),
            Self::Cloud => "cloud".into(),
            Self::AugmentedReality => "augmentedReality".into(),
            Self::Print => "print".into(),
            Self::AudioModes => "audioModes".into(),
            Self::Unknown(value) => format!("unknown({value})"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum BmapFunction {
    ProductInfoFblockInfo,
    ProductInfoBmapVersion,
    ProductInfoAllFblocks,
    ProductInfoProductIdVariants,
    ProductInfoGetAllFunctions,
    ProductInfoFirmwareVersion,
    Unknown { block: BmapFunctionBlock, raw_value: u8 },
}

impl BmapFunction {
    pub fn from_raw(block: BmapFunctionBlock, raw: u8) -> Self {
        match (block, raw) {
            (BmapFunctionBlock::ProductInfo, 0) => Self::ProductInfoFblockInfo,
            (BmapFunctionBlock::ProductInfo, 1) => Self::ProductInfoBmapVersion,
            (BmapFunctionBlock::ProductInfo, 2) => Self::ProductInfoAllFblocks,
            (BmapFunctionBlock::ProductInfo, 3) => Self::ProductInfoProductIdVariants,
            (BmapFunctionBlock::ProductInfo, 4) => Self::ProductInfoGetAllFunctions,
            (BmapFunctionBlock::ProductInfo, 5) => Self::ProductInfoFirmwareVersion,
            _ => Self::Unknown { block, raw_value: raw },
        }
    }

    pub fn block(&self) -> BmapFunctionBlock {
        match self {
            Self::ProductInfoFblockInfo
            | Self::ProductInfoBmapVersion
            | Self::ProductInfoAllFblocks
            | Self::ProductInfoProductIdVariants
            | Self::ProductInfoGetAllFunctions
            | Self::ProductInfoFirmwareVersion => BmapFunctionBlock::ProductInfo,
            Self::Unknown { block, .. } => *block,
        }
    }

    pub fn raw_value(&self) -> u8 {
        match self {
            Self::ProductInfoFblockInfo => 0,
            Self::ProductInfoBmapVersion => 1,
            Self::ProductInfoAllFblocks => 2,
            Self::ProductInfoProductIdVariants => 3,
            Self::ProductInfoGetAllFunctions => 4,
            Self::ProductInfoFirmwareVersion => 5,
            Self::Unknown { raw_value, .. } => *raw_value,
        }
    }

    pub fn name(&self) -> String {
        match self {
            Self::ProductInfoFblockInfo => "ProductInfoFblockInfo".into(),
            Self::ProductInfoBmapVersion => "ProductInfoBmapVersion".into(),
            Self::ProductInfoAllFblocks => "ProductInfoAllFblocks".into(),
            Self::ProductInfoProductIdVariants => "ProductInfoProductIdVariants".into(),
            Self::ProductInfoGetAllFunctions => "ProductInfoGetAllFunctions".into(),
            Self::ProductInfoFirmwareVersion => "ProductInfoFirmwareVersion".into(),
            Self::Unknown { block, raw_value } => format!("Unknown({}:{raw_value})", block.raw_value()),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BmapOperatorType {
    Command,
    Response,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BmapOperator {
    Set,
    Get,
    SetGet,
    Status,
    Error,
    Start,
    Result,
    Processing,
    Unknown(u8),
}

impl BmapOperator {
    pub fn from_raw(raw: u8) -> Self {
        match raw {
            0 => Self::Set,
            1 => Self::Get,
            2 => Self::SetGet,
            3 => Self::Status,
            4 => Self::Error,
            5 => Self::Start,
            6 => Self::Result,
            7 => Self::Processing,
            value => Self::Unknown(value),
        }
    }

    pub fn raw_value(self) -> u8 {
        match self {
            Self::Set => 0,
            Self::Get => 1,
            Self::SetGet => 2,
            Self::Status => 3,
            Self::Error => 4,
            Self::Start => 5,
            Self::Result => 6,
            Self::Processing => 7,
            Self::Unknown(value) => value,
        }
    }

    pub fn operator_type(self) -> BmapOperatorType {
        match self {
            Self::Set | Self::Get | Self::SetGet | Self::Start => BmapOperatorType::Command,
            Self::Status | Self::Error | Self::Result | Self::Processing => BmapOperatorType::Response,
            Self::Unknown(_) => BmapOperatorType::Unknown,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BmapPacket {
    pub function_block: BmapFunctionBlock,
    pub function: BmapFunction,
    pub device_id: i32,
    pub port: i32,
    pub operator: BmapOperator,
    pub payload: Bytes,
}

impl BmapPacket {
    pub const HEADER_SIZE: usize = 4;

    pub fn new(
        function_block: BmapFunctionBlock,
        function: BmapFunction,
        device_id: i32,
        port: i32,
        operator: BmapOperator,
        payload: Bytes,
    ) -> Self {
        Self { function_block, function, device_id, port, operator, payload }
    }
}

pub struct BmapCodec;

impl BmapCodec {
    pub fn encode(packet: &BmapPacket) -> Result<Bytes, PacketEncodeError> {
        if packet.payload.len() > 0xFF {
            return Err(PacketEncodeError::PayloadTooLarge(packet.payload.len()));
        }
        if !(0..=3).contains(&packet.device_id) {
            return Err(PacketEncodeError::DeviceIdOutOfRange(packet.device_id));
        }
        if !(0..=3).contains(&packet.port) {
            return Err(PacketEncodeError::PortOutOfRange(packet.port));
        }
        let packed_header = packet.operator.raw_value()
            | ((packet.device_id as u8) << 6)
            | ((packet.port as u8) << 4);
        let mut data = vec![
            packet.function_block.raw_value(),
            packet.function.raw_value(),
            packed_header,
            packet.payload.len() as u8,
        ];
        data.extend_from_slice(&packet.payload);
        Ok(data)
    }

    pub fn decode(bytes: &[u8]) -> Result<BmapPacket, PacketDecodeError> {
        if bytes.len() < BmapPacket::HEADER_SIZE {
            return Err(PacketDecodeError::FrameTooShort(bytes.len()));
        }
        let payload_length = bytes[3] as usize;
        let expected_length = BmapPacket::HEADER_SIZE + payload_length;
        if bytes.len() < expected_length {
            return Err(PacketDecodeError::PayloadLengthMismatch { expected: expected_length, actual: bytes.len() });
        }
        if bytes.len() > expected_length {
            return Err(PacketDecodeError::TrailingBytes(bytes.len() - expected_length));
        }
        let block = BmapFunctionBlock::from_raw(bytes[0]);
        let function = BmapFunction::from_raw(block, bytes[1]);
        let packed = bytes[2];
        let device_id = (packed >> 6) as i32;
        let port = ((packed >> 4) & 0x03) as i32;
        let operator = BmapOperator::from_raw(packed & 0x0F);
        let payload = bytes[BmapPacket::HEADER_SIZE..expected_length].to_vec();
        Ok(BmapPacket::new(block, function, device_id, port, operator, payload))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BmapErrorCode {
    Length = 0x01,
    Chksum = 0x02,
    FblockNotSupp = 0x03,
    FuncNotSupp = 0x04,
    OpNotSupp = 0x05,
    InvalidData = 0x06,
    DataUnavailable = 0x07,
    Runtime = 0x08,
    Timeout = 0x09,
    InvalidState = 0x0A,
    DeviceNotFound = 0x0B,
    Busy = 0x0C,
    NoconnTimeout = 0x0D,
    NoconnKey = 0x0E,
    OtaUpdate = 0x0F,
    OtaLowBatt = 0x10,
    OtaNoCharger = 0x11,
    OtaUpdateNotAllowed = 0x12,
    UnknownPortNumber = 0x13,
    InsecureTransport = 0x14,
    InvalidOtpKey = 0x15,
    FblockSpecific = 0xFF,
}

impl BmapErrorCode {
    pub fn from_raw(raw: u8) -> Option<Self> {
        Some(match raw {
            0x01 => Self::Length,
            0x02 => Self::Chksum,
            0x03 => Self::FblockNotSupp,
            0x04 => Self::FuncNotSupp,
            0x05 => Self::OpNotSupp,
            0x06 => Self::InvalidData,
            0x07 => Self::DataUnavailable,
            0x08 => Self::Runtime,
            0x09 => Self::Timeout,
            0x0A => Self::InvalidState,
            0x0B => Self::DeviceNotFound,
            0x0C => Self::Busy,
            0x0D => Self::NoconnTimeout,
            0x0E => Self::NoconnKey,
            0x0F => Self::OtaUpdate,
            0x10 => Self::OtaLowBatt,
            0x11 => Self::OtaNoCharger,
            0x12 => Self::OtaUpdateNotAllowed,
            0x13 => Self::UnknownPortNumber,
            0x14 => Self::InsecureTransport,
            0x15 => Self::InvalidOtpKey,
            0xFF => Self::FblockSpecific,
            _ => return None,
        })
    }
}
