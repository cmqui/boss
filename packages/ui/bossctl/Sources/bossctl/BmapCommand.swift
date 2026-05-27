import Foundation

struct BmapCommand {
    let connection: ConnectionOptions
    let action: BmapAction

    static func parse(arguments: [String]) throws -> BmapCommand {
        var args = arguments
        guard !args.isEmpty else {
            throw UsageError(Command.usage)
        }

        let verb = args.removeFirst()
        switch verb {
        case "trace":
            var parser = ArgumentParser(arguments: args)
            let durationSeconds = try parser.optionalInt(for: "--duration") ?? 30
            guard durationSeconds > 0 else {
                throw UsageError("Invalid duration for --duration: \(durationSeconds)")
            }
            let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
            return BmapCommand(connection: connection, action: .trace(durationSeconds: durationSeconds))
        case "debug-current-mode":
            var parser = ArgumentParser(arguments: args)
            let durationSeconds = try parser.optionalInt(for: "--duration") ?? 30
            guard durationSeconds > 0 else {
                throw UsageError("Invalid duration for --duration: \(durationSeconds)")
            }
            let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
            return BmapCommand(connection: connection, action: .debugCurrentMode(durationSeconds: durationSeconds))
        default:
            throw UsageError(Command.usage)
        }
    }
}

enum BmapAction {
    case trace(durationSeconds: Int)
    case debugCurrentMode(durationSeconds: Int)
}
