import XCTest
import libbossApple

@testable import bossctl

final class CommandParsingTests: XCTestCase {
    func testVersionFlagParsesVersionCommand() throws {
        let command = try Command.parse(arguments: ["-v"])
        guard case .version = command else {
            return XCTFail("Expected version command")
        }
    }

    func testBootstrapHappyPathParsesConnectionOptions() throws {
        let command = try Command.parse(arguments: [
            "bootstrap",
            "--name", "Ultra",
            "--timeout", "9",
            "--characteristic", "secure",
        ])

        guard case .bootstrap(let options) = command else {
            return XCTFail("Expected bootstrap command")
        }

        XCTAssertEqual(options.nameContains, "Ultra")
        XCTAssertNil(options.identifier)
        XCTAssertEqual(options.timeoutSeconds, 9)
        XCTAssertEqual(options.characteristicPreference, .secure)
    }

    func testSettingsHappyPathParsesEqualizerPatch() throws {
        let command = try Command.parse(arguments: [
            "settings",
            "set",
            "equalizer",
            "--bass", "3",
            "--treble", "-1",
            "--timeout", "12",
        ])

        guard case .settings(let settings) = command else {
            return XCTFail("Expected settings command")
        }

        XCTAssertEqual(settings.connection.timeoutSeconds, 12)
        guard case .setEqualizer(let patch) = settings.action else {
            return XCTFail("Expected equalizer patch action")
        }
        XCTAssertEqual(patch, BossAppleEqualizerSettingsPatch(bass: 3, treble: -1))
    }

    func testAudioModeHappyPathParsesCurrentModeSelectionByName() throws {
        let command = try Command.parse(arguments: [
            "audio-mode",
            "set",
            "current",
            "--mode", "Quiet",
            "--play-voice-prompt", "true",
        ])

        guard case .audioMode(let audioMode) = command else {
            return XCTFail("Expected audio-mode command")
        }

        guard case .setCurrent(let selection, let playVoicePrompt) = audioMode.action else {
            return XCTFail("Expected current mode write action")
        }
        guard case .name(let modeName) = selection else {
            return XCTFail("Expected mode name selection")
        }

        XCTAssertEqual(modeName, "Quiet")
        XCTAssertTrue(playVoicePrompt)
    }

    func testMissingFlagValueProducesUsageError() {
        XCTAssertThrowsError(try Command.parse(arguments: [
            "settings",
            "set",
            "standby-timer",
            "--minutes",
        ])) { error in
            XCTAssertEqual((error as? UsageError)?.message, "Missing value for --minutes")
        }
    }

    func testBadUUIDProducesUsageError() {
        XCTAssertThrowsError(try ConnectionOptions.parse(arguments: [
            "--identifier", "not-a-uuid",
        ])) { error in
            XCTAssertEqual((error as? UsageError)?.message, "Invalid UUID for --identifier: not-a-uuid")
        }
    }

    func testInvalidTimeoutProducesUsageError() {
        XCTAssertThrowsError(try ConnectionOptions.parse(arguments: [
            "--timeout", "fast",
        ])) { error in
            XCTAssertEqual((error as? UsageError)?.message, "Invalid integer for --timeout: fast")
        }
    }

    func testUnsupportedCharacteristicValueProducesUsageError() {
        XCTAssertThrowsError(try ConnectionOptions.parse(arguments: [
            "--characteristic", "legacy",
        ])) { error in
            XCTAssertEqual((error as? UsageError)?.message, "Invalid value for --characteristic: legacy")
        }
    }

    func testAudioModeRejectsConflictingSelectionFlags() {
        XCTAssertThrowsError(try Command.parse(arguments: [
            "audio-mode",
            "favorite",
            "--index", "1",
            "--mode", "Quiet",
        ])) { error in
            XCTAssertEqual((error as? UsageError)?.message, "Specify only one of --index or --mode")
        }
    }

    func testAudioModeRejectsOutOfRangeCNCLevel() {
        XCTAssertThrowsError(try Command.parse(arguments: [
            "audio-mode",
            "cnc",
            "--level", "11",
        ])) { error in
            XCTAssertEqual((error as? UsageError)?.message, "Invalid CNC level for --level: 11")
        }
    }

    func testAudioModeDeleteParsesSelectionByIndex() throws {
        let command = try Command.parse(arguments: [
            "audio-mode",
            "delete",
            "--index", "7",
        ])

        guard case .audioMode(let audioMode) = command else {
            return XCTFail("Expected audio-mode command")
        }

        guard case .delete(let selection) = audioMode.action else {
            return XCTFail("Expected delete action")
        }

        guard case .index(let index) = selection else {
            return XCTFail("Expected index selection")
        }

        XCTAssertEqual(index, 7)
    }

    func testSettingsRejectsUnsupportedVolumeControlMode() {
        XCTAssertThrowsError(try Command.parse(arguments: [
            "settings",
            "set",
            "volume-control",
            "--mode", "swipe",
        ])) { error in
            XCTAssertEqual((error as? UsageError)?.message, "Invalid volume control value for --mode: swipe")
        }
    }

    func testStreamProbeParsesTargetAndDuration() throws {
        let command = try Command.parse(arguments: [
            "stream",
            "probe",
            "device-settings",
            "--duration", "45",
            "--name", "Bose",
        ])

        guard case .stream(let stream) = command else {
            return XCTFail("Expected stream command")
        }

        XCTAssertEqual(stream.connection.nameContains, "Bose")
        guard case .probe(let options) = stream.action else {
            return XCTFail("Expected stream probe action")
        }
        XCTAssertEqual(options.target, .deviceSettings)
        XCTAssertEqual(options.durationSeconds, 45)
    }

    func testStreamProbeRejectsUnknownTarget() {
        XCTAssertThrowsError(try Command.parse(arguments: [
            "stream",
            "probe",
            "settings",
        ])) { error in
            XCTAssertEqual((error as? UsageError)?.message, "Unknown stream probe target: settings")
        }
    }

    func testBmapTraceParsesDurationAndConnection() throws {
        let command = try Command.parse(arguments: [
            "bmap",
            "trace",
            "--duration", "20",
            "--identifier", "40824082-0000-4000-8000-000000000002",
        ])

        guard case .bmap(let bmap) = command else {
            return XCTFail("Expected bmap command")
        }

        XCTAssertEqual(bmap.connection.identifier?.uuidString, "40824082-0000-4000-8000-000000000002")
        guard case .trace(let durationSeconds) = bmap.action else {
            return XCTFail("Expected trace action")
        }
        XCTAssertEqual(durationSeconds, 20)
    }

    func testBmapDebugCurrentModeParsesDurationAndCharacteristic() throws {
        let command = try Command.parse(arguments: [
            "bmap",
            "debug-current-mode",
            "--duration", "15",
            "--characteristic", "unsecure",
        ])

        guard case .bmap(let bmap) = command else {
            return XCTFail("Expected bmap command")
        }

        XCTAssertEqual(bmap.connection.characteristicPreference, .unsecure)
        guard case .debugCurrentMode(let durationSeconds) = bmap.action else {
            return XCTFail("Expected debug-current-mode action")
        }
        XCTAssertEqual(durationSeconds, 15)
    }
}
