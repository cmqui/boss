import Foundation

public enum BossAppleTransportKind: String, Equatable, Sendable {
    case ble
    case stream
}

public struct BossAppleBmapVersionInfo: Equatable, Sendable {
    public let version: String

    public init(version: String) {
        self.version = version
    }
}

public struct BossAppleFirmwareVersionInfo: Equatable, Sendable {
    public let version: String
    public let port: Int

    public init(version: String, port: Int) {
        self.version = version
        self.port = port
    }
}

public struct BossAppleProductDefinition: Equatable, Sendable {
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

public struct BossAppleProductVariant: Equatable, Sendable {
    public let productID: UInt16
    public let variant: UInt8
    public let product: BossAppleProductDefinition?
    public let variantName: String?

    public init(productID: UInt16, variant: UInt8, product: BossAppleProductDefinition?, variantName: String?) {
        self.productID = productID
        self.variant = variant
        self.product = product
        self.variantName = variantName
    }
}

public enum BossAppleBmapFunctionBlock: Hashable, Sendable, Comparable {
    case productInfo
    case settings
    case status
    case firmwareUpdate
    case deviceManagement
    case audioManagement
    case callManagement
    case control
    case debug
    case notification
    case reservedBosebuild1
    case reservedBosebuild2
    case hearingAssistance
    case dataCollection
    case heartRate
    case peerBud
    case vpa
    case wifi
    case authentication
    case experimental
    case cloud
    case augmentedReality
    case print
    case audioModes
    case unknown(UInt8)

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .productInfo
        case 1: self = .settings
        case 2: self = .status
        case 3: self = .firmwareUpdate
        case 4: self = .deviceManagement
        case 5: self = .audioManagement
        case 6: self = .callManagement
        case 7: self = .control
        case 8: self = .debug
        case 9: self = .notification
        case 10: self = .reservedBosebuild1
        case 11: self = .reservedBosebuild2
        case 12: self = .hearingAssistance
        case 13: self = .dataCollection
        case 14: self = .heartRate
        case 15: self = .peerBud
        case 16: self = .vpa
        case 17: self = .wifi
        case 18: self = .authentication
        case 19: self = .experimental
        case 20: self = .cloud
        case 21: self = .augmentedReality
        case 22: self = .print
        case 31: self = .audioModes
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: UInt8 {
        switch self {
        case .productInfo: 0
        case .settings: 1
        case .status: 2
        case .firmwareUpdate: 3
        case .deviceManagement: 4
        case .audioManagement: 5
        case .callManagement: 6
        case .control: 7
        case .debug: 8
        case .notification: 9
        case .reservedBosebuild1: 10
        case .reservedBosebuild2: 11
        case .hearingAssistance: 12
        case .dataCollection: 13
        case .heartRate: 14
        case .peerBud: 15
        case .vpa: 16
        case .wifi: 17
        case .authentication: 18
        case .experimental: 19
        case .cloud: 20
        case .augmentedReality: 21
        case .print: 22
        case .audioModes: 31
        case .unknown(let value): value
        }
    }

    public static func < (lhs: BossAppleBmapFunctionBlock, rhs: BossAppleBmapFunctionBlock) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .productInfo: "productInfo"
        case .settings: "settings"
        case .status: "status"
        case .firmwareUpdate: "firmwareUpdate"
        case .deviceManagement: "deviceManagement"
        case .audioManagement: "audioManagement"
        case .callManagement: "callManagement"
        case .control: "control"
        case .debug: "debug"
        case .notification: "notification"
        case .reservedBosebuild1: "reservedBosebuild1"
        case .reservedBosebuild2: "reservedBosebuild2"
        case .hearingAssistance: "hearingAssistance"
        case .dataCollection: "dataCollection"
        case .heartRate: "heartRate"
        case .peerBud: "peerBud"
        case .vpa: "vpa"
        case .wifi: "wifi"
        case .authentication: "authentication"
        case .experimental: "experimental"
        case .cloud: "cloud"
        case .augmentedReality: "augmentedReality"
        case .print: "print"
        case .audioModes: "audioModes"
        case .unknown(let rawValue): "unknown(\(rawValue))"
        }
    }
}

public struct BossAppleFunctionBlockSet: Equatable, Sendable {
    private let bits: Set<Int>

    public init(bits: Set<Int> = []) {
        self.bits = bits
    }

    public init(bytes: Data) {
        var values = Set<Int>()
        let totalBits = bytes.count * 8
        for bitIndex in 0..<totalBits {
            let byteIndex = bytes.count - (bitIndex / 8) - 1
            let mask = 1 << (bitIndex % 8)
            if Int(bytes[byteIndex]) & mask > 0 {
                values.insert(bitIndex)
            }
        }
        self.bits = values
    }

