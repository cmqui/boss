import Foundation
import libboss
import libbossApple

@main
struct BossctlCLI {
    private static let debugLoggingEnabled = ProcessInfo.processInfo.environment["LIBBOSS_APPLE_DEBUG"] == "1"

    static func main() async {
        do {
            let command = try Command.parse(arguments: CommandLine.arguments.dropFirst())
            try await run(command)
        } catch let error as UsageError {
            let stream: UnsafeMutablePointer<FILE> = error.isHelp ? stdout : stderr
            fputs("\(error.message)\n", stream)
            exit(error.isHelp ? 0 : 1)
        } catch {
            fputs("bossctl failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run(_ command: Command) async throws {
        switch command {
        case .bootstrap(let options):
            let device = try await withConnectedLink(options) { link in
                try await BootstrapSession(link: link).bootstrap()
            }
            printBootstrap(device)

        case .bmapSend(let options):
            try await withConnectedLink(options.connection) { link in
                let packet = options.packet
                print("Sending \(describe(packet))")
                try await link.send(packet: packet)
                let response = try await nextResponse(
                    from: link.packets,
                    matching: options.matchingMode.matches(packet),
                    timeout: .seconds(options.timeoutSeconds)
                )
                print("Received \(describe(response))")
                print("Payload hex: \(response.payload.hexString)")
                if let utf8 = String(data: response.payload, encoding: .utf8), !utf8.isEmpty {
                    print("Payload utf8: \(utf8)")
                }
            }

        case .bmapWatch(let options):
            try await withConnectedLink(options.connection) { link in
                var remaining = options.count
                for try await packet in link.packets {
                    print(describe(packet))
                    print("Payload hex: \(packet.payload.hexString)")
                    if let utf8 = String(data: packet.payload, encoding: .utf8), !utf8.isEmpty {
                        print("Payload utf8: \(utf8)")
                    }
                    if let currentRemaining = remaining {
                        let next = currentRemaining - 1
                        if next <= 0 {
                            break
                        }
                        remaining = next
                    }
                }
            }

        case .bmapTrace(let options):
            try await withConnectedLink(options.connection) { link in
                let packet = options.packet
                print("Tracing \(describe(packet))")
                try await link.send(packet: packet)
                try await tracePackets(
                    from: link.packets,
                    timeout: .seconds(options.listenSeconds),
                    predicate: options.matchingMode.matches(packet)
                )
            }

        case .bmapProbe(let options):
            try await withConnectedLink(options.connection) { link in
                for functionRaw in options.functionRange {
                    let block = BmapFunctionBlock(rawValue: options.blockRaw)
                    let function = BmapFunction(block: block, rawValue: functionRaw)
                    let packet = BmapPacket(
                        functionBlock: block,
                        function: function,
                        deviceID: options.deviceID,
                        port: options.port,
                        operator: options.operatorValue,
                        payload: options.payload
                    )

                    print("Probing \(describe(packet))")
                    try await link.send(packet: packet)

                    do {
                        let response = try await nextResponse(
                            from: link.packets,
                            matching: { incoming in
                                incoming.functionBlock == packet.functionBlock &&
                                incoming.function == packet.function &&
                                incoming.operator.type == .response
                            },
                            timeout: .milliseconds(options.responseTimeoutMilliseconds)
                        )
                        print("  -> \(response.operator.displayName) payload=\(response.payload.hexString)")
                        if let utf8 = String(data: response.payload, encoding: .utf8), !utf8.isEmpty {
                            print("     utf8=\(utf8)")
                        }
                    } catch let error as BossctlError where error.isTimeout {
                        print("  -> timeout")
                    }
                }
            }

        case .settings(let command):
            let connection = settingsConnectionOptions(for: command.connection)
            try await withConnectedLinkRetrying(connection) { error, preference in
                guard connection.characteristicPreference == .automatic,
                      preference == .unsecure else {
                    return false
                }
                if case BossctlError.responseTimedOut = error {
                    return true
                }
                if case BossctlError.bmapErrorResponse(_, let payloadHex) = error,
                   bmapErrorCode(from: payloadHex) == .insecureTransport {
                    return true
                }
                return false
            } operation: { link in
                switch command.action {
                case .getStandbyTimer:
                    let snapshot = try await awaitSettingsSnapshot(on: link, timeout: .seconds(5))
                    guard let parsed = try snapshot.standbyTimer() else {
                        throw BossctlError.unsupportedSetting("standby-timer")
                    }
                    print("Standby timer: \(parsed.minutes) minute(s)")
                    print("Supports two-byte minutes: \(parsed.supportsTwoByteMinutes)")

                case .setStandbyTimer(let minutes):
                    let response = try await sendAndAwaitSameFunction(
                        packet: BossSettingsCodec.settingsPacket(
                            functionRaw: BossSettingsCodec.standbyTimerFunctionRaw,
                            operatorValue: .setGet,
                            payload: BossSettingsCodec.encodeStandbyTimerMinutes(minutes)
                        ),
                        on: link,
                        timeout: .seconds(5)
                    )
                    let parsed = try BossSettingsCodec.parseStandbyTimer(from: response)
                    print("Standby timer updated: \(parsed.minutes) minute(s)")

                case .getAutoAware:
                    let snapshot = try await awaitSettingsSnapshot(on: link, timeout: .seconds(5))
                    guard let isEnabled = try snapshot.autoAware() else {
                        throw BossctlError.unsupportedSetting("auto-aware")
                    }
                    print("Auto-aware: \(isEnabled)")

                case .setAutoAware(let enabled):
                    let response = try await sendAndAwaitSameFunction(
                        packet: BossSettingsCodec.settingsPacket(
                            functionRaw: BossSettingsCodec.autoAwareFunctionRaw,
                            operatorValue: .setGet,
                            payload: Data([enabled ? 0x01 : 0x00])
                        ),
                        on: link,
                        timeout: .seconds(5)
                    )
                    print("Auto-aware updated: \(try BossSettingsCodec.parseEnabledFlag(from: response))")

                case .getOnHeadDetection:
                    let snapshot = try await awaitSettingsSnapshot(on: link, timeout: .seconds(5))
                    guard let parsed = try snapshot.onHeadDetection() else {
                        throw BossctlError.unsupportedSetting("on-head-detection")
                    }
                    print("On-head detection: \(parsed.isEnabled)")
                    print("Auto-play: \(formatOptionalBool(parsed.isAutoPlayEnabled))")
                    print("Auto-answer: \(formatOptionalBool(parsed.isAutoAnswerEnabled))")
                    print("Auto-transparency: \(formatOptionalBool(parsed.isAutoTransparencyEnabled))")

                case .getAutoPlayPause:
                    let snapshot = try await awaitSettingsSnapshot(on: link, timeout: .seconds(5))
                    guard let isEnabled = try snapshot.autoPlayPause() else {
                        throw BossctlError.unsupportedSetting("auto-play-pause")
                    }
                    print("Auto-play-pause: \(isEnabled)")

                case .setAutoPlayPause(let enabled):
                    let response = try await sendAndAwaitSameFunction(
                        packet: BossSettingsCodec.settingsPacket(
                            functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw,
                            operatorValue: .setGet,
                            payload: Data([enabled ? 0x01 : 0x00])
                        ),
                        on: link,
                        timeout: .seconds(5)
                    )
                    print("Auto-play-pause updated: \(try BossSettingsCodec.parseEnabledFlag(from: response))")

                case .getAutoAnswer:
                    let snapshot = try await awaitSettingsSnapshot(on: link, timeout: .seconds(5))
                    guard let isEnabled = try snapshot.autoAnswer() else {
                        throw BossctlError.unsupportedSetting("auto-answer")
                    }
                    print("Auto-answer: \(isEnabled)")

                case .setAutoAnswer(let enabled):
                    let response = try await sendAndAwaitSameFunction(
                        packet: BossSettingsCodec.settingsPacket(
                            functionRaw: BossSettingsCodec.autoAnswerFunctionRaw,
                            operatorValue: .setGet,
                            payload: Data([enabled ? 0x01 : 0x00])
                        ),
                        on: link,
                        timeout: .seconds(5)
                    )
                    print("Auto-answer updated: \(try BossSettingsCodec.parseEnabledFlag(from: response))")

                case .getVolumeControl:
                    let snapshot = try await awaitSettingsSnapshot(on: link, timeout: .seconds(5))
                    guard let status = try snapshot.volumeControl() else {
                        throw BossctlError.unsupportedSetting("volume-control")
                    }
                    print("Volume control: \(status.value.displayName)")

                case .setVolumeControl(let value):
                    let response = try await sendAndAwaitSameFunction(
                        packet: BossSettingsCodec.settingsPacket(
                            functionRaw: BossSettingsCodec.volumeControlFunctionRaw,
                            operatorValue: .setGet,
                            payload: Data([value.rawValue])
                        ),
                        on: link,
                        timeout: .seconds(5)
                    )
                    print("Volume control updated: \(try BossAudioModesCodec.parseVolumeControlStatus(from: response).value.displayName)")
                }
            }

        case .audioMode(let command):
            let connection = audioModeConnectionOptions(for: command)
            try await withConnectedLinkRetrying(connection) { error, preference in
                guard connection.characteristicPreference == .automatic,
                      preference == .unsecure else {
                    return false
                }
                if case BossctlError.responseTimedOut = error {
                    return true
                }
                if case BossctlError.bmapErrorResponse(_, let payloadHex) = error,
                   bmapErrorCode(from: payloadHex) == .insecureTransport {
                    return true
                }
                return false
            } operation: { link in
                switch command.action {
                case .list:
                    let modes = try await awaitAudioModeConfigs(on: link, timeout: .seconds(30))
                    let displayModes = displayableAudioModes(from: modes)
                    let currentIndex = try await currentAudioModeIfAvailable(on: link, timeout: .seconds(2))
                    if let currentIndex {
                        print("Current audio mode: \(currentIndex)")
                    } else {
                        print("Current audio mode: unavailable")
                    }
                    print("Available audio modes:")
                    for mode in displayModes {
                        let currentMarker = mode.modeIndex == currentIndex ? "*" : " "
                        let favoriteMarker = mode.favorite ? " favorite" : ""
                        let customMarker = mode.userConfigured ? " user-configured" : (mode.userConfigurable ? " user-configurable" : "")
                        print("\(currentMarker) \(mode.modeIndex): \(mode.name)\(favoriteMarker)\(customMarker)")
                    }

                case .getCurrent:
                    let response = try await sendAndAwaitSameFunction(
                        packet: BossAudioModesCodec.currentModeGetPacket(),
                        on: link,
                        timeout: .seconds(5)
                    )
                    print("Current audio mode: \(try BossAudioModesCodec.parseCurrentMode(from: response))")

                case .setCurrent(let selection, let playVoicePrompt):
                    let targetIndex = try await resolveAudioModeSelection(selection, on: link)
                    if let currentIndex = try await currentAudioModeIfAvailable(on: link, timeout: .seconds(2)),
                       currentIndex == targetIndex {
                        print("Current audio mode unchanged: \(currentIndex)")
                        return
                    }
                    let modeIndex: Int
                    do {
                        let response = try await sendAndAwaitSameFunction(
                            packet: BossAudioModesCodec.currentModeStartPacket(modeIndex: targetIndex, playVoicePrompt: playVoicePrompt),
                            on: link,
                            timeout: .seconds(5)
                        )
                        if response.operator == .result {
                            if let responseModeIndex = response.payload.first {
                                modeIndex = Int(responseModeIndex)
                            } else {
                                modeIndex = try await verifyCurrentAudioMode(
                                    on: link,
                                    targetIndex: targetIndex,
                                    timeoutPerAttempt: .seconds(2),
                                    attempts: 3,
                                    retryDelay: .milliseconds(500)
                                )
                            }
                        } else {
                            modeIndex = try BossAudioModesCodec.parseCurrentMode(from: response)
                        }
                    } catch {
                        guard shouldFallbackForAudioModeWrite(error) else {
                            throw error
                        }
                        debug("audio-mode set fallback triggered for target=\(targetIndex): \(error)")
                        do {
                            modeIndex = try await verifyCurrentAudioMode(
                                on: link,
                                targetIndex: targetIndex,
                                timeoutPerAttempt: .seconds(3),
                                attempts: 4,
                                retryDelay: .seconds(1),
                                fallbackError: error
                            )
                        } catch {
                            debug("in-link verification failed for target=\(targetIndex): \(error)")
                            do {
                                modeIndex = try await verifyCurrentAudioModeAfterReconnect(
                                    connection: command.connection,
                                    targetIndex: targetIndex,
                                    fallbackError: error
                                )
                            } catch let reconnectError {
                                if isVerificationInconclusiveError(reconnectError) {
                                    print("Current audio mode switch sent; verification inconclusive for target \(targetIndex)")
                                    return
                                }
                                throw reconnectError
                            }
                        }
                    }
                    print("Current audio mode updated: \(modeIndex)")
                }
            }
        }
    }

    private static func settingsConnectionOptions(for options: ConnectionOptions) -> ConnectionOptions {
        guard options.characteristicPreference == .automatic else {
            return options
        }
        return options.withCharacteristicPreference(.secure)
    }

    private static func audioModeConnectionOptions(for command: AudioModeCommand) -> ConnectionOptions {
        switch command.action {
        case .setCurrent:
            return settingsConnectionOptions(for: command.connection)
        case .list, .getCurrent:
            return command.connection
        }
    }

    private static func audioModeReadConnectionOptions(for options: ConnectionOptions) -> ConnectionOptions {
        options
    }

    private static func withConnectedLink<T: Sendable>(
        _ options: ConnectionOptions,
        operation: @escaping @Sendable (BleBmapLink) async throws -> T
    ) async throws -> T {
        try await withConnectedLinkRetrying(options, shouldRetry: { _, _ in false }, operation: operation)
    }

    private static func withConnectedLinkRetrying<T: Sendable>(
        _ options: ConnectionOptions,
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

    private static func withConnectedLinkOnce<T: Sendable>(
        _ options: ConnectionOptions,
        operation: @escaping @Sendable (BleBmapLink) async throws -> T
    ) async throws -> T {
        let filter = AppleBossScanFilter(
            peripheralIdentifier: options.identifier,
            nameContains: options.nameContains,
            scanTimeout: .seconds(options.timeoutSeconds)
        )
        let transport = try await AppleBleBossTransport.connect(
            filter: filter,
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

    private static func debug(_ message: String) {
        guard debugLoggingEnabled else {
            return
        }
        fputs("[bossctl] \(message)\n", stderr)
    }

    private static func nextResponse(
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
                throw BossctlError.responseStreamEnded
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw BossctlError.responseTimedOut(seconds: timeout.components.seconds)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func tracePackets(
        from stream: AsyncThrowingStream<BmapPacket, Error>,
        timeout: Duration,
        predicate: @escaping @Sendable (BmapPacket) -> Bool
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await packet in stream {
                    guard predicate(packet) else {
                        continue
                    }
                    print("Received \(describe(packet))")
                    print("Payload hex: \(packet.payload.hexString)")
                    if let utf8 = String(data: packet.payload, encoding: .utf8), !utf8.isEmpty {
                        print("Payload utf8: \(utf8)")
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private static func sendAndAwaitSameFunction(
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
            throw BossctlError.bmapErrorResponse(
                context: "\(packet.functionBlock.displayName).\(packet.function.name)",
                payloadHex: response.payload.hexString
            )
        }
        return response
    }

    private static func awaitSettingsSnapshot(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossSettingsSnapshot {
        try await link.send(packet: BossSettingsCodec.settingsPacket(functionRaw: BossSettingsCodec.settingsGetAllFunctionRaw, operatorValue: .start))
        return try await withThrowingTaskGroup(of: BossSettingsSnapshot.self) { group in
            group.addTask {
                var snapshot: [UInt8: BmapPacket] = [:]
                for try await packet in link.packets {
                    guard packet.functionBlock == .settings else {
                        continue
                    }
                    let rawFunction = packet.function.rawValue
                    if rawFunction == BossSettingsCodec.settingsGetAllFunctionRaw, packet.operator == .error {
                        throw BossctlError.bmapErrorResponse(
                            context: "settings.SettingsGetAll",
                            payloadHex: packet.payload.hexString
                        )
                    }
                    if rawFunction == BossSettingsCodec.settingsGetAllFunctionRaw, packet.operator == .result {
                        return BossSettingsSnapshot(packetsByFunctionRaw: snapshot)
                    }
                    guard packet.operator == .status else {
                        continue
                    }
                    snapshot[rawFunction] = packet
                }
                throw BossctlError.responseStreamEnded
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw BossctlError.responseTimedOut(seconds: timeout.components.seconds)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func awaitAudioModeConfigs(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> [BossAudioModeInfo] {
        try await link.send(packet: BossAudioModesCodec.modeConfigStartPacket())
        return try await withThrowingTaskGroup(of: [BossAudioModeInfo].self) { group in
            group.addTask {
                var modesByIndex: [Int: BossAudioModeInfo] = [:]
                for try await packet in link.packets {
                    guard packet.functionBlock == .audioModes,
                          packet.function.rawValue == BossAudioModesCodec.modeConfigFunctionRaw else {
                        continue
                    }
                    if packet.operator == .error {
                        throw BossctlError.bmapErrorResponse(
                            context: "audioModes.\(packet.function.name)",
                            payloadHex: packet.payload.hexString
                        )
                    }
                    if packet.operator == .result {
                        return modesByIndex.values.sorted { $0.modeIndex < $1.modeIndex }
                    }
                    guard packet.operator == .status else {
                        continue
                    }
                    let mode = try BossAudioModesCodec.parseModeConfig(from: packet)
                    modesByIndex[mode.modeIndex] = mode
                }
                throw BossctlError.responseStreamEnded
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw BossctlError.responseTimedOut(seconds: timeout.components.seconds)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func currentAudioModeIfAvailable(
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

    private static func requiredCurrentAudioMode(
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

    private static func verifyCurrentAudioMode(
        on link: BleBmapLink,
        targetIndex: Int,
        timeoutPerAttempt: Duration,
        attempts: Int,
        retryDelay: Duration,
        fallbackError: Error? = nil
    ) async throws -> Int {
        var lastError: Error = fallbackError ?? BossctlError.responseTimedOut(seconds: timeoutPerAttempt.components.seconds)
        var lastObservedIndex: Int?
        for attempt in 0..<attempts {
            do {
                debug("verifying current audio mode attempt \(attempt + 1)/\(attempts) target=\(targetIndex)")
                let currentIndex = try await requiredCurrentAudioMode(on: link, timeout: timeoutPerAttempt)
                debug("verification attempt \(attempt + 1) observed current mode=\(currentIndex)")
                lastObservedIndex = currentIndex
                if currentIndex == targetIndex {
                    return currentIndex
                }
            } catch {
                debug("verification attempt \(attempt + 1) failed: \(error)")
                lastError = error
            }
            if attempt < attempts - 1 {
                try await Task.sleep(for: retryDelay)
            }
        }
        if let lastObservedIndex {
            throw BossctlError.modeChangeNotObserved(targetIndex: targetIndex, observedIndex: lastObservedIndex)
        }
        throw fallbackError ?? lastError
    }

    private static func verifyCurrentAudioModeAfterReconnect(
        connection: ConnectionOptions,
        targetIndex: Int,
        fallbackError: Error
    ) async throws -> Int {
        var lastError: Error = fallbackError
        for attempt in 0..<4 {
            do {
                debug("reconnect verification attempt \(attempt + 1)/4 target=\(targetIndex)")
                let currentIndex = try await withConnectedLinkRetrying(
                    audioModeReadConnectionOptions(for: connection),
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
                debug("reconnect verification succeeded with mode=\(currentIndex)")
                return currentIndex
            } catch {
                debug("reconnect verification attempt \(attempt + 1) failed: \(error)")
                lastError = error
                try await Task.sleep(for: .seconds(1))
            }
        }
        throw lastError
    }

    private static func shouldFallbackForAudioModeWrite(_ error: Error) -> Bool {
        if let error = error as? BossctlError {
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

    private static func isVerificationInconclusiveError(_ error: Error) -> Bool {
        if shouldFallbackForAudioModeWrite(error) {
            return true
        }
        if let error = error as? BossctlError {
            switch error {
            case .bmapErrorResponse(_, let payloadHex):
                return bmapErrorCode(from: payloadHex) == .insecureTransport
            default:
                return false
            }
        }
        return false
    }

    private static func displayableAudioModes(from modes: [BossAudioModeInfo]) -> [BossAudioModeInfo] {
        modes.filter { mode in
            !(mode.userConfigurable && !mode.userConfigured && mode.name == "None")
        }
    }

    private static func resolveAudioModeSelection(
        _ selection: AudioModeSelection,
        on link: BleBmapLink
    ) async throws -> Int {
        switch selection {
        case .index(let index):
            return index
        case .name(let name):
            let normalizedTarget = normalizeAudioModeName(name)
            if let builtInIndex = builtInAudioModeIndex(for: normalizedTarget) {
                return builtInIndex
            }
            let modes = try await awaitAudioModeConfigs(on: link, timeout: .seconds(30))
            guard let match = displayableAudioModes(from: modes).first(where: {
                normalizeAudioModeName($0.name) == normalizedTarget
            }) else {
                throw UsageError("Unknown audio mode: \(name)")
            }
            return match.modeIndex
        }
    }

    private static func normalizeAudioModeName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func builtInAudioModeIndex(for normalizedName: String) -> Int? {
        switch normalizedName {
        case "quiet":
            return 0
        case "aware":
            return 1
        case "immersion":
            return 2
        case "cinema":
            return 3
        default:
            return nil
        }
    }

    private static func formatOptionalBool(_ value: Bool?) -> String {
        guard let value else { return "unsupported" }
        return value ? "enabled" : "disabled"
    }

    fileprivate static func bmapErrorCode(from payloadHex: String) -> BmapErrorCode? {
        guard payloadHex.count == 2, let rawValue = UInt8(payloadHex, radix: 16) else {
            return nil
        }
        return BmapErrorCode(rawValue: rawValue)
    }

    private static func printBootstrap(_ device: BootstrappedDevice) {
        print("Transport: \(device.transportKind.rawValue)")
        print("BMAP: \(device.bmapVersion.version)")
        print("Product: \(device.productName) (\(String(format: "0x%04X", device.productID)))")
        let variantLabel = device.productVariant.variantName ?? "Unknown"
        print("Variant: \(variantLabel) (raw=\(String(format: "0x%02X", device.productVariant.variant)))")
        let blocks = device.supportedFunctionBlocks.allBlocks().map(\.displayName).joined(separator: ", ")
        print("Function blocks: \(blocks)")
    }

    private static func describe(_ packet: BmapPacket) -> String {
        let encoded = (try? BmapCodec.encode(packet).hexString) ?? "<encode-failed>"
        return "packet block=\(packet.functionBlock.displayName)(0x\(String(format: "%02X", packet.functionBlock.rawValue))) " +
            "function=\(packet.function.name)(0x\(String(format: "%02X", packet.function.rawValue))) " +
            "op=\(packet.operator.displayName)(0x\(String(format: "%02X", packet.operator.rawValue))) " +
            "deviceID=\(packet.deviceID) port=\(packet.port) frame=\(encoded)"
    }
}

private enum Command {
    case bootstrap(ConnectionOptions)
    case bmapSend(BmapSendOptions)
    case bmapWatch(BmapWatchOptions)
    case bmapTrace(BmapTraceOptions)
    case bmapProbe(BmapProbeOptions)
    case settings(SettingsCommand)
    case audioMode(AudioModeCommand)

    static func parse<S: Sequence>(arguments: S) throws -> Command where S.Element == String {
        var args = Array(arguments)
        guard !args.isEmpty else {
            throw UsageError(Command.usage)
        }

        let head = args.removeFirst()
        switch head {
        case "bootstrap":
            return .bootstrap(try ConnectionOptions.parse(arguments: args))
        case "settings":
            return .settings(try SettingsCommand.parse(arguments: args))
        case "audio-mode":
            return .audioMode(try AudioModeCommand.parse(arguments: args))
        case "bmap":
            guard !args.isEmpty else {
                throw UsageError(Command.usage)
            }
            let subcommand = args.removeFirst()
            switch subcommand {
            case "send":
                return .bmapSend(try BmapSendOptions.parse(arguments: args))
            case "watch":
                return .bmapWatch(try BmapWatchOptions.parse(arguments: args))
            case "trace":
                return .bmapTrace(try BmapTraceOptions.parse(arguments: args))
            case "probe":
                return .bmapProbe(try BmapProbeOptions.parse(arguments: args))
            default:
                throw UsageError(Command.usage)
            }
        case "--help", "-h", "help":
            throw UsageError(Command.usage, isHelp: true)
        default:
            throw UsageError(Command.usage)
        }
    }

    static let usage = """
    Usage:
      bossctl bootstrap [connection options]
      bossctl settings get standby-timer|auto-aware|on-head-detection|auto-play-pause|auto-answer [connection options]
      bossctl settings set standby-timer --minutes <n> [connection options]
      bossctl settings set auto-aware --enabled <true|false> [connection options]
      bossctl settings set auto-play-pause --enabled <true|false> [connection options]
      bossctl settings set auto-answer --enabled <true|false> [connection options]
      bossctl settings get volume-control [connection options]
      bossctl settings set volume-control --mode <disabled|button|captouch|imu> [connection options]
      bossctl audio-mode list [connection options]
      bossctl audio-mode get current [connection options]
      bossctl audio-mode set current (--index <n> | --mode <name>) [--play-voice-prompt <true|false>] [connection options]
      bossctl bmap send --block <id> --function <id> --op <set|get|setGet|start|0x..> [--device-id <n>] [--port <n>] [--payload <hex>] [--match same|any] [--response-timeout <seconds>] [connection options]
      bossctl bmap trace --block <id> --function <id> --op <set|get|setGet|start|0x..> [--device-id <n>] [--port <n>] [--payload <hex>] [--match same|any] [--listen <seconds>] [connection options]
      bossctl bmap watch [--count <n>] [connection options]
      bossctl bmap probe --block <id> --functions <start-end> [--op <get|start|0x..>] [--device-id <n>] [--port <n>] [--payload <hex>] [--response-timeout-ms <n>] [connection options]

    Connection options:
      --name <substring>
      --identifier <uuid>
      --timeout <seconds>
      --characteristic automatic|unsecure|secure
    """
}

private struct ConnectionOptions {
    let nameContains: String?
    let identifier: UUID?
    let timeoutSeconds: Int
    let characteristicPreference: AppleBossCharacteristicPreference

    static func parse(arguments: [String]) throws -> ConnectionOptions {
        var parser = ArgumentParser(arguments: arguments)
        let nameContains = try parser.optionalValue(for: "--name")
        let identifier = try parser.optionalUUID(for: "--identifier")
        let timeoutSeconds = try parser.optionalInt(for: "--timeout") ?? 20
        let characteristicPreference = try parser.optionalCharacteristicPreference(for: "--characteristic") ?? .automatic
        try parser.finish()
        return ConnectionOptions(
            nameContains: nameContains,
            identifier: identifier,
            timeoutSeconds: timeoutSeconds,
            characteristicPreference: characteristicPreference
        )
    }

    func withCharacteristicPreference(_ preference: AppleBossCharacteristicPreference) -> ConnectionOptions {
        ConnectionOptions(
            nameContains: nameContains,
            identifier: identifier,
            timeoutSeconds: timeoutSeconds,
            characteristicPreference: preference
        )
    }
}

private struct BmapSendOptions {
    let connection: ConnectionOptions
    let packet: BmapPacket
    let matchingMode: ResponseMatchMode
    let timeoutSeconds: Int

    static func parse(arguments: [String]) throws -> BmapSendOptions {
        var parser = ArgumentParser(arguments: arguments)
        let blockRaw = try parser.requiredUInt8(for: "--block")
        let functionRaw = try parser.requiredUInt8(for: "--function")
        let operatorValue = try parser.requiredOperator(for: "--op")
        let deviceID = try parser.optionalInt(for: "--device-id") ?? 0
        let port = try parser.optionalInt(for: "--port") ?? 0
        let payload = try parser.optionalHexData(for: "--payload") ?? Data()
        let timeoutSeconds = try parser.optionalInt(for: "--response-timeout") ?? 5
        let matchingMode = try parser.optionalResponseMatchMode(for: "--match") ?? .sameFunction
        let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())

        let block = BmapFunctionBlock(rawValue: blockRaw)
        let function = BmapFunction(block: block, rawValue: functionRaw)
        return BmapSendOptions(
            connection: connection,
            packet: BmapPacket(
                functionBlock: block,
                function: function,
                deviceID: deviceID,
                port: port,
                operator: operatorValue,
                payload: payload
            ),
            matchingMode: matchingMode,
            timeoutSeconds: timeoutSeconds
        )
    }
}

private struct BmapWatchOptions {
    let connection: ConnectionOptions
    let count: Int?

    static func parse(arguments: [String]) throws -> BmapWatchOptions {
        var parser = ArgumentParser(arguments: arguments)
        let count = try parser.optionalInt(for: "--count")
        let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
        return BmapWatchOptions(connection: connection, count: count)
    }
}

private struct BmapTraceOptions {
    let connection: ConnectionOptions
    let packet: BmapPacket
    let matchingMode: ResponseMatchMode
    let listenSeconds: Int

    static func parse(arguments: [String]) throws -> BmapTraceOptions {
        var parser = ArgumentParser(arguments: arguments)
        let blockRaw = try parser.requiredUInt8(for: "--block")
        let functionRaw = try parser.requiredUInt8(for: "--function")
        let operatorValue = try parser.requiredOperator(for: "--op")
        let deviceID = try parser.optionalInt(for: "--device-id") ?? 0
        let port = try parser.optionalInt(for: "--port") ?? 0
        let payload = try parser.optionalHexData(for: "--payload") ?? Data()
        let listenSeconds = try parser.optionalInt(for: "--listen") ?? 5
        let matchingMode = try parser.optionalResponseMatchMode(for: "--match") ?? .any
        let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())

        let block = BmapFunctionBlock(rawValue: blockRaw)
        let function = BmapFunction(block: block, rawValue: functionRaw)
        return BmapTraceOptions(
            connection: connection,
            packet: BmapPacket(
                functionBlock: block,
                function: function,
                deviceID: deviceID,
                port: port,
                operator: operatorValue,
                payload: payload
            ),
            matchingMode: matchingMode,
            listenSeconds: listenSeconds
        )
    }
}

private struct BmapProbeOptions {
    let connection: ConnectionOptions
    let blockRaw: UInt8
    let functionRange: ClosedRange<UInt8>
    let operatorValue: BmapOperator
    let deviceID: Int
    let port: Int
    let payload: Data
    let responseTimeoutMilliseconds: Int

    static func parse(arguments: [String]) throws -> BmapProbeOptions {
        var parser = ArgumentParser(arguments: arguments)
        let blockRaw = try parser.requiredUInt8(for: "--block")
        let functionRange = try parser.requiredUInt8Range(for: "--functions")
        let operatorValue = try parser.optionalOperator(for: "--op") ?? .get
        let deviceID = try parser.optionalInt(for: "--device-id") ?? 0
        let port = try parser.optionalInt(for: "--port") ?? 0
        let payload = try parser.optionalHexData(for: "--payload") ?? Data()
        let responseTimeoutMilliseconds = try parser.optionalInt(for: "--response-timeout-ms") ?? 400
        let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
        return BmapProbeOptions(
            connection: connection,
            blockRaw: blockRaw,
            functionRange: functionRange,
            operatorValue: operatorValue,
            deviceID: deviceID,
            port: port,
            payload: payload,
            responseTimeoutMilliseconds: responseTimeoutMilliseconds
        )
    }
}

private struct SettingsCommand {
    let connection: ConnectionOptions
    let action: SettingsAction

    static func parse(arguments: [String]) throws -> SettingsCommand {
        var args = arguments
        guard !args.isEmpty else {
            throw UsageError(Command.usage)
        }
        let verb = args.removeFirst()
        switch verb {
        case "get":
            guard !args.isEmpty else { throw UsageError(Command.usage) }
            let key = args.removeFirst()
            let connection = try ConnectionOptions.parse(arguments: args)
            switch key {
            case "standby-timer":
                return SettingsCommand(connection: connection, action: .getStandbyTimer)
            case "auto-aware":
                return SettingsCommand(connection: connection, action: .getAutoAware)
            case "on-head-detection":
                return SettingsCommand(connection: connection, action: .getOnHeadDetection)
            case "auto-play-pause":
                return SettingsCommand(connection: connection, action: .getAutoPlayPause)
            case "auto-answer":
                return SettingsCommand(connection: connection, action: .getAutoAnswer)
            case "volume-control":
                return SettingsCommand(connection: connection, action: .getVolumeControl)
            default:
                throw UsageError("Unknown settings get target: \(key)")
            }
        case "set":
            guard !args.isEmpty else { throw UsageError(Command.usage) }
            let key = args.removeFirst()
            var parser = ArgumentParser(arguments: args)
            switch key {
            case "standby-timer":
                let minutes = try parser.requiredInt(for: "--minutes")
                let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
                return SettingsCommand(connection: connection, action: .setStandbyTimer(minutes))
            case "auto-aware":
                let enabled = try parser.requiredBool(for: "--enabled")
                let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
                return SettingsCommand(connection: connection, action: .setAutoAware(enabled))
            case "auto-play-pause":
                let enabled = try parser.requiredBool(for: "--enabled")
                let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
                return SettingsCommand(connection: connection, action: .setAutoPlayPause(enabled))
            case "auto-answer":
                let enabled = try parser.requiredBool(for: "--enabled")
                let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
                return SettingsCommand(connection: connection, action: .setAutoAnswer(enabled))
            case "volume-control":
                let value = try parser.requiredVolumeControlValue(for: "--mode")
                let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
                return SettingsCommand(connection: connection, action: .setVolumeControl(value))
            default:
                throw UsageError("Unknown settings set target: \(key)")
            }
        default:
            throw UsageError(Command.usage)
        }
    }
}

private enum SettingsAction {
    case getStandbyTimer
    case setStandbyTimer(Int)
    case getAutoAware
    case setAutoAware(Bool)
    case getOnHeadDetection
    case getAutoPlayPause
    case setAutoPlayPause(Bool)
    case getAutoAnswer
    case setAutoAnswer(Bool)
    case getVolumeControl
    case setVolumeControl(BossVolumeControlValue)
}

private struct AudioModeCommand {
    let connection: ConnectionOptions
    let action: AudioModeAction

    static func parse(arguments: [String]) throws -> AudioModeCommand {
        var args = arguments
        guard !args.isEmpty else {
            throw UsageError(Command.usage)
        }
        let verb = args.removeFirst()
        switch verb {
        case "list":
            let connection = try ConnectionOptions.parse(arguments: args)
            return AudioModeCommand(connection: connection, action: .list)
        case "get":
            guard !args.isEmpty else { throw UsageError(Command.usage) }
            let key = args.removeFirst()
            let connection = try ConnectionOptions.parse(arguments: args)
            switch key {
            case "current":
                return AudioModeCommand(connection: connection, action: .getCurrent)
            default:
                throw UsageError("Unknown audio-mode get target: \(key)")
            }
        case "set":
            guard !args.isEmpty else { throw UsageError(Command.usage) }
            let key = args.removeFirst()
            var parser = ArgumentParser(arguments: args)
            switch key {
            case "current":
                let selection = try parser.requiredAudioModeSelection()
                let playVoicePrompt = try parser.optionalBool(for: "--play-voice-prompt") ?? false
                let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
                return AudioModeCommand(connection: connection, action: .setCurrent(selection: selection, playVoicePrompt: playVoicePrompt))
            default:
                throw UsageError("Unknown audio-mode set target: \(key)")
            }
        default:
            throw UsageError(Command.usage)
        }
    }
}

private enum AudioModeAction {
    case list
    case getCurrent
    case setCurrent(selection: AudioModeSelection, playVoicePrompt: Bool)
}

private enum AudioModeSelection {
    case index(Int)
    case name(String)
}

private enum ResponseMatchMode: String {
    case sameFunction = "same"
    case any = "any"

    func matches(_ sentPacket: BmapPacket) -> @Sendable (BmapPacket) -> Bool {
        switch self {
        case .sameFunction:
            return { packet in
                packet.functionBlock == sentPacket.functionBlock &&
                packet.function == sentPacket.function &&
                packet.operator.type == .response
            }
        case .any:
            return { packet in packet.operator.type == .response }
        }
    }
}

private struct ArgumentParser {
    private var arguments: [String]

    init(arguments: [String]) {
        self.arguments = arguments
    }

    mutating func optionalValue(for flag: String) throws -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        guard index + 1 < arguments.count else {
            throw UsageError("Missing value for \(flag)")
        }
        let value = arguments[index + 1]
        arguments.removeSubrange(index...(index + 1))
        return value
    }

    mutating func optionalInt(for flag: String) throws -> Int? {
        guard let value = try optionalValue(for: flag) else {
            return nil
        }
        guard let parsed = Int(value) else {
            throw UsageError("Invalid integer for \(flag): \(value)")
        }
        return parsed
    }

    mutating func requiredInt(for flag: String) throws -> Int {
        guard let value = try optionalInt(for: flag) else {
            throw UsageError("Missing value for \(flag)")
        }
        return value
    }

    mutating func requiredBool(for flag: String) throws -> Bool {
        guard let value = try optionalValue(for: flag) else {
            throw UsageError("Missing value for \(flag)")
        }
        return try parseBool(value, flag: flag)
    }

    mutating func optionalBool(for flag: String) throws -> Bool? {
        guard let value = try optionalValue(for: flag) else {
            return nil
        }
        return try parseBool(value, flag: flag)
    }

    private func parseBool(_ value: String, flag: String) throws -> Bool {
        switch value.lowercased() {
        case "true", "1", "yes", "on":
            return true
        case "false", "0", "no", "off":
            return false
        default:
            throw UsageError("Invalid boolean for \(flag): \(value)")
        }
    }

    mutating func requiredVolumeControlValue(for flag: String) throws -> BossVolumeControlValue {
        guard let value = try optionalValue(for: flag) else {
            throw UsageError("Missing value for \(flag)")
        }
        switch value.lowercased() {
        case "disabled":
            return .disabled
        case "button":
            return .button
        case "captouch":
            return .capTouch
        case "imu":
            return .imu
        default:
            throw UsageError("Invalid volume control value for \(flag): \(value)")
        }
    }

    mutating func requiredAudioModeSelection() throws -> AudioModeSelection {
        let indexValue = try optionalValue(for: "--index")
        let modeValue = try optionalValue(for: "--mode")
        switch (indexValue, modeValue) {
        case let (.some(indexValue), nil):
            guard let parsed = Int(indexValue) else {
                throw UsageError("Invalid integer for --index: \(indexValue)")
            }
            return .index(parsed)
        case let (nil, .some(modeValue)):
            return .name(modeValue)
        case (nil, nil):
            throw UsageError("Missing value for --index or --mode")
        default:
            throw UsageError("Specify only one of --index or --mode")
        }
    }

    mutating func optionalUUID(for flag: String) throws -> UUID? {
        guard let value = try optionalValue(for: flag) else {
            return nil
        }
        guard let parsed = UUID(uuidString: value) else {
            throw UsageError("Invalid UUID for \(flag): \(value)")
        }
        return parsed
    }

    mutating func optionalHexData(for flag: String) throws -> Data? {
        guard let value = try optionalValue(for: flag) else {
            return nil
        }
        return try Data(hexString: value)
    }

    mutating func requiredUInt8(for flag: String) throws -> UInt8 {
        guard let value = try optionalValue(for: flag) else {
            throw UsageError("Missing value for \(flag)")
        }
        let raw = parseIntegerString(value)
        guard (0...Int(UInt8.max)).contains(raw) else {
            throw UsageError("Invalid byte for \(flag): \(value)")
        }
        return UInt8(raw)
    }

    mutating func requiredOperator(for flag: String) throws -> BmapOperator {
        guard let value = try optionalValue(for: flag) else {
            throw UsageError("Missing value for \(flag)")
        }
        return try parseOperator(value, flag: flag)
    }

    mutating func optionalOperator(for flag: String) throws -> BmapOperator? {
        guard let value = try optionalValue(for: flag) else {
            return nil
        }
        return try parseOperator(value, flag: flag)
    }

    private func parseOperator(_ value: String, flag: String) throws -> BmapOperator {
        switch value {
        case "set": return .set
        case "get": return .get
        case "setGet": return .setGet
        case "status": return .status
        case "error": return .error
        case "start": return .start
        case "result": return .result
        case "processing": return .processing
        default:
            let parsed = parseIntegerString(value)
            guard (0...Int(UInt8.max)).contains(parsed) else {
                throw UsageError("Invalid operator for \(flag): \(value)")
            }
            return BmapOperator(rawValue: UInt8(parsed))
        }
    }

    mutating func requiredUInt8Range(for flag: String) throws -> ClosedRange<UInt8> {
        guard let value = try optionalValue(for: flag) else {
            throw UsageError("Missing value for \(flag)")
        }
        let parts = value.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw UsageError("Invalid range for \(flag): \(value)")
        }
        let lower = parseIntegerString(parts[0])
        let upper = parseIntegerString(parts[1])
        guard (0...Int(UInt8.max)).contains(lower),
              (0...Int(UInt8.max)).contains(upper),
              lower <= upper else {
            throw UsageError("Invalid range for \(flag): \(value)")
        }
        return UInt8(lower)...UInt8(upper)
    }

    mutating func optionalResponseMatchMode(for flag: String) throws -> ResponseMatchMode? {
        guard let value = try optionalValue(for: flag) else {
            return nil
        }
        guard let mode = ResponseMatchMode(rawValue: value) else {
            throw UsageError("Invalid value for \(flag): \(value)")
        }
        return mode
    }

    mutating func optionalCharacteristicPreference(for flag: String) throws -> AppleBossCharacteristicPreference? {
        guard let value = try optionalValue(for: flag) else {
            return nil
        }
        guard let preference = AppleBossCharacteristicPreference(rawValue: value) else {
            throw UsageError("Invalid value for \(flag): \(value)")
        }
        return preference
    }

    mutating func finish() throws {
        if !arguments.isEmpty {
            throw UsageError("Unknown arguments: \(arguments.joined(separator: " "))")
        }
    }

    mutating func remainingArguments() -> [String] {
        defer { arguments.removeAll() }
        return arguments
    }
}

private struct UsageError: LocalizedError {
    let message: String
    let isHelp: Bool

    init(_ message: String, isHelp: Bool = false) {
        self.message = message
        self.isHelp = isHelp
    }

    var errorDescription: String? { message }
}

private enum BossctlError: LocalizedError {
    case responseStreamEnded
    case responseTimedOut(seconds: Int64)
    case unexpectedResponse(String)
    case bmapErrorResponse(context: String, payloadHex: String)
    case unsupportedSetting(String)
    case modeChangeNotObserved(targetIndex: Int, observedIndex: Int)

    var errorDescription: String? {
        switch self {
        case .responseStreamEnded:
            return "Response stream ended before a matching packet was received"
        case .responseTimedOut(let seconds):
            return "Timed out waiting for a matching response after \(seconds) seconds"
        case .unexpectedResponse(let operatorName):
            return "Unexpected response operator: \(operatorName)"
        case .bmapErrorResponse(let context, let payloadHex):
            if let errorCode = BossctlCLI.bmapErrorCode(from: payloadHex) {
                return "BMAP error response for \(context): payload=\(payloadHex) (\(errorCode.description))"
            }
            return "BMAP error response for \(context): payload=\(payloadHex)"
        case .unsupportedSetting(let settingName):
            return "Setting is not exposed by this device/session: \(settingName)"
        case .modeChangeNotObserved(let targetIndex, let observedIndex):
            return "Mode change was not observed: target=\(targetIndex), observed=\(observedIndex)"
        }
    }

    var isTimeout: Bool {
        if case .responseTimedOut = self {
            return true
        }
        return false
    }
}

fileprivate enum BmapErrorCode: UInt8 {
    case length = 0x01
    case chksum = 0x02
    case fblockNotSupp = 0x03
    case funcNotSupp = 0x04
    case opNotSupp = 0x05
    case invalidData = 0x06
    case dataUnavailable = 0x07
    case runtime = 0x08
    case timeout = 0x09
    case invalidState = 0x0A
    case deviceNotFound = 0x0B
    case busy = 0x0C
    case noconnTimeout = 0x0D
    case noconnKey = 0x0E
    case otaUpdate = 0x0F
    case otaLowBatt = 0x10
    case otaNoCharger = 0x11
    case otaUpdateNotAllowed = 0x12
    case unknownPortNumber = 0x13
    case insecureTransport = 0x14
    case invalidOtpKey = 0x15
    case fblockSpecific = 0xFF

    var description: String {
        switch self {
        case .length: "Length"
        case .chksum: "Chksum"
        case .fblockNotSupp: "FblockNotSupp"
        case .funcNotSupp: "FuncNotSupp"
        case .opNotSupp: "OpNotSupp"
        case .invalidData: "InvalidData"
        case .dataUnavailable: "DataUnavailable"
        case .runtime: "Runtime"
        case .timeout: "Timeout"
        case .invalidState: "InvalidState"
        case .deviceNotFound: "DeviceNotFound"
        case .busy: "Busy"
        case .noconnTimeout: "NoconnTimeout"
        case .noconnKey: "NoconnKey"
        case .otaUpdate: "OtaUpdate"
        case .otaLowBatt: "OtaLowBatt"
        case .otaNoCharger: "OtaNoCharger"
        case .otaUpdateNotAllowed: "OtaUpdateNotAllowed"
        case .unknownPortNumber: "UnknownPortNumber"
        case .insecureTransport: "InsecureTransport"
        case .invalidOtpKey: "InvalidOtpKey"
        case .fblockSpecific: "FblockSpecific"
        }
    }
}

private extension Data {
    init(hexString: String) throws {
        let normalized = hexString
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")

        guard normalized.count.isMultiple(of: 2) else {
            throw UsageError("Hex payload must contain an even number of characters")
        }

        var data = Data()
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            let byteString = normalized[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else {
                throw UsageError("Invalid hex payload: \(hexString)")
            }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }

    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}

private extension BmapFunctionBlock {
    var displayName: String {
        switch self {
        case .productInfo: "productInfo"
        case .settings: "settings"
        case .status: "status"
        case .firmwareUpdate: "firmwareUpdate"
        case .deviceManagement: "deviceManagement"
        case .audioManagement: "audioManagement"
        case .callManagement: "callManagement"
        case .control: "control"
        case .debug: "debug"
        case .notification: "notification"
        case .reservedBosebuild1: "reservedBosebuild1"
        case .reservedBosebuild2: "reservedBosebuild2"
        case .hearingAssistance: "hearingAssistance"
        case .dataCollection: "dataCollection"
        case .heartRate: "heartRate"
        case .peerBud: "peerBud"
        case .vpa: "vpa"
        case .wifi: "wifi"
        case .authentication: "authentication"
        case .experimental: "experimental"
        case .cloud: "cloud"
        case .augmentedReality: "augmentedReality"
        case .print: "print"
        case .audioModes: "audioModes"
        case .unknown(let rawValue): "unknown(\(rawValue))"
        }
    }
}

private extension BmapOperator {
    var displayName: String {
        switch self {
        case .set: "set"
        case .get: "get"
        case .setGet: "setGet"
        case .status: "status"
        case .error: "error"
        case .start: "start"
        case .result: "result"
        case .processing: "processing"
        case .unknown(let rawValue): "unknown(\(rawValue))"
        }
    }
}

private func parseIntegerString(_ value: String) -> Int {
    if value.lowercased().hasPrefix("0x") {
        Int(value.dropFirst(2), radix: 16) ?? -1
    } else {
        Int(value) ?? -1
    }
}
