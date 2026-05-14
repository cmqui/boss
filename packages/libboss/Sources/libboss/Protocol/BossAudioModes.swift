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

public struct BossAudioModePrompt: Equatable, Sendable {
    public let byte1: UInt8
    public let byte2: UInt8
    public let name: String

    public init(byte1: UInt8, byte2: UInt8, name: String) {
        self.byte1 = byte1
        self.byte2 = byte2
        self.name = name
    }

    public static let none = BossAudioModePrompt(byte1: 0, byte2: 0, name: "None")
    public static let quiet = BossAudioModePrompt(byte1: 0, byte2: 1, name: "Quiet")
    public static let aware = BossAudioModePrompt(byte1: 0, byte2: 2, name: "Aware")
    public static let transparent = BossAudioModePrompt(byte1: 0, byte2: 3, name: "Transparent")
    public static let transparency = BossAudioModePrompt(byte1: 0, byte2: 4, name: "Transparency")
    public static let masking = BossAudioModePrompt(byte1: 0, byte2: 5, name: "Masking")
    public static let comfort = BossAudioModePrompt(byte1: 0, byte2: 6, name: "Comfort")
    public static let commute = BossAudioModePrompt(byte1: 0, byte2: 7, name: "Commute")
    public static let outdoor = BossAudioModePrompt(byte1: 0, byte2: 8, name: "Outdoor")
    public static let workout = BossAudioModePrompt(byte1: 0, byte2: 9, name: "Workout")
    public static let home = BossAudioModePrompt(byte1: 0, byte2: 10, name: "Home")
    public static let work = BossAudioModePrompt(byte1: 0, byte2: 11, name: "Work")
    public static let music = BossAudioModePrompt(byte1: 0, byte2: 12, name: "Music")
    public static let focus = BossAudioModePrompt(byte1: 0, byte2: 13, name: "Focus")
    public static let relax = BossAudioModePrompt(byte1: 0, byte2: 14, name: "Relax")
    public static let flight = BossAudioModePrompt(byte1: 0, byte2: 15, name: "Flight")
    public static let airport = BossAudioModePrompt(byte1: 0, byte2: 16, name: "Airport")
    public static let driving = BossAudioModePrompt(byte1: 0, byte2: 17, name: "Driving")
    public static let training = BossAudioModePrompt(byte1: 0, byte2: 18, name: "Training")
    public static let gym = BossAudioModePrompt(byte1: 0, byte2: 19, name: "Gym")
    public static let run = BossAudioModePrompt(byte1: 0, byte2: 20, name: "Run")
    public static let walk = BossAudioModePrompt(byte1: 0, byte2: 21, name: "Walk")
    public static let hike = BossAudioModePrompt(byte1: 0, byte2: 22, name: "Hike")
    public static let talk = BossAudioModePrompt(byte1: 0, byte2: 23, name: "Talk")
    public static let call = BossAudioModePrompt(byte1: 0, byte2: 24, name: "Call")
    public static let whisper = BossAudioModePrompt(byte1: 0, byte2: 25, name: "Whisper")
    public static let hearing = BossAudioModePrompt(byte1: 0, byte2: 26, name: "Hearing")
    public static let learn = BossAudioModePrompt(byte1: 0, byte2: 27, name: "Learn")
    public static let podcast = BossAudioModePrompt(byte1: 0, byte2: 28, name: "Podcast")
    public static let audiobook = BossAudioModePrompt(byte1: 0, byte2: 29, name: "Audiobook")
    public static let calm = BossAudioModePrompt(byte1: 0, byte2: 30, name: "Calm")
    public static let sleep = BossAudioModePrompt(byte1: 0, byte2: 31, name: "Sleep")
    public static let meditate = BossAudioModePrompt(byte1: 0, byte2: 32, name: "Meditate")
    public static let yoga = BossAudioModePrompt(byte1: 0, byte2: 33, name: "Yoga")
    public static let immersion = BossAudioModePrompt(byte1: 0, byte2: 34, name: "Immersion")
    public static let stereo = BossAudioModePrompt(byte1: 0, byte2: 35, name: "Stereo")
    public static let cinema = BossAudioModePrompt(byte1: 0, byte2: 36, name: "Cinema")

    public static let allKnown: [BossAudioModePrompt] = [
        .none, .quiet, .aware, .transparent, .transparency, .masking, .comfort, .commute,
        .outdoor, .workout, .home, .work, .music, .focus, .relax, .flight, .airport,
        .driving, .training, .gym, .run, .walk, .hike, .talk, .call, .whisper,
        .hearing, .learn, .podcast, .audiobook, .calm, .sleep, .meditate, .yoga,
        .immersion, .stereo, .cinema
    ]

