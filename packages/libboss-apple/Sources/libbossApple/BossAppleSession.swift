import Foundation

public struct BossAppleModeWorkspaceSnapshot: Sendable, Equatable {
    public let currentAudioModeIndex: Int
    public let settings: BossAppleAudioModeSettingsConfig
    public let equalizer: BossAppleEqualizerSettings?
    public let deviceSettings: BossAppleDeviceSettingsReport

    public init(
        currentAudioModeIndex: Int,
        settings: BossAppleAudioModeSettingsConfig,
        equalizer: BossAppleEqualizerSettings?,
        deviceSettings: BossAppleDeviceSettingsReport
    ) {
        self.currentAudioModeIndex = currentAudioModeIndex
        self.settings = settings
        self.equalizer = equalizer
        self.deviceSettings = deviceSettings
    }
}

public struct BossAppleWorkspaceSnapshot: Sendable, Equatable {
    public let bootstrappedDevice: BossAppleBootstrappedDevice
    public let modeWorkspace: BossAppleModeWorkspaceSnapshot
    public let audioModes: [BossAppleAudioModeConfig]

    public init(
        bootstrappedDevice: BossAppleBootstrappedDevice,
        modeWorkspace: BossAppleModeWorkspaceSnapshot,
        audioModes: [BossAppleAudioModeConfig]
    ) {
        self.bootstrappedDevice = bootstrappedDevice
        self.modeWorkspace = modeWorkspace
        self.audioModes = audioModes
    }
}

