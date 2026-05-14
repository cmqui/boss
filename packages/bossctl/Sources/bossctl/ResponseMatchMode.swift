import Foundation
import libboss
import libbossApple

enum ResponseMatchMode: String {
    case sameFunction = "same"
    case any = "any"

    func matches(_ sentPacket: BmapPacket) -> @Sendable (BmapPacket) -> Bool {
        switch self {
        case .sameFunction:
            return { packet in
                packet.functionBlock == sentPacket.functionBlock &&
                packet.function == sentPacket.function &&
                packet.operator.type == .response
            }
        case .any:
            return { packet in packet.operator.type == .response }
        }
    }
}
