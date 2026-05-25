import Foundation
import libbossApple

protocol BossctlOutputWriting {
    func writeLine(_ line: String)
}

struct BossctlStandardOutputWriter: BossctlOutputWriting {
    func writeLine(_ line: String) {
        print(line)
    }
}

final class BossctlBufferingOutputWriter: BossctlOutputWriting {
    private(set) var lines: [String] = []

    func writeLine(_ line: String) {
        lines.append(line)
    }
}

extension BossctlCLI {
    static func printWearDetectionFallbackPaths(
        for patch: BossAppleOnHeadDetectionPatch,
        output: BossctlOutputWriting = BossctlStandardOutputWriter()
    ) {
        if patch.isAutoPlayEnabled != nil {
            output.writeLine("Applied subordinate setting path: auto-play-pause (settings 0x18)")
        }
        if patch.isAutoAnswerEnabled != nil {
            output.writeLine("Applied subordinate setting path: auto-answer (settings 0x1B)")
        }
        if patch.isAutoTransparencyEnabled != nil {
            output.writeLine("Applied subordinate setting path: auto-aware / auto-transparency (settings 0x1D)")
        }
    }

    static func printOnHeadDetection(
        _ value: BossAppleOnHeadDetectionValue,
        output: BossctlOutputWriting = BossctlStandardOutputWriter()
    ) {
        output.writeLine("On-head detection: \(value.isEnabled)")
        output.writeLine("Auto-play: \(formatOptionalBool(value.isAutoPlayEnabled))")
        output.writeLine("Auto-answer: \(formatOptionalBool(value.isAutoAnswerEnabled))")
        output.writeLine("Auto-transparency: \(formatOptionalBool(value.isAutoTransparencyEnabled))")
    }

    static func printWearDetectionSettingsReport(
        _ report: BossAppleDeviceSettingsReport,
        output: BossctlOutputWriting = BossctlStandardOutputWriter()
    ) {
        if let wearDetection = report.wearDetection.value {
            output.writeLine("On-head detection: \(wearDetection.isEnabled) [\(describe(report.wearDetection))]")
        } else {
            output.writeLine("On-head detection: unavailable [\(describe(report.wearDetection))]")
        }

        let autoPlay = report.wearDetection.value?.isAutoPlayEnabled ?? report.autoPlayPauseEnabled.value
        let autoAnswer = report.wearDetection.value?.isAutoAnswerEnabled ?? report.autoAnswerEnabled.value
        let autoTransparency = report.wearDetection.value?.isAutoTransparencyEnabled ?? report.autoAwareEnabled.value

        output.writeLine("Auto-play: \(formatOptionalBool(autoPlay))")
        output.writeLine("Auto-answer: \(formatOptionalBool(autoAnswer))")
        output.writeLine("Auto-transparency: \(formatOptionalBool(autoTransparency))")
    }

    static func printDeviceSettingsReport(
        _ report: BossAppleDeviceSettingsReport,
        output: BossctlOutputWriting = BossctlStandardOutputWriter()
    ) {
        if let wearDetection = report.wearDetection.value {
            output.writeLine("Wear detection: \(wearDetection.isEnabled) [\(describe(report.wearDetection))]")
            output.writeLine("Auto-play: \(formatOptionalBool(wearDetection.isAutoPlayEnabled))")
            output.writeLine("Auto-answer: \(formatOptionalBool(wearDetection.isAutoAnswerEnabled))")
            output.writeLine("Auto-transparency: \(formatOptionalBool(wearDetection.isAutoTransparencyEnabled))")
        } else {
            output.writeLine("Wear detection: unavailable [\(describe(report.wearDetection))]")
        }

        if let autoAwareEnabled = report.autoAwareEnabled.value {
            output.writeLine("Auto-aware: \(autoAwareEnabled) [\(describe(report.autoAwareEnabled))]")
        } else {
            output.writeLine("Auto-aware: unavailable [\(describe(report.autoAwareEnabled))]")
        }

        if let autoPlayPauseEnabled = report.autoPlayPauseEnabled.value {
            output.writeLine("Auto-play-pause: \(autoPlayPauseEnabled) [\(describe(report.autoPlayPauseEnabled))]")
        } else {
            output.writeLine("Auto-play-pause: unavailable [\(describe(report.autoPlayPauseEnabled))]")
        }

        if let autoAnswerEnabled = report.autoAnswerEnabled.value {
            output.writeLine("Auto-answer: \(autoAnswerEnabled) [\(describe(report.autoAnswerEnabled))]")
        } else {
            output.writeLine("Auto-answer: unavailable [\(describe(report.autoAnswerEnabled))]")
        }

        if let volumeControl = report.volumeControl.value {
            output.writeLine("Volume control: \(volumeControl.value.displayName) [\(describe(report.volumeControl))]")
            if let supportedValues = volumeControl.supportedValues, !supportedValues.isEmpty {
                let supportedModes = supportedValues.map(\.displayName).joined(separator: ", ")
                output.writeLine("Volume control supported modes: \(supportedModes)")
            }
        } else {
            output.writeLine("Volume control: unavailable [\(describe(report.volumeControl))]")
        }
    }

    static func printEqualizer(
        _ settings: BossAppleEqualizerSettings,
        output: BossctlOutputWriting = BossctlStandardOutputWriter()
    ) {
        for band in settings.ranges {
            output.writeLine("\(band.band.displayName.capitalized): \(band.currentLevel) [range \(band.minLevel)...\(band.maxLevel)]")
        }
    }

