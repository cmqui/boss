import Foundation
import libboss
import libbossApple

extension BossctlCLI {
    static func printAudioModeSettingsConfig(_ config: BossAudioModeSettingsConfig) {
        print("CNC level: \(config.cncLevel) (0=max ANC, 10=most ambient)")
        print("Auto CNC: \(config.autoCNCEnabled)")
        print("Spatial audio: \(config.spatialAudioMode.displayName)")
        print("Wind block: \(config.windBlockEnabled)")
        print("ANC toggle: \(config.ancToggleEnabled)")
    }

    static func printFavoriteAudioModes(_ favorites: [Int], modes: [BossAudioModeInfo]) {
        guard !favorites.isEmpty else {
            print("Favorite audio modes: none")
            return
        }
        let modesByIndex = Dictionary(uniqueKeysWithValues: modes.map { ($0.modeIndex, $0.name) })
        print("Favorite audio modes:")
        for index in favorites.sorted() {
            if let name = modesByIndex[index] {
                print("  \(index): \(name)")
            } else {
                print("  \(index)")
            }
        }
    }

    static func printAudioModeSettingsConfigWriteResult(
        _ result: BossAppleAudioModeSettingsWriteResult,
        output: AudioModeSettingsOutput
    ) {
        let state: AudioModeSettingsWriteState
        let config: BossAudioModeSettingsConfig
        switch result {
        case .unchanged(let unchangedConfig):
            state = .unchanged
            config = unchangedConfig
        case .updated(let updatedConfig):
            state = .updated
            config = updatedConfig
        case .verificationInconclusive(let target):
            state = .verificationInconclusive
            config = target
        }

        switch output {
        case .full:
            switch state {
            case .unchanged:
                print("Audio mode settings unchanged:")
            case .updated:
                print("Audio mode settings updated:")
            case .verificationInconclusive:
                print("Audio mode settings update sent; verification inconclusive")
            }
            printAudioModeSettingsConfig(config)
        case .field(let field):
            let prefix: String
            switch state {
            case .unchanged:
                prefix = "\(field.label) unchanged"
            case .updated:
                prefix = "\(field.label) updated"
            case .verificationInconclusive:
                prefix = "\(field.label) update sent; verification inconclusive"
            }
            print("\(prefix): \(field.value(from: config))")
        }
    }

    static func formatOptionalBool(_ value: Bool?) -> String {
        guard let value else { return "unsupported" }
        return value ? "enabled" : "disabled"
    }

    static func bmapErrorCode(from payloadHex: String) -> BmapErrorCode? {
        guard payloadHex.count == 2, let rawValue = UInt8(payloadHex, radix: 16) else {
            return nil
        }
        return BmapErrorCode(rawValue: rawValue)
    }

    static func printBootstrap(_ device: BootstrappedDevice) {
        print("Transport: \(device.transportKind.rawValue)")
        print("BMAP: \(device.bmapVersion.version)")
        print("Product: \(device.productName) (\(String(format: "0x%04X", device.productID)))")
        let variantLabel = device.productVariant.variantName ?? "Unknown"
        print("Variant: \(variantLabel) (raw=\(String(format: "0x%02X", device.productVariant.variant)))")
        let blocks = device.supportedFunctionBlocks.allBlocks().map(\.displayName).joined(separator: ", ")
        print("Function blocks: \(blocks)")
    }

    static func describe(_ packet: BmapPacket) -> String {
        let encoded = (try? BmapCodec.encode(packet).hexString) ?? "<encode-failed>"
        return "packet block=\(packet.functionBlock.displayName)(0x\(String(format: "%02X", packet.functionBlock.rawValue))) " +
            "function=\(packet.function.name)(0x\(String(format: "%02X", packet.function.rawValue))) " +
            "op=\(packet.operator.displayName)(0x\(String(format: "%02X", packet.operator.rawValue))) " +
            "deviceID=\(packet.deviceID) port=\(packet.port) frame=\(encoded)"
    }

    static func describe(_ config: BossAudioModeSettingsConfig) -> String {
        "cnc=\(config.cncLevel),autoCNC=\(config.autoCNCEnabled),spatial=\(config.spatialAudioMode.displayName),wind=\(config.windBlockEnabled),anc=\(config.ancToggleEnabled)"
    }
}
