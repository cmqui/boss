import Foundation
import libboss
import libbossApple

struct BmapSendOptions {
    let connection: ConnectionOptions
    let packet: BmapPacket
    let matchingMode: ResponseMatchMode
    let timeoutSeconds: Int

    static func parse(arguments: [String]) throws -> BmapSendOptions {
        var parser = ArgumentParser(arguments: arguments)
        let blockRaw = try parser.requiredUInt8(for: "--block")
        let functionRaw = try parser.requiredUInt8(for: "--function")
        let operatorValue = try parser.requiredOperator(for: "--op")
        let deviceID = try parser.optionalInt(for: "--device-id") ?? 0
        let port = try parser.optionalInt(for: "--port") ?? 0
        let payload = try parser.optionalHexData(for: "--payload") ?? Data()
        let timeoutSeconds = try parser.optionalInt(for: "--response-timeout") ?? 5
        let matchingMode = try parser.optionalResponseMatchMode(for: "--match") ?? .sameFunction
        let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())

        let block = BmapFunctionBlock(rawValue: blockRaw)
        let function = BmapFunction(block: block, rawValue: functionRaw)
        return BmapSendOptions(
            connection: connection,
            packet: BmapPacket(
                functionBlock: block,
                function: function,
                deviceID: deviceID,
                port: port,
                operator: operatorValue,
                payload: payload
            ),
            matchingMode: matchingMode,
            timeoutSeconds: timeoutSeconds
        )
    }
}

struct BmapWatchOptions {
    let connection: ConnectionOptions
    let count: Int?

    static func parse(arguments: [String]) throws -> BmapWatchOptions {
        var parser = ArgumentParser(arguments: arguments)
        let count = try parser.optionalInt(for: "--count")
        let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
        return BmapWatchOptions(connection: connection, count: count)
    }
}

struct BmapTraceOptions {
    let connection: ConnectionOptions
    let packet: BmapPacket
    let matchingMode: ResponseMatchMode
    let listenSeconds: Int

    static func parse(arguments: [String]) throws -> BmapTraceOptions {
        var parser = ArgumentParser(arguments: arguments)
        let blockRaw = try parser.requiredUInt8(for: "--block")
        let functionRaw = try parser.requiredUInt8(for: "--function")
        let operatorValue = try parser.requiredOperator(for: "--op")
        let deviceID = try parser.optionalInt(for: "--device-id") ?? 0
        let port = try parser.optionalInt(for: "--port") ?? 0
        let payload = try parser.optionalHexData(for: "--payload") ?? Data()
        let listenSeconds = try parser.optionalInt(for: "--listen") ?? 5
        let matchingMode = try parser.optionalResponseMatchMode(for: "--match") ?? .any
        let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())

        let block = BmapFunctionBlock(rawValue: blockRaw)
        let function = BmapFunction(block: block, rawValue: functionRaw)
        return BmapTraceOptions(
            connection: connection,
            packet: BmapPacket(
                functionBlock: block,
                function: function,
                deviceID: deviceID,
                port: port,
                operator: operatorValue,
                payload: payload
            ),
            matchingMode: matchingMode,
            listenSeconds: listenSeconds
        )
    }
}

struct BmapProbeOptions {
    let connection: ConnectionOptions
    let blockRaw: UInt8
    let functionRange: ClosedRange<UInt8>
    let operatorValue: BmapOperator
    let deviceID: Int
    let port: Int
    let payload: Data
    let responseTimeoutMilliseconds: Int

    static func parse(arguments: [String]) throws -> BmapProbeOptions {
        var parser = ArgumentParser(arguments: arguments)
        let blockRaw = try parser.requiredUInt8(for: "--block")
        let functionRange = try parser.requiredUInt8Range(for: "--functions")
        let operatorValue = try parser.optionalOperator(for: "--op") ?? .get
        let deviceID = try parser.optionalInt(for: "--device-id") ?? 0
        let port = try parser.optionalInt(for: "--port") ?? 0
        let payload = try parser.optionalHexData(for: "--payload") ?? Data()
        let responseTimeoutMilliseconds = try parser.optionalInt(for: "--response-timeout-ms") ?? 400
        let connection = try ConnectionOptions.parse(arguments: parser.remainingArguments())
        return BmapProbeOptions(
            connection: connection,
            blockRaw: blockRaw,
            functionRange: functionRange,
            operatorValue: operatorValue,
            deviceID: deviceID,
            port: port,
            payload: payload,
            responseTimeoutMilliseconds: responseTimeoutMilliseconds
        )
    }
}
