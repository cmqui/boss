import XCTest

@testable import libbossApple

final class BossAppleSettingsSnapshotTests: XCTestCase {
    func testEncodedPacketsRejectTruncatedLengthPrefix() {
        XCTAssertThrowsError(try BossAppleSettingsSnapshot(encodedPackets: Data([0x01, 0x00, 0x00]))) { error in
            XCTAssertEqual(error.localizedDescription, "Settings snapshot length prefix was truncated")
        }
    }

    func testEncodedPacketsRejectInvalidPacketLength() {
        let bytes = Data([
            0x03, 0x00, 0x00, 0x00,
            0x01, 0x02, 0x03,
        ])

        XCTAssertThrowsError(try BossAppleSettingsSnapshot(encodedPackets: bytes)) { error in
            XCTAssertEqual(error.localizedDescription, "Settings snapshot packet length was invalid")
        }
    }

    func testAutoAnswerFallsBackToOnHeadDetectionCompositeState() throws {
        try requireRuntime()

        let snapshot = BossAppleSettingsSnapshot(packetsByFunctionRaw: [
            BossAppleSettingsProtocol.onHeadDetectionFunctionRaw: settingsPacket(
                functionRaw: BossAppleSettingsProtocol.onHeadDetectionFunctionRaw,
                payload: Data([0x05, 0x00])
            ),
        ])

        XCTAssertEqual(try snapshot.autoAnswer(), false)
    }

    func testAutoAnswerPrefersStandalonePacketOverCompositeFallback() throws {
        try requireRuntime()

        let snapshot = BossAppleSettingsSnapshot(packetsByFunctionRaw: [
            BossAppleSettingsProtocol.onHeadDetectionFunctionRaw: settingsPacket(
                functionRaw: BossAppleSettingsProtocol.onHeadDetectionFunctionRaw,
                payload: Data([0x05, 0x00])
            ),
            BossAppleSettingsProtocol.autoAnswerFunctionRaw: settingsPacket(
                functionRaw: BossAppleSettingsProtocol.autoAnswerFunctionRaw,
                payload: Data([0x01])
            ),
        ])

        XCTAssertEqual(try snapshot.autoAnswer(), true)
    }

    func testDeviceSettingsAggregatesSnapshotValues() throws {
        try requireRuntime()

        let snapshot = BossAppleSettingsSnapshot(packetsByFunctionRaw: [
            BossAppleSettingsProtocol.onHeadDetectionFunctionRaw: settingsPacket(
                functionRaw: BossAppleSettingsProtocol.onHeadDetectionFunctionRaw,
                payload: Data([0x07, 0x03])
            ),
            BossAppleSettingsProtocol.autoAwareFunctionRaw: settingsPacket(
                functionRaw: BossAppleSettingsProtocol.autoAwareFunctionRaw,
                payload: Data([0x01])
            ),
            BossAppleSettingsProtocol.autoPlayPauseFunctionRaw: settingsPacket(
                functionRaw: BossAppleSettingsProtocol.autoPlayPauseFunctionRaw,
                payload: Data([0x00])
            ),
            BossAppleSettingsProtocol.volumeControlFunctionRaw: settingsPacket(
                functionRaw: BossAppleSettingsProtocol.volumeControlFunctionRaw,
                payload: Data([BossAppleVolumeControlValue.button.rawValue, 0x00])
            ),
        ])

        let settings = try snapshot.deviceSettings()
        XCTAssertEqual(settings.wearDetection?.isEnabled, true)
        XCTAssertEqual(settings.wearDetection?.isAutoPlayEnabled, true)
        XCTAssertEqual(settings.wearDetection?.isAutoAnswerEnabled, true)
        XCTAssertEqual(settings.autoAwareEnabled, true)
        XCTAssertEqual(settings.autoPlayPauseEnabled, false)
        XCTAssertEqual(settings.autoAnswerEnabled, true)
        XCTAssertEqual(settings.volumeControl?.value, .button)
    }
}

private extension BossAppleSettingsSnapshotTests {
    func requireRuntime(file: StaticString = #filePath, line: UInt = #line) throws {
        guard BossRustFfiRuntime.shared != nil else {
            throw XCTSkip("Rust runtime not available in test environment", file: file, line: line)
        }
    }

    func settingsPacket(functionRaw: UInt8, payload: Data) -> BossAppleBmapPacket {
        BossAppleBmapPacket(
            functionBlock: .settings,
            function: BossAppleBmapFunction(block: .settings, rawValue: functionRaw),
            operator: .status,
            payload: payload
        )
    }
}
