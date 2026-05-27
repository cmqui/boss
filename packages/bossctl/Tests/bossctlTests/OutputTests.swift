import XCTest
import libbossApple

@testable import bossctl

final class OutputTests: XCTestCase {
    func testPrintBootstrapWritesExpectedSummary() {
        let writer = RecordingOutputWriter()
        let device = BossAppleBootstrappedDevice(
            bmapVersion: BossAppleBmapVersionInfo(version: "1.2"),
            productID: 0x1234,
            productName: "QuietComfort Ultra",
            productVariant: BossAppleProductVariant(
                productID: 0x1234,
                variant: 0x02,
                product: BossAppleProductDefinition(
                    id: 0x1234,
                    codeName: "qc-ultra",
                    displayName: "QuietComfort Ultra",
                    family: .qcUltra2,
                    category: .headphones,
                    variants: [0x02: "Black"]
                ),
                variantName: "Black"
            ),
            protocolSupport: BossAppleProtocolSupport(
                functionBlocks: BossAppleFunctionBlockSet(bits: [1, 31]),
                transportKind: .ble,
                defaultDeviceID: 1,
                defaultPort: 2
            ),
            capabilities: BossAppleDeviceCapabilities(
                settings: BossAppleSettingsCapabilities(
                    standbyTimer: .readWrite,
                    wearDetection: .readWrite,
                    autoAware: .readWrite,
                    autoPlayPause: .readWrite,
                    autoAnswer: .readWrite,
                    volumeControl: .readWrite
                ),
                audioModes: BossAppleAudioModeCapabilities(
                    modes: .supported,
                    currentMode: .readWrite,
                    settingsConfig: .readWrite,
                    favorites: .readWrite,
                    customProfiles: .readWrite,
                    supportedPrompts: .supported
                ),
                sound: BossAppleSoundCapabilities(equalizer: .readWrite)
            )
        )

        BossctlCLI.printBootstrap(device, output: writer)

        XCTAssertEqual(writer.lines, [
            "Transport: ble",
            "BMAP: 1.2",
            "Product: QuietComfort Ultra (0x1234)",
            "Variant: Black (raw=0x02)",
            "Function blocks: productInfo, settings, audioModes",
        ])
    }

    func testPrintDeviceSettingsReportUsesObservedAndFallbackValues() {
        let writer = RecordingOutputWriter()
        let report = BossAppleDeviceSettingsReport(
            wearDetection: BossAppleObservedSetting(
                value: BossAppleOnHeadDetectionValue(
                    isEnabled: true,
                    isAutoPlayEnabled: nil,
                    isAutoAnswerEnabled: false,
                    isAutoTransparencyEnabled: nil
                ),
                source: .compositeSnapshot
            ),
            autoAwareEnabled: BossAppleObservedSetting(value: true, source: .directGet),
            autoPlayPauseEnabled: BossAppleObservedSetting(value: true, source: .snapshot),
            autoAnswerEnabled: BossAppleObservedSetting(value: nil, unavailableReason: .timedOut),
            volumeControl: BossAppleObservedSetting(
                value: BossAppleVolumeControlStatus(
                    value: .capTouch,
                    supportedValues: [.button, .capTouch]
                ),
                source: .directGet
            )
        )

        BossctlCLI.printDeviceSettingsReport(report, output: writer)

        XCTAssertEqual(writer.lines, [
            "Wear detection: true [compositeSnapshot]",
            "Auto-play: unsupported",
            "Auto-answer: disabled",
            "Auto-transparency: unsupported",
            "Auto-aware: true [directGet]",
            "Auto-play-pause: true [snapshot]",
            "Auto-answer: unavailable [timed out]",
            "Volume control: captouch [directGet]",
            "Volume control supported modes: button, captouch",
        ])
    }

    func testPrintAudioModeSettingsFieldWriteResultEmitsSingleLineSummary() {
        let writer = RecordingOutputWriter()
        let config = BossAppleAudioModeSettingsConfig(
            cncLevel: 7,
            autoCNCEnabled: true,
            spatialAudioMode: .head,
            windBlockEnabled: false,
            ancToggleEnabled: true
        )

        BossctlCLI.printAudioModeSettingsConfigWriteResult(
            .updated(config),
            output: .field(.spatialAudio),
            writer: writer
        )

        XCTAssertEqual(writer.lines, [
            "Spatial audio updated: head",
        ])
    }

    func testPrintFavoriteAudioModesHandlesEmptyAndNamedFavorites() {
        let emptyWriter = RecordingOutputWriter()
        BossctlCLI.printFavoriteAudioModes([], modes: [], output: emptyWriter)
        XCTAssertEqual(emptyWriter.lines, ["Favorite audio modes: none"])

        let writer = RecordingOutputWriter()
        BossctlCLI.printFavoriteAudioModes(
            [3, 1],
            modes: [
                BossAppleAudioModeInfo(modeIndex: 1, name: "Quiet", favorite: true, userConfigurable: false, userConfigured: false),
                BossAppleAudioModeInfo(modeIndex: 3, name: "Aware", favorite: true, userConfigurable: false, userConfigured: false),
            ],
            output: writer
        )

        XCTAssertEqual(writer.lines, [
            "Favorite audio modes:",
            "  1: Quiet",
            "  3: Aware",
        ])
    }
}
