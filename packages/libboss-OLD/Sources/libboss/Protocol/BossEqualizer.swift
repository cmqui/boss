import Foundation

public enum BossEqualizerBand: Sendable, Equatable, Hashable {
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

public struct BossEqualizerRangeLevel: Sendable, Equatable {
    public let band: BossEqualizerBand
    public let currentLevel: Int
    public let minLevel: Int
    public let maxLevel: Int

    public init(
        band: BossEqualizerBand,
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

public struct BossEqualizerSettings: Sendable, Equatable {
    public let ranges: [BossEqualizerRangeLevel]

    public init(ranges: [BossEqualizerRangeLevel]) {
        self.ranges = ranges.sorted { lhs, rhs in
            lhs.band.rawValue < rhs.band.rawValue
        }
    }

    public func range(for band: BossEqualizerBand) -> BossEqualizerRangeLevel? {
        ranges.first { $0.band == band }
    }

    public var bass: BossEqualizerRangeLevel? {
        range(for: .bass)
    }

    public var mid: BossEqualizerRangeLevel? {
        range(for: .mid)
    }

    public var treble: BossEqualizerRangeLevel? {
        range(for: .treble)
    }
}

public struct BossEqualizerSettingsPatch: Sendable, Equatable {
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

    public var requestedLevels: [(BossEqualizerBand, Int)] {
        var values: [(BossEqualizerBand, Int)] = []
        if let bass {
            values.append((.bass, bass))
        }
        if let mid {
            values.append((.mid, mid))
        }
        if let treble {
            values.append((.treble, treble))
        }
        return values
    }

    public func matches(_ settings: BossEqualizerSettings) -> Bool {
        for (band, level) in requestedLevels {
            guard settings.range(for: band)?.currentLevel == level else {
                return false
            }
        }
        return true
    }
}

public extension BossSettingsCodec {
    static let rangeControlFunctionRaw: UInt8 = 0x07

    static func equalizerGetPacket() -> BmapPacket {
        settingsPacket(functionRaw: rangeControlFunctionRaw, operatorValue: .get)
    }

    static func equalizerSetGetPacket(
        targetLevel: Int,
        band: BossEqualizerBand
    ) throws -> BmapPacket {
        guard let targetLevel = Int8(exactly: targetLevel) else {
            throw BossSettingsCodecError.invalidPayload("Equalizer target level must be in range -128...127")
        }
        return settingsPacket(
            functionRaw: rangeControlFunctionRaw,
            operatorValue: .setGet,
            payload: Data([UInt8(bitPattern: targetLevel), band.rawValue])
        )
    }

    static func parseEqualizer(from packet: BmapPacket) throws -> BossEqualizerSettings {
        guard packet.operator == .status else {
            throw BossSettingsCodecError.unexpectedOperator(expected: .status, actual: packet.operator)
        }
        let payload = Array(packet.payload)
        guard payload.count.isMultiple(of: 4) else {
            throw BossSettingsCodecError.invalidPayload("Expected range-control payload length to be a multiple of four bytes")
        }

        let ranges = stride(from: 0, to: payload.count, by: 4).map { index in
            BossEqualizerRangeLevel(
                band: BossEqualizerBand(rawValue: payload[index + 3]),
                currentLevel: Int(Int8(bitPattern: payload[index + 2])),
                minLevel: Int(Int8(bitPattern: payload[index])),
                maxLevel: Int(Int8(bitPattern: payload[index + 1]))
            )
        }
        return BossEqualizerSettings(ranges: ranges)
    }
}

public extension BossSettingsSnapshot {
    func equalizer() throws -> BossEqualizerSettings? {
        guard let packet = packet(functionRaw: BossSettingsCodec.rangeControlFunctionRaw) else {
            return nil
        }
        return try BossSettingsCodec.parseEqualizer(from: packet)
    }
}