    public static func known(byte1: UInt8, byte2: UInt8) -> BossAudioModePrompt {
        allKnown.first { $0.byte1 == byte1 && $0.byte2 == byte2 } ??
            BossAudioModePrompt(byte1: byte1, byte2: byte2, name: "Unknown")
    }
}

public struct BossAudioModeConfig: Equatable, Sendable {
    public let modeIndex: Int
    public let prompt: BossAudioModePrompt
    public let name: String
    public let favorite: Bool
    public let userConfigurable: Bool
    public let userConfigured: Bool
    public let settings: BossAudioModeSettingsConfig

    public init(
        modeIndex: Int,
        prompt: BossAudioModePrompt,
        name: String,
        favorite: Bool,
        userConfigurable: Bool,
        userConfigured: Bool,
        settings: BossAudioModeSettingsConfig
    ) {
        self.modeIndex = modeIndex
        self.prompt = prompt
        self.name = name
        self.favorite = favorite
        self.userConfigurable = userConfigurable
        self.userConfigured = userConfigured
        self.settings = settings
    }

    public var info: BossAudioModeInfo {
        BossAudioModeInfo(
            modeIndex: modeIndex,
            name: name,
            favorite: favorite,
            userConfigurable: userConfigurable,
            userConfigured: userConfigured
        )
    }