    public func contains(_ block: BossAppleBmapFunctionBlock) -> Bool {
        if block == .productInfo {
            return true
        }
        return bits.contains(Int(block.rawValue))
    }

    public func allBlocks() -> [BossAppleBmapFunctionBlock] {
        let blocks = bits
            .map { BossAppleBmapFunctionBlock(rawValue: UInt8($0)) }
            .filter {
                if case .unknown = $0 {
                    return false
                }
                return true
            }
            .sorted()

        if contains(.productInfo), !blocks.contains(.productInfo) {
            return [.productInfo] + blocks
        }

        return blocks
    }

    public func encoded() -> Data {
        let maxBit = bits.max() ?? -1
        if maxBit < 0 {
            return Data()
        }

        let byteCount = (maxBit + 8) / 8
        var output = Array(repeating: UInt8(0), count: byteCount)
        for bit in bits {
            let byteIndex = byteCount - (bit / 8) - 1
            output[byteIndex] |= UInt8(1 << (bit % 8))
        }
        return Data(output)
    }
}

public struct BossAppleBootstrappedDevice: Equatable, Sendable {
    public let bmapVersion: BossAppleBmapVersionInfo
    public let productID: UInt16
    public let productName: String
    public let productVariant: BossAppleProductVariant
    public let supportedFunctionBlocks: BossAppleFunctionBlockSet
    public let transportKind: BossAppleTransportKind
    public let defaultDeviceID: Int
    public let defaultPort: Int

    public init(
        bmapVersion: BossAppleBmapVersionInfo,
        productID: UInt16,
        productName: String,
        productVariant: BossAppleProductVariant,
        supportedFunctionBlocks: BossAppleFunctionBlockSet,
        transportKind: BossAppleTransportKind,
        defaultDeviceID: Int,
        defaultPort: Int
    ) {
        self.bmapVersion = bmapVersion
        self.productID = productID
        self.productName = productName
        self.productVariant = productVariant
        self.supportedFunctionBlocks = supportedFunctionBlocks
        self.transportKind = transportKind
        self.defaultDeviceID = defaultDeviceID
        self.defaultPort = defaultPort
    }
}

public enum BossAppleBmapErrorCode: UInt8, Sendable {
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

enum BossAppleBmapFunction: Hashable, Sendable {
    case productInfoFblockInfo
    case productInfoBmapVersion
    case productInfoAllFblocks
    case productInfoProductIDVariants
    case productInfoGetAllFunctions
    case productInfoFirmwareVersion
    case unknown(block: BossAppleBmapFunctionBlock, rawValue: UInt8)

    init(block: BossAppleBmapFunctionBlock, rawValue: UInt8) {
        switch (block, rawValue) {
        case (.productInfo, 0): self = .productInfoFblockInfo
        case (.productInfo, 1): self = .productInfoBmapVersion
        case (.productInfo, 2): self = .productInfoAllFblocks
        case (.productInfo, 3): self = .productInfoProductIDVariants
        case (.productInfo, 4): self = .productInfoGetAllFunctions
        case (.productInfo, 5): self = .productInfoFirmwareVersion
        default: self = .unknown(block: block, rawValue: rawValue)
        }
    }

    var block: BossAppleBmapFunctionBlock {
        switch self {
        case .productInfoFblockInfo,
             .productInfoBmapVersion,
             .productInfoAllFblocks,
             .productInfoProductIDVariants,
             .productInfoGetAllFunctions,
             .productInfoFirmwareVersion:
            return .productInfo
        case .unknown(let block, _):
            return block
        }
    }

    var rawValue: UInt8 {
        switch self {
        case .productInfoFblockInfo: 0
        case .productInfoBmapVersion: 1
        case .productInfoAllFblocks: 2
        case .productInfoProductIDVariants: 3
        case .productInfoGetAllFunctions: 4
        case .productInfoFirmwareVersion: 5
        case .unknown(_, let rawValue): rawValue
        }
    }

