import Foundation
import libboss

extension Data {
    init(hexString: String) throws {
        let normalized = hexString
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")

        guard normalized.count.isMultiple(of: 2) else {
            throw UsageError("Hex payload must contain an even number of characters")
        }

        var data = Data()
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            let byteString = normalized[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else {
                throw UsageError("Invalid hex payload: \(hexString)")
            }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }

    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}

func parseIntegerString(_ value: String) -> Int {
    if value.lowercased().hasPrefix("0x") {
        Int(value.dropFirst(2), radix: 16) ?? -1
    } else {
        Int(value) ?? -1
    }
}
