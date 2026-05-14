import XCTest
@testable import libbossApple

final class AppleBleBossTransportTests: XCTestCase {
    func testCharacteristicPreferenceRawValues() {
        XCTAssertEqual(AppleBossCharacteristicPreference.automatic.rawValue, "automatic")
        XCTAssertEqual(AppleBossCharacteristicPreference.unsecure.rawValue, "unsecure")
        XCTAssertEqual(AppleBossCharacteristicPreference.secure.rawValue, "secure")
    }
}
