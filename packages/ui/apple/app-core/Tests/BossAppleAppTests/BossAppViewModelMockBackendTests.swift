import XCTest

@testable import BossAppleApp

@MainActor
final class BossAppViewModelMockBackendTests: XCTestCase {
    func testMockBackendDiscoversAndLoadsWorkspace() async {
        let viewModel = BossAppViewModel(configuration: .mockDevice)

        viewModel.refreshIfNeeded()
        await waitUntil { viewModel.appScreen == .workspace && viewModel.loadState == .ready }

        XCTAssertTrue(viewModel.usesMockDeviceBackend)
        XCTAssertEqual(viewModel.deviceName, "Bose QC Ultra 2 HP")
        XCTAssertEqual(viewModel.deviceVariantName, "WolverineBlack")
        XCTAssertEqual(viewModel.firmwareVersion, "99.9.9-mock")
        XCTAssertEqual(viewModel.currentAudioModeIndex, 1)
        XCTAssertEqual(viewModel.audioModes.count, 6)
        XCTAssertEqual(viewModel.availableDevices.map(\.name), ["Bose QC Ultra 2 HP"])
    }

    func testMockBackendPersistsModeAndEqualizerChangesAcrossReconnect() async {
        let viewModel = BossAppViewModel(configuration: .mockDevice)

        viewModel.refresh()
        await waitUntil { viewModel.appScreen == .workspace && viewModel.loadState == .ready }

        viewModel.selectAudioMode(3)
        await waitUntil { viewModel.currentAudioModeIndex == 3 && viewModel.lastResultMessage == "Mode updated; settings refreshed" }

        viewModel.setBassLevelDraft(7)
        viewModel.applyEqualizerSettings()
        await waitUntil { viewModel.lastResultMessage == "EQ updated" || viewModel.lastResultMessage == "EQ unchanged" }

        viewModel.returnToDeviceSelection()
        await waitUntil { viewModel.appScreen == .waitingForDevice }
        viewModel.refresh()
        await waitUntil {
            viewModel.appScreen == .workspace
                && viewModel.loadState == .ready
                && viewModel.currentAudioModeIndex == 3
        }

        XCTAssertEqual(viewModel.currentAudioModeIndex, 3)
        XCTAssertEqual(viewModel.bassLevel, 7)
    }
}

private extension BossAppViewModelMockBackendTests {
    func waitUntil(
        timeoutNanoseconds: UInt64 = 3_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while !condition() && ContinuousClock.now < deadline {
            await Task.yield()
        }
    }
}