    var name: String {
        switch self {
        case .productInfoFblockInfo: "ProductInfoFblockInfo"
        case .productInfoBmapVersion: "ProductInfoBmapVersion"
        case .productInfoAllFblocks: "ProductInfoAllFblocks"
        case .productInfoProductIDVariants: "ProductInfoProductIdVariants"
        case .productInfoGetAllFunctions: "ProductInfoGetAllFunctions"
        case .productInfoFirmwareVersion: "ProductInfoFirmwareVersion"
        case .unknown(let block, let rawValue): "Unknown(\(block.rawValue):\(rawValue))"
        }
    }
}

enum BossAppleBmapOperatorType: String, Sendable {
    case command
    case response
    case unknown
}

enum BossAppleBmapOperator: Hashable, Sendable {
    case set
    case get
    case setGet
    case status
    case error
    case start
    case result
    case processing
    case unknown(UInt8)

    init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .set
        case 1: self = .get
        case 2: self = .setGet
        case 3: self = .status
        case 4: self = .error
        case 5: self = .start
        case 6: self = .result
        case 7: self = .processing
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: UInt8 {
        switch self {
        case .set: 0
        case .get: 1
        case .setGet: 2
        case .status: 3
        case .error: 4
        case .start: 5
        case .result: 6
        case .processing: 7
        case .unknown(let rawValue): rawValue
        }
    }

    var type: BossAppleBmapOperatorType {
        switch self {
        case .set, .get, .setGet, .start:
            return .command
        case .status, .error, .result, .processing:
            return .response
        case .unknown:
            return .unknown
        }
    }

    var displayName: String {
        switch self {
        case .set: "set"
        case .get: "get"
        case .setGet: "setGet"
        case .status: "status"
        case .error: "error"
        case .start: "start"
        case .result: "result"
        case .processing: "processing"
        case .unknown(let rawValue): "unknown(\(rawValue))"
        }
    }
}

struct BossAppleBmapPacket: Equatable, Sendable {
    static let headerSize = 4

    let functionBlock: BossAppleBmapFunctionBlock
    let function: BossAppleBmapFunction
    let deviceID: Int
    let port: Int
    let `operator`: BossAppleBmapOperator
    let payload: Data

    init(
        functionBlock: BossAppleBmapFunctionBlock,
        function: BossAppleBmapFunction,
        deviceID: Int = 0,
        port: Int = 0,
        operator: BossAppleBmapOperator,
        payload: Data = Data()
    ) {
        self.functionBlock = functionBlock
        self.function = function
        self.deviceID = deviceID
        self.port = port
        self.operator = `operator`
        self.payload = payload
    }
}

enum BossAppleLinkError: Error, Equatable {
    case unexpectedStreamTermination
}

private enum BossAppleProtocolError: LocalizedError, Equatable {
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .invalidPayload(let message):
            return message
        }
    }
}

enum BossAppleSettingsProtocol {
    static let settingsGetAllFunctionRaw: UInt8 = 0x01
    static let standbyTimerFunctionRaw: UInt8 = 0x04
    static let onHeadDetectionFunctionRaw: UInt8 = 0x10
    static let autoPlayPauseFunctionRaw: UInt8 = 0x18
    static let volumeControlFunctionRaw: UInt8 = 0x1C
    static let autoAnswerFunctionRaw: UInt8 = 0x1B
    static let autoAwareFunctionRaw: UInt8 = 0x1D
}

enum BossAppleAudioModesProtocol {
    static let capabilitiesFunctionRaw: UInt8 = 0x02
    static let currentModeFunctionRaw: UInt8 = 0x03
    static let modeConfigFunctionRaw: UInt8 = 0x06
    static let favoritesFunctionRaw: UInt8 = 0x08
    static let settingsConfigFunctionRaw: UInt8 = 0x0A
    static let namesSupportedFunctionRaw: UInt8 = 0x0B
}

enum BossAppleProductCatalog {
    static let wolverine = BossAppleProductDefinition(
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

    static func product(for id: UInt16) -> BossAppleProductDefinition? {
        switch id {
        case wolverine.id:
            return wolverine
        default:
            return nil
        }
    }
}

public enum BossAppleEqualizerBand: Sendable, Equatable, Hashable {
    case bass
    case mid
    case treble
    case unknown(UInt8)

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .bass
        case 1: self = .mid
        case 2: self = .treble
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: UInt8 {
        switch self {
        case .bass: 0
        case .mid: 1
        case .treble: 2
        case .unknown(let rawValue): rawValue
        }
    }

    public var displayName: String {
        switch self {
        case .bass: "bass"
        case .mid: "mid"
        case .treble: "treble"
        case .unknown(let rawValue): "unknown(\(rawValue))"
        }
    }
}

public struct BossAppleEqualizerRangeLevel: Sendable, Equatable {
    public let band: BossAppleEqualizerBand
    public let currentLevel: Int
    public let minLevel: Int
    public let maxLevel: Int

