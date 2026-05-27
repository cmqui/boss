import Foundation
import libbossApple

struct ArgumentParser {
    private var arguments: [String]

    init(arguments: [String]) {
        self.arguments = arguments
    }

    mutating func optionalValue(for flag: String) throws -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        guard index + 1 < arguments.count else {
            throw UsageError("Missing value for \(flag)")
        }
        let value = arguments[index + 1]
        arguments.removeSubrange(index...(index + 1))
        return value
    }

    mutating func optionalInt(for flag: String) throws -> Int? {
        guard let value = try optionalValue(for: flag) else {
            return nil
        }
        guard let parsed = Int(value) else {
            throw UsageError("Invalid integer for \(flag): \(value)")
        }
        return parsed
    }

    mutating func requiredInt(for flag: String) throws -> Int {
        guard let value = try optionalInt(for: flag) else {
            throw UsageError("Missing value for \(flag)")
        }
        return value
    }

    mutating func requiredBool(for flag: String) throws -> Bool {
        guard let value = try optionalValue(for: flag) else {
            throw UsageError("Missing value for \(flag)")
        }
        return try parseBool(value, flag: flag)
    }

    mutating func optionalBool(for flag: String) throws -> Bool? {
        guard let value = try optionalValue(for: flag) else {
            return nil
        }
        return try parseBool(value, flag: flag)
    }

    private func parseBool(_ value: String, flag: String) throws -> Bool {
        switch value.lowercased() {
        case "true", "1", "yes", "on":
            return true
        case "false", "0", "no", "off":
            return false
        default:
            throw UsageError("Invalid boolean for \(flag): \(value)")
        }
    }

    mutating func requiredBoolValue(label: String) throws -> Bool {
        guard !arguments.isEmpty else {
            throw UsageError("Missing value for \(label)")
        }
        let value = arguments.removeFirst()
        return try parseBool(value, flag: label)
    }

    mutating func requiredVolumeControlValue(for flag: String) throws -> BossAppleVolumeControlValue {
        guard let value = try optionalValue(for: flag) else {
            throw UsageError("Missing value for \(flag)")
        }
        switch value.lowercased() {
        case "disabled":
            return .disabled
        case "button":
            return .button
        case "captouch":
            return .capTouch
        case "imu":
            return .imu
        default:
            throw UsageError("Invalid volume control value for \(flag): \(value)")
        }
    }

    mutating func requiredAudioModeSelection() throws -> AudioModeSelection {
        let indexValue = try optionalValue(for: "--index")
        let modeValue = try optionalValue(for: "--mode")
        switch (indexValue, modeValue) {
        case let (.some(indexValue), nil):
            guard let parsed = Int(indexValue) else {
                throw UsageError("Invalid integer for --index: \(indexValue)")
            }
            return .index(parsed)
        case let (nil, .some(modeValue)):
            return .name(modeValue)
        case (nil, nil):
            throw UsageError("Missing value for --index or --mode")
        default:
            throw UsageError("Specify only one of --index or --mode")
        }
    }

    mutating func onHeadDetectionPatch() throws -> BossAppleOnHeadDetectionPatch {
        let isEnabled = try optionalBool(for: "--enabled")
        let isAutoPlayEnabled = try optionalBool(for: "--auto-play")
        let isAutoAnswerEnabled = try optionalBool(for: "--auto-answer")
        let isAutoTransparencyEnabled = try optionalBool(for: "--auto-transparency")
        let patch = BossAppleOnHeadDetectionPatch(
            isEnabled: isEnabled,
            isAutoPlayEnabled: isAutoPlayEnabled,
            isAutoAnswerEnabled: isAutoAnswerEnabled,
            isAutoTransparencyEnabled: isAutoTransparencyEnabled
        )
        guard !patch.isEmpty else {
            throw UsageError("Specify at least one on-head-detection option")
        }
        return patch
    }

    mutating func audioModeSettingsConfigUpdate() throws -> BossAppleAudioModeSettingsConfigPatch {
        let cncLevel = try optionalInt(for: "--cnc")
        if let cncLevel, !(0...10).contains(cncLevel) {
            throw UsageError("Invalid CNC level for --cnc: \(cncLevel)")
        }
        let autoCNCEnabled = try optionalBool(for: "--auto-cnc")
        let spatialAudioMode = try optionalSpatialAudioMode(for: "--spatial")
        let windBlockEnabled = try optionalBool(for: "--wind-block")
        let ancToggleEnabled = try optionalBool(for: "--anc-toggle")
        let patch = BossAppleAudioModeSettingsConfigPatch(
            cncLevel: cncLevel,
            autoCNCEnabled: autoCNCEnabled,
            spatialAudioMode: spatialAudioMode,
            windBlockEnabled: windBlockEnabled,
            ancToggleEnabled: ancToggleEnabled
        )
        guard !patch.isEmpty else {
            throw UsageError("Specify at least one settings-config option")
        }
        return patch
    }

    mutating func equalizerSettingsPatch() throws -> BossAppleEqualizerSettingsPatch {
        let bass = try optionalInt(for: "--bass")
        let mid = try optionalInt(for: "--mid")
        let treble = try optionalInt(for: "--treble")
        let patch = BossAppleEqualizerSettingsPatch(
            bass: bass,
            mid: mid,
            treble: treble
        )
        guard !patch.isEmpty else {
            throw UsageError("Specify at least one equalizer option")
        }
        return patch
    }

    mutating func optionalSpatialAudioMode(for flag: String) throws -> BossAppleSpatialAudioMode? {
        guard let value = try optionalValue(for: flag) else {
            return nil
        }
        return try parseSpatialAudioMode(value, label: flag)
    }

    mutating func requiredSpatialAudioMode() throws -> BossAppleSpatialAudioMode {
        guard !arguments.isEmpty else {
            throw UsageError("Missing spatial audio mode")
        }
        let value = arguments.removeFirst()
        return try parseSpatialAudioMode(value, label: "spatial")
    }

    private func parseSpatialAudioMode(_ value: String, label: String) throws -> BossAppleSpatialAudioMode {
        switch value.lowercased() {
        case "off":
            return .off
        case "room":
            return .room
        case "head":
            return .head
        default:
            throw UsageError("Invalid spatial audio mode for \(label): \(value)")
        }
    }

    mutating func optionalUUID(for flag: String) throws -> UUID? {
        guard let value = try optionalValue(for: flag) else {
            return nil
        }
        guard let parsed = UUID(uuidString: value) else {
            throw UsageError("Invalid UUID for \(flag): \(value)")
        }
        return parsed
    }

    mutating func optionalCharacteristicPreference(for flag: String) throws -> AppleBossCharacteristicPreference? {
        guard let value = try optionalValue(for: flag) else {
            return nil
        }
        guard let preference = AppleBossCharacteristicPreference(rawValue: value) else {
            throw UsageError("Invalid value for \(flag): \(value)")
        }
        return preference
    }

    mutating func finish() throws {
        if !arguments.isEmpty {
            throw UsageError("Unknown arguments: \(arguments.joined(separator: " "))")
        }
    }

    mutating func remainingArguments() -> [String] {
        defer { arguments.removeAll() }
        return arguments
    }
}
