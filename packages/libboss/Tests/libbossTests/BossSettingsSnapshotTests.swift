import Foundation
import XCTest
@testable import libboss

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

    func testVolumeControlResolvesFromSnapshotPacket() throws {
        let snapshot = BossSettingsSnapshot(packetsByFunctionRaw: [
            BossSettingsCodec.volumeControlFunctionRaw: settingsPacket(
                functionRaw: BossSettingsCodec.volumeControlFunctionRaw,
                payload: Data([BossVolumeControlValue.capTouch.rawValue, 0x00])
            )
        ])

        XCTAssertEqual(try snapshot.volumeControl()?.value, .capTouch)
    }

    func testCurrentAudioModeParserReadsModeIndex() throws {
        let packet = BmapPacket(
            functionBlock: .audioModes,
            function: BmapFunction(block: .audioModes, rawValue: BossAudioModesCodec.currentModeFunctionRaw),
            operator: .status,
            payload: Data([0x02])
        )

        XCTAssertEqual(try BossAudioModesCodec.parseCurrentMode(from: packet), 2)
    }

    func testAudioModeCapabilitiesParserReadsCounts() throws {
        let packet = BmapPacket(
            functionBlock: .audioModes,
            function: BmapFunction(block: .audioModes, rawValue: BossAudioModesCodec.capabilitiesFunctionRaw),
            operator: .status,
            payload: Data([0x03, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00])
        )

        let capabilities = try BossAudioModesCodec.parseCapabilities(from: packet)
        XCTAssertEqual(capabilities.boseModes, 3)
        XCTAssertEqual(capabilities.userModes, 1)
        XCTAssertEqual(capabilities.totalModes, 4)
    }

    func testAudioModeConfigParserReadsIndexNameAndFlags() throws {
        var payload = Data(repeating: 0, count: 44)
        payload[0] = 0x02
        payload[3] = 0x01
        payload[4] = 0x00
        payload[5] = 0x01
        let nameBytes = Array("Immersion".utf8)
        payload.replaceSubrange(6..<(6 + nameBytes.count), with: nameBytes)
        let packet = BmapPacket(
            functionBlock: .audioModes,
            function: BmapFunction(block: .audioModes, rawValue: BossAudioModesCodec.modeConfigFunctionRaw),
            operator: .status,
            payload: payload
        )

        let mode = try BossAudioModesCodec.parseModeConfig(from: packet)
        XCTAssertEqual(mode.modeIndex, 2)
        XCTAssertEqual(mode.name, "Immersion")
        XCTAssertTrue(mode.favorite)
        XCTAssertTrue(mode.userConfigurable)
        XCTAssertFalse(mode.userConfigured)
    }

    func testAudioModeSettingsConfigParserReadsLiveSettings() throws {
        let packet = BmapPacket(
            functionBlock: .audioModes,
            function: BmapFunction(block: .audioModes, rawValue: BossAudioModesCodec.settingsConfigFunctionRaw),
            operator: .status,
            payload: Data([0x05, 0x00, 0x02, 0x01, 0x01])
        )

        let config = try BossAudioModesCodec.parseSettingsConfig(from: packet)
        XCTAssertEqual(config.cncLevel, 5)
        XCTAssertFalse(config.autoCNCEnabled)
        XCTAssertEqual(config.spatialAudioMode, .head)
        XCTAssertTrue(config.windBlockEnabled)
        XCTAssertTrue(config.ancToggleEnabled)
    }

    func testAudioModeSettingsConfigEncoderWritesFiveByteSetGetPayload() throws {
        let config = BossAudioModeSettingsConfig(
            cncLevel: 3,
            autoCNCEnabled: false,
            spatialAudioMode: .room,
            windBlockEnabled: false,
            ancToggleEnabled: true
        )

        let packet = try BossAudioModesCodec.settingsConfigSetGetPacket(config)
        XCTAssertEqual(packet.functionBlock, .audioModes)
        XCTAssertEqual(packet.function.rawValue, BossAudioModesCodec.settingsConfigFunctionRaw)
        XCTAssertEqual(packet.operator, .setGet)
        XCTAssertEqual(packet.payload, Data([0x03, 0x00, 0x01, 0x00, 0x01]))
    }

    func testAudioModeSettingsConfigPatchPreservesUnspecifiedFields() {
        let current = BossAudioModeSettingsConfig(
            cncLevel: 8,
            autoCNCEnabled: false,
            spatialAudioMode: .off,
            windBlockEnabled: true,
            ancToggleEnabled: true
        )
        let patch = BossAudioModeSettingsConfigPatch(
            cncLevel: 4,
            spatialAudioMode: .head,
            windBlockEnabled: false
        )

        let merged = patch.merged(with: current)
        XCTAssertEqual(merged.cncLevel, 4)
        XCTAssertFalse(merged.autoCNCEnabled)
        XCTAssertEqual(merged.spatialAudioMode, .head)
        XCTAssertFalse(merged.windBlockEnabled)
        XCTAssertTrue(merged.ancToggleEnabled)
        XCTAssertFalse(patch.isEmpty)
        XCTAssertTrue(BossAudioModeSettingsConfigPatch().isEmpty)
    }

    func testAudioModeSettingsConfigPatchMatchesOnlySpecifiedFields() {
        let patch = BossAudioModeSettingsConfigPatch(ancToggleEnabled: false)

        XCTAssertTrue(patch.matches(BossAudioModeSettingsConfig(
            cncLevel: 10,
            autoCNCEnabled: false,
            spatialAudioMode: .off,
            windBlockEnabled: false,
            ancToggleEnabled: false
        )))
        XCTAssertFalse(patch.matches(BossAudioModeSettingsConfig(
            cncLevel: 5,
            autoCNCEnabled: false,
            spatialAudioMode: .off,
            windBlockEnabled: false,
            ancToggleEnabled: true
        )))
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
