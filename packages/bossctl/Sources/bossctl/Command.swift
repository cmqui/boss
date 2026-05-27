import Foundation
import libbossApple

enum Command {
    case version
    case bootstrap(ConnectionOptions)
    case settings(SettingsCommand)
    case audioMode(AudioModeCommand)
    case stream(StreamCommand)
    case bmap(BmapCommand)

    static func parse<S: Sequence>(arguments: S) throws -> Command where S.Element == String {
        var args = Array(arguments)
        guard !args.isEmpty else {
            throw UsageError(Command.usage)
        }

        let head = args.removeFirst()
        switch head {
        case "-v", "--version", "version":
            return .version
        case "bootstrap":
            return .bootstrap(try ConnectionOptions.parse(arguments: args))
        case "settings":
            return .settings(try SettingsCommand.parse(arguments: args))
        case "audio-mode":
            return .audioMode(try AudioModeCommand.parse(arguments: args))
        case "stream":
            return .stream(try StreamCommand.parse(arguments: args))
        case "bmap":
            return .bmap(try BmapCommand.parse(arguments: args))
        case "--help", "-h", "help":
            throw UsageError(Command.usage, isHelp: true)
        default:
            throw UsageError(Command.usage)
        }
    }

    static let usage = """
    Usage:
      bossctl -h | --help
      bossctl -v | --version
      bossctl version
      bossctl bootstrap [connection options]
      bossctl settings get all [connection options]
      bossctl settings get standby-timer|auto-aware|on-head-detection|auto-play-pause|auto-answer|equalizer [connection options]
      bossctl settings set standby-timer --minutes <n> [connection options]
      bossctl settings set auto-aware --enabled <true|false> [connection options]
      bossctl settings set on-head-detection [--enabled <true|false>] [--auto-play <true|false>] [--auto-answer <true|false>] [--auto-transparency <true|false>] [connection options]
      bossctl settings set auto-play-pause --enabled <true|false> [connection options]
      bossctl settings set auto-answer --enabled <true|false> [connection options]
      bossctl settings get volume-control [connection options]
      bossctl settings set volume-control --mode <disabled|button|captouch|imu> [connection options]
      bossctl settings set equalizer [--bass <n>] [--mid <n>] [--treble <n>] [connection options]
      bossctl audio-mode list [connection options]
      bossctl audio-mode get current [connection options]
      bossctl audio-mode set current (--index <n> | --mode <name>) [--play-voice-prompt <true|false>] [connection options]
      bossctl audio-mode get settings-config [connection options]
      bossctl audio-mode set settings-config [--cnc <0-10>] [--auto-cnc <true|false>] [--spatial off|room|head] [--wind-block <true|false>] [--anc-toggle <true|false>] [connection options]
      bossctl audio-mode cnc --level <0-10> [connection options]
      bossctl audio-mode spatial off|room|head [connection options]
      bossctl audio-mode wind-block <true|false> [connection options]
      bossctl audio-mode anc <true|false> [connection options]
      bossctl audio-mode favorites [connection options]
      bossctl audio-mode favorite (--index <n> | --mode <name>) [connection options]
      bossctl audio-mode unfavorite (--index <n> | --mode <name>) [connection options]
      bossctl audio-mode delete (--index <n> | --mode <name>) [connection options]
      bossctl stream probe all|current-audio-mode|audio-mode-settings|equalizer|device-settings|audio-mode-catalog [--duration <seconds>] [connection options]
      bossctl bmap trace [--duration <seconds>] [connection options]
      bossctl bmap debug-current-mode [--duration <seconds>] [connection options]

    Connection options:
      --name <substring>
      --identifier <uuid>
      --timeout <seconds>
      --characteristic automatic|unsecure|secure

    Commands added during the Rust migration:
      bossctl stream probe ...
      bossctl bmap trace ...
      bossctl bmap debug-current-mode ...
    """
}