    public init(
        band: BossAppleEqualizerBand,
        currentLevel: Int,
        minLevel: Int,
        maxLevel: Int
    ) {
        self.band = band
        self.currentLevel = currentLevel
        self.minLevel = minLevel
        self.maxLevel = maxLevel
    }
}

public struct BossAppleEqualizerSettings: Sendable, Equatable {
    public let ranges: [BossAppleEqualizerRangeLevel]

    public init(ranges: [BossAppleEqualizerRangeLevel]) {
        self.ranges = ranges.sorted { lhs, rhs in
            lhs.band.rawValue < rhs.band.rawValue
        }
    }

    public func range(for band: BossAppleEqualizerBand) -> BossAppleEqualizerRangeLevel? {
        ranges.first { $0.band == band }
    }

    public var bass: BossAppleEqualizerRangeLevel? { range(for: .bass) }
    public var mid: BossAppleEqualizerRangeLevel? { range(for: .mid) }
    public var treble: BossAppleEqualizerRangeLevel? { range(for: .treble) }
}

public struct BossAppleEqualizerSettingsPatch: Sendable, Equatable {
    public let bass: Int?
    public let mid: Int?
    public let treble: Int?

    public init(
        bass: Int? = nil,
        mid: Int? = nil,
        treble: Int? = nil
    ) {
        self.bass = bass
        self.mid = mid
        self.treble = treble
    }

    public var isEmpty: Bool {
        bass == nil && mid == nil && treble == nil
    }

    public var requestedLevels: [(BossAppleEqualizerBand, Int)] {
        var values: [(BossAppleEqualizerBand, Int)] = []
        if let bass { values.append((.bass, bass)) }
        if let mid { values.append((.mid, mid)) }
        if let treble { values.append((.treble, treble)) }
        return values
    }

    public func matches(_ settings: BossAppleEqualizerSettings) -> Bool {
        for (band, level) in requestedLevels {
            guard settings.range(for: band)?.currentLevel == level else {
                return false
            }
        }
        return true
    }
}

public struct BossAppleAudioModesCapabilities: Equatable, Sendable {
    public let boseModes: Int
    public let userModes: Int

    public init(boseModes: Int, userModes: Int) {
        self.boseModes = boseModes
        self.userModes = userModes
    }

    public var totalModes: Int { boseModes + userModes }
}

public struct BossAppleAudioModeInfo: Equatable, Sendable {
    public let modeIndex: Int
    public let name: String
    public let favorite: Bool
    public let userConfigurable: Bool
    public let userConfigured: Bool

    public init(
        modeIndex: Int,
        name: String,
        favorite: Bool,
        userConfigurable: Bool,
        userConfigured: Bool
    ) {
        self.modeIndex = modeIndex
        self.name = name
        self.favorite = favorite
        self.userConfigurable = userConfigurable
        self.userConfigured = userConfigured
    }
}

public struct BossAppleAudioModePrompt: Equatable, Sendable {
    public let byte1: UInt8
    public let byte2: UInt8
    public let name: String

    public init(byte1: UInt8, byte2: UInt8, name: String) {
        self.byte1 = byte1
        self.byte2 = byte2
        self.name = name
    }

