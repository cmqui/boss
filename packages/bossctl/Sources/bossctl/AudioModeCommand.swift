import Foundation
import libboss
import libbossApple

struct AudioModeCommand {
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
            case "settings-config":
                return AudioModeCommand(connection: connection, action: .getSettingsConfig)
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
            case "settings-config":
                let update = try parser.audioModeSettingsConfigUpdate()
                let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
                return AudioModeCommand(connection: connection, action: .setSettingsConfig(update, output: .full))
            default:
                throw UsageError("Unknown audio-mode set target: \(key)")
            }
        case "cnc":
            var parser = ArgumentParser(arguments: args)
            let level = try parser.requiredInt(for: "--level")
            guard (0...10).contains(level) else {
                throw UsageError("Invalid CNC level for --level: \(level)")
            }
            let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
            return AudioModeCommand(
                connection: connection,
                action: .setSettingsConfig(
                    BossAudioModeSettingsConfigPatch(cncLevel: level),
                    output: .field(.cncLevel)
                )
            )
        case "spatial":
            var parser = ArgumentParser(arguments: args)
            let mode = try parser.requiredSpatialAudioMode()
            let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
            return AudioModeCommand(
                connection: connection,
                action: .setSettingsConfig(
                    BossAudioModeSettingsConfigPatch(spatialAudioMode: mode),
                    output: .field(.spatialAudio)
                )
            )
        case "wind-block":
            var parser = ArgumentParser(arguments: args)
            let enabled = try parser.requiredBoolValue(label: "wind-block")
            let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
            return AudioModeCommand(
                connection: connection,
                action: .setSettingsConfig(
                    BossAudioModeSettingsConfigPatch(windBlockEnabled: enabled),
                    output: .field(.windBlock)
                )
            )
        case "anc":
            var parser = ArgumentParser(arguments: args)
            let enabled = try parser.requiredBoolValue(label: "anc")
            let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
            return AudioModeCommand(
                connection: connection,
                action: .setSettingsConfig(
                    BossAudioModeSettingsConfigPatch(ancToggleEnabled: enabled),
                    output: .field(.ancToggle)
                )
            )
        default:
            throw UsageError(Command.usage)
        }
    }
}

enum AudioModeAction {
    case list
    case getCurrent
    case setCurrent(selection: AudioModeSelection, playVoicePrompt: Bool)
    case getSettingsConfig
    case setSettingsConfig(BossAudioModeSettingsConfigPatch, output: AudioModeSettingsOutput)
}

enum AudioModeSelection {
    case index(Int)
    case name(String)
}

enum AudioModeSettingsWriteState {
    case unchanged
    case updated
    case verificationInconclusive
}

enum AudioModeSettingsOutput {
    case full
    case field(AudioModeSettingsField)
}

enum AudioModeSettingsField {
    case cncLevel
    case spatialAudio
    case windBlock
    case ancToggle

    var label: String {
        switch self {
        case .cncLevel: "CNC level"
        case .spatialAudio: "Spatial audio"
        case .windBlock: "Wind block"
        case .ancToggle: "ANC toggle"
        }
    }

    func value(from config: BossAudioModeSettingsConfig) -> String {
        switch self {
        case .cncLevel:
            return "\(config.cncLevel) (0=max ANC, 10=most ambient)"
        case .spatialAudio:
            return config.spatialAudioMode.displayName
        case .windBlock:
            return "\(config.windBlockEnabled)"
        case .ancToggle:
            return "\(config.ancToggleEnabled)"
        }
    }
}
