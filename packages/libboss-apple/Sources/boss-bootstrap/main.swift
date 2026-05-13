import Foundation
import libboss
import libbossApple

@main
struct BossBootstrapCLI {
    static func main() async {
        do {
            let options = try Options.parse(arguments: CommandLine.arguments.dropFirst())
            let filter = AppleBossScanFilter(
                peripheralIdentifier: options.identifier,
                nameContains: options.nameContains,
                scanTimeout: .seconds(options.timeoutSeconds)
            )
            let device = try await bootstrap(
                filter: filter,
                options: options
            )

            print("Connected: \(options.nameContains ?? transportDescription(for: filter))")
            print("Transport: \(device.transportKind.rawValue)")
            print("BMAP: \(device.bmapVersion.version)")
            print("Product: \(device.productName) (\(String(format: "0x%04X", device.productID)))")
            print("Variant: \(device.productVariant.variantName ?? "Unknown")")
            print("Function blocks: \(device.supportedFunctionBlocks.sortedNames.joined(separator: ", "))")
        } catch {
            fputs("boss-bootstrap failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func bootstrap(
        filter: AppleBossScanFilter,
        options: Options
    ) async throws -> BootstrappedDevice {
        let preferences: [AppleBossCharacteristicPreference] = options.characteristicPreference == .automatic
            ? [.unsecure, .secure]
            : [options.characteristicPreference]
        var lastError: Error?

        for preference in preferences {
            do {
                let transport = try await AppleBleBossTransport.connect(
                    filter: filter,
                    characteristicPreference: preference
                )
                defer {
                    Task {
                        await transport.close()
                    }
                }

                let link = BleBmapLink(transport: transport)
                let session = BootstrapSession(link: link)
                return try await session.bootstrap()
            } catch {
                lastError = error
                if case BootstrapTimeoutError.bmapVersion = error, preference == .unsecure {
                    fputs("boss-bootstrap retrying with secure characteristic\n", stderr)
                    continue
                }
                throw error
            }
        }

        throw lastError ?? AppleBleBossTransportError.transportClosed
    }

    private static func transportDescription(for filter: AppleBossScanFilter) -> String {
        if let identifier = filter.peripheralIdentifier {
            return identifier.uuidString
        }
        return "first Bose peripheral"
    }
}

private struct Options {
    let nameContains: String?
    let identifier: UUID?
    let timeoutSeconds: Int
    let characteristicPreference: AppleBossCharacteristicPreference

    static func parse<S: Sequence>(arguments: S) throws -> Options where S.Element == String {
        var iterator = arguments.makeIterator()
        var nameContains: String?
        var identifier: UUID?
        var timeoutSeconds = 10
        var characteristicPreference: AppleBossCharacteristicPreference = .automatic

        while let argument = iterator.next() {
            switch argument {
            case "--name":
                guard let value = iterator.next(), !value.isEmpty else {
                    throw UsageError("Missing value for --name")
                }
                nameContains = value
            case "--identifier":
                guard let value = iterator.next(), let parsed = UUID(uuidString: value) else {
                    throw UsageError("Invalid value for --identifier")
                }
                identifier = parsed
            case "--timeout":
                guard let value = iterator.next(), let parsed = Int(value), parsed > 0 else {
                    throw UsageError("Invalid value for --timeout")
                }
                timeoutSeconds = parsed
            case "--characteristic":
                guard let value = iterator.next(),
                      let parsed = AppleBossCharacteristicPreference(rawValue: value) else {
                    throw UsageError("Invalid value for --characteristic")
                }
                characteristicPreference = parsed
            case "--help":
                print(usage)
                exit(0)
            default:
                throw UsageError("Unknown argument: \(argument)")
            }
        }

        return Options(
            nameContains: nameContains,
            identifier: identifier,
            timeoutSeconds: timeoutSeconds,
            characteristicPreference: characteristicPreference
        )
    }

    static let usage = """
    Usage: boss-bootstrap [--name <substring>] [--identifier <uuid>] [--timeout <seconds>] [--characteristic automatic|unsecure|secure]
    """
}

private struct UsageError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        "\(message)\n\(Options.usage)"
    }
}

private extension FunctionBlockSet {
    var sortedNames: [String] {
        allBlocks()
            .map(\.displayName)
            .sorted()
    }
}

private extension BmapFunctionBlock {
    var displayName: String {
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
