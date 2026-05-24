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
}
