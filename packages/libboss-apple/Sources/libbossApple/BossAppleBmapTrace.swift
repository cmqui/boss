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
    var link: BossAppleLink?
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
                    let link = BossAppleLink(transport: transport)
                    holder.link = link
                    let runtime = try traceRequireRustRuntime()

                    // Open a BMAP session on the same traced link by issuing the standard
                    // version query used during bootstrap.
                    try await link.send(
                        packet: BossAppleBmapPacket(
                            functionBlock: .productInfo,
                            function: .productInfoBmapVersion,
                            deviceID: 0,
                            port: 0,
                            operator: .get,
                            payload: Data()
                        )
                    )

                    for try await packet in link.packets {
                        let packetData = try BossRustCodecBridge.encode(packet, runtime: runtime)
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

                if let link = holder.link {
                    await link.close()
                    holder.link = nil
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task {
                    if let link = holder.link {
                        await link.close()
                        holder.link = nil
                    }
                }
            }
        }
    }
}

private func traceHex(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined()
}

private func traceRequireRustRuntime() throws -> BossRustFfiRuntime {
    guard let runtime = BossRustFfiRuntime.shared else {
        throw BossAppleControlError.unsupportedOperation("Rust runtime is required for packet transport")
    }
    return runtime
}
