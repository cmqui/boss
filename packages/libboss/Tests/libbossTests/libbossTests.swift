import Foundation
import XCTest
@testable import libboss

final class LibbossTests: XCTestCase {
    func testPacketCodecEncodesAndDecodes() throws {
        let packet = BmapPacket(
            functionBlock: .productInfo,
            function: .productInfoBmapVersion,
            deviceID: 2,
            port: 1,
            operator: .get,
            payload: Data([0xAA, 0xBB])
        )

        let encoded = try BmapCodec.encode(packet)
        XCTAssertEqual(encoded, Data([0x00, 0x01, 0x91, 0x02, 0xAA, 0xBB]))
        let decoded = try BmapCodec.decode(encoded)
        XCTAssertEqual(decoded, packet)
    }

    func testPacketDecodeRejectsShortFrames() {
        XCTAssertThrowsError(try BmapCodec.decode(Data([0x00, 0x01, 0x02]))) { error in
            XCTAssertEqual(error as? PacketDecodeError, .frameTooShort(3))
        }
    }

    func testPacketDecodeRejectsPayloadLengthMismatch() {
        XCTAssertThrowsError(try BmapCodec.decode(Data([0x00, 0x01, 0x01, 0x02, 0xAA]))) { error in
            XCTAssertEqual(error as? PacketDecodeError, .payloadLengthMismatch(expected: 6, actual: 5))
        }
    }

    func testPacketDecodePreservesUnknownValues() throws {
        let decoded = try BmapCodec.decode(Data([0x7E, 0x55, 0xF9, 0x00]))
        XCTAssertEqual(decoded.functionBlock, .unknown(0x7E))
        XCTAssertEqual(decoded.function, .unknown(block: .unknown(0x7E), rawValue: 0x55))
        XCTAssertEqual(decoded.operator, .unknown(0x09))
        XCTAssertEqual(decoded.deviceID, 3)
        XCTAssertEqual(decoded.port, 3)
    }

    func testBleSegmentationSingleFrameAddsZeroHeader() throws {
        let frames = try BleSegmentation.encode(packetBytes: Data([0x01, 0x02, 0x03]), mtu: 23)
        XCTAssertEqual(frames, [Data([0x00, 0x01, 0x02, 0x03])])
    }

