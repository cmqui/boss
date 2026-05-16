import XCTest
import libboss
@testable import libbossApple

final class AppleBleBossTransportTests: XCTestCase {
    func testCharacteristicPreferenceRawValues() {
        XCTAssertEqual(AppleBossCharacteristicPreference.automatic.rawValue, "automatic")
        XCTAssertEqual(AppleBossCharacteristicPreference.unsecure.rawValue, "unsecure")
        XCTAssertEqual(AppleBossCharacteristicPreference.secure.rawValue, "secure")
    }

    func testConnectionOptionsPreserveSelectionWhenChangingCharacteristicPreference() {
        let identifier = UUID()
        let options = BossAppleConnectionOptions(
            nameContains: "Bose",
            identifier: identifier,
            scanTimeout: .seconds(7),
            characteristicPreference: .automatic
        )

        let secure = options.withCharacteristicPreference(.secure)

        XCTAssertEqual(secure.nameContains, "Bose")
        XCTAssertEqual(secure.identifier, identifier)
        XCTAssertEqual(secure.scanTimeout, .seconds(7))
        XCTAssertEqual(secure.characteristicPreference, .secure)
    }

    func testBmapErrorCodeIsExposedFromControlError() {
        let error = BossAppleControlError.bmapErrorResponse(context: "settings.example", payloadHex: "14")

        XCTAssertEqual(error.bmapErrorCode, .insecureTransport)
    }

    func testUnavailableSettingReadErrorsRecognizeProtocolUnsupportedCodes() {
        XCTAssertTrue(
            BossAppleController.isUnavailableSettingReadError(
                BossAppleControlError.bmapErrorResponse(context: "settings.autoAware", payloadHex: "04")
            )
        )
        XCTAssertTrue(
            BossAppleController.isUnavailableSettingReadError(
                BossAppleControlError.bmapErrorResponse(context: "settings.autoAware", payloadHex: "05")
            )
        )
        XCTAssertTrue(
            BossAppleController.isUnavailableSettingReadError(
                BossAppleControlError.bmapErrorResponse(context: "settings.autoAware", payloadHex: "07")
            )
        )
    }

    func testUnavailableSettingReadErrorsTreatTimeoutsAsUnavailable() {
        XCTAssertTrue(
            BossAppleController.isUnavailableSettingReadError(
                BossAppleControlError.responseTimedOut(seconds: 5)
            )
        )
        XCTAssertTrue(BossAppleController.isUnavailableSettingReadError(BossAppleControlError.responseStreamEnded))
    }

    func testDeviceSettingsReportProjectsToPlainSettings() {
        let report = BossAppleDeviceSettingsReport(
            wearDetection: BossAppleObservedSetting(
                value: BossOnHeadDetectionValue(
                    isEnabled: true,
                    isAutoPlayEnabled: true,
                    isAutoAnswerEnabled: false,
                    isAutoTransparencyEnabled: nil
                ),
                source: .directGet
            ),
            autoAwareEnabled: BossAppleObservedSetting(value: false, source: .snapshot),
            autoPlayPauseEnabled: BossAppleObservedSetting(value: false, source: .snapshot),
            autoAnswerEnabled: BossAppleObservedSetting(value: false, source: .compositeSnapshot),
            volumeControl: BossAppleObservedSetting(value: nil, unavailableReason: .timedOut)
        )

        XCTAssertEqual(report.settings.wearDetection?.isEnabled, true)
        XCTAssertEqual(report.settings.autoAwareEnabled, false)
        XCTAssertEqual(report.settings.autoPlayPauseEnabled, false)
        XCTAssertEqual(report.settings.autoAnswerEnabled, false)
        XCTAssertNil(report.settings.volumeControl)
    }
}