    static func printEqualizerWriteResult(
        _ result: BossAppleEqualizerWriteResult,
        output: BossctlOutputWriting = BossctlStandardOutputWriter()
    ) {
        let prefix: String
        let settings: BossAppleEqualizerSettings
        switch result {
        case .unchanged(let unchanged):
            prefix = "Equalizer unchanged:"
            settings = unchanged
        case .updated(let updated):
            prefix = "Equalizer updated:"
            settings = updated
        case .verificationInconclusive(let target):
            prefix = "Equalizer update sent; verification inconclusive"
            settings = target
        }
        output.writeLine(prefix)
        printEqualizer(settings, output: output)
    }

    static func printAudioModeSettingsConfig(
        _ config: BossAppleAudioModeSettingsConfig,
        output: BossctlOutputWriting = BossctlStandardOutputWriter()
    ) {
        output.writeLine("CNC level: \(config.cncLevel) (0=max ANC, 10=most ambient)")
        output.writeLine("Auto CNC: \(config.autoCNCEnabled)")
        output.writeLine("Spatial audio: \(config.spatialAudioMode.displayName)")
        output.writeLine("Wind block: \(config.windBlockEnabled)")
        output.writeLine("ANC toggle: \(config.ancToggleEnabled)")
    }

    static func printFavoriteAudioModes(
        _ favorites: [Int],
        modes: [BossAppleAudioModeInfo],
        output: BossctlOutputWriting = BossctlStandardOutputWriter()
    ) {
        guard !favorites.isEmpty else {
            output.writeLine("Favorite audio modes: none")
            return
        }
        let modesByIndex = Dictionary(uniqueKeysWithValues: modes.map { ($0.modeIndex, $0.name) })
        output.writeLine("Favorite audio modes:")
        for index in favorites.sorted() {
            if let name = modesByIndex[index] {
                output.writeLine("  \(index): \(name)")
            } else {
                output.writeLine("  \(index)")
            }
        }
    }

    static func printAudioModeSettingsConfigWriteResult(
        _ result: BossAppleAudioModeSettingsWriteResult,
        output: AudioModeSettingsOutput,
        writer: BossctlOutputWriting = BossctlStandardOutputWriter()
    ) {
        let state: AudioModeSettingsWriteState
        let config: BossAppleAudioModeSettingsConfig
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
                writer.writeLine("Audio mode settings unchanged:")
            case .updated:
                writer.writeLine("Audio mode settings updated:")
            case .verificationInconclusive:
                writer.writeLine("Audio mode settings update sent; verification inconclusive")
            }
            printAudioModeSettingsConfig(config, output: writer)
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
            writer.writeLine("\(prefix): \(field.value(from: config))")
        }
    }

    static func printBmapTraceEvent(
        _ event: BossAppleBmapTraceEvent,
        output: BossctlOutputWriting = BossctlStandardOutputWriter()
    ) {
        output.writeLine(
            "packet=\(event.packetHex) | block=\(event.functionBlockName)(\(hexByte(event.functionBlockRaw))) | function=\(event.functionName)(\(hexByte(event.functionRaw))) | operator=\(event.operatorName)(\(hexByte(event.operatorRaw))) | device=\(event.deviceID) | port=\(event.port) | payload=\(event.payloadHex)"
        )
    }

    static func formatOptionalBool(_ value: Bool?) -> String {
        guard let value else { return "unsupported" }
        return value ? "enabled" : "disabled"
    }

    static func hexByte(_ value: UInt8) -> String {
        String(format: "0x%02X", value)
    }

    static func bmapErrorCode(from payloadHex: String) -> BossAppleBmapErrorCode? {
        guard payloadHex.count == 2, let rawValue = UInt8(payloadHex, radix: 16) else {
            return nil
        }
        return BossAppleBmapErrorCode(rawValue: rawValue)
    }

    static func printBootstrap(
        _ device: BossAppleBootstrappedDevice,
        output: BossctlOutputWriting = BossctlStandardOutputWriter()
    ) {
        output.writeLine("Transport: \(device.transportKind.rawValue)")
        output.writeLine("BMAP: \(device.bmapVersion.version)")
        output.writeLine("Product: \(device.productName) (\(String(format: "0x%04X", device.productID)))")
        let variantLabel = device.productVariant.variantName ?? "Unknown"
        output.writeLine("Variant: \(variantLabel) (raw=\(String(format: "0x%02X", device.productVariant.variant)))")
        let blocks = device.supportedFunctionBlocks.allBlocks().map(\.displayName).joined(separator: ", ")
        output.writeLine("Function blocks: \(blocks)")
    }

    static func describe(_ config: BossAppleAudioModeSettingsConfig) -> String {
        "cnc=\(config.cncLevel),autoCNC=\(config.autoCNCEnabled),spatial=\(config.spatialAudioMode.displayName),wind=\(config.windBlockEnabled),anc=\(config.ancToggleEnabled)"
    }

    static func describe<Value: Sendable & Equatable>(_ observed: BossAppleObservedSetting<Value>) -> String {
        if let source = observed.source {
            return source.rawValue
        }
        if let reason = observed.unavailableReason {
            return reason.description
        }
        return "unknown"
    }
}
