import Foundation
import libboss

public struct BossAppleModeWorkspaceSnapshot: Sendable, Equatable {
    public let currentAudioModeIndex: Int
    public let settings: BossAudioModeSettingsConfig
    public let equalizer: BossEqualizerSettings?
    public let deviceSettings: BossAppleDeviceSettingsReport

    public init(
        currentAudioModeIndex: Int,
        settings: BossAudioModeSettingsConfig,
        equalizer: BossEqualizerSettings?,
        deviceSettings: BossAppleDeviceSettingsReport
    ) {
        self.currentAudioModeIndex = currentAudioModeIndex
        self.settings = settings
        self.equalizer = equalizer
        self.deviceSettings = deviceSettings
    }
}

public struct BossAppleWorkspaceSnapshot: Sendable, Equatable {
    public let bootstrappedDevice: BootstrappedDevice
    public let modeWorkspace: BossAppleModeWorkspaceSnapshot
    public let audioModes: [BossAudioModeConfig]

    public init(
        bootstrappedDevice: BootstrappedDevice,
        modeWorkspace: BossAppleModeWorkspaceSnapshot,
        audioModes: [BossAudioModeConfig]
    ) {
        self.bootstrappedDevice = bootstrappedDevice
        self.modeWorkspace = modeWorkspace
        self.audioModes = audioModes
    }
}

