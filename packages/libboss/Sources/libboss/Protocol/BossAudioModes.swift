import Foundation

public enum BossVolumeControlValue: UInt8, CaseIterable, Sendable {
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

public struct BossAudioModesCapabilities: Equatable, Sendable {
    public let boseModes: Int
    public let userModes: Int

    public init(boseModes: Int, userModes: Int) {
        self.boseModes = boseModes
        self.userModes = userModes
    }

    public var totalModes: Int {
        boseModes + userModes
    }
}

public struct BossAudioModeInfo: Equatable, Sendable {
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

public enum BossSpatialAudioMode: UInt8, CaseIterable, Sendable {
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

public struct BossAudioModeSettingsConfig: Equatable, Sendable {
    public let cncLevel: Int
    public let autoCNCEnabled: Bool
    public let spatialAudioMode: BossSpatialAudioMode
    public let windBlockEnabled: Bool
    public let ancToggleEnabled: Bool

    public init(
        cncLevel: Int,
        autoCNCEnabled: Bool,
        spatialAudioMode: BossSpatialAudioMode,
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

public struct BossAudioModeSettingsConfigPatch: Equatable, Sendable {
    public let cncLevel: Int?
    public let autoCNCEnabled: Bool?
    public let spatialAudioMode: BossSpatialAudioMode?
    public let windBlockEnabled: Bool?
    public let ancToggleEnabled: Bool?

    public init(
        cncLevel: Int? = nil,
        autoCNCEnabled: Bool? = nil,
        spatialAudioMode: BossSpatialAudioMode? = nil,
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

    public func merged(with current: BossAudioModeSettingsConfig) -> BossAudioModeSettingsConfig {
        BossAudioModeSettingsConfig(
            cncLevel: cncLevel ?? current.cncLevel,
            autoCNCEnabled: autoCNCEnabled ?? current.autoCNCEnabled,
            spatialAudioMode: spatialAudioMode ?? current.spatialAudioMode,
            windBlockEnabled: windBlockEnabled ?? current.windBlockEnabled,
            ancToggleEnabled: ancToggleEnabled ?? current.ancToggleEnabled
        )
    }

    public func matches(_ config: BossAudioModeSettingsConfig) -> Bool {
        if let cncLevel, config.cncLevel != cncLevel {
            return false
        }
        if let autoCNCEnabled, config.autoCNCEnabled != autoCNCEnabled {
            return false
        }
        if let spatialAudioMode, config.spatialAudioMode != spatialAudioMode {
            return false
        }
        if let windBlockEnabled, config.windBlockEnabled != windBlockEnabled {
            return false
        }
        if let ancToggleEnabled, config.ancToggleEnabled != ancToggleEnabled {
            return false
        }
        return true
    }
}

public struct BossVolumeControlStatus: Equatable, Sendable {
    public let value: BossVolumeControlValue

    public init(value: BossVolumeControlValue) {
        self.value = value
    }
}

public enum BossAudioModesCodecError: LocalizedError, Equatable {
    case unexpectedOperator(expected: BmapOperator, actual: BmapOperator)
    case invalidPayload(String)

    public var errorDescription: String? {
        switch self {
        case .unexpectedOperator(let expected, let actual):
            "Unexpected audio-modes operator: expected \(expected.rawValue), got \(actual.rawValue)"
        case .invalidPayload(let message):
            message
        }
    }
}

public enum BossAudioModesCodec {
    public static let capabilitiesFunctionRaw: UInt8 = 0x02
    public static let currentModeFunctionRaw: UInt8 = 0x03
    public static let modeConfigFunctionRaw: UInt8 = 0x06
    public static let settingsConfigFunctionRaw: UInt8 = 0x0A

    public static func packet(
        functionRaw: UInt8,
        operatorValue: BmapOperator,
        payload: Data = Data()
    ) -> BmapPacket {
        let block = BmapFunctionBlock.audioModes
        return BmapPacket(
            functionBlock: block,
            function: BmapFunction(block: block, rawValue: functionRaw),
            operator: operatorValue,
            payload: payload
        )
    }

    public static func currentModeGetPacket() -> BmapPacket {
        packet(functionRaw: currentModeFunctionRaw, operatorValue: .get)
    }

    public static func capabilitiesGetPacket() -> BmapPacket {
        packet(functionRaw: capabilitiesFunctionRaw, operatorValue: .get)
    }

    public static func modeConfigGetPacket(modeIndex: Int) -> BmapPacket {
        packet(functionRaw: modeConfigFunctionRaw, operatorValue: .get, payload: Data([UInt8(modeIndex)]))
    }

    public static func modeConfigStartPacket() -> BmapPacket {
        packet(functionRaw: modeConfigFunctionRaw, operatorValue: .start)
    }

    public static func currentModeStartPacket(modeIndex: Int, playVoicePrompt: Bool) -> BmapPacket {
        packet(
            functionRaw: currentModeFunctionRaw,
            operatorValue: .start,
            payload: Data([UInt8(modeIndex), playVoicePrompt ? 0x01 : 0x00])
        )
    }

    public static func settingsConfigGetPacket() -> BmapPacket {
        packet(functionRaw: settingsConfigFunctionRaw, operatorValue: .get)
    }

    public static func settingsConfigSetGetPacket(_ config: BossAudioModeSettingsConfig) throws -> BmapPacket {
        try packet(
            functionRaw: settingsConfigFunctionRaw,
            operatorValue: .setGet,
            payload: encodeSettingsConfig(config)
        )
    }

    public static func parseCapabilities(from packet: BmapPacket) throws -> BossAudioModesCapabilities {
        try requireStatus(packet)
        let payload = Array(packet.payload)
        guard payload.count >= 2 else {
            throw BossAudioModesCodecError.invalidPayload("Expected at least two payload bytes for audio mode capabilities")
        }
        return BossAudioModesCapabilities(
            boseModes: Int(payload[0]),
            userModes: Int(payload[1])
        )
    }

    public static func parseCurrentMode(from packet: BmapPacket) throws -> Int {
        try requireStatus(packet)
        guard let first = packet.payload.first else {
            throw BossAudioModesCodecError.invalidPayload("Expected at least one payload byte for current audio mode")
        }
        return Int(first)
    }

    public static func parseModeConfig(from packet: BmapPacket) throws -> BossAudioModeInfo {
        try requireStatus(packet)
        let payload = Array(packet.payload)
        guard payload.count >= 44 else {
            throw BossAudioModesCodecError.invalidPayload("Expected at least 44 payload bytes for audio mode config")
        }
        let nameField = Data(payload[6..<38])
        let zeroIndex = nameField.firstIndex(of: 0) ?? nameField.endIndex
        let trimmed = nameField[..<zeroIndex]
        let name = String(data: trimmed, encoding: .utf8) ?? ""
        return BossAudioModeInfo(
            modeIndex: Int(payload[0]),
            name: name,
            favorite: payload[5] == 1,
            userConfigurable: payload[3] == 1,
            userConfigured: payload[4] == 1
        )
    }

    public static func parseSettingsConfig(from packet: BmapPacket) throws -> BossAudioModeSettingsConfig {
        try requireStatus(packet)
        let payload = Array(packet.payload)
        guard payload.count >= 5 else {
            throw BossAudioModesCodecError.invalidPayload("Expected at least five payload bytes for audio mode settings config")
        }
        guard let spatialAudioMode = BossSpatialAudioMode(rawValue: payload[2]) else {
            throw BossAudioModesCodecError.invalidPayload("Unknown spatial audio mode: \(payload[2])")
        }
        return BossAudioModeSettingsConfig(
            cncLevel: Int(payload[0]),
            autoCNCEnabled: payload[1] != 0,
            spatialAudioMode: spatialAudioMode,
            windBlockEnabled: payload[3] != 0,
            ancToggleEnabled: payload[4] != 0
        )
    }

    public static func encodeSettingsConfig(_ config: BossAudioModeSettingsConfig) throws -> Data {
        guard (0...10).contains(config.cncLevel) else {
            throw BossAudioModesCodecError.invalidPayload("CNC level must be in range 0...10")
        }
        return Data([
            UInt8(config.cncLevel),
            config.autoCNCEnabled ? 0x01 : 0x00,
            config.spatialAudioMode.rawValue,
            config.windBlockEnabled ? 0x01 : 0x00,
            config.ancToggleEnabled ? 0x01 : 0x00
        ])
    }

    public static func parseVolumeControlStatus(from packet: BmapPacket) throws -> BossVolumeControlStatus {
        try requireStatus(packet)
        guard let first = packet.payload.first else {
            throw BossAudioModesCodecError.invalidPayload("Expected at least one payload byte for volume control")
        }
        let value = BossVolumeControlValue(rawValue: first) ?? .disabled
        return BossVolumeControlStatus(value: value)
    }

    private static func requireStatus(_ packet: BmapPacket) throws {
        guard packet.operator == .status else {
            throw BossAudioModesCodecError.unexpectedOperator(expected: .status, actual: packet.operator)
        }
    }
}
