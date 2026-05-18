import AppKit
import Foundation

extension Bundle {
    static var bossResources: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }
}

enum BossImageResource: String {
    case bossLogo = "BossLogo"
    case headphonesMark = "HeadphonesMark"
    case headphonesMenuBar = "HeadphonesMenuBar"

    func nsImage(fileExtension: String = "png") -> NSImage? {
        guard let url = Bundle.bossResources.url(forResource: rawValue, withExtension: fileExtension) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

enum BossDeviceImageResource {
    case wolverine(String)

    init?(productName: String, variantName: String?) {
        guard productName == "Bose QC Ultra 2 HP",
              let assetName = Self.wolverineAssetName(for: variantName) else {
            return nil
        }
        self = .wolverine(assetName)
    }

    func nsImage(fileExtension: String = "png") -> NSImage? {
        let resourceName: String

        switch self {
        case .wolverine(let assetName):
            resourceName = assetName
        }

        if let url = Bundle.bossResources.url(
            forResource: resourceName,
            withExtension: fileExtension,
            subdirectory: "Devices/wolverine"
        ) {
            return NSImage(contentsOf: url)
        }

        guard let url = Bundle.bossResources.url(
            forResource: resourceName,
            withExtension: fileExtension
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private static func wolverineAssetName(for variantName: String?) -> String? {
        guard let variantName else {
            return nil
        }
        let normalizedVariantName = normalizedAssetKey(variantName)

        let aliases = [
            "black": "Black",
            "whitesmoke": "WhiteSmoke",
            "driftwoodsand": "DriftwoodSand",
            "midnightviolet": "MidnightViolet",
            "desertgold": "DesertGold",
        ]

        if let assetName = aliases[normalizedVariantName] {
            return assetName
        }

        return aliases.first { normalizedVariantName.hasSuffix($0.key) }?.value
    }

    private static func normalizedAssetKey(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "wolverine", with: "")
            .filter(\.isLetter)
    }
}
