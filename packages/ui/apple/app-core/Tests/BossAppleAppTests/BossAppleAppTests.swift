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

    func testRuntimeConfigurationPrefersExplicitMockFlags() {
        XCTAssertEqual(
            BossAppRuntimeConfiguration.current(
                arguments: ["Boss", "--mock-device"],
                environment: [:]
            ),
            .mockDevice
        )

        XCTAssertEqual(
            BossAppRuntimeConfiguration.current(
                arguments: ["Boss", "--live-device"],
                environment: ["BOSS_USE_MOCK_DEVICE": "1"]
            ),
            .bluetooth
        )

        XCTAssertEqual(
            BossAppRuntimeConfiguration.current(
                arguments: ["Boss"],
                environment: ["BOSS_DEVICE_BACKEND": "mock"]
            ),
            .mockDevice
        )
    }
}
