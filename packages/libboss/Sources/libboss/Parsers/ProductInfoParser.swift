import Foundation

public struct BmapVersionInfo: Equatable, Sendable {
    public let version: String

    public init(version: String) {
        self.version = version
    }
}

public struct FirmwareVersionInfo: Equatable, Sendable {
    public let version: String
    public let port: Int

    public init(version: String, port: Int) {
        self.version = version
        self.port = port
    }
}

public struct ProductIDVariant: Equatable, Sendable {
    public let productID: UInt16
    public let variant: UInt8
    public let product: ProductDefinition?
    public let variantName: String?

    public init(productID: UInt16, variant: UInt8, product: ProductDefinition?, variantName: String?) {
        self.productID = productID
        self.variant = variant
        self.product = product
        self.variantName = variantName
    }
}

public enum ProductInfoParser {
    public static func parseBmapVersion(from packet: BmapPacket) throws -> BmapVersionInfo {
        try ensure(packet, function: .productInfoBmapVersion)
        return BmapVersionInfo(version: try decodeUTF8(packet.payload))
    }

    public static func parseProductIDVariant(from packet: BmapPacket) throws -> ProductIDVariant {
        try ensure(packet, function: .productInfoProductIDVariants)
        guard packet.payload.count >= 3 else {
            throw PacketDecodeError.payloadLengthMismatch(expected: 3, actual: packet.payload.count)
        }
        let productID = (UInt16(packet.payload[0]) << 8) | UInt16(packet.payload[1])
        let variant = packet.payload[2]
        let product = ProductMap.product(for: productID)
        return ProductIDVariant(
            productID: productID,
            variant: variant,
            product: product,
            variantName: product?.variants[variant]
        )
    }

    public static func parseFunctionBlocks(from packet: BmapPacket) throws -> FunctionBlockSet {
        try ensure(packet, function: .productInfoAllFblocks)
        return FunctionBlockSet(bytes: packet.payload)
    }

    public static func parseFirmwareVersion(from packet: BmapPacket) throws -> FirmwareVersionInfo {
        try ensure(packet, function: .productInfoFirmwareVersion)
        return FirmwareVersionInfo(version: try decodeUTF8(packet.payload), port: packet.port)
    }

    private static func decodeUTF8(_ data: Data) throws -> String {
        guard let string = String(data: data, encoding: .utf8) else {
            throw PacketDecodeError.payloadLengthMismatch(expected: data.count, actual: 0)
        }
        return string
    }

    private static func ensure(_ packet: BmapPacket, function: BmapFunction) throws {
        guard packet.function == function else {
            throw UnsupportedFunctionError(functionBlock: packet.functionBlock, function: packet.function)
        }
        guard packet.operator == .status else {
            throw UnexpectedOperatorError(expected: .status, actual: packet.operator)
        }
    }
}
