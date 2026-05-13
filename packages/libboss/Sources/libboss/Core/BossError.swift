import Foundation

public protocol BossError: Error, Sendable {}

public enum PacketEncodeError: BossError, Equatable {
    case payloadTooLarge(Int)
    case deviceIDOutOfRange(Int)
    case portOutOfRange(Int)
}

public enum PacketDecodeError: BossError, Equatable {
    case frameTooShort(Int)
    case payloadLengthMismatch(expected: Int, actual: Int)
    case trailingBytes(Int)
}

public enum BleSegmentationError: BossError, Equatable {
    case invalidMTU(Int)
    case tooManySegments(Int)
}

public enum BleReassemblyError: BossError, Equatable {
    case emptySegment
    case segmentTooShort(Int)
    case inconsistentSegmentSeries(expectedMaxIndex: Int, actualMaxIndex: Int)
    case invalidSegmentIndex(Int)
    case duplicateSegmentIndex(Int)
    case missingSegments(expected: Int, actual: Int)
}

public enum BootstrapTimeoutError: BossError, Equatable {
    case bmapVersion(timeoutMilliseconds: Int)
    case packet(function: String, timeoutMilliseconds: Int)
}

public struct UnexpectedOperatorError: BossError, Equatable {
    public let expected: BmapOperator
    public let actual: BmapOperator

    public init(expected: BmapOperator, actual: BmapOperator) {
        self.expected = expected
        self.actual = actual
    }
}

public struct UnsupportedFunctionError: BossError, Equatable {
    public let functionBlock: BmapFunctionBlock
    public let function: BmapFunction

    public init(functionBlock: BmapFunctionBlock, function: BmapFunction) {
        self.functionBlock = functionBlock
        self.function = function
    }
}