public actor BossAppleSession {
    private struct ConnectedLink {
        let transport: AppleBleBossTransport
        let link: BleBmapLink
        var packetSession: BossPacketSession?
        var bossSession: BossSession?
        let preference: AppleBossCharacteristicPreference
    }

    public let connection: BossAppleConnectionOptions

    private var connectedLink: ConnectedLink?

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

    public func bootstrap() async throws -> BootstrappedDevice {
        try await withRawLinkRetrying(preferredPreferences: [.unsecure, .secure], preferActiveLink: false) { link in
            try await BootstrapSession(link: link).bootstrap()
        }
    }

    public func loadWorkspaceSnapshot() async throws -> BossAppleWorkspaceSnapshot {
        let bootstrappedDevice = try await bootstrap()
        return try await withCoreSessionRetrying(preferredPreferences: appOperationPreferences()) { [self] session in
            try await mapCoreErrors {
                wrap(try await session.loadWorkspaceSnapshot(bootstrappedDevice: bootstrappedDevice))
            }
        }
    }

    public func refreshModeWorkspaceSnapshot() async throws -> BossAppleModeWorkspaceSnapshot {
        try await withCoreSessionRetrying(preferredPreferences: appOperationPreferences()) { [self] session in
            try await mapCoreErrors {
                wrap(try await session.refreshModeWorkspaceSnapshot())
            }
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

    public func supportedAudioModePrompts() async throws -> [BossAudioModePrompt] {
        try await withCoreSessionRetrying(preferredPreferences: appOperationPreferences()) { [self] session in
            try await mapCoreErrors {
                try await session.supportedAudioModePrompts()
            }
        }
    }

    public func audioModeConfigs() async throws -> [BossAudioModeConfig] {
        try await withCoreSessionRetrying(preferredPreferences: appOperationPreferences()) { [self] session in
            try await mapCoreErrors {
                try await session.audioModeConfigs()
            }
        }
    }

    public func setCurrentAudioMode(
        index targetIndex: Int,
        playVoicePrompt: Bool = false
    ) async throws -> BossAppleCurrentAudioModeWriteResult {
        try await withCoreSessionRetrying(preferredPreferences: [.secure, .unsecure]) { [self] session in
            try await mapCoreErrors {
                wrap(try await session.setCurrentAudioMode(index: targetIndex, playVoicePrompt: playVoicePrompt))
            }
        }
    }

    public func setAudioModeSettings(
        _ update: BossAudioModeSettingsConfigPatch
    ) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await withCoreSessionRetrying(preferredPreferences: [.secure, .unsecure]) { [self] session in
            try await mapCoreErrors {
                wrap(try await session.setAudioModeSettings(update))
            }
        }
    }

    public func setEqualizer(
        _ update: BossEqualizerSettingsPatch
    ) async throws -> BossAppleEqualizerWriteResult {
        try await withCoreSessionRetrying(preferredPreferences: [.secure, .unsecure]) { [self] session in
            try await mapCoreErrors {
                wrap(try await session.setEqualizer(update))
            }
        }
    }

    public func setWearDetectionEnabled(_ enabled: Bool) async throws -> BossOnHeadDetectionValue {
        try await withCoreSessionRetrying(preferredPreferences: [.secure, .unsecure]) { [self] session in
            try await mapCoreErrors {
                try await session.setWearDetectionEnabled(enabled)
            }
        }
    }

    public func setAutoAware(_ enabled: Bool) async throws -> Bool {
        try await setEnabledSetting(functionRaw: BossSettingsCodec.autoAwareFunctionRaw, enabled: enabled)
    }

    public func setAutoPlayPause(_ enabled: Bool) async throws -> Bool {
        try await setEnabledSetting(functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw, enabled: enabled)
    }

    public func setAutoAnswer(_ enabled: Bool) async throws -> Bool {
        try await setEnabledSetting(functionRaw: BossSettingsCodec.autoAnswerFunctionRaw, enabled: enabled)
    }

    public func setVolumeControl(_ value: BossVolumeControlValue) async throws -> BossVolumeControlStatus {
        try await withCoreSessionRetrying(preferredPreferences: [.secure, .unsecure]) { [self] session in
            try await mapCoreErrors {
                try await session.setVolumeControl(value)
            }
        }
    }

    public func favoriteAudioMode(index: Int) async throws -> [Int] {
        try await setAudioModeFavorite(index: index, isFavorite: true)
    }

    public func unfavoriteAudioMode(index: Int) async throws -> [Int] {
        try await setAudioModeFavorite(index: index, isFavorite: false)
    }

    public func deleteCustomAudioMode(slot: Int) async throws -> BossAudioModeConfig {
        let configs = try await audioModeConfigs()
        guard let existing = configs.first(where: { $0.modeIndex == slot }) else {
            throw BossAppleControlError.customAudioModeSlotNotFound(slot)
        }
        guard existing.userConfigurable else {
            throw BossAppleControlError.customAudioModeSlotNotEditable(slot)
        }

        if existing.favorite {
            _ = try await unfavoriteAudioMode(index: slot)
        }

        return try await writeCustomAudioMode(
            slot: slot,
            name: "",
            settings: existing.deletedSettingsBaseline,
            prompt: .none
        )
    }

    public func saveCustomAudioMode(
        name: String,
        settings: BossAudioModeSettingsConfig,
        prompt: BossAudioModePrompt = .none,
        slot requestedSlot: Int? = nil
    ) async throws -> BossAudioModeConfig {
        let configs = try await audioModeConfigs()
        let slot: Int
        if let requestedSlot {
            guard configs.first(where: { $0.modeIndex == requestedSlot })?.userConfigurable == true else {
                throw BossAppleControlError.customAudioModeSlotNotEditable(requestedSlot)
            }
            slot = requestedSlot
        } else {
            guard let freeSlot = BossAppleController.firstFreeCustomAudioModeSlot(in: configs) else {
                throw BossAppleControlError.noFreeCustomAudioModeSlot
            }
            slot = freeSlot
        }

        return try await writeCustomAudioMode(slot: slot, name: name, settings: settings, prompt: prompt)
    }

    private func setEnabledSetting(functionRaw: UInt8, enabled: Bool) async throws -> Bool {
        try await withCoreSessionRetrying(preferredPreferences: [.secure, .unsecure]) { [self] session in
            try await mapCoreErrors {
                switch functionRaw {
                case BossSettingsCodec.autoAwareFunctionRaw:
                    return try await session.setAutoAware(enabled)
                case BossSettingsCodec.autoPlayPauseFunctionRaw:
                    return try await session.setAutoPlayPause(enabled)
                case BossSettingsCodec.autoAnswerFunctionRaw:
                    return try await session.setAutoAnswer(enabled)
                default:
                    throw BossAppleControlError.unsupportedOperation("Unsupported setting function \(functionRaw)")
                }
            }
        }
    }

    private func setAudioModeFavorite(index: Int, isFavorite: Bool) async throws -> [Int] {
        try await withCoreSessionRetrying(preferredPreferences: appOperationPreferences()) { [self] session in
            try await mapCoreErrors {
                if isFavorite {
                    return try await session.favoriteAudioMode(index: index)
                }
                return try await session.unfavoriteAudioMode(index: index)
            }
        }
    }

    private func writeCustomAudioMode(
        slot: Int,
        name: String,
        settings: BossAudioModeSettingsConfig,
        prompt: BossAudioModePrompt
    ) async throws -> BossAudioModeConfig {
        try await withCoreSessionRetrying(preferredPreferences: [.secure, .unsecure]) { [self] session in
            try await mapCoreErrors {
                try await session.saveCustomAudioMode(
                    name: name,
                    settings: settings,
                    prompt: prompt,
                    slot: slot
                )
            }
        }
    }

    private func withSessionLinkRetrying<T: Sendable>(
        preferredPreferences: [AppleBossCharacteristicPreference],
        preferActiveLink: Bool = true,
        operation: @escaping @Sendable (BossPacketSession) async throws -> T
    ) async throws -> T {
        let preferences = normalizedPreferences(preferredPreferences, preferActiveLink: preferActiveLink)
        var lastError: Error?

        for preference in preferences {
            for attempt in 0..<2 {
                do {
                    let packetSession = try await ensurePacketSession(preference: preference, forceReconnect: attempt > 0)
                    return try await operation(packetSession)
                } catch {
                    lastError = error

                    if BossAppleController.retrySecureCharacteristicIfNeeded(error, preference) {
                        await invalidateLink(for: preference)
                        break
                    }

                    if shouldFallbackToNextPreference(for: error, activePreference: preference) {
                        await invalidateLink(for: preference)
                        break
                    }

                    if shouldReconnectCurrentSession(for: error), attempt == 0 {
                        await invalidateLink(for: preference)
                        continue
                    }

                    throw error
                }
            }
        }

        throw lastError ?? AppleBleBossTransportError.transportClosed
    }

    private func withCoreSessionRetrying<T: Sendable>(
        preferredPreferences: [AppleBossCharacteristicPreference],
        preferActiveLink: Bool = true,
        operation: @escaping @Sendable (BossSession) async throws -> T
    ) async throws -> T {
        let preferences = normalizedPreferences(preferredPreferences, preferActiveLink: preferActiveLink)
        var lastError: Error?

        for preference in preferences {
            for attempt in 0..<2 {
                do {
                    let bossSession = try await ensureBossSession(preference: preference, forceReconnect: attempt > 0)
                    return try await operation(bossSession)
                } catch {
                    lastError = error

                    if BossAppleController.retrySecureCharacteristicIfNeeded(error, preference) {
                        await invalidateLink(for: preference)
                        break
                    }

                    if shouldFallbackToNextPreference(for: error, activePreference: preference) {
                        await invalidateLink(for: preference)
                        break
                    }

                    if shouldReconnectCurrentSession(for: error), attempt == 0 {
                        await invalidateLink(for: preference)
                        continue
                    }

                    throw error
                }
            }
        }

        throw lastError ?? AppleBleBossTransportError.transportClosed
    }

    private func withRawLinkRetrying<T: Sendable>(
        preferredPreferences: [AppleBossCharacteristicPreference],
        preferActiveLink: Bool = true,
        operation: @escaping @Sendable (BleBmapLink) async throws -> T
    ) async throws -> T {
        let preferences = normalizedPreferences(preferredPreferences, preferActiveLink: preferActiveLink)
        var lastError: Error?

        for preference in preferences {
            for attempt in 0..<2 {
                do {
                    let connected = try await ensureConnected(preference: preference, forceReconnect: attempt > 0)
                    return try await operation(connected.link)
                } catch {
                    lastError = error

                    if BossAppleController.retrySecureCharacteristicIfNeeded(error, preference) {
                        await invalidateLink(for: preference)
                        break
                    }

                    if shouldFallbackToNextPreference(for: error, activePreference: preference) {
                        await invalidateLink(for: preference)
                        break
                    }

                    if shouldReconnectCurrentSession(for: error), attempt == 0 {
                        await invalidateLink(for: preference)
                        continue
                    }

                    throw error
                }
            }
        }

        throw lastError ?? AppleBleBossTransportError.transportClosed
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
        let link = BleBmapLink(transport: transport)
        let connected = ConnectedLink(
            transport: transport,
            link: link,
            packetSession: nil,
            bossSession: nil,
            preference: preference
        )
        connectedLink = connected
        return connected
    }

    private func ensurePacketSession(
        preference: AppleBossCharacteristicPreference,
        forceReconnect: Bool
    ) async throws -> BossPacketSession {
        let connected = try await ensureConnected(preference: preference, forceReconnect: forceReconnect)
        if let packetSession = connected.packetSession {
            return packetSession
        }

        let packetSession = BossPacketSession(link: connected.link)
        if var stored = connectedLink, stored.preference == preference {
            stored.packetSession = packetSession
            connectedLink = stored
        }
        return packetSession
    }

    private func ensureBossSession(
        preference: AppleBossCharacteristicPreference,
        forceReconnect: Bool
    ) async throws -> BossSession {
        let connected = try await ensureConnected(preference: preference, forceReconnect: forceReconnect)
        if let bossSession = connected.bossSession {
            return bossSession
        }

        let packetSession: BossPacketSession
        if let existing = connected.packetSession {
            packetSession = existing
        } else {
            packetSession = BossPacketSession(link: connected.link)
        }

        let bossSession = BossSession(packetSession: packetSession)
        if var stored = connectedLink, stored.preference == preference {
            stored.packetSession = packetSession
            stored.bossSession = bossSession
            connectedLink = stored
        }
        return bossSession
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
        connectedLink.packetSession?.invalidate()
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
        if let error = error as? BossLinkError, error == .unexpectedStreamTermination {
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

        if let error = error as? BossLinkError, error == .unexpectedStreamTermination {
            return true
        }

        return false
    }
}

private extension BossAppleSession {
    nonisolated func wrap(_ workspace: BossWorkspaceSnapshot) -> BossAppleWorkspaceSnapshot {
        BossAppleWorkspaceSnapshot(
            bootstrappedDevice: workspace.bootstrappedDevice,
            modeWorkspace: wrap(workspace.modeWorkspace),
            audioModes: workspace.audioModes
        )
    }

    nonisolated func wrap(_ workspace: BossModeWorkspaceSnapshot) -> BossAppleModeWorkspaceSnapshot {
        BossAppleModeWorkspaceSnapshot(
            currentAudioModeIndex: workspace.currentAudioModeIndex,
            settings: workspace.settings,
            equalizer: workspace.equalizer,
            deviceSettings: wrap(workspace.deviceSettings)
        )
    }

    nonisolated func wrap(_ report: BossDeviceSettingsReport) -> BossAppleDeviceSettingsReport {
        BossAppleDeviceSettingsReport(
            wearDetection: wrap(report.wearDetection),
            autoAwareEnabled: wrap(report.autoAwareEnabled),
            autoPlayPauseEnabled: wrap(report.autoPlayPauseEnabled),
            autoAnswerEnabled: wrap(report.autoAnswerEnabled),
            volumeControl: wrap(report.volumeControl)
        )
    }

    nonisolated func wrap<Value>(_ setting: BossObservedSetting<Value>) -> BossAppleObservedSetting<Value> {
        BossAppleObservedSetting(
            value: setting.value,
            source: setting.source.map(wrap),
            unavailableReason: setting.unavailableReason.map(wrap)
        )
    }

    nonisolated func wrap(_ source: BossSettingSource) -> BossAppleSettingSource {
        switch source {
        case .snapshot:
            return .snapshot
        case .compositeSnapshot:
            return .compositeSnapshot
        case .directGet:
            return .directGet
        }
    }

    nonisolated func wrap(_ reason: BossSettingUnavailableReason) -> BossAppleSettingUnavailableReason {
        switch reason {
        case .missingFromSnapshot:
            return .missingFromSnapshot
        case .timedOut:
            return .timedOut
        case .responseStreamEnded:
            return .responseStreamEnded
        case .functionUnsupported:
            return .functionUnsupported
        case .operatorUnsupported:
            return .operatorUnsupported
        case .dataUnavailable:
            return .dataUnavailable
        case .insecureTransport:
            return .insecureTransport
        case .unexpectedStreamTermination:
            return .unexpectedStreamTermination
        case .bmapError(let code):
            return .bmapError(code)
        }
    }

    nonisolated func wrap(_ result: BossCurrentAudioModeWriteResult) -> BossAppleCurrentAudioModeWriteResult {
        switch result {
        case .unchanged(let value):
            return .unchanged(value)
        case .updated(let value):
            return .updated(value)
        case .verificationInconclusive(let targetIndex):
            return .verificationInconclusive(targetIndex: targetIndex)
        }
    }

    nonisolated func wrap(_ result: BossAudioModeSettingsWriteResult) -> BossAppleAudioModeSettingsWriteResult {
        switch result {
        case .unchanged(let value):
            return .unchanged(value)
        case .updated(let value):
            return .updated(value)
        case .verificationInconclusive(let value):
            return .verificationInconclusive(value)
        }
    }

    nonisolated func wrap(_ result: BossEqualizerWriteResult) -> BossAppleEqualizerWriteResult {
        switch result {
        case .unchanged(let value):
            return .unchanged(value)
        case .updated(let value):
            return .updated(value)
        case .verificationInconclusive(let value):
            return .verificationInconclusive(value)
        }
    }

    func timeoutError(for timeout: Duration) -> BossAppleControlError {
        .responseTimedOut(seconds: timeout.components.seconds)
    }

    func mapCoreErrors<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let error as BossSessionError {
            switch error {
            case .responseStreamEnded:
                throw BossAppleControlError.responseStreamEnded
            case .responseTimedOut(let seconds):
                throw BossAppleControlError.responseTimedOut(seconds: seconds)
            case .bmapErrorResponse(let context, let payloadHex):
                throw BossAppleControlError.bmapErrorResponse(context: context, payloadHex: payloadHex)
            case .unsupportedOperation(let message):
                throw BossAppleControlError.unsupportedOperation(message)
            case .modeChangeNotObserved(let targetIndex, let observedIndex):
                throw BossAppleControlError.modeChangeNotObserved(targetIndex: targetIndex, observedIndex: observedIndex)
            case .equalizerNotObserved(let expected, let observed):
                throw BossAppleControlError.equalizerNotObserved(expected: expected, observed: observed)
            case .settingsConfigNotObserved(let expected, let observed):
                throw BossAppleControlError.settingsConfigNotObserved(expected: expected, observed: observed)
            case .noFreeCustomAudioModeSlot:
                throw BossAppleControlError.noFreeCustomAudioModeSlot
            case .customAudioModeSlotNotEditable(let slot):
                throw BossAppleControlError.customAudioModeSlotNotEditable(slot)
            case .customAudioModeSlotNotFound(let slot):
                throw BossAppleControlError.customAudioModeSlotNotFound(slot)
            }
        }
    }

    func mapSessionErrors<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let error as BmapResponseError {
            throw BossAppleControlError.bmapErrorResponse(
                context: error.context,
                payloadHex: error.payloadHex
            )
        } catch let error as BossLinkError where error == .unexpectedStreamTermination {
            throw BossAppleControlError.responseStreamEnded
        }
    }

    func awaitSettingsSnapshot(
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> BossSettingsSnapshot {
        try await mapSessionErrors {
            try await session.settingsSnapshot(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func awaitAudioModeConfigs(
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> [BossAudioModeConfig] {
        try await mapSessionErrors {
            try await session.audioModeConfigs(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func currentAudioModeIfAvailable(
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> Int? {
        do {
            return try await requiredCurrentAudioMode(on: session, timeout: timeout)
        } catch {
            guard BossAppleController.shouldFallbackForAudioModeWrite(error) else {
                throw error
            }
            return nil
        }
    }

    func requiredCurrentAudioMode(
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> Int {
        try await mapSessionErrors {
            try await session.currentAudioMode(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func requiredEqualizer(
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> BossEqualizerSettings {
        try await mapSessionErrors {
            try await session.equalizerSettings(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func requiredAudioModeSettingsConfig(
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> BossAudioModeSettingsConfig {
        try await mapSessionErrors {
            try await session.audioModeSettingsConfig(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func requiredFavoriteAudioModeIndices(
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> [Int] {
        try await mapSessionErrors {
            try await session.favoriteAudioModeIndices(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func requiredAudioModeCapabilities(
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> BossAudioModesCapabilities {
        try await mapSessionErrors {
            try await session.audioModeCapabilities(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func readAudioModeSettingsConfig(
        on session: BossPacketSession,
        attempts: Int,
        timeoutPerAttempt: Duration,
        retryDelay: Duration
    ) async throws -> BossAudioModeSettingsConfig {
        var lastError: Error = timeoutError(for: timeoutPerAttempt)
        for attempt in 0..<attempts {
            do {
                return try await requiredAudioModeSettingsConfig(on: session, timeout: timeoutPerAttempt)
            } catch {
                lastError = error
                guard BossAppleController.isRecoverableAudioModeSettingsConfigError(error), attempt < attempts - 1 else {
                    throw error
                }
                try await Task.sleep(for: retryDelay)
            }
        }
        throw lastError
    }

    func sendEqualizerSetGets(
        _ requests: [(BossEqualizerBand, Int)],
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> BossEqualizerSettings {
        try await mapSessionErrors {
            try await session.setEqualizer(
                requests: requests,
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func sendAudioModeSettingsConfigSetGet(
        _ config: BossAudioModeSettingsConfig,
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> BossAudioModeSettingsConfig {
        try await mapSessionErrors {
            try await session.setAudioModeSettingsConfig(
                config,
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func sendAudioModeConfigSetGet(
        modeIndex: Int,
        prompt: BossAudioModePrompt,
        name: String,
        settings: BossAudioModeSettingsConfig,
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> BossAudioModeConfig {
        try await mapSessionErrors {
            try await session.setAudioModeConfig(
                modeIndex: modeIndex,
                prompt: prompt,
                name: name,
                settings: settings,
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func sendAudioModeFavoritesSetGet(
        numberOfModes: Int,
        favoriteModeIndices: [Int],
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> [Int] {
        try await mapSessionErrors {
            try await session.setFavoriteAudioModeIndices(
                numberOfModes: numberOfModes,
                favoriteModeIndices: favoriteModeIndices,
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func onHeadDetectionIfAvailable(
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> BossOnHeadDetectionValue? {
        try await mapSessionErrors {
            try await session.onHeadDetection(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func enabledSettingIfAvailable(
        functionRaw: UInt8,
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> Bool? {
        try await mapSessionErrors {
            try await session.enabledSetting(
                functionRaw: functionRaw,
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func volumeControlIfAvailable(
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> BossVolumeControlStatus? {
        try await mapSessionErrors {
            try await session.volumeControlStatus(
                timeout: timeout,
                timeoutError: timeoutError(for: timeout)
            )
        }
    }

    func equalizerIfAvailable(
        from snapshot: BossSettingsSnapshot,
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> BossEqualizerSettings? {
        if let value = try snapshot.equalizer() {
            return value
        }
        return try await BossAppleController.observeSettingAfterDirectRead(
            initialUnavailableReason: .missingFromSnapshot,
            read: { try await self.requiredEqualizer(on: session, timeout: timeout) }
        ).value
    }

    func deviceSettingsReport(
        from snapshot: BossSettingsSnapshot,
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> BossAppleDeviceSettingsReport {
        let wearDetection = try await observedWearDetection(from: snapshot, on: session, timeout: timeout)
        let autoAwareEnabled = try await observedEnabledSetting(
            functionRaw: BossSettingsCodec.autoAwareFunctionRaw,
            snapshotValue: try snapshot.autoAware(),
            snapshotPacketExists: snapshot.packet(functionRaw: BossSettingsCodec.autoAwareFunctionRaw) != nil,
            on: session,
            timeout: timeout
        )
        let autoPlayPauseEnabled = try await observedEnabledSetting(
            functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw,
            snapshotValue: try snapshot.autoPlayPause(),
            snapshotPacketExists: snapshot.packet(functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw) != nil,
            on: session,
            timeout: timeout
        )
        let autoAnswerEnabled = try await observedAutoAnswer(from: snapshot, on: session, timeout: timeout)
        let volumeControl = try await observedVolumeControl(from: snapshot, on: session, timeout: timeout)

        return BossAppleDeviceSettingsReport(
            wearDetection: wearDetection,
            autoAwareEnabled: autoAwareEnabled,
            autoPlayPauseEnabled: autoPlayPauseEnabled,
            autoAnswerEnabled: autoAnswerEnabled,
            volumeControl: volumeControl
        )
    }

    func observedWearDetection(
        from snapshot: BossSettingsSnapshot,
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> BossAppleObservedSetting<BossOnHeadDetectionValue> {
        if let value = try snapshot.onHeadDetection() {
            return BossAppleObservedSetting(value: value, source: .snapshot)
        }
        return try await BossAppleController.observeSettingAfterDirectRead(
            initialUnavailableReason: .missingFromSnapshot,
            read: { try await self.onHeadDetectionIfAvailable(on: session, timeout: timeout) }
        )
    }

    func observedEnabledSetting(
        functionRaw: UInt8,
        snapshotValue: Bool?,
        snapshotPacketExists: Bool,
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> BossAppleObservedSetting<Bool> {
        if let snapshotValue {
            return BossAppleObservedSetting(value: snapshotValue, source: .snapshot)
        }
        return try await BossAppleController.observeSettingAfterDirectRead(
            initialUnavailableReason: snapshotPacketExists ? .dataUnavailable : .missingFromSnapshot,
            read: { try await self.enabledSettingIfAvailable(functionRaw: functionRaw, on: session, timeout: timeout) }
        )
    }

    func observedAutoAnswer(
        from snapshot: BossSettingsSnapshot,
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> BossAppleObservedSetting<Bool> {
        if let packet = snapshot.packet(functionRaw: BossSettingsCodec.autoAnswerFunctionRaw) {
            return BossAppleObservedSetting(
                value: try BossSettingsCodec.parseEnabledFlag(from: packet),
                source: .snapshot
            )
        }
        if let derived = try snapshot.onHeadDetection()?.isAutoAnswerEnabled {
            return BossAppleObservedSetting(value: derived, source: .compositeSnapshot)
        }
        return try await BossAppleController.observeSettingAfterDirectRead(
            initialUnavailableReason: .missingFromSnapshot,
            read: { try await self.enabledSettingIfAvailable(functionRaw: BossSettingsCodec.autoAnswerFunctionRaw, on: session, timeout: timeout) }
        )
    }

    func observedVolumeControl(
        from snapshot: BossSettingsSnapshot,
        on session: BossPacketSession,
        timeout: Duration
    ) async throws -> BossAppleObservedSetting<BossVolumeControlStatus> {
        if let value = try snapshot.volumeControl() {
            return BossAppleObservedSetting(value: value, source: .snapshot)
        }
        return try await BossAppleController.observeSettingAfterDirectRead(
            initialUnavailableReason: .missingFromSnapshot,
            read: { try await self.volumeControlIfAvailable(on: session, timeout: timeout) }
        )
    }

    func verifyCurrentAudioMode(
        on session: BossPacketSession,
        targetIndex: Int,
        timeoutPerAttempt: Duration,
        attempts: Int,
        retryDelay: Duration,
        fallbackError: Error? = nil
    ) async throws -> Int {
        var lastError: Error = fallbackError ?? timeoutError(for: timeoutPerAttempt)
        var lastObservedIndex: Int?
        for attempt in 0..<attempts {
            do {
                let currentIndex = try await requiredCurrentAudioMode(on: session, timeout: timeoutPerAttempt)
                lastObservedIndex = currentIndex
                if currentIndex == targetIndex {
                    return currentIndex
                }
            } catch {
                lastError = error
            }
            if attempt < attempts - 1 {
                try await Task.sleep(for: retryDelay)
            }
        }
        if let lastObservedIndex {
            throw BossAppleControlError.modeChangeNotObserved(targetIndex: targetIndex, observedIndex: lastObservedIndex)
        }
        throw fallbackError ?? lastError
    }
}
