import Foundation
import libbossApple

extension BossAppViewModel {
    func debugSummary(
        _ prefix: String,
        selectedModeIndex: Int?,
        currentModeIndex: Int?,
        incomingModeIndex: Int? = nil,
        mode: BossAppleAudioModeConfig? = nil,
        draftSettings: BossAppleAudioModeSettingsConfig? = nil,
        returnedSettings: BossAppleAudioModeSettingsConfig? = nil,
        liveSettings: BossAppleAudioModeSettingsConfig? = nil
    ) -> String {
        var fields: [String] = [
            "selected=\(selectedModeIndex.map(String.init) ?? "nil")",
            "current=\(currentModeIndex.map(String.init) ?? "nil")"
        ]

        if let incomingModeIndex {
            fields.append("incoming=\(incomingModeIndex)")
        }

        if let mode {
            fields.append("mode=\(debugModeLabel(mode))")
        }

        if let draftSettings {
            fields.append("draft=\(debugSettingsLabel(draftSettings))")
        }

        if let returnedSettings {
            fields.append("returned=\(debugSettingsLabel(returnedSettings))")
        }

        if let liveSettings {
            fields.append("live=\(debugSettingsLabel(liveSettings))")
        }

        return "\(prefix) | " + fields.joined(separator: " | ")
    }

    func debugModeLabel(_ mode: BossAppleAudioModeConfig) -> String {
        "\(customProfileDisplayName(for: mode))#\(mode.modeIndex){userConfigurable=\(mode.userConfigurable),userConfigured=\(mode.userConfigured),favorite=\(mode.favorite),prompt=\(mode.prompt.name),settings=\(debugSettingsLabel(mode.settings))}"
    }

    func debugSettingsLabel(_ settings: BossAppleAudioModeSettingsConfig) -> String {
        "{cnc=\(settings.cncLevel),autoCNC=\(settings.autoCNCEnabled),spatial=\(String(describing: settings.spatialAudioMode)),wind=\(settings.windBlockEnabled),ancToggle=\(settings.ancToggleEnabled)}"
    }

    static func log(_ message: String) {
        fputs("[boss-apple-app] \(message)\n", stderr)
    }
}
