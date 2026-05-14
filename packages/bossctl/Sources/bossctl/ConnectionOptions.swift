import Foundation
import libboss
import libbossApple

struct ConnectionOptions {
    let nameContains: String?
    let identifier: UUID?
    let timeoutSeconds: Int
    let characteristicPreference: AppleBossCharacteristicPreference

    static func parse(arguments: [String]) throws -> ConnectionOptions {
        var parser = ArgumentParser(arguments: arguments)
        let nameContains = try parser.optionalValue(for: "--name")
        let identifier = try parser.optionalUUID(for: "--identifier")
        let timeoutSeconds = try parser.optionalInt(for: "--timeout") ?? 20
        let characteristicPreference = try parser.optionalCharacteristicPreference(for: "--characteristic") ?? .automatic
        try parser.finish()
        return ConnectionOptions(
            nameContains: nameContains,
            identifier: identifier,
            timeoutSeconds: timeoutSeconds,
            characteristicPreference: characteristicPreference
        )
    }

    func withCharacteristicPreference(_ preference: AppleBossCharacteristicPreference) -> ConnectionOptions {
        ConnectionOptions(
            nameContains: nameContains,
            identifier: identifier,
            timeoutSeconds: timeoutSeconds,
            characteristicPreference: preference
        )
    }
}
