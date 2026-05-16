import Foundation
import libboss
import libbossApple

struct SettingsCommand {
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
            case "all":
                return SettingsCommand(connection: connection, action: .getAll)
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
            case "on-head-detection":
                let patch = try parser.onHeadDetectionPatch()
                let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
                return SettingsCommand(connection: connection, action: .setOnHeadDetection(patch))
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

enum SettingsAction {
    case getAll
    case getStandbyTimer
    case setStandbyTimer(Int)
    case getAutoAware
    case setAutoAware(Bool)
    case getOnHeadDetection
    case setOnHeadDetection(BossOnHeadDetectionPatch)
    case getAutoPlayPause
    case setAutoPlayPause(Bool)
    case getAutoAnswer
    case setAutoAnswer(Bool)
    case getVolumeControl
    case setVolumeControl(BossVolumeControlValue)
}