    public static let none = BossAppleAudioModePrompt(byte1: 0, byte2: 0, name: "None")
    public static let quiet = BossAppleAudioModePrompt(byte1: 0, byte2: 1, name: "Quiet")
    public static let aware = BossAppleAudioModePrompt(byte1: 0, byte2: 2, name: "Aware")
    public static let transparent = BossAppleAudioModePrompt(byte1: 0, byte2: 3, name: "Transparent")
    public static let transparency = BossAppleAudioModePrompt(byte1: 0, byte2: 4, name: "Transparency")
    public static let masking = BossAppleAudioModePrompt(byte1: 0, byte2: 5, name: "Masking")
    public static let comfort = BossAppleAudioModePrompt(byte1: 0, byte2: 6, name: "Comfort")
    public static let commute = BossAppleAudioModePrompt(byte1: 0, byte2: 7, name: "Commute")
    public static let outdoor = BossAppleAudioModePrompt(byte1: 0, byte2: 8, name: "Outdoor")
    public static let workout = BossAppleAudioModePrompt(byte1: 0, byte2: 9, name: "Workout")
    public static let home = BossAppleAudioModePrompt(byte1: 0, byte2: 10, name: "Home")
    public static let work = BossAppleAudioModePrompt(byte1: 0, byte2: 11, name: "Work")
    public static let music = BossAppleAudioModePrompt(byte1: 0, byte2: 12, name: "Music")
    public static let focus = BossAppleAudioModePrompt(byte1: 0, byte2: 13, name: "Focus")
    public static let relax = BossAppleAudioModePrompt(byte1: 0, byte2: 14, name: "Relax")
    public static let flight = BossAppleAudioModePrompt(byte1: 0, byte2: 15, name: "Flight")
    public static let airport = BossAppleAudioModePrompt(byte1: 0, byte2: 16, name: "Airport")
    public static let driving = BossAppleAudioModePrompt(byte1: 0, byte2: 17, name: "Driving")
    public static let training = BossAppleAudioModePrompt(byte1: 0, byte2: 18, name: "Training")
    public static let gym = BossAppleAudioModePrompt(byte1: 0, byte2: 19, name: "Gym")
    public static let run = BossAppleAudioModePrompt(byte1: 0, byte2: 20, name: "Run")
    public static let walk = BossAppleAudioModePrompt(byte1: 0, byte2: 21, name: "Walk")
    public static let hike = BossAppleAudioModePrompt(byte1: 0, byte2: 22, name: "Hike")
    public static let talk = BossAppleAudioModePrompt(byte1: 0, byte2: 23, name: "Talk")
    public static let call = BossAppleAudioModePrompt(byte1: 0, byte2: 24, name: "Call")
    public static let whisper = BossAppleAudioModePrompt(byte1: 0, byte2: 25, name: "Whisper")
    public static let hearing = BossAppleAudioModePrompt(byte1: 0, byte2: 26, name: "Hearing")
    public static let learn = BossAppleAudioModePrompt(byte1: 0, byte2: 27, name: "Learn")
    public static let podcast = BossAppleAudioModePrompt(byte1: 0, byte2: 28, name: "Podcast")
    public static let audiobook = BossAppleAudioModePrompt(byte1: 0, byte2: 29, name: "Audiobook")
    public static let calm = BossAppleAudioModePrompt(byte1: 0, byte2: 30, name: "Calm")
    public static let sleep = BossAppleAudioModePrompt(byte1: 0, byte2: 31, name: "Sleep")
    public static let meditate = BossAppleAudioModePrompt(byte1: 0, byte2: 32, name: "Meditate")
    public static let yoga = BossAppleAudioModePrompt(byte1: 0, byte2: 33, name: "Yoga")
    public static let immersion = BossAppleAudioModePrompt(byte1: 0, byte2: 34, name: "Immersion")
    public static let stereo = BossAppleAudioModePrompt(byte1: 0, byte2: 35, name: "Stereo")
    public static let cinema = BossAppleAudioModePrompt(byte1: 0, byte2: 36, name: "Cinema")

    public static let allKnown: [BossAppleAudioModePrompt] = [
        .none, .quiet, .aware, .transparent, .transparency, .masking, .comfort, .commute,
        .outdoor, .workout, .home, .work, .music, .focus, .relax, .flight, .airport,
        .driving, .training, .gym, .run, .walk, .hike, .talk, .call, .whisper,
        .hearing, .learn, .podcast, .audiobook, .calm, .sleep, .meditate, .yoga,
        .immersion, .stereo, .cinema
    ]

    public static func known(byte1: UInt8, byte2: UInt8) -> BossAppleAudioModePrompt {
        allKnown.first { $0.byte1 == byte1 && $0.byte2 == byte2 } ??
            BossAppleAudioModePrompt(byte1: byte1, byte2: byte2, name: "Unknown")
    }
}

public struct BossAppleAudioModeConfig: Equatable, Sendable {
    public let modeIndex: Int
    public let prompt: BossAppleAudioModePrompt
    public let name: String
    public let favorite: Bool
    public let userConfigurable: Bool
    public let userConfigured: Bool
    public let settings: BossAppleAudioModeSettingsConfig

    public init(
        modeIndex: Int,
        prompt: BossAppleAudioModePrompt,
        name: String,
        favorite: Bool,
        userConfigurable: Bool,
        userConfigured: Bool,
        settings: BossAppleAudioModeSettingsConfig
    ) {
        self.modeIndex = modeIndex
        self.prompt = prompt
        self.name = name
        self.favorite = favorite
        self.userConfigurable = userConfigurable
        self.userConfigured = userConfigured
        self.settings = settings
    }

    public var info: BossAppleAudioModeInfo {
        BossAppleAudioModeInfo(
            modeIndex: modeIndex,
            name: name,
            favorite: favorite,
            userConfigurable: userConfigurable,
            userConfigured: userConfigured
        )
    }

