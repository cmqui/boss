import Foundation
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
        case .version:
            print("bossctl \(BossctlVersion.current)")

        case .bootstrap(let options):
            let description = bootstrapAttemptDescription(for: options)
            print("Bootstrapping \(description)...")
            print("Scan timeout per attempt: \(options.timeoutSeconds)s")
            if options.characteristicPreference == .automatic {
                print("Characteristic preference: automatic (may try unsecure, then secure)")
            } else {
                print("Characteristic preference: \(options.characteristicPreference.rawValue)")
            }
            fflush(stdout)
            let device = try await BossAppleSession(connection: options.appleConnectionOptions()).bootstrap()
            printBootstrap(device)

        case .settings(let command):
            let controller = BossAppleController(connection: command.connection.appleConnectionOptions())
            let session = BossAppleSession(connection: command.connection.appleConnectionOptions())
            switch command.action {
            case .getAll:
                let report = try await controller.deviceSettingsReport()
                printDeviceSettingsReport(report)

            case .getStandbyTimer:
                guard let parsed = try await controller.standbyTimer() else {
                    throw BossctlError.unsupportedSetting("standby-timer")
                }
                print("Standby timer: \(parsed.minutes) minute(s)")
                print("Supports two-byte minutes: \(parsed.supportsTwoByteMinutes)")

            case .setStandbyTimer(let minutes):
                let parsed = try await session.setStandbyTimer(minutes: minutes)
                print("Standby timer updated: \(parsed.minutes) minute(s)")

            case .getAutoAware:
                guard let isEnabled = try await controller.autoAware() else {
                    throw BossctlError.unsupportedSetting("auto-aware")
                }
                print("Auto-aware: \(isEnabled)")

            case .setAutoAware(let enabled):
                let updated = try await session.setAutoAware(enabled)
                print("Auto-aware updated: \(updated)")

            case .getOnHeadDetection:
                let report = try await controller.deviceSettingsReport()
                printWearDetectionSettingsReport(report)

            case .setOnHeadDetection(let patch):
                printWearDetectionFallbackPaths(for: patch)
                let report = try await controller.updateWearDetectionRelatedSettings(patch)
                printWearDetectionSettingsReport(report)

            case .getAutoPlayPause:
                guard let isEnabled = try await controller.autoPlayPause() else {
                    throw BossctlError.unsupportedSetting("auto-play-pause")
                }
                print("Auto-play-pause: \(isEnabled)")

            case .setAutoPlayPause(let enabled):
                let updated = try await session.setAutoPlayPause(enabled)
                print("Auto-play-pause updated: \(updated)")

            case .getAutoAnswer:
                guard let isEnabled = try await controller.autoAnswer() else {
                    throw BossctlError.unsupportedSetting("auto-answer")
                }
                print("Auto-answer: \(isEnabled)")

            case .setAutoAnswer(let enabled):
                let updated = try await session.setAutoAnswer(enabled)
                print("Auto-answer updated: \(updated)")

            case .getVolumeControl:
                guard let status = try await controller.volumeControl() else {
                    throw BossctlError.unsupportedSetting("volume-control")
                }
                print("Volume control: \(status.value.displayName)")
                if let supportedValues = status.supportedValues, !supportedValues.isEmpty {
                    print("Supported modes: \(supportedValues.map(\.displayName).joined(separator: ", "))")
                }

            case .setVolumeControl(let value):
                let status = try await session.setVolumeControl(value)
                print("Volume control updated: \(status.value.displayName)")
                if let supportedValues = status.supportedValues, !supportedValues.isEmpty {
                    print("Supported modes: \(supportedValues.map(\.displayName).joined(separator: ", "))")
                }

            case .getEqualizer:
                guard let settings = try await controller.equalizer() else {
                    throw BossctlError.unsupportedSetting("equalizer")
                }
                printEqualizer(settings)

            case .setEqualizer(let patch):
                let result = try await session.setEqualizer(patch)
                printEqualizerWriteResult(result)
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
                    let customMarker: String
                    let displayName: String
                    if mode.userConfigurable && mode.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        displayName = "<empty custom slot>"
                        customMarker = " reusable-custom-slot"
                    } else {
                        displayName = mode.name
                        customMarker = mode.userConfigured ? " user-configured" : (mode.userConfigurable ? " user-configurable" : "")
                    }
                    print("\(currentMarker) \(mode.modeIndex): \(displayName)\(favoriteMarker)\(customMarker)")
                }

            case .getCurrent:
                print("Current audio mode: \(try await controller.currentAudioMode())")

            case .setCurrent(let selection, let playVoicePrompt):
                let targetIndex = try await resolveAudioModeSelection(selection, controller: controller)
                let session = BossAppleSession(connection: command.connection.appleConnectionOptions())
                let result = try await session.setCurrentAudioMode(index: targetIndex, playVoicePrompt: playVoicePrompt)
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
                let session = BossAppleSession(connection: command.connection.appleConnectionOptions())
                let result = try await session.setAudioModeSettings(update)
                printAudioModeSettingsConfigWriteResult(result, output: output)

            case .getFavorites:
                let favorites = try await controller.favoriteAudioModeIndices()
                let modes = (try? await controller.displayableAudioModes()) ?? []
                printFavoriteAudioModes(favorites, modes: modes)

            case .setFavorite(let selection, let isFavorite):
                let targetIndex = try await resolveAudioModeSelection(selection, controller: controller)
                let session = BossAppleSession(connection: command.connection.appleConnectionOptions())
                let favorites = if isFavorite {
                    try await session.favoriteAudioMode(index: targetIndex)
                } else {
                    try await session.unfavoriteAudioMode(index: targetIndex)
                }
                let modes = (try? await controller.displayableAudioModes()) ?? []
                let action = isFavorite ? "favorited" : "unfavorited"
                print("Audio mode \(targetIndex) \(action)")
                printFavoriteAudioModes(favorites, modes: modes)

            case .delete(let selection):
                let targetIndex = try await resolveAudioModeSelection(selection, controller: controller)
                let session = BossAppleSession(connection: command.connection.appleConnectionOptions())
                let deleted = try await session.deleteCustomAudioMode(slot: targetIndex)
                let displayName = deleted.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "<empty custom slot>"
                    : deleted.name
                print("Deleted audio mode \(targetIndex): \(displayName)")
            }

        case .stream(let command):
            switch command.action {
            case .probe(let options):
                let session = BossAppleSession(connection: command.connection.appleConnectionOptions())
                try await runStreamProbe(options, session: session)
            }

        case .bmap(let command):
            switch command.action {
            case .trace(let durationSeconds):
                try await runBmapTrace(durationSeconds: durationSeconds, connection: command.connection.appleConnectionOptions())
            case .debugCurrentMode(let durationSeconds):
                let session = BossAppleSession(connection: command.connection.appleConnectionOptions())
                try await runCurrentModeDebug(durationSeconds: durationSeconds, session: session)
            }
        }
    }

    private static func bootstrapAttemptDescription(for options: ConnectionOptions) -> String {
        if let identifier = options.identifier {
            return "device \(identifier.uuidString)"
        }
        if let nameContains = options.nameContains, !nameContains.isEmpty {
            return "device matching \"\(nameContains)\""
        }
        return "nearby Bose device"
    }

    private static func runStreamProbe(
        _ options: StreamProbeOptions,
        session: BossAppleSession
    ) async throws {
        let targets = options.target == .all ? StreamProbeTarget.individualTargets : [options.target]
        print("Starting stream probe for \(options.target.displayName)")
        print("Duration: \(options.durationSeconds)s")
        print("Press Ctrl-C to stop early")

        var tasks: [Task<Void, Never>] = []
        for target in targets {
            tasks.append(await makeStreamProbeTask(target: target, session: session))
        }

        do {
            try await Task.sleep(for: .seconds(options.durationSeconds))
        } catch is CancellationError {
        }

        tasks.forEach { $0.cancel() }
        for task in tasks {
            await task.value
        }
        await session.close()
        print("Stream probe complete")
    }

    private static func makeStreamProbeTask(
        target: StreamProbeTarget,
        session: BossAppleSession
    ) async -> Task<Void, Never> {
        switch target {
        case .all:
            return Task {}
        case .currentAudioMode:
            return probeStream(
                label: target.displayName,
                stream: await session.currentAudioModeUpdateStream()
            ) { "modeIndex=\($0)" }
        case .audioModeSettings:
            return probeStream(
                label: target.displayName,
                stream: await session.audioModeSettingsUpdateStream()
            ) { describe($0) }
        case .equalizer:
            return probeStream(
                label: target.displayName,
                stream: await session.equalizerUpdateStream()
            ) { renderEqualizer($0) }
        case .deviceSettings:
            return probeStream(
                label: target.displayName,
                stream: await session.deviceSettingsUpdateStream()
            ) { renderDeviceSettingsReport($0) }
        case .audioModeCatalog:
            return probeStream(
                label: target.displayName,
                stream: await session.audioModeCatalogUpdateStream()
            ) { renderAudioModeCatalog($0) }
        }
    }

    private static func runBmapTrace(
        durationSeconds: Int,
        connection: BossAppleConnectionOptions
    ) async throws {
        print("Starting incoming BMAP trace")
        print("Duration: \(durationSeconds)s")
        print("Press hardware controls or use the Bose app during the trace window")

        let stream = BossAppleSession.bmapTraceStream(connection: connection)
        let task = Task {
            do {
                for try await event in stream {
                    printBmapTraceEvent(event)
                }
            } catch is CancellationError {
            } catch {
                fputs("BMAP trace error: \(error)\n", stderr)
            }
        }

        do {
            try await Task.sleep(for: .seconds(durationSeconds))
        } catch is CancellationError {
        }

        task.cancel()
        await task.value
        print("BMAP trace complete")
    }

    private static func runCurrentModeDebug(
        durationSeconds: Int,
        session: BossAppleSession
    ) async throws {
        print("Starting current-mode debug")
        print("Duration: \(durationSeconds)s")
        print("Watching typed current-mode updates and raw packets on the same session/transport")
        print("Press hardware controls during the window")

        let startedAt = ContinuousClock.now
        let rawStream = await session.rawPacketTraceUpdateStream()
        let typedStream = await session.currentAudioModeUpdateStream()

        let rawTask = Task<Void, Never> {
            do {
                for try await event in rawStream {
                    guard !Task.isCancelled else {
                        return
                    }
                    let output = BossctlBufferingOutputWriter()
                    printBmapTraceEvent(event, output: output)
                    let line = output.lines.joined(separator: " ")
                    print("[raw +\(elapsedMillis(since: startedAt))ms] \(line)")
                }
                if !Task.isCancelled {
                    print("[raw] stream ended")
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled {
                    print("[raw] error: \(error)")
                }
            }
        }

        let typedTask = Task<Void, Never> {
            do {
                for try await modeIndex in typedStream {
                    guard !Task.isCancelled else {
                        return
                    }
                    print("[typed +\(elapsedMillis(since: startedAt))ms] modeIndex=\(modeIndex)")
                }
                if !Task.isCancelled {
                    print("[typed] stream ended")
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled {
                    print("[typed] error: \(error)")
                }
            }
        }

        do {
            try await Task.sleep(for: .seconds(durationSeconds))
        } catch is CancellationError {
        }

        rawTask.cancel()
        typedTask.cancel()
        await rawTask.value
        await typedTask.value
        await session.close()
        print("Current-mode debug complete")
    }

    private static func probeStream<Element: Sendable>(
        label: String,
        stream: AsyncThrowingStream<Element, Error>,
        formatter: @escaping @Sendable (Element) -> String
    ) -> Task<Void, Never> {
        Task {
            do {
                for try await value in stream {
                    guard !Task.isCancelled else {
                        return
                    }
                    print("[\(label)] \(formatter(value))")
                }
                if !Task.isCancelled {
                    print("[\(label)] stream ended")
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled {
                    print("[\(label)] error: \(error)")
                }
            }
        }
    }

    private static func renderEqualizer(_ settings: BossAppleEqualizerSettings) -> String {
        settings.ranges
            .map { "\($0.band.displayName)=\($0.currentLevel)" }
            .joined(separator: ",")
    }

    private static func renderDeviceSettingsReport(_ report: BossAppleDeviceSettingsReport) -> String {
        let output = BossctlBufferingOutputWriter()
        printDeviceSettingsReport(report, output: output)
        return output.lines.joined(separator: " | ")
    }

    private static func renderAudioModeCatalog(_ modes: [BossAppleAudioModeConfig]) -> String {
        modes.map { mode in
            let trimmedName = mode.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmedName.isEmpty ? "<empty>" : trimmedName
            let flags = [
                mode.favorite ? "favorite" : nil,
                mode.userConfigurable ? "user-configurable" : nil,
                mode.userConfigured ? "user-configured" : nil,
            ]
            .compactMap { $0 }
            .joined(separator: ",")

            if flags.isEmpty {
                return "\(mode.modeIndex)=\(name)"
            }
            return "\(mode.modeIndex)=\(name) [\(flags)]"
        }
        .joined(separator: "; ")
    }
    private static func elapsedMillis(since start: ContinuousClock.Instant) -> Int {
        let duration = start.duration(to: .now).components
        return Int(duration.seconds * 1_000)
            + Int(duration.attoseconds / 1_000_000_000_000_000)
    }
}
