import Foundation

public struct BmapFrameStreamDecoder: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func push(_ chunk: Data) throws -> [BmapPacket] {
        buffer.append(chunk)

        var packets: [BmapPacket] = []
        while buffer.count >= BmapPacket.headerSize {
            let bytes = Array(buffer)
            let payloadLength = Int(bytes[3])
            let packetLength = BmapPacket.headerSize + payloadLength
            if buffer.count < packetLength {
                break
            }

            let packetBytes = buffer.prefix(packetLength)
            packets.append(try BmapCodec.decode(Data(packetBytes)))
            buffer.removeFirst(packetLength)
        }

        return packets
    }
}
