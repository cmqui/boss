import Foundation
import libboss

public struct BossAppleConnectionOptions: Sendable, Equatable {
    public let nameContains: String?
    public let identifier: UUID?
    public let scanTimeout: Duration
    public let characteristicPreference: AppleBossCharacteristicPreference

    public init(
        nameContains: String? = nil,
        identifier: UUID? = nil,
        scanTimeout: Duration = .seconds(20),
        characteristicPreference: AppleBossCharacteristicPreference = .automatic
    ) {
        self.nameContains = nameContains
        self.identifier = identifier
        self.scanTimeout = scanTimeout
        self.characteristicPreference = characteristicPreference
    }

    public func withCharacteristicPreference(_ preference: AppleBossCharacteristicPreference) -> BossAppleConnectionOptions {
        BossAppleConnectionOptions(
            nameContains: nameContains,
            identifier: identifier,
            scanTimeout: scanTimeout,
            characteristicPreference: preference
        )
    }

    fileprivate var securePreferred: BossAppleConnectionOptions {
        guard characteristicPreference == .automatic else {
            return self
        }
        return withCharacteristicPreference(.secure)
    }

    fileprivate var scanFilter: AppleBossScanFilter {
        AppleBossScanFilter(
            peripheralIdentifier: identifier,
            nameContains: nameContains,
            scanTimeout: scanTimeout
        )
    }
}

public enum BossAppleControlError: Error, Sendable, Equatable, CustomStringConvertible {
    case responseStreamEnded
    case responseTimedOut(seconds: Int64)
    case bmapErrorResponse(context: String, payloadHex: String)
    case modeChangeNotObserved(targetIndex: Int, observedIndex: Int)
    case settingsConfigNotObserved(expected: String, observed: String)
    case noFreeCustomAudioModeSlot
    case customAudioModeSlotNotEditable(Int)
    case customAudioModeSlotNotFound(Int)

    public var bmapErrorCode: BmapErrorCode? {
        guard case .bmapErrorResponse(_, let payloadHex) = self else {
            return nil
        }
        return Self.bmapErrorCode(from: payloadHex)
    }

    public var description: String {
        switch self {
        case .responseStreamEnded:
            return "responseStreamEnded"
        case .responseTimedOut(let seconds):
            return "responseTimedOut(seconds: \(seconds))"
        case .bmapErrorResponse(let context, let payloadHex):
            if let code = bmapErrorCode {
                return "bmapErrorResponse(context: \"\(context)\", payloadHex: \"\(payloadHex)\", code: \(code.description))"
            }
            return "bmapErrorResponse(context: \"\(context)\", payloadHex: \"\(payloadHex)\")"
        case .modeChangeNotObserved(let targetIndex, let observedIndex):
            return "modeChangeNotObserved(targetIndex: \(targetIndex), observedIndex: \(observedIndex))"
        case .settingsConfigNotObserved(let expected, let observed):
            return "settingsConfigNotObserved(expected: \"\(expected)\", observed: \"\(observed)\")"
        case .noFreeCustomAudioModeSlot:
            return "noFreeCustomAudioModeSlot"
        case .customAudioModeSlotNotEditable(let slot):
            return "customAudioModeSlotNotEditable(\(slot))"
        case .customAudioModeSlotNotFound(let slot):
            return "customAudioModeSlotNotFound(\(slot))"
        }
    }

    private static func bmapErrorCode(from payloadHex: String) -> BmapErrorCode? {
        guard payloadHex.count == 2, let rawValue = UInt8(payloadHex, radix: 16) else {
            return nil
        }
        return BmapErrorCode(rawValue: rawValue)
    }
}

public enum BossAppleAudioModeSettingsWriteResult: Sendable, Equatable {
    case unchanged(BossAudioModeSettingsConfig)
    case updated(BossAudioModeSettingsConfig)
    case verificationInconclusive(BossAudioModeSettingsConfig)
}

public enum BossAppleCurrentAudioModeWriteResult: Sendable, Equatable {
    case unchanged(Int)
    case updated(Int)
    case verificationInconclusive(targetIndex: Int)
}

public struct BossAppleController: Sendable {
    public let connection: BossAppleConnectionOptions

    public init(connection: BossAppleConnectionOptions = BossAppleConnectionOptions()) {
        self.connection = connection
    }

    public func withConnectedLink<T: Sendable>(
        _ operation: @escaping @Sendable (BleBmapLink) async throws -> T
    ) async throws -> T {
        try await Self.withConnectedLink(connection, operation: operation)
    }

