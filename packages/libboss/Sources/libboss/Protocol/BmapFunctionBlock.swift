import Foundation

public enum BmapFunctionBlock: Hashable, Sendable, Comparable {
    case productInfo
    case settings
    case status
    case firmwareUpdate
    case deviceManagement
    case audioManagement
    case callManagement
    case control
    case debug
    case notification
    case reservedBosebuild1
    case reservedBosebuild2
    case hearingAssistance
    case dataCollection
    case heartRate
    case peerBud
    case vpa
    case wifi
    case authentication
    case experimental
    case cloud
    case augmentedReality
    case print
    case audioModes
    case unknown(UInt8)

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .productInfo
        case 1: self = .settings
        case 2: self = .status
        case 3: self = .firmwareUpdate
        case 4: self = .deviceManagement
        case 5: self = .audioManagement
        case 6: self = .callManagement
        case 7: self = .control
        case 8: self = .debug
        case 9: self = .notification
        case 10: self = .reservedBosebuild1
        case 11: self = .reservedBosebuild2
        case 12: self = .hearingAssistance
        case 13: self = .dataCollection
        case 14: self = .heartRate
        case 15: self = .peerBud
        case 16: self = .vpa
        case 17: self = .wifi
        case 18: self = .authentication
        case 19: self = .experimental
        case 20: self = .cloud
        case 21: self = .augmentedReality
        case 22: self = .print
        case 31: self = .audioModes
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: UInt8 {
        switch self {
        case .productInfo: 0
        case .settings: 1
        case .status: 2
        case .firmwareUpdate: 3
        case .deviceManagement: 4
        case .audioManagement: 5
        case .callManagement: 6
        case .control: 7
        case .debug: 8
        case .notification: 9
        case .reservedBosebuild1: 10
        case .reservedBosebuild2: 11
        case .hearingAssistance: 12
        case .dataCollection: 13
        case .heartRate: 14
        case .peerBud: 15
        case .vpa: 16
        case .wifi: 17
        case .authentication: 18
        case .experimental: 19
        case .cloud: 20
        case .augmentedReality: 21
        case .print: 22
        case .audioModes: 31
        case .unknown(let value): value
        }
    }

    public static func < (lhs: BmapFunctionBlock, rhs: BmapFunctionBlock) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