    public var deletedSettingsBaseline: BossAudioModeSettingsConfig {
        BossAudioModeSettingsConfig(
            cncLevel: 5,
            autoCNCEnabled: settings.autoCNCEnabled,
            spatialAudioMode: settings.spatialAudioMode,
            windBlockEnabled: settings.windBlockEnabled,
            ancToggleEnabled: settings.ancToggleEnabled
        )
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
    public static let favoritesFunctionRaw: UInt8 = 0x08
    public static let settingsConfigFunctionRaw: UInt8 = 0x0A
    public static let namesSupportedFunctionRaw: UInt8 = 0x0B

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

    public static func favoritesGetPacket() -> BmapPacket {
        packet(functionRaw: favoritesFunctionRaw, operatorValue: .get)
    }

    public static func favoritesSetGetPacket(numberOfModes: Int, favoriteModeIndices: [Int]) throws -> BmapPacket {
        try packet(
            functionRaw: favoritesFunctionRaw,
            operatorValue: .setGet,
            payload: encodeFavorites(numberOfModes: numberOfModes, favoriteModeIndices: favoriteModeIndices)
        )
    }

    public static func modeConfigSetGetPacket(
        modeIndex: Int,
        prompt: BossAudioModePrompt = .none,
        name: String,
        settings: BossAudioModeSettingsConfig
    ) throws -> BmapPacket {
        try packet(
            functionRaw: modeConfigFunctionRaw,
            operatorValue: .setGet,
            payload: encodeModeConfigSetGetPayload(
                modeIndex: modeIndex,
                prompt: prompt,
                name: name,
                settings: settings
            )
        )
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

    public static func namesSupportedGetPacket() -> BmapPacket {
        packet(functionRaw: namesSupportedFunctionRaw, operatorValue: .get)
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
        try parseModeConfigDetail(from: packet).info
    }

    public static func parseModeConfigDetail(from packet: BmapPacket) throws -> BossAudioModeConfig {
        try requireStatus(packet)
        let payload = Array(packet.payload)
        if payload.count >= 48 {
            guard let spatialAudioMode = BossSpatialAudioMode(rawValue: payload[44]) else {
                throw BossAudioModesCodecError.invalidPayload("Unknown spatial audio mode: \(payload[44])")
            }
            return BossAudioModeConfig(
                modeIndex: Int(payload[0]),
                prompt: BossAudioModePrompt.known(byte1: payload[1], byte2: payload[2]),
                name: parseModeName(payload: payload, range: 6..<38),
                favorite: payload[5] == 1,
                userConfigurable: payload[3] == 1,
                userConfigured: payload[4] == 1,
                settings: BossAudioModeSettingsConfig(
                    cncLevel: Int(payload[42]),
                    autoCNCEnabled: payload[43] != 0,
                    spatialAudioMode: spatialAudioMode,
                    windBlockEnabled: payload[45] != 0,
                    ancToggleEnabled: payload[47] != 0
                )
            )
        }
        if payload.count >= 40 {
            guard let spatialAudioMode = BossSpatialAudioMode(rawValue: payload[37]) else {
                throw BossAudioModesCodecError.invalidPayload("Unknown spatial audio mode: \(payload[37])")
            }
            return BossAudioModeConfig(
                modeIndex: Int(payload[0]),
                prompt: BossAudioModePrompt.known(byte1: payload[1], byte2: payload[2]),
                name: parseModeName(payload: payload, range: 3..<35),
                favorite: false,
                userConfigurable: true,
                userConfigured: true,
                settings: BossAudioModeSettingsConfig(
                    cncLevel: Int(payload[35]),
                    autoCNCEnabled: payload[36] != 0,
                    spatialAudioMode: spatialAudioMode,
                    windBlockEnabled: payload[38] != 0,
                    ancToggleEnabled: payload[39] != 0
                )
            )
        }
        throw BossAudioModesCodecError.invalidPayload("Expected at least 40 payload bytes for audio mode config")
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

    public static func encodeModeConfigSetGetPayload(
        modeIndex: Int,
        prompt: BossAudioModePrompt,
        name: String,
        settings: BossAudioModeSettingsConfig
    ) throws -> Data {
        guard (0...255).contains(modeIndex) else {
            throw BossAudioModesCodecError.invalidPayload("Mode index must be in range 0...255")
        }
        var payload = Data()
        payload.reserveCapacity(40)
        payload.append(UInt8(modeIndex))
        payload.append(prompt.byte1)
        payload.append(prompt.byte2)
        payload.append(encodeModeName(name))
        payload.append(try encodeSettingsConfig(settings))
        return payload
    }

    public static func parseSupportedPrompts(from packet: BmapPacket) throws -> [BossAudioModePrompt] {
        try requireStatus(packet)
        let payload = Array(packet.payload)
        var prompts: [BossAudioModePrompt] = []
        for byteIndex in 0..<min(payload.count, 5) {
            let byte = payload[byteIndex]
            let maxBit = byteIndex == 4 ? 4 : 7
            for bitIndex in 0...maxBit where ((byte >> UInt8(bitIndex)) & 1) == 1 {
                prompts.append(.known(byte1: 0, byte2: UInt8(byteIndex * 8 + bitIndex)))
            }
        }
        return prompts
    }

    public static func parseFavorites(from packet: BmapPacket) throws -> [Int] {
        try requireStatus(packet)
        let payload = Array(packet.payload)
        guard let numberOfModesByte = payload.first else {
            throw BossAudioModesCodecError.invalidPayload("Expected at least one payload byte for audio mode favorites")
        }
        let numberOfModes = Int(numberOfModesByte)
        let bitmaskByteCount = Int(ceil(Double(numberOfModes) / 8.0))
        guard payload.count >= bitmaskByteCount + 1 else {
            throw BossAudioModesCodecError.invalidPayload("Expected \(bitmaskByteCount + 1) payload bytes for audio mode favorites")
        }

        var favorites: [Int] = []
        for payloadIndex in stride(from: bitmaskByteCount, through: 1, by: -1) {
            let byte = payload[payloadIndex]
            for bitIndex in 0..<8 where ((byte >> UInt8(bitIndex)) & 1) == 1 {
                let modeIndex = (bitmaskByteCount - payloadIndex) * 8 + bitIndex
                if modeIndex < numberOfModes {
                    favorites.append(modeIndex)
                }
            }
        }
        return favorites
    }

    public static func encodeFavorites(numberOfModes: Int, favoriteModeIndices: [Int]) throws -> Data {
        guard (0...255).contains(numberOfModes) else {
            throw BossAudioModesCodecError.invalidPayload("Number of audio modes must be in range 0...255")
        }
        let uniqueFavoriteIndices = Array(Set(favoriteModeIndices)).sorted()
        guard uniqueFavoriteIndices.allSatisfy({ (0..<numberOfModes).contains($0) }) else {
            throw BossAudioModesCodecError.invalidPayload("Favorite mode indices must be in range 0..<\(numberOfModes)")
        }

        let bitmaskByteCount = Int(ceil(Double(numberOfModes) / 8.0))
        var payload = Data(repeating: 0, count: bitmaskByteCount + 1)
        payload[0] = UInt8(numberOfModes)
        for favoriteModeIndex in uniqueFavoriteIndices {
            let bitmaskOffset = bitmaskByteCount - (favoriteModeIndex / 8)
            payload[bitmaskOffset] |= UInt8(1 << (favoriteModeIndex % 8))
        }
        return payload
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

    private static func parseModeName(payload: [UInt8], range: Range<Int>) -> String {
        let nameField = Data(payload[range])
        let zeroIndex = nameField.firstIndex(of: 0) ?? nameField.endIndex
        return String(data: nameField[..<zeroIndex], encoding: .utf8) ?? ""
    }

    private static func encodeModeName(_ name: String) -> Data {
        let bytes = Array(name.data(using: .utf8) ?? Data()).prefix(31)
        var data = Data(repeating: 0, count: 32)
        data.replaceSubrange(0..<bytes.count, with: bytes)
        return data
    }
}
