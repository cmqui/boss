import Foundation
import libboss
import libbossApple

extension BossctlCLI {
    static func resolveAudioModeSelection(
        _ selection: AudioModeSelection,
        controller: BossAppleController
    ) async throws -> Int {
        switch selection {
        case .index(let index):
            return index
        case .name(let name):
            let normalizedTarget = normalizeAudioModeName(name)
            if let builtInIndex = builtInAudioModeIndex(for: normalizedTarget) {
                return builtInIndex
            }
            let modes = try await controller.displayableAudioModes()
            guard let match = modes.first(where: { normalizeAudioModeName($0.name) == normalizedTarget }) else {
                throw UsageError("Unknown audio mode: \(name)")
            }
            return match.modeIndex
        }
    }

    static func normalizeAudioModeName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func builtInAudioModeIndex(for normalizedName: String) -> Int? {
        switch normalizedName {
        case "quiet":
            return 0
        case "aware":
            return 1
        case "immersion":
            return 2
        case "cinema":
            return 3
        default:
            return nil
        }
    }
}
