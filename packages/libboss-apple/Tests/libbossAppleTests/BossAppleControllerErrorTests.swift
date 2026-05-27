import XCTest

@testable import libbossApple

final class BossAppleControllerErrorTests: XCTestCase {
    func testUnavailableSettingReasonCoversExpectedVariants() {
        XCTAssertEqual(
            BossAppleController.unavailableSettingReason(
                BossAppleControlError.responseTimedOut(seconds: 5)
            ),
            .timedOut
        )
        XCTAssertEqual(
            BossAppleController.unavailableSettingReason(BossAppleControlError.responseStreamEnded),
            .responseStreamEnded
        )
        XCTAssertEqual(
            BossAppleController.unavailableSettingReason(
                BossAppleControlError.bmapErrorResponse(context: "settings.autoAware", payloadHex: "03")
            ),
            .functionUnsupported
        )
        XCTAssertEqual(
            BossAppleController.unavailableSettingReason(
                BossAppleControlError.bmapErrorResponse(context: "settings.autoAware", payloadHex: "04")
            ),
            .functionUnsupported
        )
        XCTAssertEqual(
            BossAppleController.unavailableSettingReason(
                BossAppleControlError.bmapErrorResponse(context: "settings.autoAware", payloadHex: "05")
            ),
            .operatorUnsupported
        )
        XCTAssertEqual(
            BossAppleController.unavailableSettingReason(
                BossAppleControlError.bmapErrorResponse(context: "settings.autoAware", payloadHex: "07")
            ),
            .dataUnavailable
        )
        XCTAssertEqual(
            BossAppleController.unavailableSettingReason(
                BossAppleControlError.bmapErrorResponse(context: "settings.autoAware", payloadHex: "14")
            ),
            .insecureTransport
        )
        XCTAssertEqual(
            BossAppleController.unavailableSettingReason(BossAppleLinkError.unexpectedStreamTermination),
            .unexpectedStreamTermination
        )
    }

    func testUnavailableReadErrorRejectsNonUnavailableErrors() {
        XCTAssertFalse(
            BossAppleController.isUnavailableSettingReadError(
                BossAppleControlError.unsupportedOperation("nope")
            )
        )
    }

    func testRetrySecureCharacteristicFallsBackForUnsupportedBootstrapStyleErrors() {
        XCTAssertTrue(
            BossAppleController.retrySecureCharacteristicIfNeeded(
                BossAppleControlError.bmapErrorResponse(context: "libboss", payloadHex: "04"),
                .unsecure
            )
        )
        XCTAssertTrue(
            BossAppleController.retrySecureCharacteristicIfNeeded(
                BossAppleControlError.bmapErrorResponse(context: "libboss", payloadHex: "03"),
                .unsecure
            )
        )
        XCTAssertFalse(
            BossAppleController.retrySecureCharacteristicIfNeeded(
                BossAppleControlError.bmapErrorResponse(context: "libboss", payloadHex: "04"),
                .secure
            )
        )
    }

    func testCompositeInPlaceDetectionUnsupportedMatchesProtocolUnsupportedOnly() {
        XCTAssertTrue(
            BossAppleController.isCompositeInPlaceDetectionUnsupported(
                BossAppleControlError.bmapErrorResponse(context: "settings.wearDetection", payloadHex: "03")
            )
        )
        XCTAssertTrue(
            BossAppleController.isCompositeInPlaceDetectionUnsupported(
                BossAppleControlError.bmapErrorResponse(context: "settings.wearDetection", payloadHex: "05")
            )
        )
        XCTAssertFalse(
            BossAppleController.isCompositeInPlaceDetectionUnsupported(
                BossAppleControlError.bmapErrorResponse(context: "settings.wearDetection", payloadHex: "07")
            )
        )
    }
}
