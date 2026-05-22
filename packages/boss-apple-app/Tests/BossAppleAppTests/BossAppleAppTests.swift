import XCTest
@testable import BossAppleApp

@MainActor
final class BossAppleAppTests: XCTestCase {
    func testViewModelStartsInWaitingState() {
        let viewModel = BossAppViewModel()

        XCTAssertEqual(viewModel.appScreen, .waitingForDevice)
        XCTAssertEqual(viewModel.waitingStatusMessage, "Looking for a Bose device nearby.")
        XCTAssertEqual(viewModel.deviceName, "Bose Device")
        XCTAssertFalse(viewModel.isBusy)
    }
}
