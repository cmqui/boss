import Foundation

public struct FunctionBlockSet: Equatable, Sendable {
    private let bits: Set<Int>

    public init(bits: Set<Int> = []) {
        self.bits = bits
    }

    public init(bytes: Data) {
        var values = Set<Int>()
        let totalBits = bytes.count * 8
        for bitIndex in 0..<totalBits {
            let byteIndex = bytes.count - (bitIndex / 8) - 1
            let mask = 1 << (bitIndex % 8)
            if Int(bytes[byteIndex]) & mask > 0 {
                values.insert(bitIndex)
            }
        }
        self.bits = values
    }

    public func contains(_ block: BmapFunctionBlock) -> Bool {
        if block == .productInfo {
            return true
        }
        return bits.contains(Int(block.rawValue))
    }

    public func allBlocks() -> [BmapFunctionBlock] {
        let blocks = bits
            .map { BmapFunctionBlock(rawValue: UInt8($0)) }
            .filter {
                if case .unknown = $0 {
                    return false
                }
                return true
            }
            .sorted()

        if contains(.productInfo), !blocks.contains(.productInfo) {
            return [.productInfo] + blocks
        }

        return blocks
    }

    public func encoded() -> Data {
        let maxBit = bits.max() ?? -1
        if maxBit < 0 {
            return Data()
        }

        let byteCount = (maxBit + 8) / 8
        var output = Array(repeating: UInt8(0), count: byteCount)
        for bit in bits {
            let byteIndex = byteCount - (bit / 8) - 1
            output[byteIndex] |= UInt8(1 << (bit % 8))
        }
        return Data(output)
    }
}
