use crate::{BmapFunction, BmapFunctionBlock, BmapOperator};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PacketEncodeError {
    PayloadTooLarge(usize),
    DeviceIdOutOfRange(i32),
    PortOutOfRange(i32),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PacketDecodeError {
    FrameTooShort(usize),
    PayloadLengthMismatch { expected: usize, actual: usize },
    TrailingBytes(usize),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BleSegmentationError {
    InvalidMtu(usize),
    TooManySegments(usize),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BleReassemblyError {
    EmptySegment,
    SegmentTooShort(usize),
    InconsistentSegmentSeries { expected_max_index: usize, actual_max_index: usize },
    InvalidSegmentIndex(usize),
    DuplicateSegmentIndex(usize),
    MissingSegments { expected: usize, actual: usize },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnexpectedOperatorError {
    pub expected: BmapOperator,
    pub actual: BmapOperator,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnsupportedFunctionError {
    pub function_block: BmapFunctionBlock,
    pub function: BmapFunction,
}
