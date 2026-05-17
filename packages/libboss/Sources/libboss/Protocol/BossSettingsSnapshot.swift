import Foundation

public struct BossStandbyTimerValue: Equatable, Sendable {
    public let minutes: Int
    public let supportsTwoByteMinutes: Bool

    public init(minutes: Int, supportsTwoByteMinutes: Bool) {
        self.minutes = minutes
        self.supportsTwoByteMinutes = supportsTwoByteMinutes
    }
}

public struct BossOnHeadDetectionValue: Equatable, Sendable {
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

public struct BossOnHeadDetectionPatch: Equatable, Sendable {
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

    public func merged(with current: BossOnHeadDetectionValue) -> BossOnHeadDetectionValue {
        BossOnHeadDetectionValue(
            isEnabled: isEnabled ?? current.isEnabled,
            isAutoPlayEnabled: isAutoPlayEnabled ?? current.isAutoPlayEnabled,
            isAutoAnswerEnabled: isAutoAnswerEnabled ?? current.isAutoAnswerEnabled,
            isAutoTransparencyEnabled: isAutoTransparencyEnabled ?? current.isAutoTransparencyEnabled
        )
    }
}

public struct BossDeviceSettings: Equatable, Sendable {
    public let wearDetection: BossOnHeadDetectionValue?
    public let autoAwareEnabled: Bool?
    public let autoPlayPauseEnabled: Bool?
    public let autoAnswerEnabled: Bool?
    public let volumeControl: BossVolumeControlStatus?

    public init(
        wearDetection: BossOnHeadDetectionValue?,
        autoAwareEnabled: Bool?,
        autoPlayPauseEnabled: Bool?,
        autoAnswerEnabled: Bool?,
        volumeControl: BossVolumeControlStatus?
    ) {
        self.wearDetection = wearDetection
        self.autoAwareEnabled = autoAwareEnabled
        self.autoPlayPauseEnabled = autoPlayPauseEnabled
        self.autoAnswerEnabled = autoAnswerEnabled
        self.volumeControl = volumeControl
    }
}

public enum BossSettingsCodecError: LocalizedError, Equatable {
    case unexpectedOperator(expected: BmapOperator, actual: BmapOperator)
    case invalidPayload(String)

    public var errorDescription: String? {
        switch self {
        case .unexpectedOperator(let expected, let actual):
            "Unexpected settings operator: expected \(expected.rawValue), got \(actual.rawValue)"
        case .invalidPayload(let message):
            message
        }
    }
}

public enum BossSettingsCodec {
    public static let settingsGetAllFunctionRaw: UInt8 = 0x01
    public static let standbyTimerFunctionRaw: UInt8 = 0x04
    public static let onHeadDetectionFunctionRaw: UInt8 = 0x10
    public static let autoPlayPauseFunctionRaw: UInt8 = 0x18
    public static let volumeControlFunctionRaw: UInt8 = 0x1C
    public static let autoAnswerFunctionRaw: UInt8 = 0x1B
    public static let autoAwareFunctionRaw: UInt8 = 0x1D

    public static func settingsPacket(
        functionRaw: UInt8,
        operatorValue: BmapOperator,
        payload: Data = Data()
    ) -> BmapPacket {
        let block = BmapFunctionBlock.settings
        return BmapPacket(
            functionBlock: block,
            function: BmapFunction(block: block, rawValue: functionRaw),
            operator: operatorValue,
            payload: payload
        )
    }

    public static func onHeadDetectionGetPacket() -> BmapPacket {
        settingsPacket(functionRaw: onHeadDetectionFunctionRaw, operatorValue: .get)
    }

    public static func standbyTimerGetPacket() -> BmapPacket {
        settingsPacket(functionRaw: standbyTimerFunctionRaw, operatorValue: .get)
    }

    public static func standbyTimerSetGetPacket(minutes: Int) throws -> BmapPacket {
        try validateStandbyTimerMinutes(minutes)
        return settingsPacket(
            functionRaw: standbyTimerFunctionRaw,
            operatorValue: .setGet,
            payload: encodeStandbyTimerMinutes(minutes)
        )
    }

    public static func onHeadDetectionSetGetPacket(_ value: BossOnHeadDetectionValue) -> BmapPacket {
        settingsPacket(
            functionRaw: onHeadDetectionFunctionRaw,
            operatorValue: .setGet,
            payload: encodeOnHeadDetection(value)
        )
    }

    public static func encodeStandbyTimerMinutes(_ minutes: Int) -> Data {
        if minutes <= 0xFF {
            return Data([UInt8(minutes)])
        }
        let low = UInt8(minutes & 0xFF)
        let high = UInt8((minutes >> 8) & 0xFF)
        return Data([low, high])
    }

