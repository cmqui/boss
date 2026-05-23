import XCTest
import libbossApple

@testable import BossAppleApp

@MainActor
final class BossAppViewModelLifecycleTests: XCTestCase {
    func testRefreshTransitionsToWorkspaceAndLoadsSnapshot() async throws {
        let session = FakeBossAppSession()
        session.workspaceSnapshot = .fixture()
        session.supportedPrompts = [.quiet, .aware]
        session.firmwareVersionInfo = BossAppleFirmwareVersionInfo(version: "9.1.0", port: 0)

        let viewModel = BossAppViewModel(sessionFactory: { _ in session })

        viewModel.refresh()
        await waitUntil { viewModel.loadState == .ready }

        XCTAssertEqual(viewModel.appScreen, .workspace)
        XCTAssertEqual(viewModel.currentAudioModeIndex, 1)
        XCTAssertEqual(viewModel.selectedAudioModeIndex, 1)
        XCTAssertEqual(viewModel.deviceName, "QuietComfort Ultra")
        XCTAssertEqual(viewModel.deviceVariantName, "Black")
        XCTAssertEqual(viewModel.firmwareVersion, "9.1.0")
        XCTAssertEqual(viewModel.supportedPrompts, [.quiet, .aware])
        XCTAssertEqual(viewModel.lastResultMessage, "Loaded 2 audio modes")
        XCTAssertFalse(viewModel.hasDetachedSettingsDraft)
        XCTAssertFalse(viewModel.hasDetachedEqualizerDraft)
    }

    func testRefreshFailureReturnsToWaitingStateAndSurfacesError() async throws {
        let session = FakeBossAppSession()
        session.workspaceSnapshotError = BossAppleControlError.unsupportedOperation("refresh failed")

        let viewModel = BossAppViewModel(sessionFactory: { _ in session })

        viewModel.refresh()
        await waitUntil {
            if case .failed = viewModel.loadState { return true }
            return false
        }

        XCTAssertEqual(viewModel.appScreen, .waitingForDevice)
        XCTAssertEqual(viewModel.waitingStatusMessage, "unsupportedOperation(\"refresh failed\")")
        XCTAssertNil(viewModel.session)
        XCTAssertEqual(session.closeCallCount, 1)
    }
}

private extension BossAppViewModelLifecycleTests {
    func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while !condition() && ContinuousClock.now < deadline {
            await Task.yield()
        }
    }
}
