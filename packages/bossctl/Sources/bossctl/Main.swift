import Foundation
import libboss

@main
struct BossctlCLI {
    static let debugLoggingEnabled = ProcessInfo.processInfo.environment["LIBBOSS_APPLE_DEBUG"] == "1"

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
            switch command.action {
            case .getSettingsConfig:
                let config = try await readAudioModeSettingsConfigAfterReconnect(connection: connection)
                printAudioModeSettingsConfig(config)
                return

            case .setSettingsConfig(let update, let output):
                let result = try await setAudioModeSettingsConfigWithVerification(update, connection: connection)
                printAudioModeSettingsConfigWriteResult(result, output: output)
                return

            default:
                break
            }

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

                case .getSettingsConfig:
                    preconditionFailure("settings-config reads are handled by the hardened reconnect path")

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

                case .setSettingsConfig:
                    preconditionFailure("settings-config writes are handled by the hardened reconnect path")
                }
            }
        }
    }
}
