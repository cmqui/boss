use crate::{BmapFunction, BmapFunctionBlock, BmapOperator, BmapPacket};

pub struct ProductInfoCommands;

impl ProductInfoCommands {
    pub fn bmap_version(device_id: i32, port: i32) -> BmapPacket {
        Self::packet(BmapFunction::ProductInfoBmapVersion, device_id, port, BmapOperator::Get)
    }

    pub fn product_id_variant(device_id: i32, port: i32) -> BmapPacket {
        Self::packet(BmapFunction::ProductInfoProductIdVariants, device_id, port, BmapOperator::Get)
    }

    pub fn all_function_blocks_get(device_id: i32, port: i32) -> BmapPacket {
        Self::packet(BmapFunction::ProductInfoAllFblocks, device_id, port, BmapOperator::Get)
    }

    pub fn firmware_version(port: i32, device_id: i32) -> BmapPacket {
        Self::packet(BmapFunction::ProductInfoFirmwareVersion, device_id, port, BmapOperator::Get)
    }

    fn packet(function: BmapFunction, device_id: i32, port: i32, operator: BmapOperator) -> BmapPacket {
        BmapPacket::new(BmapFunctionBlock::ProductInfo, function, device_id, port, operator, vec![])
    }
}
