import Foundation

public enum BleSegmentation {
    public static func encode(packetBytes: Data, mtu: Int) throws -> [Data] {
        guard mtu >= 4 else {
            throw BleSegmentationError.invalidMTU(mtu)
        }

        let unsegmentedPayloadLimit = mtu - 4
        if packetBytes.count <= unsegmentedPayloadLimit {
            var singleFrame = Data([0x00])
            singleFrame.append(packetBytes)
            return [singleFrame]
        }

        let chunkSize = mtu - 4
        let segmentCount = Int(ceil(Double(packetBytes.count) / Double(chunkSize)))
        guard segmentCount <= 16 else {
            throw BleSegmentationError.tooManySegments(segmentCount)
        }

        let maxIndex = segmentCount - 1
        return (0..<segmentCount).map { segmentIndex in
            let start = segmentIndex * chunkSize
            let end = min(start + chunkSize, packetBytes.count)
            var frame = Data([UInt8((maxIndex << 4) | segmentIndex)])
            frame.append(packetBytes[start..<end])
            return frame
        }
    }
}
