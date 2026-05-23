import XCTest
import libbossApple

@testable import BossAppleApp

@MainActor
final class BossAppViewModelModeActionTests: XCTestCase {
    func testSelectAudioModeUpdatesCurrentModeAndRefreshesWorkspace() async throws {
        let session = FakeBossAppSession()
        session.workspaceSnapshot = .fixture()
        session.refreshModeWorkspaceSnapshotResult = .fixture(currentAudioModeIndex: 2, settings: .fixture(cncLevel: 4))
        session.currentAudioModeWriteResult = .updated(2)

        let viewModel = BossAppViewModel(sessionFactory: { _ in session })
        viewModel.refresh()
        await waitUntil { viewModel.loadState == .ready }

        viewModel.selectAudioMode(2)
        await waitUntil { viewModel.lastResultMessage == "Mode updated; settings refreshed" }

        XCTAssertEqual(session.setCurrentAudioModeCalls, [2])
        XCTAssertEqual(viewModel.currentAudioModeIndex, 2)
        XCTAssertEqual(viewModel.selectedAudioModeIndex, 2)
        XCTAssertEqual(viewModel.settings, .fixture(cncLevel: 4))
    }

    func testApplyModeSettingsWritesPatchAndClearsDetachedDraft() async throws {
        let session = FakeBossAppSession()
        session.workspaceSnapshot = .fixture()
        session.audioModeSettingsWriteResult = .updated(.fixture(cncLevel: 6, spatialAudioMode: .head, windBlockEnabled: true))

        let viewModel = BossAppViewModel(sessionFactory: { _ in session })
        viewModel.refresh()
        await waitUntil { viewModel.loadState == .ready }

        viewModel.setCNCLevelDraft(4)
        viewModel.setSpatialAudioModeDraft(.head)
        viewModel.setWindBlockEnabledDraft(true)
        XCTAssertTrue(viewModel.hasDetachedSettingsDraft)

        viewModel.applyModeSettings()
        await waitUntil { viewModel.lastResultMessage == "Mode settings updated" }

        XCTAssertEqual(
            session.audioModeSettingsPatches,
            [BossAppleAudioModeSettingsConfigPatch(
                cncLevel: 0,
                spatialAudioMode: .head,
                windBlockEnabled: true,
                ancToggleEnabled: false
            )]
        )
        XCTAssertEqual(viewModel.settings, .fixture(cncLevel: 6, spatialAudioMode: .head, windBlockEnabled: true))
        XCTAssertFalse(viewModel.hasDetachedSettingsDraft)
    }
}

private extension BossAppViewModelModeActionTests {
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
