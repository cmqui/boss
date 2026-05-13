import Foundation
import XCTest
@testable import libboss
@testable import libbossApple

final class BossSettingsSnapshotTests: XCTestCase {
    func testAutoPlayPauseResolvesFromStandaloneSnapshotPacket() throws {
        let snapshot = BossSettingsSnapshot(packetsByFunctionRaw: [
            BossSettingsCodec.autoPlayPauseFunctionRaw: settingsPacket(
                functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw,
                payload: Data([0x00])
            )
        ])

        XCTAssertEqual(try snapshot.autoPlayPause(), false)
    }

    func testAutoAnswerPrefersStandaloneSnapshotPacket() throws {
        let snapshot = BossSettingsSnapshot(packetsByFunctionRaw: [
            BossSettingsCodec.onHeadDetectionFunctionRaw: settingsPacket(
                functionRaw: BossSettingsCodec.onHeadDetectionFunctionRaw,
                payload: Data([0x05, 0x00])
            ),
            BossSettingsCodec.autoAnswerFunctionRaw: settingsPacket(
                functionRaw: BossSettingsCodec.autoAnswerFunctionRaw,
                payload: Data([0x01])
            )
        ])

        XCTAssertEqual(try snapshot.autoAnswer(), true)
    }

    func testAutoAnswerFallsBackToOnHeadDetectionCompositeState() throws {
        let snapshot = BossSettingsSnapshot(packetsByFunctionRaw: [
            BossSettingsCodec.onHeadDetectionFunctionRaw: settingsPacket(
                functionRaw: BossSettingsCodec.onHeadDetectionFunctionRaw,
                payload: Data([0x05, 0x00])
            )
        ])

        XCTAssertEqual(try snapshot.autoAnswer(), false)
    }

    func testAutoAnswerReturnsNilWhenUnsupportedInSnapshot() throws {
        let snapshot = BossSettingsSnapshot(packetsByFunctionRaw: [
            BossSettingsCodec.onHeadDetectionFunctionRaw: settingsPacket(
                functionRaw: BossSettingsCodec.onHeadDetectionFunctionRaw,
                payload: Data([0x03, 0x01])
            )
        ])

        XCTAssertNil(try snapshot.autoAnswer())
    }

    private func settingsPacket(functionRaw: UInt8, payload: Data) -> BmapPacket {
        BmapPacket(
            functionBlock: .settings,
            function: BmapFunction(block: .settings, rawValue: functionRaw),
            operator: .status,
            payload: payload
        )
    }
}
