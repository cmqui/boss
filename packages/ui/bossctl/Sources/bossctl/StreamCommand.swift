import Foundation

struct StreamCommand {
    let connection: ConnectionOptions
    let action: StreamAction

    static func parse(arguments: [String]) throws -> StreamCommand {
        var args = arguments
        guard !args.isEmpty else {
            throw UsageError(Command.usage)
        }

        let verb = args.removeFirst()
        switch verb {
        case "probe":
            guard !args.isEmpty else {
                throw UsageError("Missing stream probe target")
            }
            let target = try StreamProbeTarget.parse(args.removeFirst())
            var parser = ArgumentParser(arguments: args)
            let durationSeconds = try parser.optionalInt(for: "--duration") ?? 30
            guard durationSeconds > 0 else {
                throw UsageError("Invalid duration for --duration: \(durationSeconds)")
            }
            let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
            return StreamCommand(
                connection: connection,
                action: .probe(StreamProbeOptions(target: target, durationSeconds: durationSeconds))
            )
        default:
            throw UsageError(Command.usage)
        }
    }
}

enum StreamAction {
    case probe(StreamProbeOptions)
}

struct StreamProbeOptions {
    let target: StreamProbeTarget
    let durationSeconds: Int
}

enum StreamProbeTarget: CaseIterable, Equatable {
    case all
    case currentAudioMode
    case audioModeSettings
    case equalizer
    case deviceSettings
    case audioModeCatalog

    static func parse(_ rawValue: String) throws -> StreamProbeTarget {
        switch rawValue {
        case "all":
            return .all
        case "current-audio-mode":
            return .currentAudioMode
        case "audio-mode-settings":
            return .audioModeSettings
        case "equalizer":
            return .equalizer
        case "device-settings":
            return .deviceSettings
        case "audio-mode-catalog":
            return .audioModeCatalog
        default:
            throw UsageError("Unknown stream probe target: \(rawValue)")
        }
    }

    var displayName: String {
        switch self {
        case .all:
            return "all"
        case .currentAudioMode:
            return "current-audio-mode"
        case .audioModeSettings:
            return "audio-mode-settings"
        case .equalizer:
            return "equalizer"
        case .deviceSettings:
            return "device-settings"
        case .audioModeCatalog:
            return "audio-mode-catalog"
        }
    }

    static var individualTargets: [StreamProbeTarget] {
        allCases.filter { $0 != .all }
    }
}