    public var deletedSettingsBaseline: BossAppleAudioModeSettingsConfig {
        BossAppleAudioModeSettingsConfig(
            cncLevel: 5,
            autoCNCEnabled: settings.autoCNCEnabled,
            spatialAudioMode: settings.spatialAudioMode,
            windBlockEnabled: settings.windBlockEnabled,
            ancToggleEnabled: settings.ancToggleEnabled
        )
    }
}

public enum BossAppleSpatialAudioMode: UInt8, CaseIterable, Sendable {
    case off = 0
    case room = 1
    case head = 2

    public var displayName: String {
        switch self {
        case .off: "off"
        case .room: "room"
        case .head: "head"
        }
    }
}

public struct BossAppleAudioModeSettingsConfig: Equatable, Sendable {
    public let cncLevel: Int
    public let autoCNCEnabled: Bool
    public let spatialAudioMode: BossAppleSpatialAudioMode
    public let windBlockEnabled: Bool
    public let ancToggleEnabled: Bool

    public init(
        cncLevel: Int,
        autoCNCEnabled: Bool,
        spatialAudioMode: BossAppleSpatialAudioMode,
        windBlockEnabled: Bool,
        ancToggleEnabled: Bool
    ) {
        self.cncLevel = cncLevel
        self.autoCNCEnabled = autoCNCEnabled
        self.spatialAudioMode = spatialAudioMode
        self.windBlockEnabled = windBlockEnabled
        self.ancToggleEnabled = ancToggleEnabled
    }
}

public struct BossAppleAudioModeSettingsConfigPatch: Equatable, Sendable {
    public let cncLevel: Int?
    public let autoCNCEnabled: Bool?
    public let spatialAudioMode: BossAppleSpatialAudioMode?
    public let windBlockEnabled: Bool?
    public let ancToggleEnabled: Bool?

    public init(
        cncLevel: Int? = nil,
        autoCNCEnabled: Bool? = nil,
        spatialAudioMode: BossAppleSpatialAudioMode? = nil,
        windBlockEnabled: Bool? = nil,
        ancToggleEnabled: Bool? = nil
    ) {
        self.cncLevel = cncLevel
        self.autoCNCEnabled = autoCNCEnabled
        self.spatialAudioMode = spatialAudioMode
        self.windBlockEnabled = windBlockEnabled
        self.ancToggleEnabled = ancToggleEnabled
    }

    public var isEmpty: Bool {
        cncLevel == nil &&
            autoCNCEnabled == nil &&
            spatialAudioMode == nil &&
            windBlockEnabled == nil &&
            ancToggleEnabled == nil
    }

    public func merged(with current: BossAppleAudioModeSettingsConfig) -> BossAppleAudioModeSettingsConfig {
        BossAppleAudioModeSettingsConfig(
            cncLevel: cncLevel ?? current.cncLevel,
            autoCNCEnabled: autoCNCEnabled ?? current.autoCNCEnabled,
            spatialAudioMode: spatialAudioMode ?? current.spatialAudioMode,
            windBlockEnabled: windBlockEnabled ?? current.windBlockEnabled,
            ancToggleEnabled: ancToggleEnabled ?? current.ancToggleEnabled
        )
    }

    public func matches(_ config: BossAppleAudioModeSettingsConfig) -> Bool {
        if let cncLevel, config.cncLevel != cncLevel { return false }
        if let autoCNCEnabled, config.autoCNCEnabled != autoCNCEnabled { return false }
        if let spatialAudioMode, config.spatialAudioMode != spatialAudioMode { return false }
        if let windBlockEnabled, config.windBlockEnabled != windBlockEnabled { return false }
        if let ancToggleEnabled, config.ancToggleEnabled != ancToggleEnabled { return false }
        return true
    }
}

public struct BossAppleStandbyTimerValue: Equatable, Sendable {
    public let minutes: Int
    public let supportsTwoByteMinutes: Bool

    public init(minutes: Int, supportsTwoByteMinutes: Bool) {
        self.minutes = minutes
        self.supportsTwoByteMinutes = supportsTwoByteMinutes
    }
}

public struct BossAppleOnHeadDetectionValue: Equatable, Sendable {
    public let isEnabled: Bool
    public let isAutoPlayEnabled: Bool?
    public let isAutoAnswerEnabled: Bool?
    public let isAutoTransparencyEnabled: Bool?

