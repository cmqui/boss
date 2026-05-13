import Foundation

public enum BmapCodec {
    public static func encode(_ packet: BmapPacket) throws -> Data {
        guard packet.payload.count <= 0xFF else {
            throw PacketEncodeError.payloadTooLarge(packet.payload.count)
        }
        guard (0...3).contains(packet.deviceID) else {
            throw PacketEncodeError.deviceIDOutOfRange(packet.deviceID)
        }
        guard (0...3).contains(packet.port) else {
            throw PacketEncodeError.portOutOfRange(packet.port)
        }

        let packedHeader = UInt8(packet.operator.rawValue | UInt8(packet.deviceID << 6) | UInt8(packet.port << 4))
        var data = Data([
            packet.functionBlock.rawValue,
            packet.function.rawValue,
            packedHeader,
            UInt8(packet.payload.count),
        ])
        data.append(packet.payload)
        return data
    }

    public static func decode(_ bytes: Data) throws -> BmapPacket {
        guard bytes.count >= BmapPacket.headerSize else {
            throw PacketDecodeError.frameTooShort(bytes.count)
        }

        let payloadLength = Int(bytes[3])
        let expectedLength = BmapPacket.headerSize + payloadLength
        guard bytes.count >= expectedLength else {
            throw PacketDecodeError.payloadLengthMismatch(expected: expectedLength, actual: bytes.count)
        }
        guard bytes.count == expectedLength else {
            throw PacketDecodeError.trailingBytes(bytes.count - expectedLength)
        }

        let block = BmapFunctionBlock(rawValue: bytes[0])
        let function = BmapFunction(block: block, rawValue: bytes[1])
        let packed = bytes[2]
        let deviceID = Int(packed >> 6)
        let port = Int((packed >> 4) & 0x03)
        let op = BmapOperator(rawValue: packed & 0x0F)
        let payload = bytes[BmapPacket.headerSize..<expectedLength]

        return BmapPacket(
            functionBlock: block,
            function: function,
            deviceID: deviceID,
            port: port,
            operator: op,
            payload: Data(payload)
        )
    }
}
