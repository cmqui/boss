@preconcurrency import CoreBluetooth
import XCTest

@testable import libbossApple

final class AppleBossDeviceDiscoveryTests: XCTestCase {
    func testAdvertisesBoseServiceMatchesPrimaryServiceUUIDList() {
        XCTAssertTrue(
            AppleBossDeviceDiscovery.advertisesBoseService(
                advertisementData: [
                    CBAdvertisementDataServiceUUIDsKey: [CBUUID(nsuuid: AppleBoseUUIDs.service)]
                ]
            )
        )
    }

    func testAdvertisesBoseServiceMatchesOverflowServiceUUIDList() {
        XCTAssertTrue(
            AppleBossDeviceDiscovery.advertisesBoseService(
                advertisementData: [
                    CBAdvertisementDataOverflowServiceUUIDsKey: [CBUUID(nsuuid: AppleBoseUUIDs.service)]
                ]
            )
        )
    }

    func testAdvertisesBoseServiceRejectsNameOnlyAdvertisement() {
        XCTAssertFalse(
            AppleBossDeviceDiscovery.advertisesBoseService(
                advertisementData: [
                    CBAdvertisementDataLocalNameKey: "LE-Bose QC45"
                ]
            )
        )
    }
}
