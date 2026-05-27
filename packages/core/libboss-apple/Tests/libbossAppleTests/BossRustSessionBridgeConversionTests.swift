import CBossRustFFI
import XCTest

@testable import libbossApple

final class BossRustSessionBridgeConversionTests: XCTestCase {
    func testSwiftConfigMapsFFIFields() throws {
        let ffi = BossFfiAudioModeSettingsConfig(
            cnc_level: 8,
            auto_cnc_enabled: true,
            spatial_audio_mode: BossAppleSpatialAudioMode.room.rawValue,
            wind_block_enabled: false,
            anc_toggle_enabled: true
        )

        let config = try BossRustSessionBridge.swiftConfig(from: ffi)

        XCTAssertEqual(
            config,
            BossAppleAudioModeSettingsConfig(
                cncLevel: 8,
                autoCNCEnabled: true,
                spatialAudioMode: .room,
                windBlockEnabled: false,
                ancToggleEnabled: true
            )
        )
    }

    func testSwiftConfigRejectsUnknownSpatialAudioMode() {
        let ffi = BossFfiAudioModeSettingsConfig(
            cnc_level: 3,
            auto_cnc_enabled: false,
            spatial_audio_mode: 99,
            wind_block_enabled: false,
            anc_toggle_enabled: false
        )

        XCTAssertThrowsError(try BossRustSessionBridge.swiftConfig(from: ffi)) { error in
            XCTAssertEqual(
                error as? BossAppleControlError,
                .unsupportedOperation("Rust FFI returned unknown spatial audio mode 99")
            )
        }
    }

    func testSwiftObservedMappingsProjectSourceAndUnavailableReason() {
        let observedBool = BossRustSessionBridge.swiftObservedBool(
            from: BossFfiObservedBool(
                has_value: false,
                value: false,
                has_source: false,
                source: 0,
                has_unavailable_reason: true,
                unavailable_reason: 1
            )
        )
        XCTAssertEqual(observedBool.value, nil)
        XCTAssertEqual(observedBool.unavailableReason, .timedOut)

        let observedWearDetection = BossRustSessionBridge.swiftObservedOnHeadDetection(
            from: BossFfiObservedOnHeadDetection(
                has_value: true,
                value: BossFfiOnHeadDetectionValue(
                    is_enabled: true,
                    has_auto_play_enabled: true,
                    auto_play_enabled: false,
                    has_auto_answer_enabled: true,
                    auto_answer_enabled: true,
                    has_auto_transparency_enabled: false,
                    auto_transparency_enabled: false
                ),
                has_source: true,
                source: 1,
                has_unavailable_reason: false,
                unavailable_reason: 0
            )
        )
        XCTAssertEqual(observedWearDetection.source, .compositeSnapshot)
        XCTAssertEqual(
            observedWearDetection.value,
            BossAppleOnHeadDetectionValue(
                isEnabled: true,
                isAutoPlayEnabled: false,
                isAutoAnswerEnabled: true,
                isAutoTransparencyEnabled: nil
            )
        )
    }

    func testSwiftVolumeControlStatusMapsBitmaskAndRejectsUnknownValue() throws {
        let ffi = BossFfiVolumeControlStatus(
            value: BossAppleVolumeControlValue.capTouch.rawValue,
            has_supported_values_mask: true,
            supported_values_mask: 0x07
        )

        let status = try BossRustSessionBridge.swiftVolumeControlStatus(from: ffi)
        XCTAssertEqual(status.value, .capTouch)
        XCTAssertEqual(status.supportedValues, [.button, .capTouch, .imu])

        XCTAssertThrowsError(
            try BossRustSessionBridge.swiftVolumeControlStatus(
                from: BossFfiVolumeControlStatus(
                    value: 255,
                    has_supported_values_mask: false,
                    supported_values_mask: 0
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? BossAppleControlError,
                .unsupportedOperation("Rust FFI returned unknown volume control value 255")
            )
        }
    }

    func testSwiftAudioModeConfigTrimsNameBufferAndMapsKnownPrompt() throws {
        var nameBytes = [UInt8](repeating: 0, count: 32)
        Array("Commute".utf8).enumerated().forEach { index, byte in
            nameBytes[index] = byte
        }
        let ffi = BossFfiAudioModeConfig(
            mode_index: 4,
            prompt_byte1: 0,
            prompt_byte2: 7,
            name_len: 7,
            name_bytes: (
                nameBytes[0], nameBytes[1], nameBytes[2], nameBytes[3],
                nameBytes[4], nameBytes[5], nameBytes[6], nameBytes[7],
                nameBytes[8], nameBytes[9], nameBytes[10], nameBytes[11],
                nameBytes[12], nameBytes[13], nameBytes[14], nameBytes[15],
                nameBytes[16], nameBytes[17], nameBytes[18], nameBytes[19],
                nameBytes[20], nameBytes[21], nameBytes[22], nameBytes[23],
                nameBytes[24], nameBytes[25], nameBytes[26], nameBytes[27],
                nameBytes[28], nameBytes[29], nameBytes[30], nameBytes[31]
            ),
            favorite: true,
            user_configurable: true,
            user_configured: false,
            settings: BossFfiAudioModeSettingsConfig(
                cnc_level: 2,
                auto_cnc_enabled: false,
                spatial_audio_mode: BossAppleSpatialAudioMode.off.rawValue,
                wind_block_enabled: false,
                anc_toggle_enabled: true
            )
        )

        let config = try BossRustSessionBridge.swiftAudioModeConfig(from: ffi)

        XCTAssertEqual(config.modeIndex, 4)
        XCTAssertEqual(config.prompt, .commute)
        XCTAssertEqual(config.name, "Commute")
        XCTAssertTrue(config.favorite)
        XCTAssertTrue(config.userConfigurable)
        XCTAssertFalse(config.userConfigured)
    }
}
