import Foundation
import libboss

extension BossctlCLI {
    static func awaitSettingsSnapshot(
        on link: BleBmapLink,
        timeout: Duration
    ) async throws -> BossSettingsSnapshot {
        try await link.send(packet: BossSettingsCodec.settingsPacket(functionRaw: BossSettingsCodec.settingsGetAllFunctionRaw, operatorValue: .start))
        return try await withThrowingTaskGroup(of: BossSettingsSnapshot.self) { group in
            group.addTask {
                var snapshot: [UInt8: BmapPacket] = [:]
                for try await packet in link.packets {
                    guard packet.functionBlock == .settings else {
                        continue
                    }
                    let rawFunction = packet.function.rawValue
                    if rawFunction == BossSettingsCodec.settingsGetAllFunctionRaw, packet.operator == .error {
                        throw BossctlError.bmapErrorResponse(
                            context: "settings.SettingsGetAll",
                            payloadHex: packet.payload.hexString
                        )
                    }
                    if rawFunction == BossSettingsCodec.settingsGetAllFunctionRaw, packet.operator == .result {
                        return BossSettingsSnapshot(packetsByFunctionRaw: snapshot)
                    }
                    guard packet.operator == .status else {
                        continue
                    }
                    snapshot[rawFunction] = packet
                }
                throw BossctlError.responseStreamEnded
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw BossctlError.responseTimedOut(seconds: timeout.components.seconds)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
