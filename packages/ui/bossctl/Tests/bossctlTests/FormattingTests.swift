import XCTest

@testable import bossctl

final class FormattingTests: XCTestCase {
    func testHexStringInitializerAcceptsPrefixesAndSeparators() throws {
        let data = try Data(hexString: "0x01_0A ff")

        XCTAssertEqual(data, Data([0x01, 0x0A, 0xFF]))
        XCTAssertEqual(data.hexString, "010AFF")
    }

    func testHexStringInitializerRejectsOddLengthInput() {
        XCTAssertThrowsError(try Data(hexString: "ABC")) { error in
            XCTAssertEqual((error as? UsageError)?.message, "Hex payload must contain an even number of characters")
        }
    }

    func testParseIntegerStringSupportsDecimalAndHex() {
        XCTAssertEqual(parseIntegerString("42"), 42)
        XCTAssertEqual(parseIntegerString("0x2A"), 42)
        XCTAssertEqual(parseIntegerString("oops"), -1)
    }

    func testFormatOptionalBoolUsesEnabledDisabledAndUnsupported() {
        XCTAssertEqual(BossctlCLI.formatOptionalBool(true), "enabled")
        XCTAssertEqual(BossctlCLI.formatOptionalBool(false), "disabled")
        XCTAssertEqual(BossctlCLI.formatOptionalBool(nil), "unsupported")
    }

    func testBmapErrorCodeReturnsNilForInvalidPayload() {
        XCTAssertNil(BossctlCLI.bmapErrorCode(from: ""))
        XCTAssertNil(BossctlCLI.bmapErrorCode(from: "XYZ"))
        XCTAssertEqual(BossctlCLI.bmapErrorCode(from: "14"), .insecureTransport)
    }
}
