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
