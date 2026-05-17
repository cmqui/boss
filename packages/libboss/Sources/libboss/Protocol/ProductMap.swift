import Foundation

public struct ProductDefinition: Equatable, Sendable {
    public let id: UInt16
    public let codeName: String
    public let displayName: String
    public let variants: [UInt8: String]

    public init(id: UInt16, codeName: String, displayName: String, variants: [UInt8: String]) {
        self.id = id
        self.codeName = codeName
        self.displayName = displayName
        self.variants = variants
    }
}

public enum ProductMap {
    public static let wolverine = ProductDefinition(
        id: 0x4082,
        codeName: "Wolverine",
        displayName: "Bose QC Ultra 2 HP",
        variants: [
            1: "WolverineBlack",
            2: "WolverineWhiteSmoke",
            3: "WolverineDriftwoodSand",
            4: "WolverineMidnightViolet",
            5: "WolverineDesertGold",
        ]
    )

    public static func product(for id: UInt16) -> ProductDefinition? {
        switch id {
        case wolverine.id:
            wolverine
        default:
            nil
        }
    }
}