public actor BossAppleSession {
    private struct ConnectedLink {
        let transport: AppleBleBossTransport
        let preference: AppleBossCharacteristicPreference
    }

    private enum RetryResolution {
        case nextPreference
        case reconnectCurrentPreference
        case rethrow
    }

    public let connection: BossAppleConnectionOptions

    private var connectedLink: ConnectedLink?
    private var cachedBootstrappedDevice: BossAppleBootstrappedDevice?

    public init(connection: BossAppleConnectionOptions = BossAppleConnectionOptions()) {
        self.connection = connection
    }

    deinit {
        let transport = connectedLink?.transport
        if let transport {
            Task {
                await transport.close()
            }
        }
    }

    public func close() async {
        await closeCurrentLink()
    }

    public func bootstrap() async throws -> BossAppleBootstrappedDevice {
        if let cachedBootstrappedDevice {
            return cachedBootstrappedDevice
        }

        guard let rustBridge = BossRustSessionBridge.shared else {
            throw BossAppleControlError.unsupportedOperation("Rust runtime is required for bootstrap")
        }
        let bootstrappedDevice = try await withRustBleTransportRetrying(
            preferredPreferences: [.unsecure, .secure],
            preferActiveLink: false
        ) { transport in
            try await rustBridge.bootstrap(on: transport)
        }
        cachedBootstrappedDevice = bootstrappedDevice
        return bootstrappedDevice
    }

    public func loadWorkspaceSnapshot() async throws -> BossAppleWorkspaceSnapshot {
        let bootstrappedDevice = try await bootstrap()
        let modeWorkspace = try await refreshModeWorkspaceSnapshot()
        let audioModes = try await audioModeConfigs()
        return BossAppleWorkspaceSnapshot(
            bootstrappedDevice: bootstrappedDevice,
            modeWorkspace: modeWorkspace,
            audioModes: audioModes
        )
    }

    public func refreshModeWorkspaceSnapshot() async throws -> BossAppleModeWorkspaceSnapshot {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: appOperationPreferences()) { transport in
            try await rustBridge.refreshModeWorkspaceSnapshot(on: transport)
        }
    }

    func settingsSnapshot() async throws -> BossAppleSettingsSnapshot {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: appOperationPreferences()) { transport in
            try await rustBridge.settingsSnapshot(on: transport)
        }
    }

    public nonisolated func modeWorkspaceUpdates(
        interval: Duration = .seconds(5)
    ) -> AsyncThrowingStream<BossAppleModeWorkspaceSnapshot, Error> {
        let session = self
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        continuation.yield(try await session.refreshModeWorkspaceSnapshot())
                        try await Task.sleep(for: interval)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func currentAudioModeUpdateStream() -> AsyncThrowingStream<Int, Error> {
        guard let rustBridge = BossRustSessionBridge.shared else {
            return Self.rustRequiredStream()
        }
        return reconnectingRustStream(
            initial: { try await self.readCurrentAudioMode() }
        ) { transport in
            rustBridge.currentAudioModeUpdateStream(on: transport)
        }
    }

    public func audioModeSettingsUpdateStream() -> AsyncThrowingStream<BossAppleAudioModeSettingsConfig, Error> {
        guard let rustBridge = BossRustSessionBridge.shared else {
            return Self.rustRequiredStream()
        }
        return reconnectingRustStream(
            initial: { try await self.readAudioModeSettingsConfig() }
        ) { transport in
            rustBridge.audioModeSettingsUpdateStream(on: transport)
        }
    }

    public func equalizerUpdateStream() -> AsyncThrowingStream<BossAppleEqualizerSettings, Error> {
        guard let rustBridge = BossRustSessionBridge.shared else {
            return Self.rustRequiredStream()
        }
        return reconnectingRustStream(
            initial: { try await self.readEqualizerSettingsIfAvailable() }
        ) { transport in
            rustBridge.equalizerUpdateStream(on: transport)
        }
    }

    public func deviceSettingsUpdateStream() -> AsyncThrowingStream<BossAppleDeviceSettingsReport, Error> {
        guard let rustBridge = BossRustSessionBridge.shared else {
            return Self.rustRequiredStream()
        }
        return reconnectingRustStream(
            initial: { try await self.readDeviceSettingsReport() }
        ) { transport in
            rustBridge.deviceSettingsUpdateStream(on: transport)
        }
    }

    public func audioModeCatalogUpdateStream() -> AsyncThrowingStream<[BossAppleAudioModeConfig], Error> {
        guard let rustBridge = BossRustSessionBridge.shared else {
            return Self.rustRequiredStream()
        }
        return reconnectingRustStream(
            initial: { try await self.readAudioModeConfigs() }
        ) { transport in
            rustBridge.audioModeCatalogUpdateStream(on: transport)
        }
    }

    public func supportedAudioModePrompts() async throws -> [BossAppleAudioModePrompt] {
        try await readSupportedAudioModePrompts()
    }

    public func audioModeConfigs() async throws -> [BossAppleAudioModeConfig] {
        try await readAudioModeConfigs()
    }

    public func firmwareVersion(port: Int = 0, deviceID: Int = 0) async throws -> BossAppleFirmwareVersionInfo {
        try await readFirmwareVersion(port: port, deviceID: deviceID)
    }

    public func standbyTimer() async throws -> BossAppleStandbyTimerValue? {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: appOperationPreferences()) { transport in
            try await rustBridge.standbyTimer(on: transport)
        }
    }

    public func setStandbyTimer(minutes: Int) async throws -> BossAppleStandbyTimerValue {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: [.secure, .unsecure]) { transport in
            try await rustBridge.setStandbyTimer(on: transport, minutes: minutes)
        }
    }

    public func equalizer() async throws -> BossAppleEqualizerSettings? {
        try await readEqualizerSettingsIfAvailable()
    }

    public func deviceSettingsReport() async throws -> BossAppleDeviceSettingsReport {
        try await readDeviceSettingsReport()
    }

    public func onHeadDetection() async throws -> BossAppleOnHeadDetectionValue? {
        try await readDeviceSettingsReport().wearDetection.value
    }

    public func wearDetection() async throws -> BossAppleOnHeadDetectionValue? {
        try await onHeadDetection()
    }

    public func autoAware() async throws -> Bool? {
        try await readDeviceSettingsReport().autoAwareEnabled.value
    }

    public func autoPlayPause() async throws -> Bool? {
        try await readDeviceSettingsReport().autoPlayPauseEnabled.value
    }

    public func autoAnswer() async throws -> Bool? {
        try await readDeviceSettingsReport().autoAnswerEnabled.value
    }

    public func volumeControl() async throws -> BossAppleVolumeControlStatus? {
        try await readDeviceSettingsReport().volumeControl.value
    }

    public func currentAudioMode() async throws -> Int {
        try await readCurrentAudioMode()
    }

    public func audioModeSettings() async throws -> BossAppleAudioModeSettingsConfig {
        try await readAudioModeSettingsConfig()
    }

    public func favoriteAudioModeIndices() async throws -> [Int] {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: appOperationPreferences()) { transport in
            try await rustBridge.favoriteAudioModeIndices(on: transport)
        }
    }

    public func audioModeCapabilities() async throws -> BossAppleAudioModesCapabilities {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: appOperationPreferences()) { transport in
            try await rustBridge.audioModeCapabilities(on: transport)
        }
    }

    public func setFavoriteAudioModeIndices(
        _ indices: [Int],
        numberOfModes requestedNumberOfModes: Int? = nil
    ) async throws -> [Int] {
        let numberOfModes: Int
        if let requestedNumberOfModes {
            numberOfModes = requestedNumberOfModes
        } else {
            numberOfModes = try await audioModeCapabilities().totalModes
        }

        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: appOperationPreferences()) { transport in
            try await rustBridge.setFavoriteAudioModeIndices(
                on: transport,
                indices: indices,
                numberOfModes: numberOfModes
            )
        }
    }

    private func readSupportedAudioModePrompts() async throws -> [BossAppleAudioModePrompt] {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: appOperationPreferences()) { transport in
            try await rustBridge.supportedAudioModePrompts(on: transport)
        }
    }

    private func readAudioModeConfigs() async throws -> [BossAppleAudioModeConfig] {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: appOperationPreferences()) { transport in
            try await rustBridge.audioModeConfigs(on: transport)
        }
    }

    private func readFirmwareVersion(port: Int, deviceID: Int) async throws -> BossAppleFirmwareVersionInfo {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: appOperationPreferences()) { transport in
            try await rustBridge.firmwareVersion(on: transport, port: port, deviceID: deviceID)
        }
    }

    public func setCurrentAudioMode(
        index targetIndex: Int,
        playVoicePrompt: Bool = false
    ) async throws -> BossAppleCurrentAudioModeWriteResult {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: [.secure, .unsecure]) { transport in
            try await rustBridge.setCurrentAudioMode(
                on: transport,
                targetIndex: targetIndex,
                playVoicePrompt: playVoicePrompt
            )
        }
    }

    public func setAudioModeSettings(
        _ update: BossAppleAudioModeSettingsConfigPatch
    ) async throws -> BossAppleAudioModeSettingsWriteResult {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: [.secure, .unsecure]) { transport in
            try await rustBridge.setAudioModeSettings(on: transport, update: update)
        }
    }

    public func setEqualizer(
        _ update: BossAppleEqualizerSettingsPatch
    ) async throws -> BossAppleEqualizerWriteResult {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: [.secure, .unsecure]) { transport in
            try await rustBridge.setEqualizer(on: transport, update: update)
        }
    }

    public func setWearDetection(_ value: BossAppleOnHeadDetectionValue) async throws -> BossAppleOnHeadDetectionValue {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: [.secure, .unsecure]) { transport in
            try await rustBridge.setWearDetection(on: transport, value: value)
        }
    }

    public func setWearDetection(_ patch: BossAppleOnHeadDetectionPatch) async throws -> BossAppleOnHeadDetectionValue {
        guard !patch.isEmpty else {
            guard let current = try await wearDetection() else {
                throw BossAppleControlError.unsupportedOperation("Wear detection is not exposed by this device/session")
            }
            return current
        }

        do {
            let current = try await wearDetection() ?? BossAppleOnHeadDetectionValue(
                isEnabled: false,
                isAutoPlayEnabled: nil,
                isAutoAnswerEnabled: nil,
                isAutoTransparencyEnabled: nil
            )
            return try await setWearDetection(patch.merged(with: current))
        } catch {
            guard BossAppleController.isCompositeInPlaceDetectionUnsupported(error) else {
                throw error
            }
        }

        guard patch.isEnabled == nil else {
            throw BossAppleControlError.unsupportedOperation(
                "This device does not expose the master wear-detection toggle over BMAP; only auto-play, auto-answer, and auto-transparency subsettings are writable"
            )
        }

        throw BossAppleControlError.unsupportedOperation(
            "This device does not expose a composite wear-detection state over BMAP; use updateWearDetectionRelatedSettings(_:) for subordinate auto-play, auto-answer, and auto-transparency writes"
        )
    }

    public func updateWearDetectionRelatedSettings(_ patch: BossAppleOnHeadDetectionPatch) async throws -> BossAppleDeviceSettingsReport {
        if patch.isEmpty {
            return try await deviceSettingsReport()
        }
        do {
            let current = try await wearDetection() ?? BossAppleOnHeadDetectionValue(
                isEnabled: false,
                isAutoPlayEnabled: nil,
                isAutoAnswerEnabled: nil,
                isAutoTransparencyEnabled: nil
            )
            _ = try await setWearDetection(patch.merged(with: current))
            return try await deviceSettingsReport()
        } catch {
            guard BossAppleController.isCompositeInPlaceDetectionUnsupported(error) else {
                throw error
            }
        }

        guard patch.isEnabled == nil else {
            throw BossAppleControlError.unsupportedOperation(
                "This device does not expose the master wear-detection toggle over BMAP; only auto-play, auto-answer, and auto-transparency subsettings are writable"
            )
        }

        if let enabled = patch.isAutoPlayEnabled {
            _ = try await setAutoPlayPause(enabled)
        }
        if let enabled = patch.isAutoAnswerEnabled {
            _ = try await setAutoAnswer(enabled)
        }
        if let enabled = patch.isAutoTransparencyEnabled {
            do {
                _ = try await setAutoAware(enabled)
            } catch {
                if BossAppleController.isCompositeInPlaceDetectionUnsupported(error) || BossAppleController.isUnavailableSettingReadError(error) {
                    throw BossAppleControlError.unsupportedOperation(
                        "Auto-transparency is not exposed by this device/session over the standalone auto-aware setting path"
                    )
                }
                throw error
            }
        }

        return try await deviceSettingsReport()
    }

    public func setWearDetectionEnabled(_ enabled: Bool) async throws -> BossAppleOnHeadDetectionValue {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: [.secure, .unsecure]) { transport in
            try await rustBridge.setWearDetectionEnabled(on: transport, enabled: enabled)
        }
    }

    public func setAutoAware(_ enabled: Bool) async throws -> Bool {
        try await setEnabledSetting(functionRaw: BossAppleSettingsProtocol.autoAwareFunctionRaw, enabled: enabled)
    }

    public func setAutoPlayPause(_ enabled: Bool) async throws -> Bool {
        try await setEnabledSetting(functionRaw: BossAppleSettingsProtocol.autoPlayPauseFunctionRaw, enabled: enabled)
    }

    public func setAutoAnswer(_ enabled: Bool) async throws -> Bool {
        try await setEnabledSetting(functionRaw: BossAppleSettingsProtocol.autoAnswerFunctionRaw, enabled: enabled)
    }

    public func setVolumeControl(_ value: BossAppleVolumeControlValue) async throws -> BossAppleVolumeControlStatus {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: [.secure, .unsecure]) { transport in
            try await rustBridge.setVolumeControl(on: transport, value: value)
        }
    }

    public func favoriteAudioMode(index: Int) async throws -> [Int] {
        try await setAudioModeFavorite(index: index, isFavorite: true)
    }

    public func unfavoriteAudioMode(index: Int) async throws -> [Int] {
        try await setAudioModeFavorite(index: index, isFavorite: false)
    }

    public func deleteCustomAudioMode(slot: Int) async throws -> BossAppleAudioModeConfig {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: [.secure, .unsecure]) { transport in
            try await rustBridge.deleteCustomAudioMode(on: transport, slot: slot)
        }
    }

    public func saveCustomAudioMode(
        name: String,
        settings: BossAppleAudioModeSettingsConfig,
        prompt: BossAppleAudioModePrompt = .none,
        slot requestedSlot: Int? = nil
    ) async throws -> BossAppleAudioModeConfig {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: [.secure, .unsecure]) { transport in
            try await rustBridge.saveCustomAudioMode(
                on: transport,
                name: name,
                settings: settings,
                prompt: prompt,
                requestedSlot: requestedSlot
            )
        }
    }

    public func renameCustomAudioMode(
        slot: Int,
        name: String,
        prompt: BossAppleAudioModePrompt? = nil
    ) async throws -> BossAppleAudioModeConfig {
        let configs = try await audioModeConfigs()
        guard let existing = configs.first(where: { $0.modeIndex == slot }) else {
            throw BossAppleControlError.customAudioModeSlotNotFound(slot)
        }
        guard existing.userConfigurable else {
            throw BossAppleControlError.customAudioModeSlotNotEditable(slot)
        }
        return try await writeCustomAudioMode(
            slot: slot,
            name: name,
            settings: existing.settings,
            prompt: prompt ?? existing.prompt
        )
    }

    public func updateCustomAudioMode(
        slot: Int,
        name: String? = nil,
        settings: BossAppleAudioModeSettingsConfig? = nil,
        prompt: BossAppleAudioModePrompt? = nil
    ) async throws -> BossAppleAudioModeConfig {
        let configs = try await audioModeConfigs()
        guard let existing = configs.first(where: { $0.modeIndex == slot }) else {
            throw BossAppleControlError.customAudioModeSlotNotFound(slot)
        }
        guard existing.userConfigurable else {
            throw BossAppleControlError.customAudioModeSlotNotEditable(slot)
        }
        return try await writeCustomAudioMode(
            slot: slot,
            name: name ?? existing.name,
            settings: settings ?? existing.settings,
            prompt: prompt ?? existing.prompt
        )
    }

    private func setEnabledSetting(functionRaw: UInt8, enabled: Bool) async throws -> Bool {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: [.secure, .unsecure]) { transport in
            try await rustBridge.setEnabledSetting(on: transport, functionRaw: functionRaw, enabled: enabled)
        }
    }

    private func setAudioModeFavorite(index: Int, isFavorite: Bool) async throws -> [Int] {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: appOperationPreferences()) { transport in
            try await rustBridge.setAudioModeFavorite(on: transport, index: index, isFavorite: isFavorite)
        }
    }

    private func writeCustomAudioMode(
        slot: Int,
        name: String,
        settings: BossAppleAudioModeSettingsConfig,
        prompt: BossAppleAudioModePrompt
    ) async throws -> BossAppleAudioModeConfig {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: [.secure, .unsecure]) { transport in
            try await rustBridge.saveCustomAudioMode(
                on: transport,
                name: name,
                settings: settings,
                prompt: prompt,
                requestedSlot: slot
            )
        }
    }

    private func readCurrentAudioMode() async throws -> Int {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: appOperationPreferences()) { transport in
            try await rustBridge.currentAudioMode(on: transport)
        }
    }

    private func readAudioModeSettingsConfig() async throws -> BossAppleAudioModeSettingsConfig {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: appOperationPreferences()) { transport in
            try await rustBridge.audioModeSettingsConfig(on: transport)
        }
    }

    private func readEqualizerSettingsIfAvailable() async throws -> BossAppleEqualizerSettings? {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: appOperationPreferences()) { transport in
            try await rustBridge.equalizerSettingsIfAvailable(on: transport)
        }
    }

    private func readDeviceSettingsReport() async throws -> BossAppleDeviceSettingsReport {
        let rustBridge = try requireRustBridge()
        return try await withRustBleTransportRetrying(preferredPreferences: appOperationPreferences()) { transport in
            try await rustBridge.deviceSettingsReport(on: transport)
        }
    }

    private func withRustBleTransportRetrying<T: Sendable>(
        preferredPreferences: [AppleBossCharacteristicPreference],
        preferActiveLink: Bool = true,
        operation: @escaping @Sendable (AppleBleBossTransport) async throws -> T
    ) async throws -> T {
        try await withRetryingResource(
            preferredPreferences: preferredPreferences,
            preferActiveLink: preferActiveLink,
            acquire: { [self] preference, attempt in
                    let connected = try await ensureConnected(
                        preference: preference,
                        forceReconnect: attempt > 0
                    )
                    return connected.transport
            },
            operation: operation
        )
    }

    private func withRetryingResource<Resource: Sendable, T: Sendable>(
        preferredPreferences: [AppleBossCharacteristicPreference],
        preferActiveLink: Bool,
        acquire: @escaping (_ preference: AppleBossCharacteristicPreference, _ attempt: Int) async throws -> Resource,
        operation: @escaping (Resource) async throws -> T
    ) async throws -> T {
        let preferences = normalizedPreferences(preferredPreferences, preferActiveLink: preferActiveLink)
        var lastError: Error?

        for preference in preferences {
            for attempt in 0..<2 {
                do {
                    let resource = try await acquire(preference, attempt)
                    return try await operation(resource)
                } catch {
                    lastError = error

                    switch retryResolution(for: error, preference: preference, attempt: attempt) {
                    case .nextPreference:
                        await invalidateLink(for: preference)
                        break
                    case .reconnectCurrentPreference:
                        await invalidateLink(for: preference)
                        continue
                    case .rethrow:
                        throw error
                    }
                }
            }
        }

        throw lastError ?? AppleBleBossTransportError.transportClosed
    }

    private func retryResolution(
        for error: Error,
        preference: AppleBossCharacteristicPreference,
        attempt: Int
    ) -> RetryResolution {
        if BossAppleController.retrySecureCharacteristicIfNeeded(error, preference) {
            return .nextPreference
        }

        if shouldFallbackToNextPreference(for: error, activePreference: preference) {
            return .nextPreference
        }

        if shouldReconnectCurrentSession(for: error), attempt == 0 {
            return .reconnectCurrentPreference
        }

        return .rethrow
    }

    private func ensureConnected(
        preference: AppleBossCharacteristicPreference,
        forceReconnect: Bool
    ) async throws -> ConnectedLink {
        if forceReconnect {
            await closeCurrentLink()
        } else if let connectedLink, connectedLink.preference == preference {
            return connectedLink
        } else if connectedLink != nil {
            await closeCurrentLink()
        }

        let transport = try await AppleBleBossTransport.connect(
            filter: AppleBossScanFilter(
                peripheralIdentifier: connection.identifier,
                nameContains: connection.nameContains,
                scanTimeout: connection.scanTimeout
            ),
            characteristicPreference: preference
        )
        let connected = ConnectedLink(
            transport: transport,
            preference: preference
        )
        connectedLink = connected
        return connected
    }

    private func invalidateLink(for preference: AppleBossCharacteristicPreference) async {
        guard connectedLink?.preference == preference else {
            return
        }
        await closeCurrentLink()
    }

    private func closeCurrentLink() async {
        guard let connectedLink else {
            return
        }
        self.connectedLink = nil
        await connectedLink.transport.close()
    }

    private func resolvedPreferences() -> [AppleBossCharacteristicPreference] {
        switch connection.characteristicPreference {
        case .automatic:
            return [.unsecure, .secure]
        case .unsecure:
            return [.unsecure]
        case .secure:
            return [.secure]
        }
    }

    private func appOperationPreferences() -> [AppleBossCharacteristicPreference] {
        switch connection.characteristicPreference {
        case .automatic:
            return [.secure, .unsecure]
        case .unsecure:
            return [.unsecure]
        case .secure:
            return [.secure]
        }
    }

    private func normalizedPreferences(
        _ requested: [AppleBossCharacteristicPreference],
        preferActiveLink: Bool
    ) -> [AppleBossCharacteristicPreference] {
        var seen = Set<AppleBossCharacteristicPreference>()
        let allowed = Set(resolvedPreferences())
        let filtered = requested.filter { allowed.contains($0) }
        let ordered = (filtered + resolvedPreferences()).filter { seen.insert($0).inserted }

        if preferActiveLink,
           let activePreference = connectedLink?.preference,
           let index = ordered.firstIndex(of: activePreference) {
            var reordered = ordered
            reordered.remove(at: index)
            reordered.insert(activePreference, at: 0)
            return reordered
        }

        return ordered
    }

    private func reconnectingRustPollingStream<Element: Sendable & Equatable>(
        interval: Duration = .seconds(2),
        read: @escaping @Sendable () async throws -> Element?
    ) -> AsyncThrowingStream<Element, Error> {
        let owner = self
        return AsyncThrowingStream { continuation in
            let task = Task {
                var lastElement: Element?

                while !Task.isCancelled {
                    do {
                        if let element = try await read(), element != lastElement {
                            lastElement = element
                            continuation.yield(element)
                        }
                        try await Task.sleep(for: interval)
                    } catch is CancellationError {
                        continuation.finish()
                        return
                    } catch {
                        if await owner.shouldReconnectCurrentSession(for: error) {
                            await owner.closeCurrentLink()
                            try? await Task.sleep(for: .milliseconds(250))
                            continue
                        }
                        continuation.finish(throwing: error)
                        return
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func reconnectingRustStream<Element: Sendable & Equatable>(
        initial: @escaping @Sendable () async throws -> Element?,
        stream: @escaping @Sendable (AppleBleBossTransport) -> AsyncThrowingStream<Element, Error>
    ) -> AsyncThrowingStream<Element, Error> {
        let owner = self
        return AsyncThrowingStream { continuation in
            let task = Task {
                var lastElement: Element?
                while !Task.isCancelled {
                    do {
                        let transport = try await owner.withRustBleTransportRetrying(
                            preferredPreferences: owner.appOperationPreferences()
                        ) { transport in
                            transport
                        }

                        if let initialElement = try await initial() {
                            guard !Task.isCancelled else {
                                continuation.finish()
                                return
                            }
                            if initialElement != lastElement {
                                lastElement = initialElement
                                continuation.yield(initialElement)
                            }
                        }

                        for try await element in stream(transport) {
                            guard !Task.isCancelled else {
                                continuation.finish()
                                return
                            }
                            if element != lastElement {
                                lastElement = element
                                continuation.yield(element)
                            }
                        }

                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        await owner.closeCurrentLink()
                        try? await Task.sleep(for: .milliseconds(250))
                    } catch is CancellationError {
                        continuation.finish()
                        return
                    } catch {
                        if await owner.shouldReconnectCurrentSession(for: error) {
                            await owner.closeCurrentLink()
                            try? await Task.sleep(for: .milliseconds(250))
                            continue
                        }
                        continuation.finish(throwing: error)
                        return
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func shouldReconnectCurrentSession(for error: Error) -> Bool {
        if let error = error as? BossAppleControlError {
            switch error {
            case .responseStreamEnded, .responseTimedOut:
                return true
            default:
                break
            }
        }
        if let error = error as? AppleBleBossTransportError {
            switch error {
            case .peripheralDisconnected, .transportClosed, .transportNotReady:
                return true
            default:
                return false
            }
        }
        if let error = error as? BossAppleLinkError, error == .unexpectedStreamTermination {
            return true
        }
        return false
    }

    private func shouldFallbackToNextPreference(
        for error: Error,
        activePreference: AppleBossCharacteristicPreference
    ) -> Bool {
        guard activePreference == .unsecure,
              connection.characteristicPreference == .automatic else {
            return false
        }

        if let error = error as? BossAppleControlError {
            switch error {
            case .responseStreamEnded, .responseTimedOut:
                return true
            default:
                return false
            }
        }

        if let error = error as? AppleBleBossTransportError {
            switch error {
            case .peripheralDisconnected, .transportClosed, .transportNotReady:
                return true
            default:
                return false
            }
        }

        if let error = error as? BossAppleLinkError, error == .unexpectedStreamTermination {
            return true
        }

        return false
    }

    private func requireRustBridge() throws -> BossRustSessionBridge {
        guard let rustBridge = BossRustSessionBridge.shared else {
            throw BossAppleControlError.unsupportedOperation("Rust runtime is required for BossAppleSession")
        }
        return rustBridge
    }

    nonisolated static func rustRequiredStream<Element>() -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: BossAppleControlError.unsupportedOperation(
                    "Rust runtime is required for BossAppleSession streams"
                )
            )
        }
    }
}