    public func bootstrap() async throws -> BootstrappedDevice {
        try await withConnectedLink { link in
            try await BootstrapSession(link: link).bootstrap()
        }
    }

    public func audioModes() async throws -> [BossAudioModeInfo] {
        try await audioModeConfigs().map(\.info)
    }

    public func audioModeConfigs() async throws -> [BossAudioModeConfig] {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.awaitAudioModeConfigs(on: link, timeout: .seconds(30))
        }
    }

    public func displayableAudioModes() async throws -> [BossAudioModeInfo] {
        try await audioModes().filter { mode in
            !(mode.userConfigurable && !mode.userConfigured && mode.name == "None")
        }
    }

    public func audioModeCapabilities() async throws -> BossAudioModesCapabilities {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.requiredAudioModeCapabilities(on: link, timeout: .seconds(5))
        }
    }

    public func supportedAudioModePrompts() async throws -> [BossAudioModePrompt] {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            let response = try await Self.sendAndAwaitSameFunction(
                packet: BossAudioModesCodec.namesSupportedGetPacket(),
                on: link,
                timeout: .seconds(5)
            )
            return try BossAudioModesCodec.parseSupportedPrompts(from: response)
        }
    }

    public func favoriteAudioModeIndices() async throws -> [Int] {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.requiredFavoriteAudioModeIndices(on: link, timeout: .seconds(5))
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

        return try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.sendAudioModeFavoritesSetGet(
                numberOfModes: numberOfModes,
                favoriteModeIndices: indices,
                on: link,
                timeout: .seconds(5)
            )
        }
    }

    public func setAudioModeFavorite(index: Int, isFavorite: Bool) async throws -> [Int] {
        let numberOfModes = try await audioModeCapabilities().totalModes
        var favorites = Set(try await favoriteAudioModeIndices())
        if isFavorite {
            favorites.insert(index)
        } else {
            favorites.remove(index)
        }
        return try await setFavoriteAudioModeIndices(Array(favorites).sorted(), numberOfModes: numberOfModes)
    }

    public func favoriteAudioMode(index: Int) async throws -> [Int] {
        try await setAudioModeFavorite(index: index, isFavorite: true)
    }

    public func unfavoriteAudioMode(index: Int) async throws -> [Int] {
        try await setAudioModeFavorite(index: index, isFavorite: false)
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
            guard let freeSlot = Self.firstFreeCustomAudioModeSlot(in: configs) else {
                throw BossAppleControlError.noFreeCustomAudioModeSlot
            }
            slot = freeSlot
        }
        return try await writeCustomAudioMode(slot: slot, name: name, settings: settings, prompt: prompt)
    }

    public func renameCustomAudioMode(
        slot: Int,
        name: String,
        prompt: BossAudioModePrompt? = nil
    ) async throws -> BossAudioModeConfig {
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
        settings: BossAudioModeSettingsConfig? = nil,
        prompt: BossAudioModePrompt? = nil
    ) async throws -> BossAudioModeConfig {
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

        let cleared = try await writeCustomAudioMode(
            slot: slot,
            name: "",
            settings: existing.deletedSettingsBaseline,
            prompt: .none
        )

        return cleared
    }

    public func currentAudioMode() async throws -> Int {
        try await Self.withConnectedLinkRetrying(connection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.requiredCurrentAudioMode(on: link, timeout: .seconds(5))
        }
    }

    public func setCurrentAudioMode(index targetIndex: Int, playVoicePrompt: Bool = false) async throws -> BossAppleCurrentAudioModeWriteResult {
        let commandConnection = connection.securePreferred
        return try await Self.withConnectedLinkRetrying(commandConnection, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            if let currentIndex = try await Self.currentAudioModeIfAvailable(on: link, timeout: .seconds(2)),
               currentIndex == targetIndex {
                return .unchanged(currentIndex)
            }

            do {
                let response = try await Self.sendAndAwaitSameFunction(
                    packet: BossAudioModesCodec.currentModeStartPacket(modeIndex: targetIndex, playVoicePrompt: playVoicePrompt),
                    on: link,
                    timeout: .seconds(5)
                )
                if response.operator == .result {
                    if let responseModeIndex = response.payload.first {
                        return .updated(Int(responseModeIndex))
                    }
                    let verified = try await Self.verifyCurrentAudioMode(
                        on: link,
                        targetIndex: targetIndex,
                        timeoutPerAttempt: .seconds(2),
                        attempts: 3,
                        retryDelay: .milliseconds(500)
                    )
                    return .updated(verified)
                }
                return .updated(try BossAudioModesCodec.parseCurrentMode(from: response))
            } catch {
                guard Self.shouldFallbackForAudioModeWrite(error) else {
                    throw error
                }
                do {
                    let verified = try await Self.verifyCurrentAudioMode(
                        on: link,
                        targetIndex: targetIndex,
                        timeoutPerAttempt: .seconds(3),
                        attempts: 4,
                        retryDelay: .seconds(1),
                        fallbackError: error
                    )
                    return .updated(verified)
                } catch {
                    do {
                        let verified = try await Self.verifyCurrentAudioModeAfterReconnect(
                            connection: connection,
                            targetIndex: targetIndex,
                            fallbackError: error
                        )
                        return .updated(verified)
                    } catch let reconnectError {
                        if Self.isVerificationInconclusiveError(reconnectError) {
                            return .verificationInconclusive(targetIndex: targetIndex)
                        }
                        throw reconnectError
                    }
                }
            }
        }
    }

    public func audioModeSettings() async throws -> BossAudioModeSettingsConfig {
        try await Self.readAudioModeSettingsConfigAfterReconnect(connection: connection.securePreferred)
    }

    public func setAudioModeSettings(
        _ update: BossAudioModeSettingsConfigPatch
    ) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await Self.setAudioModeSettingsConfigWithVerification(update, connection: connection.securePreferred)
    }

    public func setCNCLevel(_ level: Int) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await setAudioModeSettings(BossAudioModeSettingsConfigPatch(cncLevel: level))
    }

    public func setSpatialAudioMode(_ mode: BossSpatialAudioMode) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await setAudioModeSettings(BossAudioModeSettingsConfigPatch(spatialAudioMode: mode))
    }

    public func setWindBlockEnabled(_ enabled: Bool) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await setAudioModeSettings(BossAudioModeSettingsConfigPatch(windBlockEnabled: enabled))
    }

    public func setANCEnabled(_ enabled: Bool) async throws -> BossAppleAudioModeSettingsWriteResult {
        try await setAudioModeSettings(BossAudioModeSettingsConfigPatch(ancToggleEnabled: enabled))
    }

    private func writeCustomAudioMode(
        slot: Int,
        name: String,
        settings: BossAudioModeSettingsConfig,
        prompt: BossAudioModePrompt
    ) async throws -> BossAudioModeConfig {
        try await Self.withConnectedLinkRetrying(connection.securePreferred, shouldRetry: Self.retrySecureCharacteristicIfNeeded) { link in
            try await Self.sendAudioModeConfigSetGet(
                modeIndex: slot,
                prompt: prompt,
                name: name,
                settings: settings,
                on: link,
                timeout: .seconds(5)
            )
        }
    }
}

