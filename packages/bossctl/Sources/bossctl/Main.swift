import Foundation
import libboss
import libbossApple

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
            let controller = BossAppleController(connection: command.connection.appleConnectionOptions())
            switch command.action {
            case .list:
                let modes = try await controller.displayableAudioModes()
                let currentIndex = try? await controller.currentAudioMode()
                if let currentIndex {
                    print("Current audio mode: \(currentIndex)")
                } else {
                    print("Current audio mode: unavailable")
                }
                print("Available audio modes:")
                for mode in modes {
                    let currentMarker = mode.modeIndex == currentIndex ? "*" : " "
                    let favoriteMarker = mode.favorite ? " favorite" : ""
                    let customMarker = mode.userConfigured ? " user-configured" : (mode.userConfigurable ? " user-configurable" : "")
                    print("\(currentMarker) \(mode.modeIndex): \(mode.name)\(favoriteMarker)\(customMarker)")
                }

            case .getCurrent:
                print("Current audio mode: \(try await controller.currentAudioMode())")

            case .setCurrent(let selection, let playVoicePrompt):
                let targetIndex = try await resolveAudioModeSelection(selection, controller: controller)
                let result = try await controller.setCurrentAudioMode(index: targetIndex, playVoicePrompt: playVoicePrompt)
                switch result {
                case .unchanged(let modeIndex):
                    print("Current audio mode unchanged: \(modeIndex)")
                case .updated(let modeIndex):
                    print("Current audio mode updated: \(modeIndex)")
                case .verificationInconclusive(let targetIndex):
                    print("Current audio mode switch sent; verification inconclusive for target \(targetIndex)")
                }

            case .getSettingsConfig:
                let config = try await controller.audioModeSettings()
                printAudioModeSettingsConfig(config)

            case .setSettingsConfig(let update, let output):
                let result = try await controller.setAudioModeSettings(update)
                printAudioModeSettingsConfigWriteResult(result, output: output)

            case .getFavorites:
                let favorites = try await controller.favoriteAudioModeIndices()
                let modes = (try? await controller.displayableAudioModes()) ?? []
                printFavoriteAudioModes(favorites, modes: modes)

            case .setFavorite(let selection, let isFavorite):
                let targetIndex = try await resolveAudioModeSelection(selection, controller: controller)
                let favorites = try await controller.setAudioModeFavorite(index: targetIndex, isFavorite: isFavorite)
                let modes = (try? await controller.displayableAudioModes()) ?? []
                let action = isFavorite ? "favorited" : "unfavorited"
                print("Audio mode \(targetIndex) \(action)")
                printFavoriteAudioModes(favorites, modes: modes)
            }
        }
    }
}
