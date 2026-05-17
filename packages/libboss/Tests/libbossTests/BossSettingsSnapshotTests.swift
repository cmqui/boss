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

    func testStandbyTimerSetGetPacketEncodesSingleByteMinutes() throws {
        let packet = try BossSettingsCodec.standbyTimerSetGetPacket(minutes: 30)

        XCTAssertEqual(packet.functionBlock, .settings)
        XCTAssertEqual(packet.function.rawValue, BossSettingsCodec.standbyTimerFunctionRaw)
        XCTAssertEqual(packet.operator, .setGet)
        XCTAssertEqual(packet.payload, Data([0x1E]))
    }

    func testStandbyTimerSetGetPacketEncodesTwoByteMinutes() throws {
        let packet = try BossSettingsCodec.standbyTimerSetGetPacket(minutes: 300)

        XCTAssertEqual(packet.payload, Data([0x2C, 0x01]))
    }

    func testStandbyTimerSetGetPacketRejectsOutOfRangeMinutes() {
        XCTAssertThrowsError(try BossSettingsCodec.standbyTimerSetGetPacket(minutes: -1)) { error in
            XCTAssertEqual(
                error as? BossSettingsCodecError,
                .invalidPayload("Standby timer minutes must be in range 0...65535")
            )
        }

        XCTAssertThrowsError(try BossSettingsCodec.standbyTimerSetGetPacket(minutes: 65_536)) { error in
            XCTAssertEqual(
                error as? BossSettingsCodecError,
                .invalidPayload("Standby timer minutes must be in range 0...65535")
            )
        }
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

    func testOnHeadDetectionSetGetPacketEncodesExpectedTwoBytePayload() {
        let packet = BossSettingsCodec.onHeadDetectionSetGetPacket(
            BossOnHeadDetectionValue(
                isEnabled: true,
                isAutoPlayEnabled: true,
                isAutoAnswerEnabled: false,
                isAutoTransparencyEnabled: true
            )
        )

        XCTAssertEqual(packet.functionBlock, .settings)
        XCTAssertEqual(packet.function.rawValue, BossSettingsCodec.onHeadDetectionFunctionRaw)
        XCTAssertEqual(packet.operator, .setGet)
        XCTAssertEqual(packet.payload, Data([0x01, 0x05]))
    }

    func testOnHeadDetectionPatchPreservesUnspecifiedFields() {
        let current = BossOnHeadDetectionValue(
            isEnabled: true,
            isAutoPlayEnabled: true,
            isAutoAnswerEnabled: false,
            isAutoTransparencyEnabled: nil
        )
        let patch = BossOnHeadDetectionPatch(
            isEnabled: false,
            isAutoAnswerEnabled: true
        )

        let merged = patch.merged(with: current)
        XCTAssertEqual(
            merged,
            BossOnHeadDetectionValue(
                isEnabled: false,
                isAutoPlayEnabled: true,
                isAutoAnswerEnabled: true,
                isAutoTransparencyEnabled: nil
            )
        )
        XCTAssertFalse(patch.isEmpty)
        XCTAssertTrue(BossOnHeadDetectionPatch().isEmpty)
    }

    func testVolumeControlResolvesFromSnapshotPacket() throws {
        let snapshot = BossSettingsSnapshot(packetsByFunctionRaw: [
            BossSettingsCodec.volumeControlFunctionRaw: settingsPacket(
                functionRaw: BossSettingsCodec.volumeControlFunctionRaw,
                payload: Data([BossVolumeControlValue.capTouch.rawValue, 0x00])
            )
        ])

        XCTAssertEqual(try snapshot.volumeControl()?.value, .capTouch)
        XCTAssertEqual(try snapshot.volumeControl()?.supportedValues, [])
    }

    func testVolumeControlSupportBitmaskResolvesFromSnapshotPacket() throws {
        let snapshot = BossSettingsSnapshot(packetsByFunctionRaw: [
            BossSettingsCodec.volumeControlFunctionRaw: settingsPacket(
                functionRaw: BossSettingsCodec.volumeControlFunctionRaw,
                payload: Data([BossVolumeControlValue.capTouch.rawValue, 0x03])
            )
        ])

        XCTAssertEqual(try snapshot.volumeControl()?.value, .capTouch)
        XCTAssertEqual(try snapshot.volumeControl()?.supportedValues, [.button, .capTouch])
    }

    func testEqualizerParserReadsSignedRangeLevels() throws {
        let packet = BmapPacket(
            functionBlock: .settings,
            function: BmapFunction(block: .settings, rawValue: BossSettingsCodec.rangeControlFunctionRaw),
            operator: .status,
            payload: Data([
                0xF6, 0x0A, 0x03, 0x00,
                0xF6, 0x0A, 0xFE, 0x01,
                0xF6, 0x0A, 0x05, 0x02
            ])
        )

        let equalizer = try BossSettingsCodec.parseEqualizer(from: packet)
        XCTAssertEqual(equalizer.bass, BossEqualizerRangeLevel(band: .bass, currentLevel: 3, minLevel: -10, maxLevel: 10))
        XCTAssertEqual(equalizer.mid, BossEqualizerRangeLevel(band: .mid, currentLevel: -2, minLevel: -10, maxLevel: 10))
        XCTAssertEqual(equalizer.treble, BossEqualizerRangeLevel(band: .treble, currentLevel: 5, minLevel: -10, maxLevel: 10))
    }

    func testEqualizerSetGetPacketEncodesSignedLevelAndBand() throws {
        let packet = try BossSettingsCodec.equalizerSetGetPacket(targetLevel: -3, band: .mid)

        XCTAssertEqual(packet.functionBlock, .settings)
        XCTAssertEqual(packet.function.rawValue, BossSettingsCodec.rangeControlFunctionRaw)
        XCTAssertEqual(packet.operator, .setGet)
        XCTAssertEqual(packet.payload, Data([0xFD, 0x01]))
    }

    func testEqualizerResolvesFromSnapshotPacket() throws {
        let snapshot = BossSettingsSnapshot(packetsByFunctionRaw: [
            BossSettingsCodec.rangeControlFunctionRaw: settingsPacket(
                functionRaw: BossSettingsCodec.rangeControlFunctionRaw,
                payload: Data([
                    0xF6, 0x0A, 0x03, 0x00,
                    0xF6, 0x0A, 0xFE, 0x01,
                    0xF6, 0x0A, 0x05, 0x02
                ])
            )
        ])

        let equalizer = try XCTUnwrap(snapshot.equalizer())
        XCTAssertEqual(equalizer.bass?.currentLevel, 3)
        XCTAssertEqual(equalizer.mid?.currentLevel, -2)
        XCTAssertEqual(equalizer.treble?.currentLevel, 5)
    }

    func testEqualizerSettingsPatchMatchesOnlySpecifiedBands() {
        let patch = BossEqualizerSettingsPatch(mid: -1)
        let matching = BossEqualizerSettings(ranges: [
            BossEqualizerRangeLevel(band: .bass, currentLevel: 4, minLevel: -10, maxLevel: 10),
            BossEqualizerRangeLevel(band: .mid, currentLevel: -1, minLevel: -10, maxLevel: 10),
            BossEqualizerRangeLevel(band: .treble, currentLevel: 2, minLevel: -10, maxLevel: 10)
        ])
        let nonMatching = BossEqualizerSettings(ranges: [
            BossEqualizerRangeLevel(band: .bass, currentLevel: 4, minLevel: -10, maxLevel: 10),
            BossEqualizerRangeLevel(band: .mid, currentLevel: 1, minLevel: -10, maxLevel: 10),
            BossEqualizerRangeLevel(band: .treble, currentLevel: 2, minLevel: -10, maxLevel: 10)
        ])

        XCTAssertFalse(patch.isEmpty)
        XCTAssertTrue(BossEqualizerSettingsPatch().isEmpty)
        XCTAssertTrue(patch.matches(matching))
        XCTAssertFalse(patch.matches(nonMatching))
    }

    func testDeviceSettingsAggregatesSnapshotValues() throws {
        let snapshot = BossSettingsSnapshot(packetsByFunctionRaw: [
            BossSettingsCodec.onHeadDetectionFunctionRaw: settingsPacket(
                functionRaw: BossSettingsCodec.onHeadDetectionFunctionRaw,
                payload: Data([0x07, 0x03])
            ),
            BossSettingsCodec.autoAwareFunctionRaw: settingsPacket(
                functionRaw: BossSettingsCodec.autoAwareFunctionRaw,
                payload: Data([0x01])
            ),
            BossSettingsCodec.autoPlayPauseFunctionRaw: settingsPacket(
                functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw,
                payload: Data([0x00])
            ),
            BossSettingsCodec.volumeControlFunctionRaw: settingsPacket(
                functionRaw: BossSettingsCodec.volumeControlFunctionRaw,
                payload: Data([BossVolumeControlValue.button.rawValue, 0x00])
            )
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
        var payload = Data(repeating: 0, count: 48)
        payload[0] = 0x02
        payload[1] = 0x00
        payload[2] = 0x22
        payload[3] = 0x01
        payload[4] = 0x00
        payload[5] = 0x01
        payload[42] = 0x05
        payload[44] = 0x02
        payload[45] = 0x01
        payload[47] = 0x01
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

        let detail = try BossAudioModesCodec.parseModeConfigDetail(from: packet)
        XCTAssertEqual(detail.prompt, .immersion)
        XCTAssertEqual(detail.settings.cncLevel, 5)
        XCTAssertEqual(detail.settings.spatialAudioMode, .head)
        XCTAssertTrue(detail.settings.windBlockEnabled)
        XCTAssertTrue(detail.settings.ancToggleEnabled)
    }

    func testAudioModeConfigSetGetPacketEncodesProfileNamePromptAndSettings() throws {
        let settings = BossAudioModeSettingsConfig(
            cncLevel: 7,
            autoCNCEnabled: false,
            spatialAudioMode: .head,
            windBlockEnabled: true,
            ancToggleEnabled: true
        )

        let packet = try BossAudioModesCodec.modeConfigSetGetPacket(
            modeIndex: 5,
            prompt: .focus,
            name: "Deep Work",
            settings: settings
        )

        XCTAssertEqual(packet.functionBlock, .audioModes)
        XCTAssertEqual(packet.function.rawValue, BossAudioModesCodec.modeConfigFunctionRaw)
        XCTAssertEqual(packet.operator, .setGet)
        XCTAssertEqual(packet.payload.count, 40)
        XCTAssertEqual(packet.payload[0], 5)
        XCTAssertEqual(packet.payload[1], 0)
        XCTAssertEqual(packet.payload[2], 13)
        XCTAssertEqual(String(data: packet.payload[3..<12], encoding: .utf8), "Deep Work")
        XCTAssertEqual(packet.payload[35], 7)
        XCTAssertEqual(packet.payload[36], 0)
        XCTAssertEqual(packet.payload[37], 2)
        XCTAssertEqual(packet.payload[38], 1)
        XCTAssertEqual(packet.payload[39], 1)
    }

    func testAudioModeConfigParserReadsSetGetEchoPayload() throws {
        let settings = BossAudioModeSettingsConfig(
            cncLevel: 4,
            autoCNCEnabled: true,
            spatialAudioMode: .room,
            windBlockEnabled: false,
            ancToggleEnabled: true
        )
        let payload = try BossAudioModesCodec.encodeModeConfigSetGetPayload(
            modeIndex: 6,
            prompt: .home,
            name: "Home Office",
            settings: settings
        )
        let packet = BmapPacket(
            functionBlock: .audioModes,
            function: BmapFunction(block: .audioModes, rawValue: BossAudioModesCodec.modeConfigFunctionRaw),
            operator: .status,
            payload: payload
        )

        let mode = try BossAudioModesCodec.parseModeConfigDetail(from: packet)
        XCTAssertEqual(mode.modeIndex, 6)
        XCTAssertEqual(mode.prompt, .home)
        XCTAssertEqual(mode.name, "Home Office")
        XCTAssertTrue(mode.userConfigurable)
        XCTAssertTrue(mode.userConfigured)
        XCTAssertEqual(mode.settings, settings)
    }

    func testSupportedAudioModePromptParserReadsBitmask() throws {
        let packet = BmapPacket(
            functionBlock: .audioModes,
            function: BmapFunction(block: .audioModes, rawValue: BossAudioModesCodec.namesSupportedFunctionRaw),
            operator: .status,
            payload: Data([0b0000_0111, 0b0010_0000])
        )

        XCTAssertEqual(try BossAudioModesCodec.parseSupportedPrompts(from: packet), [.none, .quiet, .aware, .focus])
    }

    func testAudioModeFavoritesParserReadsReversedBitmask() throws {
        let packet = BmapPacket(
            functionBlock: .audioModes,
            function: BmapFunction(block: .audioModes, rawValue: BossAudioModesCodec.favoritesFunctionRaw),
            operator: .status,
            payload: Data([0x0B, 0b0000_0100, 0b0000_0101])
        )

        XCTAssertEqual(try BossAudioModesCodec.parseFavorites(from: packet), [0, 2, 10])
    }

    func testAudioModeFavoritesSetGetPacketEncodesReversedBitmask() throws {
        let packet = try BossAudioModesCodec.favoritesSetGetPacket(
            numberOfModes: 11,
            favoriteModeIndices: [10, 0, 2, 2]
        )

        XCTAssertEqual(packet.functionBlock, .audioModes)
        XCTAssertEqual(packet.function.rawValue, BossAudioModesCodec.favoritesFunctionRaw)
        XCTAssertEqual(packet.operator, .setGet)
        XCTAssertEqual(packet.payload, Data([0x0B, 0b0000_0100, 0b0000_0101]))
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

    func testDeletedSettingsBaselinePreservesNonNameSettingsAndResetsCNC() {
        let config = BossAudioModeConfig(
            modeIndex: 7,
            prompt: .focus,
            name: "Focus Work",
            favorite: true,
            userConfigurable: true,
            userConfigured: true,
            settings: BossAudioModeSettingsConfig(
                cncLevel: 9,
                autoCNCEnabled: true,
                spatialAudioMode: .head,
                windBlockEnabled: false,
                ancToggleEnabled: true
            )
        )

        XCTAssertEqual(
            config.deletedSettingsBaseline,
            BossAudioModeSettingsConfig(
                cncLevel: 5,
                autoCNCEnabled: true,
                spatialAudioMode: .head,
                windBlockEnabled: false,
                ancToggleEnabled: true
            )
        )
    }
}