extension BossAppleController {
    static func withConnectedLink<T: Sendable>(
        _ options: BossAppleConnectionOptions,
        operation: @escaping @Sendable (BleBmapLink) async throws -> T
    ) async throws -> T {
        try await withConnectedLinkRetrying(options, shouldRetry: { _, _ in false }, operation: operation)
    }

    static func withConnectedLinkRetrying<T: Sendable>(
        _ options: BossAppleConnectionOptions,
        shouldRetry: @escaping @Sendable (Error, AppleBossCharacteristicPreference) -> Bool,
        operation: @escaping @Sendable (BleBmapLink) async throws -> T
    ) async throws -> T {
        let preferences: [AppleBossCharacteristicPreference] = options.characteristicPreference == .automatic
            ? [.unsecure, .secure]
            : [options.characteristicPreference]
        var lastError: Error?

        for preference in preferences {
            let attemptOptions = options.withCharacteristicPreference(preference)
            do {
                return try await withConnectedLinkOnce(attemptOptions, operation: operation)
            } catch {
                lastError = error
                guard shouldRetry(error, preference) else {
                    throw error
                }
            }
        }

        throw lastError ?? AppleBleBossTransportError.transportClosed
    }

    static func withConnectedLinkOnce<T: Sendable>(
        _ options: BossAppleConnectionOptions,
        operation: @escaping @Sendable (BleBmapLink) async throws -> T
    ) async throws -> T {
        let transport = try await AppleBleBossTransport.connect(
            filter: options.scanFilter,
            characteristicPreference: options.characteristicPreference
        )
        defer {
            Task {
                await transport.close()
            }
        }
        let link = BleBmapLink(transport: transport)
        return try await operation(link)
    }