    func testBleSegmentationMultipleFrames() throws {
        let payload = Data(0..<40)
        let frames = try BleSegmentation.encode(packetBytes: payload, mtu: 23)
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].first, 0x20)
        XCTAssertEqual(frames[1].first, 0x21)
        XCTAssertEqual(frames[2].first, 0x22)
    }

    func testBleReassemblyReturnsFullPacket() throws {
        let packetData = Data(0..<40)
        let frames = try BleSegmentation.encode(packetBytes: packetData, mtu: 23)
        var reassembler = BleSegmentReassembler()
        XCTAssertNil(try reassembler.push(frames[0]))
        XCTAssertNil(try reassembler.push(frames[1]))
        let final = try reassembler.push(frames[2])
        XCTAssertEqual(final, packetData)
    }

    func testBleReassemblyRejectsInvalidHeaders() throws {
        var reassembler = BleSegmentReassembler()
        XCTAssertThrowsError(try reassembler.push(Data([0x12, 0x01])))
    }

    func testStreamDecoderHandlesMultiplePacketsAndLeftovers() throws {
        let first = try BmapCodec.encode(ProductInfoCommands.bmapVersion())
        let second = try BmapCodec.encode(ProductInfoCommands.productIDVariant())
        let combined = first + second

        var decoder = BmapFrameStreamDecoder()
        let partial = try decoder.push(combined.prefix(5))
        XCTAssertEqual(partial.count, 1)
        let remainder = try decoder.push(combined.dropFirst(5))
        XCTAssertEqual(remainder.count, 1)
        XCTAssertEqual(remainder[0].function, .productInfoProductIDVariants)
    }

    func testFunctionBlockSetHonorsImplicitProductInfo() {
        let set = FunctionBlockSet(bytes: Data([0x00, 0x06]))
        XCTAssertTrue(set.contains(.productInfo))
        XCTAssertTrue(set.contains(.settings))
        XCTAssertTrue(set.contains(.status))
    }

    func testProductInfoParsing() throws {
        let version = try ProductInfoParser.parseBmapVersion(
            from: BmapPacket(functionBlock: .productInfo, function: .productInfoBmapVersion, operator: .status, payload: Data("1.2.3".utf8))
        )
        XCTAssertEqual(version.version, "1.2.3")

        let black = try ProductInfoParser.parseProductIDVariant(
            from: BmapPacket(functionBlock: .productInfo, function: .productInfoProductIDVariants, operator: .status, payload: Data([0x40, 0x82, 0x01]))
        )
        XCTAssertEqual(black.productID, 0x4082)
        XCTAssertEqual(black.product?.displayName, "Bose QC Ultra 2 HP")
        XCTAssertEqual(black.variantName, "WolverineBlack")

        let violet = try ProductInfoParser.parseProductIDVariant(
            from: BmapPacket(functionBlock: .productInfo, function: .productInfoProductIDVariants, operator: .status, payload: Data([0x40, 0x82, 0x04]))
        )
        XCTAssertEqual(violet.variantName, "WolverineMidnightViolet")

        let firmware = try ProductInfoParser.parseFirmwareVersion(
            from: BmapPacket(functionBlock: .productInfo, function: .productInfoFirmwareVersion, port: 2, operator: .status, payload: Data("9.9.9".utf8))
        )
        XCTAssertEqual(firmware.version, "9.9.9")
        XCTAssertEqual(firmware.port, 2)
    }

    func testBootstrapSessionSuccess() async throws {
        let transport = MockTransport(frames: [
            try BmapCodec.encode(BmapPacket(functionBlock: .productInfo, function: .productInfoBmapVersion, operator: .status, payload: Data("1.0.0".utf8))),
            try BmapCodec.encode(BmapPacket(functionBlock: .productInfo, function: .productInfoProductIDVariants, operator: .status, payload: Data([0x40, 0x82, 0x02]))),
            try BmapCodec.encode(BmapPacket(functionBlock: .productInfo, function: .productInfoAllFblocks, operator: .status, payload: Data([0x00, 0x06]))),
        ])
        let link = StreamBmapLink(transport: transport)
        let session = BootstrapSession(
            link: link,
            configuration: SessionConfiguration(firstVersionTimeout: .milliseconds(50), retryVersionTimeout: .milliseconds(100), requestTimeout: .milliseconds(50))
        )

        let device = try await session.bootstrap()
        XCTAssertEqual(device.bmapVersion.version, "1.0.0")
        XCTAssertEqual(device.productID, 0x4082)
        XCTAssertEqual(device.productVariant.variantName, "WolverineWhiteSmoke")
        XCTAssertTrue(device.supportedFunctionBlocks.contains(.settings))
        XCTAssertEqual(device.transportKind, .stream)
        let sentFrames = await transport.sentFrames
        XCTAssertEqual(sentFrames.count, 3)
    }

    func testBootstrapSessionRetriesVersionRequest() async throws {
        let transport = MockTransport(
            frames: [
                try BmapCodec.encode(BmapPacket(functionBlock: .productInfo, function: .productInfoBmapVersion, operator: .status, payload: Data("1.0.1".utf8))),
                try BmapCodec.encode(BmapPacket(functionBlock: .productInfo, function: .productInfoProductIDVariants, operator: .status, payload: Data([0x40, 0x82, 0x01]))),
                try BmapCodec.encode(BmapPacket(functionBlock: .productInfo, function: .productInfoAllFblocks, operator: .status, payload: Data([0x00]))),
            ],
            initialDelay: .milliseconds(30)
        )
        let link = StreamBmapLink(transport: transport)
        let session = BootstrapSession(
            link: link,
            configuration: SessionConfiguration(firstVersionTimeout: .milliseconds(5), retryVersionTimeout: .milliseconds(100), requestTimeout: .milliseconds(50))
        )

        _ = try await session.bootstrap()
        let versionRequests = await transport.sentFrames.filter { $0.count > 1 && $0[1] == 0x01 }
        XCTAssertEqual(versionRequests.count, 2)
    }

    func testBootstrapSessionFailsOnUnexpectedOperator() async throws {
        let transport = MockTransport(frames: [
            try BmapCodec.encode(BmapPacket(functionBlock: .productInfo, function: .productInfoBmapVersion, operator: .error, payload: Data([0x00])))
        ])
        let link = StreamBmapLink(transport: transport)
        let session = BootstrapSession(
            link: link,
            configuration: SessionConfiguration(firstVersionTimeout: .milliseconds(50), retryVersionTimeout: .milliseconds(50), requestTimeout: .milliseconds(50))
        )

        do {
            _ = try await session.bootstrap()
            XCTFail("Expected failure")
        } catch let error as UnexpectedOperatorError {
            XCTAssertEqual(error.expected, .status)
            XCTAssertEqual(error.actual, .error)
        }
    }

    func testBootstrapSessionTimesOut() async throws {
        let transport = MockTransport(frames: [], finishStream: false)
        let link = StreamBmapLink(transport: transport)
        let session = BootstrapSession(
            link: link,
            configuration: SessionConfiguration(firstVersionTimeout: .milliseconds(5), retryVersionTimeout: .milliseconds(5), requestTimeout: .milliseconds(5))
        )

        do {
            _ = try await session.bootstrap()
            XCTFail("Expected timeout")
        } catch let error as BootstrapTimeoutError {
            XCTAssertEqual(error, .bmapVersion(timeoutMilliseconds: 5))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor MockTransportState {
    var sentFrames: [Data] = []

    func append(_ frame: Data) {
        sentFrames.append(frame)
    }

    func snapshot() -> [Data] {
        sentFrames
    }
}

private final class MockTransport: BossTransport, @unchecked Sendable {
    let incomingFrames: AsyncThrowingStream<Data, Error>

    private let state = MockTransportState()

    var sentFrames: [Data] {
        get async {
            await state.snapshot()
        }
    }

    init(frames: [Data], initialDelay: Duration? = nil, finishStream: Bool = true) {
        self.incomingFrames = AsyncThrowingStream { continuation in
            Task {
                if let initialDelay {
                    try? await Task.sleep(for: initialDelay)
                }
                for frame in frames {
                    continuation.yield(frame)
                }
                if finishStream {
                    continuation.finish()
                }
            }
        }
    }

    func send(_ frame: Data) async throws {
        await state.append(frame)
    }

    func close() async {}
}
