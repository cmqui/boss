import Foundation

public struct BossAppRuntimeConfiguration: Sendable, Equatable {
    public enum DeviceBackend: String, Sendable {
        case bluetooth
        case mock
    }

    public let deviceBackend: DeviceBackend

    public init(deviceBackend: DeviceBackend) {
        self.deviceBackend = deviceBackend
    }

    public static let bluetooth = BossAppRuntimeConfiguration(deviceBackend: .bluetooth)
    public static let mockDevice = BossAppRuntimeConfiguration(deviceBackend: .mock)

    public static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> BossAppRuntimeConfiguration {
        if arguments.contains("--live-device") {
            return .bluetooth
        }

        if arguments.contains("--mock-device") {
            return .mockDevice
        }

        if let explicitBackend = environment["BOSS_DEVICE_BACKEND"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            switch explicitBackend {
            case "bluetooth", "live":
                return .bluetooth
            case "mock":
                return .mockDevice
            default:
                break
            }
        }

        if let useMock = environment["BOSS_USE_MOCK_DEVICE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let boolValue = Self.boolValue(from: useMock) {
            return boolValue ? .mockDevice : .bluetooth
        }

        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return .mockDevice
        }

#if os(iOS)
        #if targetEnvironment(simulator)
            return .mockDevice
        #else
            return .bluetooth
        #endif
#else
        return .bluetooth
#endif
    }

    private static func boolValue(from rawValue: String) -> Bool? {
        switch rawValue.lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }
}
