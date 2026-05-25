import Foundation

public struct BossAppleBmapTraceEvent: Equatable, Sendable {
    public let functionBlockRaw: UInt8
    public let functionBlockName: String
    public let functionRaw: UInt8
    public let functionName: String
    public let deviceID: Int
    public let port: Int
    public let operatorRaw: UInt8
    public let operatorName: String
    public let payloadHex: String
    public let packetHex: String

    public init(
        functionBlockRaw: UInt8,
        functionBlockName: String,
        functionRaw: UInt8,
        functionName: String,
        deviceID: Int,
        port: Int,
        operatorRaw: UInt8,
        operatorName: String,
        payloadHex: String,
        packetHex: String
    ) {
        self.functionBlockRaw = functionBlockRaw
        self.functionBlockName = functionBlockName
        self.functionRaw = functionRaw
        self.functionName = functionName
        self.deviceID = deviceID
        self.port = port
        self.operatorRaw = operatorRaw
        self.operatorName = operatorName
        self.payloadHex = payloadHex
        self.packetHex = packetHex
    }
}

private final class BossAppleBmapTraceLinkHolder: @unchecked Sendable {
    var transport: AppleBleBossTransport?
}

public extension BossAppleSession {
    static func bmapTraceStream(
        connection: BossAppleConnectionOptions
    ) -> AsyncThrowingStream<BossAppleBmapTraceEvent, Error> {
        let holder = BossAppleBmapTraceLinkHolder()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let transport = try await AppleBleBossTransport.connect(
                        filter: AppleBossScanFilter(
                            peripheralIdentifier: connection.identifier,
                            nameContains: connection.nameContains,
                            scanTimeout: connection.scanTimeout
                        ),
                        characteristicPreference: connection.characteristicPreference
                    )
                    holder.transport = transport
                    let rustBridge = try traceRequireRustBridge()
                    let stream = rustBridge.rawPacketUpdateStream(on: transport)

                    Task {
                        _ = try? await rustBridge.bootstrap(on: transport)
                    }

                    for try await packet in stream {
                        let packetData = try BossRustCodecBridge.encode(packet, runtime: rustBridge.runtime)
                        continuation.yield(
                            BossAppleBmapTraceEvent(
                                functionBlockRaw: packet.functionBlock.rawValue,
                                functionBlockName: packet.functionBlock.displayName,
                                functionRaw: packet.function.rawValue,
                                functionName: packet.function.name,
                                deviceID: packet.deviceID,
                                port: packet.port,
                                operatorRaw: packet.operator.rawValue,
                                operatorName: packet.operator.displayName,
                                payloadHex: traceHex(packet.payload),
                                packetHex: traceHex(packetData)
                            )
                        )
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }

                if let transport = holder.transport {
                    await transport.close()
                    holder.transport = nil
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task {
                    if let transport = holder.transport {
                        await transport.close()
                        holder.transport = nil
                    }
                }
            }
        }
    }
}

private func traceHex(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined()
}

private func traceRequireRustBridge() throws -> BossRustSessionBridge {
    guard let bridge = BossRustSessionBridge.shared else {
        throw BossAppleControlError.unsupportedOperation("Rust runtime is required for packet transport")
    }
    return bridge
}