    static func nextResponse(
        from stream: AsyncThrowingStream<BmapPacket, Error>,
        matching predicate: @escaping @Sendable (BmapPacket) -> Bool,
        timeout: Duration
    ) async throws -> BmapPacket {
        try await withThrowingTaskGroup(of: BmapPacket.self) { group in
            group.addTask {
                for try await packet in stream {
                    if predicate(packet) {
                        return packet
                    }
                }
                throw BossAppleControlError.responseStreamEnded
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw BossAppleControlError.responseTimedOut(seconds: timeout.components.seconds)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    static func sendAndAwaitSameFunction(
        packet: BmapPacket,
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BmapPacket {
        try await link.send(packet: packet)
        let response = try await nextResponse(
            from: link.packets,
            matching: { incoming in
                incoming.functionBlock == packet.functionBlock &&
                incoming.function == packet.function &&
                incoming.operator.type == .response
            },
            timeout: timeout
        )
        if response.operator == .error {
            throw BossAppleControlError.bmapErrorResponse(
                context: "\(packet.functionBlock.displayName).\(packet.function.name)",
                payloadHex: hexString(response.payload)
            )
        }
        return response
    }
}

extension BossAppleController {
    static func awaitAudioModeConfigs(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> [BossAudioModeConfig] {
        try await link.send(packet: BossAudioModesCodec.modeConfigStartPacket())
        return try await withThrowingTaskGroup(of: [BossAudioModeConfig].self) { group in
            group.addTask {
                var modesByIndex: [Int: BossAudioModeConfig] = [:]
                for try await packet in link.packets {
                    guard packet.functionBlock == .audioModes,
                          packet.function.rawValue == BossAudioModesCodec.modeConfigFunctionRaw else {
                        continue
                    }
                    if packet.operator == .error {
                        throw BossAppleControlError.bmapErrorResponse(
                            context: "audioModes.\(packet.function.name)",
                            payloadHex: hexString(packet.payload)
                        )
                    }
                    if packet.operator == .result {
                        return modesByIndex.values.sorted { $0.modeIndex < $1.modeIndex }
                    }
                    guard packet.operator == .status else {
                        continue
                    }
                    let mode = try BossAudioModesCodec.parseModeConfigDetail(from: packet)
                    modesByIndex[mode.modeIndex] = mode
                }
                throw BossAppleControlError.responseStreamEnded
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw BossAppleControlError.responseTimedOut(seconds: timeout.components.seconds)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    static func firstFreeCustomAudioModeSlot(in configs: [BossAudioModeConfig]) -> Int? {
        configs
            .filter { $0.userConfigurable && !$0.userConfigured }
            .sorted { $0.modeIndex < $1.modeIndex }
            .first(where: { $0.name.isEmpty || $0.name.caseInsensitiveCompare("None") == .orderedSame })?
            .modeIndex
    }

    static func currentAudioModeIfAvailable(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> Int? {
        do {
            let response = try await sendAndAwaitSameFunction(
                packet: BossAudioModesCodec.currentModeGetPacket(),
                on: link,
                timeout: timeout
            )
            return try BossAudioModesCodec.parseCurrentMode(from: response)
        } catch {
            guard shouldFallbackForAudioModeWrite(error) else {
                throw error
            }
            return nil
        }
    }

    static func requiredCurrentAudioMode(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> Int {
        let response = try await sendAndAwaitSameFunction(
            packet: BossAudioModesCodec.currentModeGetPacket(),
            on: link,
            timeout: timeout
        )
        return try BossAudioModesCodec.parseCurrentMode(from: response)
    }

    static func requiredAudioModeSettingsConfig(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossAudioModeSettingsConfig {
        let response = try await sendAndAwaitSameFunction(
            packet: BossAudioModesCodec.settingsConfigGetPacket(),
            on: link,
            timeout: timeout
        )
        return try BossAudioModesCodec.parseSettingsConfig(from: response)
    }

    static func requiredFavoriteAudioModeIndices(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> [Int] {
        let response = try await sendAndAwaitSameFunction(
            packet: BossAudioModesCodec.favoritesGetPacket(),
            on: link,
            timeout: timeout
        )
        return try BossAudioModesCodec.parseFavorites(from: response)
    }

    static func requiredAudioModeCapabilities(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossAudioModesCapabilities {
        let response = try await sendAndAwaitSameFunction(
            packet: BossAudioModesCodec.capabilitiesGetPacket(),
            on: link,
            timeout: timeout
        )
        return try BossAudioModesCodec.parseCapabilities(from: response)
    }

    static func readAudioModeSettingsConfigAfterReconnect(
        connection: BossAppleConnectionOptions,
        attempts: Int = 3,
        retryDelay: Duration = .milliseconds(750)
    ) async throws -> BossAudioModeSettingsConfig {
        var lastError: Error = BossAppleControlError.responseTimedOut(seconds: 5)
        for attempt in 0..<attempts {
            do {
                return try await withConnectedLinkRetrying(connection, shouldRetry: retrySecureCharacteristicIfNeeded) { link in
                    try await readAudioModeSettingsConfig(on: link, attempts: 2, timeoutPerAttempt: .seconds(5), retryDelay: .milliseconds(300))
                }
            } catch {
                lastError = error
                guard isRecoverableAudioModeSettingsConfigError(error), attempt < attempts - 1 else {
                    throw error
                }
                try await Task.sleep(for: retryDelay)
            }
        }
        throw lastError
    }

    static func readAudioModeSettingsConfig(
        on link: BleBmapLink,
        attempts: Int,
        timeoutPerAttempt: Duration,
        retryDelay: Duration
    ) async throws -> BossAudioModeSettingsConfig {
        var lastError: Error = BossAppleControlError.responseTimedOut(seconds: timeoutPerAttempt.components.seconds)
        for attempt in 0..<attempts {
            do {
                return try await requiredAudioModeSettingsConfig(on: link, timeout: timeoutPerAttempt)
            } catch {
                lastError = error
                guard isRecoverableAudioModeSettingsConfigError(error), attempt < attempts - 1 else {
                    throw error
                }
                try await Task.sleep(for: retryDelay)
            }
        }
        throw lastError
    }

    static func setAudioModeSettingsConfigWithVerification(
        _ update: BossAudioModeSettingsConfigPatch,
        connection: BossAppleConnectionOptions
    ) async throws -> BossAppleAudioModeSettingsWriteResult {
        let current = try await readAudioModeSettingsConfigAfterReconnect(connection: connection)
        let target = update.merged(with: current)
        guard target != current else {
            return .unchanged(current)
        }

        var lastRecoverableError: Error?
        for attempt in 0..<2 {
            do {
                let updated = try await withConnectedLinkRetrying(connection, shouldRetry: retrySecureCharacteristicIfNeeded) { link in
                    try await sendAudioModeSettingsConfigSetGet(target, on: link, timeout: .seconds(5))
                }
                guard update.matches(updated) else {
                    throw BossAppleControlError.settingsConfigNotObserved(
                        expected: describe(target),
                        observed: describe(updated)
                    )
                }
                return .updated(updated)
            } catch {
                guard isRecoverableAudioModeSettingsConfigError(error) else {
                    throw error
                }
                lastRecoverableError = error

                do {
                    let verified = try await readAudioModeSettingsConfigAfterReconnect(connection: connection, attempts: 3)
                    if update.matches(verified) {
                        return .updated(verified)
                    }
                } catch {
                    lastRecoverableError = error
                }

                if attempt == 0 {
                    try await Task.sleep(for: .seconds(1))
                }
            }
        }

        _ = lastRecoverableError
        return .verificationInconclusive(target)
    }

    static func sendAudioModeSettingsConfigSetGet(
        _ config: BossAudioModeSettingsConfig,
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossAudioModeSettingsConfig {
        let packet = try BossAudioModesCodec.settingsConfigSetGetPacket(config)
        try await link.send(packet: packet)
        let response = try await nextResponse(
            from: link.packets,
            matching: { incoming in
                incoming.functionBlock == packet.functionBlock &&
                incoming.function == packet.function &&
                incoming.operator.type == .response
            },
            timeout: timeout
        )
        if response.operator == .error {
            throw BossAppleControlError.bmapErrorResponse(
                context: "\(packet.functionBlock.displayName).\(packet.function.name)",
                payloadHex: hexString(response.payload)
            )
        }
        return try BossAudioModesCodec.parseSettingsConfig(from: response)
    }

    static func sendAudioModeConfigSetGet(
        modeIndex: Int,
        prompt: BossAudioModePrompt,
        name: String,
        settings: BossAudioModeSettingsConfig,
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossAudioModeConfig {
        let packet = try BossAudioModesCodec.modeConfigSetGetPacket(
            modeIndex: modeIndex,
            prompt: prompt,
            name: name,
            settings: settings
        )
        let response = try await sendAndAwaitSameFunction(packet: packet, on: link, timeout: timeout)
        return try BossAudioModesCodec.parseModeConfigDetail(from: response)
    }

    static func sendAudioModeFavoritesSetGet(
        numberOfModes: Int,
        favoriteModeIndices: [Int],
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> [Int] {
        let packet = try BossAudioModesCodec.favoritesSetGetPacket(
            numberOfModes: numberOfModes,
            favoriteModeIndices: favoriteModeIndices
        )
        let response = try await sendAndAwaitSameFunction(packet: packet, on: link, timeout: timeout)
        return try BossAudioModesCodec.parseFavorites(from: response)
    }
}

extension BossAppleController {
    static func verifyCurrentAudioMode(
        on link: BleBmapLink,
        targetIndex: Int,
        timeoutPerAttempt: Duration,
        attempts: Int,
        retryDelay: Duration,
        fallbackError: Error? = nil
    ) async throws -> Int {
        var lastError: Error = fallbackError ?? BossAppleControlError.responseTimedOut(seconds: timeoutPerAttempt.components.seconds)
        var lastObservedIndex: Int?
        for attempt in 0..<attempts {
            do {
                let currentIndex = try await requiredCurrentAudioMode(on: link, timeout: timeoutPerAttempt)
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

    static func verifyCurrentAudioModeAfterReconnect(
        connection: BossAppleConnectionOptions,
        targetIndex: Int,
        fallbackError: Error
    ) async throws -> Int {
        var lastError: Error = fallbackError
        for attempt in 0..<4 {
            do {
                return try await withConnectedLinkRetrying(
                    connection,
                    shouldRetry: { error, preference in
                        guard preference == .unsecure else {
                            return false
                        }
                        return shouldFallbackForAudioModeWrite(error)
                    }
                ) { link in
                    try await verifyCurrentAudioMode(
                        on: link,
                        targetIndex: targetIndex,
                        timeoutPerAttempt: .seconds(3),
                        attempts: 3,
                        retryDelay: .milliseconds(750),
                        fallbackError: fallbackError
                    )
                }
            } catch {
                lastError = error
                if attempt < 3 {
                    try await Task.sleep(for: .seconds(1))
                }
            }
        }
        throw lastError
    }

    static func shouldFallbackForAudioModeWrite(_ error: Error) -> Bool {
        if let error = error as? BossAppleControlError {
            switch error {
            case .responseTimedOut, .responseStreamEnded:
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

    static func retrySecureCharacteristicIfNeeded(_ error: Error, _ preference: AppleBossCharacteristicPreference) -> Bool {
        guard preference == .unsecure else {
            return false
        }
        if case BossAppleControlError.responseTimedOut = error {
            return true
        }
        if case BossAppleControlError.bmapErrorResponse(_, let payloadHex) = error,
           bmapErrorCode(from: payloadHex) == .insecureTransport {
            return true
        }
        return false
    }

    static func isRecoverableAudioModeSettingsConfigError(_ error: Error) -> Bool {
        if shouldFallbackForAudioModeWrite(error) {
            return true
        }
        if let error = error as? BossAppleControlError {
            switch error {
            case .settingsConfigNotObserved:
                return true
            case .bmapErrorResponse(_, let payloadHex):
                return bmapErrorCode(from: payloadHex) == .insecureTransport ||
                    bmapErrorCode(from: payloadHex) == .timeout ||
                    bmapErrorCode(from: payloadHex) == .busy
            default:
                return false
            }
        }
        return false
    }

    static func isVerificationInconclusiveError(_ error: Error) -> Bool {
        if shouldFallbackForAudioModeWrite(error) {
            return true
        }
        if let error = error as? BossAppleControlError {
            switch error {
            case .bmapErrorResponse(_, let payloadHex):
                return bmapErrorCode(from: payloadHex) == .insecureTransport
            default:
                return false
            }
        }
        return false
    }

    static func bmapErrorCode(from payloadHex: String) -> BmapErrorCode? {
        guard payloadHex.count == 2, let rawValue = UInt8(payloadHex, radix: 16) else {
            return nil
        }
        return BmapErrorCode(rawValue: rawValue)
    }

    static func describe(_ config: BossAudioModeSettingsConfig) -> String {
        "cnc=\(config.cncLevel),autoCNC=\(config.autoCNCEnabled),spatial=\(config.spatialAudioMode.displayName),wind=\(config.windBlockEnabled),anc=\(config.ancToggleEnabled)"
    }

    static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}