    public init(
        isEnabled: Bool,
        isAutoPlayEnabled: Bool?,
        isAutoAnswerEnabled: Bool?,
        isAutoTransparencyEnabled: Bool?
    ) {
        self.isEnabled = isEnabled
        self.isAutoPlayEnabled = isAutoPlayEnabled
        self.isAutoAnswerEnabled = isAutoAnswerEnabled
        self.isAutoTransparencyEnabled = isAutoTransparencyEnabled
    }
}

public struct BossAppleOnHeadDetectionPatch: Equatable, Sendable {
    public let isEnabled: Bool?
    public let isAutoPlayEnabled: Bool?
    public let isAutoAnswerEnabled: Bool?
    public let isAutoTransparencyEnabled: Bool?

    public init(
        isEnabled: Bool? = nil,
        isAutoPlayEnabled: Bool? = nil,
        isAutoAnswerEnabled: Bool? = nil,
        isAutoTransparencyEnabled: Bool? = nil
    ) {
        self.isEnabled = isEnabled
        self.isAutoPlayEnabled = isAutoPlayEnabled
        self.isAutoAnswerEnabled = isAutoAnswerEnabled
        self.isAutoTransparencyEnabled = isAutoTransparencyEnabled
    }

    public var isEmpty: Bool {
        isEnabled == nil &&
            isAutoPlayEnabled == nil &&
            isAutoAnswerEnabled == nil &&
            isAutoTransparencyEnabled == nil
    }

    public func merged(with current: BossAppleOnHeadDetectionValue) -> BossAppleOnHeadDetectionValue {
        BossAppleOnHeadDetectionValue(
            isEnabled: isEnabled ?? current.isEnabled,
            isAutoPlayEnabled: isAutoPlayEnabled ?? current.isAutoPlayEnabled,
            isAutoAnswerEnabled: isAutoAnswerEnabled ?? current.isAutoAnswerEnabled,
            isAutoTransparencyEnabled: isAutoTransparencyEnabled ?? current.isAutoTransparencyEnabled
        )
    }
}

public enum BossAppleVolumeControlValue: UInt8, CaseIterable, Sendable {
    case disabled = 0
    case button = 1
    case capTouch = 2
    case imu = 3

    public var displayName: String {
        switch self {
        case .disabled: "disabled"
        case .button: "button"
        case .capTouch: "captouch"
        case .imu: "imu"
        }
    }
}

public struct BossAppleVolumeControlStatus: Equatable, Sendable {
    public let value: BossAppleVolumeControlValue
    public let supportedValues: [BossAppleVolumeControlValue]?

    public init(
        value: BossAppleVolumeControlValue,
        supportedValues: [BossAppleVolumeControlValue]? = nil
    ) {
        self.value = value
        self.supportedValues = supportedValues
    }
}

public struct BossAppleDeviceSettings: Equatable, Sendable {
    public let wearDetection: BossAppleOnHeadDetectionValue?
    public let autoAwareEnabled: Bool?
    public let autoPlayPauseEnabled: Bool?
    public let autoAnswerEnabled: Bool?
    public let volumeControl: BossAppleVolumeControlStatus?

    public init(
        wearDetection: BossAppleOnHeadDetectionValue?,
        autoAwareEnabled: Bool?,
        autoPlayPauseEnabled: Bool?,
        autoAnswerEnabled: Bool?,
        volumeControl: BossAppleVolumeControlStatus?
    ) {
        self.wearDetection = wearDetection
        self.autoAwareEnabled = autoAwareEnabled
        self.autoPlayPauseEnabled = autoPlayPauseEnabled
        self.autoAnswerEnabled = autoAnswerEnabled
        self.volumeControl = volumeControl
    }
}

public struct BossAppleDeviceSettingsAvailability: Equatable, Sendable {
    public let wearDetection: Bool
    public let autoAware: Bool
    public let autoPlayPause: Bool
    public let autoAnswer: Bool
    public let volumeControl: Bool

    public init(
        wearDetection: Bool,
        autoAware: Bool,
        autoPlayPause: Bool,
        autoAnswer: Bool,
        volumeControl: Bool
    ) {
        self.wearDetection = wearDetection
        self.autoAware = autoAware
        self.autoPlayPause = autoPlayPause
        self.autoAnswer = autoAnswer
        self.volumeControl = volumeControl
    }

    public var hasAnySupport: Bool {
        wearDetection || autoAware || autoPlayPause || autoAnswer || volumeControl
    }
}

public extension BossAppleDeviceSettings {
    var availability: BossAppleDeviceSettingsAvailability {
        BossAppleDeviceSettingsAvailability(
            wearDetection: wearDetection != nil,
            autoAware: autoAwareEnabled != nil,
            autoPlayPause: autoPlayPauseEnabled != nil || wearDetection?.isAutoPlayEnabled != nil,
            autoAnswer: autoAnswerEnabled != nil || wearDetection?.isAutoAnswerEnabled != nil,
            volumeControl: volumeControl != nil
        )
    }
}

struct BossAppleSettingsSnapshot: Sendable {
    private let packetsByFunctionRaw: [UInt8: BossAppleBmapPacket]

