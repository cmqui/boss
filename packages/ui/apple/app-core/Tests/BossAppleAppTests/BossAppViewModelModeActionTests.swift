import XCTest
import libbossApple

@testable import BossAppleApp

@MainActor
final class BossAppViewModelModeActionTests: XCTestCase {
    func testSelectAudioModeUpdatesCurrentModeWithoutBlockingOnWorkspaceRefresh() async throws {
        let session = FakeBossAppSession()
        session.workspaceSnapshot = .fixture()
        session.refreshModeWorkspaceSnapshotResult = .fixture(currentAudioModeIndex: 2, settings: .fixture(cncLevel: 4))
        session.currentAudioModeWriteResult = .updated(2)

        let viewModel = BossAppViewModel(sessionFactory: { _ in session })
        viewModel.refresh()
        await waitUntil { viewModel.loadState == .ready }

        viewModel.selectAudioMode(2)
        await waitUntil { viewModel.lastResultMessage == "Mode updated" }

        XCTAssertEqual(session.setCurrentAudioModeCalls, [2])
        XCTAssertEqual(viewModel.currentAudioModeIndex, 2)
        XCTAssertEqual(viewModel.selectedAudioModeIndex, 2)
        XCTAssertEqual(viewModel.settings, .fixture(cncLevel: 4))
    }

