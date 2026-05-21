import Foundation
@_exported import libboss

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

public typealias BossAppleBmapErrorCode = BmapErrorCode
typealias BossAppleBmapPacket = BmapPacket
typealias BossAppleBmapFunction = BmapFunction
typealias BossAppleBmapOperator = BmapOperator
typealias BossAppleBmapOperatorType = BmapOperatorType

typealias BossAppleLinkError = BossLinkError
typealias BossAppleSettingsCodec = BossSettingsCodec

public typealias BossAppleEqualizerSettings = BossEqualizerSettings
public typealias BossAppleEqualizerSettingsPatch = BossEqualizerSettingsPatch
public typealias BossAppleEqualizerBand = BossEqualizerBand

public typealias BossAppleAudioModeInfo = BossAudioModeInfo
public typealias BossAppleAudioModeConfig = BossAudioModeConfig
public typealias BossAppleAudioModesCapabilities = BossAudioModesCapabilities
public typealias BossAppleAudioModePrompt = BossAudioModePrompt
public typealias BossAppleAudioModeSettingsConfig = BossAudioModeSettingsConfig
public typealias BossAppleAudioModeSettingsConfigPatch = BossAudioModeSettingsConfigPatch
public typealias BossAppleSpatialAudioMode = BossSpatialAudioMode

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

public struct BossAppleSettingsSnapshot: Sendable {
    private let packetsByFunctionRaw: [UInt8: BmapPacket]

    init(packetsByFunctionRaw: [UInt8: BmapPacket]) {
        self.packetsByFunctionRaw = packetsByFunctionRaw
    }

    public init(encodedPackets bytes: Data) throws {
        var offset = 0
        var packetsByFunctionRaw: [UInt8: BmapPacket] = [:]

        while offset < bytes.count {
            guard offset + 4 <= bytes.count else {
                throw BossSettingsCodecError.invalidPayload("Settings snapshot length prefix was truncated")
            }
            let length = Int(bytes[offset])
                | (Int(bytes[offset + 1]) << 8)
                | (Int(bytes[offset + 2]) << 16)
                | (Int(bytes[offset + 3]) << 24)
            offset += 4

            guard length >= BmapPacket.headerSize, offset + length <= bytes.count else {
                throw BossSettingsCodecError.invalidPayload("Settings snapshot packet length was invalid")
            }

            let packetBytes = Data(bytes[offset..<(offset + length)])
            let packet = try BmapCodec.decode(packetBytes)
            packetsByFunctionRaw[packet.function.rawValue] = packet
            offset += length
        }

        self.init(packetsByFunctionRaw: packetsByFunctionRaw)
    }

    func packet(functionRaw: UInt8) -> BmapPacket? {
        packetsByFunctionRaw[functionRaw]
    }

    public func standbyTimer() throws -> BossAppleStandbyTimerValue? {
        guard let packet = packet(functionRaw: BossSettingsCodec.standbyTimerFunctionRaw) else {
            return nil
        }
        return BossAppleStandbyTimerValue(try BossSettingsCodec.parseStandbyTimer(from: packet))
    }

    public func autoAware() throws -> Bool? {
        guard let packet = packet(functionRaw: BossSettingsCodec.autoAwareFunctionRaw) else {
            return nil
        }
        return try BossSettingsCodec.parseEnabledFlag(from: packet)
    }

    public func onHeadDetection() throws -> BossAppleOnHeadDetectionValue? {
        guard let packet = packet(functionRaw: BossSettingsCodec.onHeadDetectionFunctionRaw) else {
            return nil
        }
        return BossAppleOnHeadDetectionValue(try BossSettingsCodec.parseOnHeadDetection(from: packet))
    }

    public func autoPlayPause() throws -> Bool? {
        guard let packet = packet(functionRaw: BossSettingsCodec.autoPlayPauseFunctionRaw) else {
            return nil
        }
        return try BossSettingsCodec.parseEnabledFlag(from: packet)
    }

    public func autoAnswer() throws -> Bool? {
        if let packet = packet(functionRaw: BossSettingsCodec.autoAnswerFunctionRaw) {
            return try BossSettingsCodec.parseEnabledFlag(from: packet)
        }
        return try onHeadDetection()?.isAutoAnswerEnabled
    }

    public func volumeControl() throws -> BossAppleVolumeControlStatus? {
        guard let packet = packet(functionRaw: BossSettingsCodec.volumeControlFunctionRaw) else {
            return nil
        }
        return BossAppleVolumeControlStatus(try BossAudioModesCodec.parseVolumeControlStatus(from: packet))
    }

