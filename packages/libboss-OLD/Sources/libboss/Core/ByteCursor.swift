import Foundation

struct ByteCursor {
    let data: Data
    private(set) var index: Int = 0

    init(data: Data) {
        self.data = data
    }

    var remainingCount: Int {
        data.count - index
    }

    mutating func readUInt8() throws -> UInt8 {
        guard remainingCount >= 1 else {
            throw PacketDecodeError.frameTooShort(data.count)
        }
        defer { index += 1 }
        return data[index]
    }

    mutating func readData(count: Int) throws -> Data {
        guard remainingCount >= count else {
            throw PacketDecodeError.frameTooShort(data.count)
        }
        defer { index += count }
        return data[index..<(index + count)]
    }
}