    func testSelectAudioModeShowsStandbyMessageForHostSendFailure() async throws {
        let session = FakeBossAppSession()
        session.workspaceSnapshot = .fixture()
        session.currentAudioModeWriteError = BossAppleControlError.unsupportedOperation(
            "UnsupportedOperation(\"host send callback returned other\")"
        )

        let viewModel = BossAppViewModel(sessionFactory: { _ in session })
        viewModel.refresh()
        await waitUntil { viewModel.loadState == .ready }

        viewModel.selectAudioMode(2)
        await waitUntil {
            viewModel.loadState == .failed("The device appears to be in standby. Wake it up, then try again.")
        }

        XCTAssertEqual(session.setCurrentAudioModeCalls, [2])
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

    func testApplyModeSettingsFallsBackToLiveWriteWhenCurrentCustomSlotRejectsEdit() async throws {
        let initialSettings = BossAppleAudioModeSettingsConfig.fixture(
            cncLevel: 0,
            spatialAudioMode: .off,
            windBlockEnabled: false,
            ancToggleEnabled: false
        )
        let targetSettings = BossAppleAudioModeSettingsConfig.fixture(
            cncLevel: 0,
            spatialAudioMode: .off,
            windBlockEnabled: false,
            ancToggleEnabled: true
        )
        let customMode = BossAppleAudioModeConfig.fixture(
            modeIndex: 6,
            name: "Comfort",
            prompt: .comfort,
            settings: initialSettings,
            favorite: true,
            userConfigurable: true,
            userConfigured: true
        )

        let session = FakeBossAppSession()
        session.workspaceSnapshot = .fixture(
            currentAudioModeIndex: 6,
            settings: initialSettings,
            audioModes: [customMode]
        )
        session.refreshModeWorkspaceSnapshotResult = .fixture(
            currentAudioModeIndex: 6,
            settings: targetSettings
        )
        session.audioModeConfigsResult = [
            BossAppleAudioModeConfig.fixture(
                modeIndex: 6,
                name: "Comfort",
                prompt: .comfort,
                settings: targetSettings,
                favorite: true,
                userConfigurable: true,
                userConfigured: true
            )
        ]
        session.saveCustomAudioModeError = BossAppleControlError.unsupportedOperation(
            "CustomAudioModeSlotNotEditable(6)"
        )
        session.audioModeSettingsWriteResult = .updated(targetSettings)

        let viewModel = BossAppViewModel(sessionFactory: { _ in session })
        viewModel.refresh()
        await waitUntil { viewModel.loadState == .ready }

        viewModel.setANCEnabledDraft(true)
        XCTAssertTrue(viewModel.hasDetachedSettingsDraft)

        viewModel.applyModeSettings()
        await waitUntil { viewModel.lastResultMessage == "Updated \"Comfort\" after live fallback" }

        XCTAssertEqual(
            session.saveCustomAudioModeCalls,
            [SavedCustomModeCall(name: "Comfort", settings: targetSettings, prompt: .comfort, slot: 6)]
        )
        XCTAssertEqual(
            session.audioModeSettingsPatches,
            [BossAppleAudioModeSettingsConfigPatch(
                cncLevel: 0,
                spatialAudioMode: .off,
                windBlockEnabled: false,
                ancToggleEnabled: true
            )]
        )
        XCTAssertEqual(viewModel.settings, targetSettings)
        XCTAssertFalse(viewModel.hasDetachedSettingsDraft)
    }

    func testApplyModeSettingsKeepsLiveFallbackSettingsWhenRefreshReportsUnknownCurrentMode() async throws {
        let initialSettings = BossAppleAudioModeSettingsConfig.fixture(
            cncLevel: 5,
            spatialAudioMode: .off,
            windBlockEnabled: false,
            ancToggleEnabled: false
        )
        let targetSettings = BossAppleAudioModeSettingsConfig.fixture(
            cncLevel: 2,
            spatialAudioMode: .off,
            windBlockEnabled: false,
            ancToggleEnabled: true
        )
        let staleCatalogMode = BossAppleAudioModeConfig.fixture(
            modeIndex: 6,
            name: "Comfort",
            prompt: .comfort,
            settings: initialSettings,
            favorite: true,
            userConfigurable: true,
            userConfigured: true
        )

        let session = FakeBossAppSession()
        session.workspaceSnapshot = .fixture(
            currentAudioModeIndex: 6,
            settings: initialSettings,
            audioModes: [staleCatalogMode]
        )
        session.refreshModeWorkspaceSnapshotResult = .fixture(
            currentAudioModeIndex: 255,
            settings: targetSettings
        )
        session.audioModeConfigsResult = [staleCatalogMode]
        session.saveCustomAudioModeError = BossAppleControlError.unsupportedOperation(
            "CustomAudioModeSlotNotEditable(6)"
        )
        session.audioModeSettingsWriteResult = .updated(targetSettings)

        let viewModel = BossAppViewModel(sessionFactory: { _ in session })
        viewModel.refresh()
        await waitUntil { viewModel.loadState == .ready }

        viewModel.setCNCLevelDraft(8)
        viewModel.setANCEnabledDraft(true)
        XCTAssertTrue(viewModel.hasDetachedSettingsDraft)

        viewModel.applyModeSettings()
        await waitUntil {
            viewModel.lastResultMessage
                == "Mode settings updated; current mode updated, but the saved profile may not have persisted this change"
        }

        XCTAssertEqual(viewModel.currentAudioModeIndex, 255)
        XCTAssertEqual(viewModel.settings, targetSettings)
        XCTAssertEqual(viewModel.cncLevel, 8)
        XCTAssertEqual(viewModel.ancToggleEnabled, true)
        XCTAssertFalse(viewModel.hasDetachedSettingsDraft)
    }

    func testRemovingFavoriteUpdatesLocalAudioModesImmediately() async throws {
        let customMode = BossAppleAudioModeConfig.fixture(
            modeIndex: 6,
            name: "Comfort",
            prompt: .comfort,
            settings: .fixture(cncLevel: 0),
            favorite: true,
            userConfigurable: true,
            userConfigured: true
        )
        let session = FakeBossAppSession()
        session.workspaceSnapshot = .fixture(
            currentAudioModeIndex: 6,
            settings: .fixture(cncLevel: 0),
            audioModes: [customMode]
        )

        let viewModel = BossAppViewModel(sessionFactory: { _ in session })
        viewModel.refresh()
        await waitUntil { viewModel.loadState == .ready }

        XCTAssertEqual(viewModel.selectedModeConfig?.favorite, true)

        viewModel.setFavorite(false, for: customMode)
        await waitUntil { viewModel.lastResultMessage == "Removed \"Comfort\" from favorites" }

        XCTAssertEqual(viewModel.selectedModeConfig?.favorite, false)
        XCTAssertEqual(viewModel.audioModes.first?.favorite, false)
    }

    func testCanDeleteUnnamedConfiguredCustomMode() async throws {
        let customMode = BossAppleAudioModeConfig.fixture(
            modeIndex: 7,
            name: "None",
            prompt: .none,
            settings: .fixture(cncLevel: 0),
            favorite: false,
            userConfigurable: true,
            userConfigured: true
        )
        let session = FakeBossAppSession()
        session.workspaceSnapshot = .fixture(
            currentAudioModeIndex: 7,
            settings: .fixture(cncLevel: 0),
            audioModes: [customMode]
        )

        let viewModel = BossAppViewModel(sessionFactory: { _ in session })
        viewModel.refresh()
        await waitUntil { viewModel.loadState == .ready }

        XCTAssertTrue(viewModel.canDelete(customMode))
    }

    func testDeletingCurrentCustomModeDoesNotFallBackSelectionToBuiltInMode() async throws {
        let customMode = BossAppleAudioModeConfig.fixture(
            modeIndex: 6,
            name: "Comfort",
            prompt: .comfort,
            settings: .fixture(cncLevel: 5),
            favorite: true,
            userConfigurable: true,
            userConfigured: true
        )
        let session = FakeBossAppSession()
        session.workspaceSnapshot = .fixture(
            currentAudioModeIndex: 6,
            settings: .fixture(cncLevel: 5),
            audioModes: [
                BossAppleAudioModeConfig.fixture(modeIndex: 0, name: "Quiet", prompt: .quiet, settings: .fixture(cncLevel: 0)),
                customMode,
            ]
        )

        let viewModel = BossAppViewModel(sessionFactory: { _ in session })
        viewModel.refresh()
        await waitUntil { viewModel.loadState == .ready }

        viewModel.deleteCustomProfile(customMode)
        await waitUntil { viewModel.lastResultMessage == "Deleted \"Comfort\"" }

        XCTAssertEqual(viewModel.currentAudioModeIndex, 6)
        XCTAssertEqual(viewModel.selectedAudioModeIndex, 6)
        XCTAssertEqual(viewModel.resolvedSelectedAudioModeIndex, 6)
    }

    func testSavingNewCustomProfileSwitchesCurrentModeAndKeepsSavedModeVisible() async throws {
        let currentMode = BossAppleAudioModeConfig.fixture(
            modeIndex: 6,
            name: "Comfort",
            prompt: .comfort,
            settings: .fixture(cncLevel: 5),
            favorite: true,
            userConfigurable: true,
            userConfigured: true
        )
        let reusableSlot = BossAppleAudioModeConfig.fixture(
            modeIndex: 7,
            name: "",
            prompt: .none,
            settings: .fixture(cncLevel: 0),
            userConfigurable: true,
            userConfigured: true
        )
        let session = FakeBossAppSession()
        session.workspaceSnapshot = .fixture(
            currentAudioModeIndex: 6,
            settings: .fixture(cncLevel: 5),
            audioModes: [
                BossAppleAudioModeConfig.fixture(modeIndex: 0, name: "Quiet", prompt: .quiet, settings: .fixture(cncLevel: 0)),
                currentMode,
                reusableSlot,
            ]
        )
        session.refreshModeWorkspaceSnapshotResult = .fixture(
            currentAudioModeIndex: 7,
            settings: .fixture(cncLevel: 4, ancToggleEnabled: true)
        )
        session.currentAudioModeWriteResult = .updated(7)
        session.savedCustomAudioModeResult = BossAppleAudioModeConfig.fixture(
            modeIndex: 7,
            name: "Home",
            prompt: .home,
            settings: .fixture(cncLevel: 4, ancToggleEnabled: true),
            userConfigurable: true,
            userConfigured: true
        )

        let viewModel = BossAppViewModel(sessionFactory: { _ in session })
        viewModel.refresh()
        await waitUntil { viewModel.loadState == .ready }

        viewModel.setCNCLevelDraft(7)
        viewModel.setANCEnabledDraft(true)
        XCTAssertTrue(viewModel.hasDetachedSettingsDraft)

        viewModel.saveCustomProfile(profileName: "Home", prompt: .home)
        await waitUntil { viewModel.lastResultMessage == "Saved profile \"Home\"" }

        XCTAssertEqual(session.setCurrentAudioModeCalls, [7])
        XCTAssertEqual(viewModel.currentAudioModeIndex, 7)
        XCTAssertEqual(viewModel.selectedAudioModeIndex, 7)
        XCTAssertEqual(viewModel.resolvedSelectedAudioModeIndex, 7)
        XCTAssertEqual(viewModel.selectedModeConfig?.modeIndex, 7)
        XCTAssertEqual(viewModel.selectedModeName, "Home")
        XCTAssertEqual(viewModel.settings, .fixture(cncLevel: 4, ancToggleEnabled: true))
        XCTAssertEqual(viewModel.audioModes.first(where: { $0.modeIndex == 7 })?.name, "Home")
        XCTAssertTrue(viewModel.selectableAudioModes.contains(where: { $0.modeIndex == 7 && $0.name == "Home" }))
        XCTAssertFalse(viewModel.hasDetachedSettingsDraft)
    }

    func testSelectableAudioModesHidesUnnamedCustomModesUnlessCurrent() async throws {
        let session = FakeBossAppSession()
        session.workspaceSnapshot = .fixture(
            currentAudioModeIndex: 6,
            audioModes: [
                BossAppleAudioModeConfig.fixture(
                    modeIndex: 0,
                    name: "Quiet",
                    prompt: .quiet,
                    settings: .fixture(cncLevel: 0)
                ),
                BossAppleAudioModeConfig.fixture(
                    modeIndex: 6,
                    name: "Comfort",
                    prompt: .comfort,
                    settings: .fixture(cncLevel: 5),
                    userConfigurable: true,
                    userConfigured: true
                ),
                BossAppleAudioModeConfig.fixture(
                    modeIndex: 7,
                    name: "None",
                    prompt: .none,
                    settings: .fixture(cncLevel: 4),
                    userConfigurable: true,
                    userConfigured: true
                ),
                BossAppleAudioModeConfig.fixture(
                    modeIndex: 8,
                    name: "",
                    prompt: .none,
                    settings: .fixture(cncLevel: 3),
                    userConfigurable: true,
                    userConfigured: false
                ),
            ]
        )

        let viewModel = BossAppViewModel(sessionFactory: { _ in session })
        viewModel.refresh()
        await waitUntil { viewModel.loadState == .ready }

        XCTAssertTrue(viewModel.selectableAudioModes.contains(where: { $0.modeIndex == 0 }))
        XCTAssertTrue(viewModel.selectableAudioModes.contains(where: { $0.modeIndex == 6 }))
        XCTAssertFalse(viewModel.selectableAudioModes.contains(where: { $0.modeIndex == 7 }))
        XCTAssertFalse(viewModel.selectableAudioModes.contains(where: { $0.modeIndex == 8 }))
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
