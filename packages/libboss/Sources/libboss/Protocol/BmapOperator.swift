import Foundation

public enum BmapOperatorType: String, Sendable {
    case command
    case response
    case unknown
}

public enum BmapOperator: Hashable, Sendable {
    case set
    case get
    case setGet
    case status
    case error
    case start
    case result
    case processing
    case unknown(UInt8)

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .set
        case 1: self = .get
        case 2: self = .setGet
        case 3: self = .status
        case 4: self = .error
        case 5: self = .start
        case 6: self = .result
        case 7: self = .processing
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: UInt8 {
        switch self {
        case .set: 0
        case .get: 1
        case .setGet: 2
        case .status: 3
        case .error: 4
        case .start: 5
        case .result: 6
        case .processing: 7
        case .unknown(let value): value
        }
    }

    public var type: BmapOperatorType {
        switch self {
        case .set, .get, .setGet, .start:
            .command
        case .status, .error, .result, .processing:
            .response
        case .unknown:
            .unknown
        }
    }
}
