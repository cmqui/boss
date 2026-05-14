import Foundation
import libboss
import libbossApple

enum Command {
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
      bossctl audio-mode get settings-config [connection options]
      bossctl audio-mode set settings-config [--cnc <0-10>] [--auto-cnc <true|false>] [--spatial off|room|head] [--wind-block <true|false>] [--anc-toggle <true|false>] [connection options]
      bossctl audio-mode cnc --level <0-10> [connection options]
      bossctl audio-mode spatial off|room|head [connection options]
      bossctl audio-mode wind-block <true|false> [connection options]
      bossctl audio-mode anc <true|false> [connection options]
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
