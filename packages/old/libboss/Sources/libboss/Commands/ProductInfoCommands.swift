import Foundation

public enum ProductInfoCommands {
    public static func bmapVersion(deviceID: Int = 0, port: Int = 0) -> BmapPacket {
        packet(function: .productInfoBmapVersion, deviceID: deviceID, port: port, operator: .get)
    }

    public static func productIDVariant(deviceID: Int = 0, port: Int = 0) -> BmapPacket {
        packet(function: .productInfoProductIDVariants, deviceID: deviceID, port: port, operator: .get)
    }

    public static func allFunctionBlocksGet(deviceID: Int = 0, port: Int = 0) -> BmapPacket {
        packet(function: .productInfoAllFblocks, deviceID: deviceID, port: port, operator: .get)
    }

    public static func allFunctionBlocksStart(deviceID: Int = 0, port: Int = 0) -> BmapPacket {
        packet(function: .productInfoAllFblocks, deviceID: deviceID, port: port, operator: .start)
    }

    public static func firmwareVersion(port: Int = 0, deviceID: Int = 0) -> BmapPacket {
        packet(function: .productInfoFirmwareVersion, deviceID: deviceID, port: port, operator: .get)
    }

    private static func packet(function: BmapFunction, deviceID: Int, port: Int, operator: BmapOperator) -> BmapPacket {
        BmapPacket(
            functionBlock: .productInfo,
            function: function,
            deviceID: deviceID,
            port: port,
            operator: `operator`
        )
    }
}
