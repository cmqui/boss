import Foundation

public enum BmapErrorCode: UInt8, Sendable {
    case length = 0x01
    case chksum = 0x02
    case fblockNotSupp = 0x03
    case funcNotSupp = 0x04
    case opNotSupp = 0x05
    case invalidData = 0x06
    case dataUnavailable = 0x07
    case runtime = 0x08
    case timeout = 0x09
    case invalidState = 0x0A
    case deviceNotFound = 0x0B
    case busy = 0x0C
    case noconnTimeout = 0x0D
    case noconnKey = 0x0E
    case otaUpdate = 0x0F
    case otaLowBatt = 0x10
    case otaNoCharger = 0x11
    case otaUpdateNotAllowed = 0x12
    case unknownPortNumber = 0x13
    case insecureTransport = 0x14
    case invalidOtpKey = 0x15
    case fblockSpecific = 0xFF

    public var description: String {
        switch self {
        case .length: "Length"
        case .chksum: "Chksum"
        case .fblockNotSupp: "FblockNotSupp"
        case .funcNotSupp: "FuncNotSupp"
        case .opNotSupp: "OpNotSupp"
        case .invalidData: "InvalidData"
        case .dataUnavailable: "DataUnavailable"
        case .runtime: "Runtime"
        case .timeout: "Timeout"
        case .invalidState: "InvalidState"
        case .deviceNotFound: "DeviceNotFound"
        case .busy: "Busy"
        case .noconnTimeout: "NoconnTimeout"
        case .noconnKey: "NoconnKey"
        case .otaUpdate: "OtaUpdate"
        case .otaLowBatt: "OtaLowBatt"
        case .otaNoCharger: "OtaNoCharger"
        case .otaUpdateNotAllowed: "OtaUpdateNotAllowed"
        case .unknownPortNumber: "UnknownPortNumber"
        case .insecureTransport: "InsecureTransport"
        case .invalidOtpKey: "InvalidOtpKey"
        case .fblockSpecific: "FblockSpecific"
        }
    }
}
