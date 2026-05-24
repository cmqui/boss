import Combine
import Foundation
import libbossApple

@MainActor
public final class BossAppViewModel: ObservableObject {
    public enum AppScreen: Equatable {
        case waitingForDevice
        case workspace
    }

    public enum LoadState: Equatable {
        case idle
        case loading(String)
        case failed(String)
        case ready
    }

    @Published public var nameFilter = "Bose"
    @Published public var scanTimeoutSeconds = 20
    @Published public internal(set) var appScreen: AppScreen = .waitingForDevice
    @Published public internal(set) var loadState: LoadState = .idle
    @Published public internal(set) var availableDevices: [BossAppleDiscoveredDevice] = []
    @Published public var selectedDiscoveredDeviceID: UUID?
    @Published public internal(set) var audioModes: [BossAppleAudioModeConfig] = []
    @Published public internal(set) var customProfileModes: [BossAppleAudioModeConfig] = []
    @Published public internal(set) var currentAudioModeIndex: Int?
    @Published public internal(set) var settings: BossAppleAudioModeSettingsConfig?
    @Published public internal(set) var equalizer: BossAppleEqualizerSettings?
    @Published public internal(set) var deviceName = "Bose Device"
    @Published public internal(set) var deviceVariantName: String?
    @Published public internal(set) var firmwareVersion: String?
    @Published public internal(set) var wearDetectionEnabled: Bool?
    @Published public internal(set) var autoAwareEnabled: Bool?
    @Published public internal(set) var autoPlayPauseEnabled: Bool?
    @Published public internal(set) var autoAnswerEnabled: Bool?
    @Published public internal(set) var volumeControlValue: BossAppleVolumeControlValue?
    @Published public internal(set) var lastResultMessage: String?
    @Published public internal(set) var waitingStatusMessage = "Looking for a Bose device nearby."
    @Published public internal(set) var hasDetachedSettingsDraft = false
    @Published public internal(set) var hasDetachedEqualizerDraft = false
    @Published public var isPresentingSaveProfilePrompt = false
    @Published public var pendingProfileName = ""
    @Published public internal(set) var supportedPrompts: [BossAppleAudioModePrompt] = []
    @Published public var selectedSaveProfilePromptName = "None"

    @Published public var selectedAudioModeIndex: Int?
    @Published public var cncLevel = 0
    @Published public var spatialAudioMode: BossAppleSpatialAudioMode = .off
    @Published public var windBlockEnabled = false
    @Published public var ancToggleEnabled = false
    @Published public var bassLevel = 0
    @Published public var midLevel = 0
    @Published public var trebleLevel = 0

    var hasStartedInitialRefresh = false
    var discoveryTask: Task<Void, Never>?
    var workspaceUpdateTask: Task<Void, Never>?
    static let audioModeCatalogPollInterval = 6
    var session: (any BossAppSessioning)?
    var selectedDeviceIdentifier: UUID?
    var isManualDeviceSelection = false
    var isConnectingSelectedDevice = false
    let discoveryProvider: any BossAppDiscoveryProviding
    let sessionFactory: (BossAppleConnectionOptions) -> any BossAppSessioning
    let runtimeConfiguration: BossAppRuntimeConfiguration
    let cncTotalSteps = 11
    var cncDisplayMaximum: Int { cncTotalSteps - 1 }

    public convenience init(configuration: BossAppRuntimeConfiguration = .current()) {
        self.init(
            runtimeConfiguration: configuration,
            discoveryProvider: Self.makeDiscoveryProvider(configuration: configuration),
            sessionFactory: Self.makeSessionFactory(configuration: configuration)
        )
    }

    init(
        runtimeConfiguration: BossAppRuntimeConfiguration = .bluetooth,
        discoveryProvider: any BossAppDiscoveryProviding = BossBluetoothDiscoveryProvider(),
        sessionFactory: @escaping (BossAppleConnectionOptions) -> any BossAppSessioning = { options in
            BossAppleSession(connection: options)
        }
    ) {
        self.runtimeConfiguration = runtimeConfiguration
        self.discoveryProvider = discoveryProvider
        self.sessionFactory = sessionFactory
        if runtimeConfiguration.deviceBackend == .mock {
            waitingStatusMessage = "Mock QC Ultra 2 HP mode is enabled."
        }
    }

    public var isBusy: Bool {
        if case .loading = loadState {
            return true
        }
        return false
    }

    public var selectedModeName: String {
        if hasDetachedSettingsDraft {
            return "Custom changes"
        }
        guard let currentAudioModeIndex,
              let mode = audioModes.first(where: { $0.modeIndex == currentAudioModeIndex }) else {
            return "Unknown"
        }
        return customProfileDisplayName(for: mode)
    }

    public var displayedCurrentAudioModeIndex: Int? {
        hasDetachedSettingsDraft ? nil : currentAudioModeIndex
    }

    public var canApplyModeSettings: Bool {
        settings != nil && hasDetachedSettingsDraft && !isBusy
    }

    public var isCNCForcedToDisplayMaximumByCurrentConstraint: Bool {
        windBlockEnabled
    }

    public var canApplyEqualizer: Bool {
        equalizer != nil && hasDetachedEqualizerDraft && !isBusy
    }

    public var canSaveCustomProfile: Bool {
        settings != nil && hasDetachedSettingsDraft && hasAvailableCustomProfileSlot && !isBusy
    }

    public var selectableAudioModes: [BossAppleAudioModeConfig] {
        audioModes.filter { mode in
            if mode.userConfigurable {
                if mode.modeIndex == currentAudioModeIndex {
                    return true
                }
                return mode.userConfigured && hasCustomProfileName(mode)
            }
            return true
        }
    }

    public var selectableSaveProfilePrompts: [BossAppleAudioModePrompt] {
        let nonNone = supportedPrompts.filter { $0 != .none }
        return nonNone.isEmpty ? supportedPrompts : nonNone
    }

    public var resolvedSelectedAudioModeIndex: Int? {
        if let selectedAudioModeIndex,
           selectableAudioModes.contains(where: { $0.modeIndex == selectedAudioModeIndex }) {
            return selectedAudioModeIndex
        }

        if let currentAudioModeIndex,
           selectableAudioModes.contains(where: { $0.modeIndex == currentAudioModeIndex }) {
            return currentAudioModeIndex
        }

        return selectableAudioModes.first?.modeIndex
    }

    public var usesMockDeviceBackend: Bool {
        runtimeConfiguration.deviceBackend == .mock
    }

    private static func makeDiscoveryProvider(
        configuration: BossAppRuntimeConfiguration
    ) -> any BossAppDiscoveryProviding {
        switch configuration.deviceBackend {
        case .bluetooth:
            return BossBluetoothDiscoveryProvider()
        case .mock:
            return MockBossAppDiscoveryProvider()
        }
    }

    private static func makeSessionFactory(
        configuration: BossAppRuntimeConfiguration
    ) -> (BossAppleConnectionOptions) -> any BossAppSessioning {
        switch configuration.deviceBackend {
        case .bluetooth:
            return { options in
                BossAppleSession(connection: options)
            }
        case .mock:
            return { options in
                MockBossAppSession(connection: options)
            }
        }
    }
}