    public static func parseStandbyTimer(from packet: BmapPacket) throws -> BossStandbyTimerValue {
        try requireStatus(packet)
        let payload = Array(packet.payload)
        guard !payload.isEmpty else {
            throw BossSettingsCodecError.invalidPayload("Standby timer payload was empty")
        }
        if payload.count < 3 {
            return BossStandbyTimerValue(minutes: Int(payload[0]), supportsTwoByteMinutes: false)
        }
        let minutes = (Int(payload[2]) << 8) | Int(payload[0])
        return BossStandbyTimerValue(minutes: minutes, supportsTwoByteMinutes: true)
    }

    public static func parseEnabledFlag(from packet: BmapPacket) throws -> Bool {
        try requireStatus(packet)
        guard let first = packet.payload.first else {
            throw BossSettingsCodecError.invalidPayload("Expected at least one payload byte")
        }
        return (first & 0x01) == 0x01
    }

    public static func parseOnHeadDetection(from packet: BmapPacket) throws -> BossOnHeadDetectionValue {
        try requireStatus(packet)
        let payload = Array(packet.payload)
        guard payload.count >= 2 else {
            throw BossSettingsCodecError.invalidPayload("Expected at least two payload bytes for on-head detection")
        }
        let flags = payload[0]
        let values = payload[1]
        return BossOnHeadDetectionValue(
            isEnabled: (flags & 0x01) == 0x01,
            isAutoPlayEnabled: (flags & 0x02) == 0x02 ? ((values & 0x01) == 0x01) : nil,
            isAutoAnswerEnabled: (flags & 0x04) == 0x04 ? ((values & 0x02) == 0x02) : nil,
            isAutoTransparencyEnabled: (flags & 0x08) == 0x08 ? ((values & 0x04) == 0x04) : nil
        )
    }

    public static func encodeOnHeadDetection(_ value: BossOnHeadDetectionValue) -> Data {
        Data([
            value.isEnabled ? 0x01 : 0x00,
            (value.isAutoPlayEnabled == true ? 0x01 : 0x00) |
                (value.isAutoAnswerEnabled == true ? 0x02 : 0x00) |
                (value.isAutoTransparencyEnabled == true ? 0x04 : 0x00)
        ])
    }

    private static func validateStandbyTimerMinutes(_ minutes: Int) throws {
        guard (0...0xFFFF).contains(minutes) else {
            throw BossSettingsCodecError.invalidPayload("Standby timer minutes must be in range 0...65535")
        }
    }

    private static func requireStatus(_ packet: BmapPacket) throws {
        guard packet.operator == .status else {
            throw BossSettingsCodecError.unexpectedOperator(expected: .status, actual: packet.operator)
        }
    }
}

public struct BossSettingsSnapshot: Sendable {
    private let packetsByFunctionRaw: [UInt8: BmapPacket]

    public init(packetsByFunctionRaw: [UInt8: BmapPacket]) {
        self.packetsByFunctionRaw = packetsByFunctionRaw
    }

    public func packet(functionRaw: UInt8) -> BmapPacket? {
        packetsByFunctionRaw[functionRaw]
    }

    public func standbyTimer() throws -> BossStandbyTimerValue? {
        guard let packet = packet(functionRaw: BossSettingsCodec.standbyTimerFunctionRaw) else {
            return nil
        }
        return try BossSettingsCodec.parseStandbyTimer(from: packet)
    }

    public func autoAware() throws -> Bool? {
        guard let packet = packet(functionRaw: BossSettingsCodec.autoAwareFunctionRaw) else {
            return nil
        }
        return try BossSettingsCodec.parseEnabledFlag(from: packet)
    }

    public func onHeadDetection() throws -> BossOnHeadDetectionValue? {
        guard let packet = packet(functionRaw: BossSettingsCodec.onHeadDetectionFunctionRaw) else {
            return nil
        }
        return try BossSettingsCodec.parseOnHeadDetection(from: packet)
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

    public func volumeControl() throws -> BossVolumeControlStatus? {
        guard let packet = packet(functionRaw: BossSettingsCodec.volumeControlFunctionRaw) else {
            return nil
        }
        return try BossAudioModesCodec.parseVolumeControlStatus(from: packet)
    }

    public func deviceSettings() throws -> BossDeviceSettings {
        try BossDeviceSettings(
            wearDetection: onHeadDetection(),
            autoAwareEnabled: autoAware(),
            autoPlayPauseEnabled: autoPlayPause(),
            autoAnswerEnabled: autoAnswer(),
            volumeControl: volumeControl()
        )
    }
}
