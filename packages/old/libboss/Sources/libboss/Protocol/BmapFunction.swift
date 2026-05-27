import Foundation

public enum BmapFunction: Hashable, Sendable {
    case productInfoFblockInfo
    case productInfoBmapVersion
    case productInfoAllFblocks
    case productInfoProductIDVariants
    case productInfoGetAllFunctions
    case productInfoFirmwareVersion
    case unknown(block: BmapFunctionBlock, rawValue: UInt8)

    public init(block: BmapFunctionBlock, rawValue: UInt8) {
        switch (block, rawValue) {
        case (.productInfo, 0): self = .productInfoFblockInfo
        case (.productInfo, 1): self = .productInfoBmapVersion
        case (.productInfo, 2): self = .productInfoAllFblocks
        case (.productInfo, 3): self = .productInfoProductIDVariants
        case (.productInfo, 4): self = .productInfoGetAllFunctions
        case (.productInfo, 5): self = .productInfoFirmwareVersion
        default: self = .unknown(block: block, rawValue: rawValue)
        }
    }

    public var block: BmapFunctionBlock {
        switch self {
        case .productInfoFblockInfo,
             .productInfoBmapVersion,
             .productInfoAllFblocks,
             .productInfoProductIDVariants,
             .productInfoGetAllFunctions,
             .productInfoFirmwareVersion:
            .productInfo
        case .unknown(let block, _):
            block
        }
    }

    public var rawValue: UInt8 {
        switch self {
        case .productInfoFblockInfo: 0
        case .productInfoBmapVersion: 1
        case .productInfoAllFblocks: 2
        case .productInfoProductIDVariants: 3
        case .productInfoGetAllFunctions: 4
        case .productInfoFirmwareVersion: 5
        case .unknown(_, let rawValue): rawValue
        }
    }

    public var name: String {
        switch self {
        case .productInfoFblockInfo: "ProductInfoFblockInfo"
        case .productInfoBmapVersion: "ProductInfoBmapVersion"
        case .productInfoAllFblocks: "ProductInfoAllFblocks"
        case .productInfoProductIDVariants: "ProductInfoProductIdVariants"
        case .productInfoGetAllFunctions: "ProductInfoGetAllFunctions"
        case .productInfoFirmwareVersion: "ProductInfoFirmwareVersion"
        case .unknown(let block, let rawValue): "Unknown(\(block.rawValue):\(rawValue))"
        }
    }
}
