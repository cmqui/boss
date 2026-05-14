import XCTest
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
}