    init(packetsByFunctionRaw: [UInt8: BossAppleBmapPacket]) {
        self.packetsByFunctionRaw = packetsByFunctionRaw
    }

    init(encodedPackets bytes: Data) throws {
        guard let runtime = BossRustFfiRuntime.shared else {
            throw BossAppleControlError.unsupportedOperation("Rust runtime is required for settings snapshot decoding")
        }
        var offset = 0
        var packetsByFunctionRaw: [UInt8: BossAppleBmapPacket] = [:]

        while offset < bytes.count {
            guard offset + 4 <= bytes.count else {
                throw BossAppleProtocolError.invalidPayload("Settings snapshot length prefix was truncated")
            }
            let length = Int(bytes[offset])
                | (Int(bytes[offset + 1]) << 8)
                | (Int(bytes[offset + 2]) << 16)
                | (Int(bytes[offset + 3]) << 24)
            offset += 4

            guard length >= BossAppleBmapPacket.headerSize, offset + length <= bytes.count else {
                throw BossAppleProtocolError.invalidPayload("Settings snapshot packet length was invalid")
            }

            let packetBytes = Data(bytes[offset..<(offset + length)])
            let packet = try BossRustCodecBridge.decode(packetBytes, runtime: runtime)
            packetsByFunctionRaw[packet.function.rawValue] = packet
            offset += length
        }

        self.init(packetsByFunctionRaw: packetsByFunctionRaw)
    }

    func packet(functionRaw: UInt8) -> BossAppleBmapPacket? {
        packetsByFunctionRaw[functionRaw]
    }

    func standbyTimer() throws -> BossAppleStandbyTimerValue? {
        guard let packet = packet(functionRaw: BossAppleSettingsProtocol.standbyTimerFunctionRaw) else {
            return nil
        }
        return try BossRustCodecBridge.parseStandbyTimer(from: packet, runtime: requireRustRuntime())
    }

    func autoAware() throws -> Bool? {
        guard let packet = packet(functionRaw: BossAppleSettingsProtocol.autoAwareFunctionRaw) else {
            return nil
        }
        return try BossRustCodecBridge.parseEnabledFlag(from: packet, runtime: requireRustRuntime())
    }

    func onHeadDetection() throws -> BossAppleOnHeadDetectionValue? {
        guard let packet = packet(functionRaw: BossAppleSettingsProtocol.onHeadDetectionFunctionRaw) else {
            return nil
        }
        return try BossRustCodecBridge.parseOnHeadDetection(from: packet, runtime: requireRustRuntime())
    }

    func autoPlayPause() throws -> Bool? {
        guard let packet = packet(functionRaw: BossAppleSettingsProtocol.autoPlayPauseFunctionRaw) else {
            return nil
        }
        return try BossRustCodecBridge.parseEnabledFlag(from: packet, runtime: requireRustRuntime())
    }

    func autoAnswer() throws -> Bool? {
        if let packet = packet(functionRaw: BossAppleSettingsProtocol.autoAnswerFunctionRaw) {
            return try BossRustCodecBridge.parseEnabledFlag(from: packet, runtime: requireRustRuntime())
        }
        return try onHeadDetection()?.isAutoAnswerEnabled
    }

    func volumeControl() throws -> BossAppleVolumeControlStatus? {
        guard let packet = packet(functionRaw: BossAppleSettingsProtocol.volumeControlFunctionRaw) else {
            return nil
        }
        return try BossRustCodecBridge.parseVolumeControlStatus(from: packet, runtime: requireRustRuntime())
    }

    func deviceSettings() throws -> BossAppleDeviceSettings {
        BossAppleDeviceSettings(
            wearDetection: try onHeadDetection(),
            autoAwareEnabled: try autoAware(),
            autoPlayPauseEnabled: try autoPlayPause(),
            autoAnswerEnabled: try autoAnswer(),
            volumeControl: try volumeControl()
        )
    }
}

private extension BossAppleSettingsSnapshot {
    func requireRustRuntime() throws -> BossRustFfiRuntime {
        guard let runtime = BossRustFfiRuntime.shared else {
            throw BossAppleControlError.unsupportedOperation("Rust runtime is required for settings snapshot decoding")
        }
        return runtime
    }
}