    public func deviceSettings() throws -> BossAppleDeviceSettings {
        BossAppleDeviceSettings(
            wearDetection: try onHeadDetection(),
            autoAwareEnabled: try autoAware(),
            autoPlayPauseEnabled: try autoPlayPause(),
            autoAnswerEnabled: try autoAnswer(),
            volumeControl: try volumeControl()
        )
    }
}

extension BossAppleProductDefinition {
    init(_ core: ProductDefinition) {
        self.init(
            id: core.id,
            codeName: core.codeName,
            displayName: core.displayName,
            variants: core.variants
        )
    }
}

extension BossAppleStandbyTimerValue {
    init(_ core: BossStandbyTimerValue) {
        self.init(minutes: core.minutes, supportsTwoByteMinutes: core.supportsTwoByteMinutes)
    }

    var core: BossStandbyTimerValue {
        BossStandbyTimerValue(minutes: minutes, supportsTwoByteMinutes: supportsTwoByteMinutes)
    }
}

extension BossAppleOnHeadDetectionValue {
    init(_ core: BossOnHeadDetectionValue) {
        self.init(
            isEnabled: core.isEnabled,
            isAutoPlayEnabled: core.isAutoPlayEnabled,
            isAutoAnswerEnabled: core.isAutoAnswerEnabled,
            isAutoTransparencyEnabled: core.isAutoTransparencyEnabled
        )
    }

    var core: BossOnHeadDetectionValue {
        BossOnHeadDetectionValue(
            isEnabled: isEnabled,
            isAutoPlayEnabled: isAutoPlayEnabled,
            isAutoAnswerEnabled: isAutoAnswerEnabled,
            isAutoTransparencyEnabled: isAutoTransparencyEnabled
        )
    }
}

extension BossAppleVolumeControlValue {
    init(_ core: BossVolumeControlValue) {
        self = BossAppleVolumeControlValue(rawValue: core.rawValue) ?? .disabled
    }

    var core: BossVolumeControlValue {
        BossVolumeControlValue(rawValue: rawValue) ?? .disabled
    }
}

extension BossAppleVolumeControlStatus {
    init(_ core: BossVolumeControlStatus) {
        self.init(
            value: BossAppleVolumeControlValue(core.value),
            supportedValues: core.supportedValues?.map(BossAppleVolumeControlValue.init)
        )
    }

    var core: BossVolumeControlStatus {
        BossVolumeControlStatus(
            value: value.core,
            supportedValues: supportedValues?.map(\.core)
        )
    }
}

extension BossAppleDeviceSettings {
    init(_ core: BossDeviceSettings) {
        self.init(
            wearDetection: core.wearDetection.map(BossAppleOnHeadDetectionValue.init),
            autoAwareEnabled: core.autoAwareEnabled,
            autoPlayPauseEnabled: core.autoPlayPauseEnabled,
            autoAnswerEnabled: core.autoAnswerEnabled,
            volumeControl: core.volumeControl.map(BossAppleVolumeControlStatus.init)
        )
    }
}

extension BossAppleProductVariant {
    init(_ core: ProductIDVariant) {
        self.init(
            productID: core.productID,
            variant: core.variant,
            product: core.product.map(BossAppleProductDefinition.init),
            variantName: core.variantName
        )
    }
}

extension BossAppleFunctionBlockSet {
    init(_ core: FunctionBlockSet) {
        self.init(bytes: core.encoded())
    }
}

extension BossAppleTransportKind {
    init(_ core: BossTransportKind) {
        switch core {
        case .ble:
            self = .ble
        case .stream:
            self = .stream
        }
    }

    var core: BossTransportKind {
        switch self {
        case .ble:
            return .ble
        case .stream:
            return .stream
        }
    }
}

extension BossAppleBootstrappedDevice {
    init(_ core: BootstrappedDevice) {
        self.init(
            bmapVersion: BossAppleBmapVersionInfo(version: core.bmapVersion.version),
            productID: core.productID,
            productName: core.productName,
            productVariant: BossAppleProductVariant(core.productVariant),
            supportedFunctionBlocks: BossAppleFunctionBlockSet(core.supportedFunctionBlocks),
            transportKind: BossAppleTransportKind(core.transportKind),
            defaultDeviceID: core.defaultDeviceID,
            defaultPort: core.defaultPort
        )
    }
}
