use std::collections::BTreeSet;

use crate::{
    BmapFunction, BmapFunctionBlock, BmapOperator, BmapPacket, PacketDecodeError,
    UnexpectedOperatorError, UnsupportedFunctionError,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FunctionBlockSet {
    bits: BTreeSet<usize>,
}

impl FunctionBlockSet {
    pub fn new(bits: BTreeSet<usize>) -> Self {
        Self { bits }
    }

    pub fn from_bytes(bytes: &[u8]) -> Self {
        let mut values = BTreeSet::new();
        let total_bits = bytes.len() * 8;
        for bit_index in 0..total_bits {
            let byte_index = bytes.len() - (bit_index / 8) - 1;
            let mask = 1 << (bit_index % 8);
            if (bytes[byte_index] as usize) & mask > 0 {
                values.insert(bit_index);
            }
        }
        Self { bits: values }
    }

    pub fn contains(&self, block: BmapFunctionBlock) -> bool {
        block == BmapFunctionBlock::ProductInfo || self.bits.contains(&(block.raw_value() as usize))
    }

    pub fn all_blocks(&self) -> Vec<BmapFunctionBlock> {
        let mut blocks: Vec<_> = self
            .bits
            .iter()
            .map(|bit| BmapFunctionBlock::from_raw(*bit as u8))
            .filter(|block| !matches!(block, BmapFunctionBlock::Unknown(_)))
            .collect();
        blocks.sort();
        if self.contains(BmapFunctionBlock::ProductInfo) && !blocks.contains(&BmapFunctionBlock::ProductInfo) {
            blocks.insert(0, BmapFunctionBlock::ProductInfo);
        }
        blocks
    }

    pub fn encoded(&self) -> Vec<u8> {
        let Some(max_bit) = self.bits.iter().max().copied() else {
            return vec![];
        };
        let byte_count = (max_bit + 8) / 8;
        let mut output = vec![0u8; byte_count];
        for bit in &self.bits {
            let byte_index = byte_count - (bit / 8) - 1;
            output[byte_index] |= 1 << (bit % 8);
        }
        output
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BmapVersionInfo {
    pub version: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FirmwareVersionInfo {
    pub version: String,
    pub port: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProductDefinition {
    pub id: u16,
    pub code_name: &'static str,
    pub display_name: &'static str,
    pub variants: &'static [(u8, &'static str)],
}

pub const WOLVERINE_PRODUCT: ProductDefinition = ProductDefinition {
    id: 0x4082,
    code_name: "Wolverine",
    display_name: "Bose QC Ultra 2 HP",
    variants: &[
        (1, "WolverineBlack"),
        (2, "WolverineWhiteSmoke"),
        (3, "WolverineDriftwoodSand"),
        (4, "WolverineMidnightViolet"),
        (5, "WolverineDesertGold"),
    ],
};

pub fn product_for_id(id: u16) -> Option<&'static ProductDefinition> {
    match id {
        0x4082 => Some(&WOLVERINE_PRODUCT),
        _ => None,
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProductIdVariant {
    pub product_id: u16,
    pub variant: u8,
    pub product: Option<&'static ProductDefinition>,
    pub variant_name: Option<&'static str>,
}

pub struct ProductInfoParser;

impl ProductInfoParser {
    pub fn parse_bmap_version(packet: &BmapPacket) -> Result<BmapVersionInfo, ProductInfoParseError> {
        Self::ensure(packet, &BmapFunction::ProductInfoBmapVersion)?;
        let version = String::from_utf8(packet.payload.clone()).map_err(|_| ProductInfoParseError::InvalidUtf8)?;
        Ok(BmapVersionInfo { version })
    }

    pub fn parse_product_id_variant(packet: &BmapPacket) -> Result<ProductIdVariant, ProductInfoParseError> {
        Self::ensure(packet, &BmapFunction::ProductInfoProductIdVariants)?;
        if packet.payload.len() < 3 {
            return Err(ProductInfoParseError::PacketDecode(PacketDecodeError::PayloadLengthMismatch {
                expected: 3,
                actual: packet.payload.len(),
            }));
        }
        let product_id = ((packet.payload[0] as u16) << 8) | (packet.payload[1] as u16);
        let variant = packet.payload[2];
        let product = product_for_id(product_id);
        let variant_name = product.and_then(|product| product.variants.iter().find(|entry| entry.0 == variant).map(|entry| entry.1));
        Ok(ProductIdVariant { product_id, variant, product, variant_name })
    }

    pub fn parse_function_blocks(packet: &BmapPacket) -> Result<FunctionBlockSet, ProductInfoParseError> {
        Self::ensure(packet, &BmapFunction::ProductInfoAllFblocks)?;
        Ok(FunctionBlockSet::from_bytes(&packet.payload))
    }

    pub fn parse_firmware_version(packet: &BmapPacket) -> Result<FirmwareVersionInfo, ProductInfoParseError> {
        Self::ensure(packet, &BmapFunction::ProductInfoFirmwareVersion)?;
        let version = String::from_utf8(packet.payload.clone()).map_err(|_| ProductInfoParseError::InvalidUtf8)?;
        Ok(FirmwareVersionInfo { version, port: packet.port })
    }

    fn ensure(packet: &BmapPacket, function: &BmapFunction) -> Result<(), ProductInfoParseError> {
        if &packet.function != function {
            return Err(ProductInfoParseError::UnsupportedFunction(UnsupportedFunctionError {
                function_block: packet.function_block,
                function: packet.function.clone(),
            }));
        }
        if packet.operator != BmapOperator::Status {
            return Err(ProductInfoParseError::UnexpectedOperator(UnexpectedOperatorError {
                expected: BmapOperator::Status,
                actual: packet.operator,
            }));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProductInfoParseError {
    PacketDecode(PacketDecodeError),
    UnsupportedFunction(UnsupportedFunctionError),
    UnexpectedOperator(UnexpectedOperatorError),
    InvalidUtf8,
}
