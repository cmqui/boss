@preconcurrency import CoreBluetooth
import Foundation
import libboss

public struct BossAppleDiscoveredDevice: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let isCurrentlyConnected: Bool

    public init(id: UUID, name: String, isCurrentlyConnected: Bool) {
        self.id = id
        self.name = name
        self.isCurrentlyConnected = isCurrentlyConnected
    }
}

public final class AppleBossDeviceDiscovery: NSObject, @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "dev.libboss.apple.discovery")
    private let scanTimeout: Duration
    private let nameContains: String?
    private lazy var central = CBCentralManager(delegate: self, queue: stateQueue)

    private var continuation: CheckedContinuation<[BossAppleDiscoveredDevice], Error>?
    private var timeoutTask: Task<Void, Never>?
    private var discoveredByID: [UUID: BossAppleDiscoveredDevice] = [:]

    public static func discoverDevices(
        nameContains: String? = "Bose",
        scanTimeout: Duration = .seconds(4)
    ) async throws -> [BossAppleDiscoveredDevice] {
        let discovery = AppleBossDeviceDiscovery(nameContains: nameContains, scanTimeout: scanTimeout)
        return try await discovery.run()
    }

    private init(nameContains: String?, scanTimeout: Duration) {
        self.nameContains = nameContains
        self.scanTimeout = scanTimeout
        super.init()
    }

    private func run() async throws -> [BossAppleDiscoveredDevice] {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async {
                self.continuation = continuation
                _ = self.central
                self.armTimeout()
                self.handleState(self.central.state)
            }
        }
    }

    private func armTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else {
                return
            }
            try? await Task.sleep(for: self.scanTimeout)
            self.stateQueue.async {
                self.finish()
            }
        }
    }

    private func handleState(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            startDiscovery()
        case .unauthorized:
            finish(throwing: AppleBleBossTransportError.bluetoothUnauthorized)
        case .unsupported:
            finish(throwing: AppleBleBossTransportError.bluetoothUnsupported)
        case .poweredOff, .resetting:
            finish(throwing: AppleBleBossTransportError.bluetoothUnavailable)
        case .unknown:
            break
        @unknown default:
            finish(throwing: AppleBleBossTransportError.bluetoothUnavailable)
        }
    }

    private func startDiscovery() {
        let serviceUUID = CBUUID(nsuuid: BoseUUIDs.service)
        let connected = central.retrieveConnectedPeripherals(withServices: [serviceUUID])
        for peripheral in connected {
            addDevice(id: peripheral.identifier, name: peripheral.name, isConnected: true)
        }
        central.scanForPeripherals(withServices: nil)
    }

    private func addDevice(id: UUID, name: String?, isConnected: Bool) {
        let resolvedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard matches(name: resolvedName) else {
            return
        }
        let displayName = resolvedName.isEmpty ? "Unknown Bose Device" : resolvedName
        let existing = discoveredByID[id]
        discoveredByID[id] = BossAppleDiscoveredDevice(
            id: id,
            name: displayName,
            isCurrentlyConnected: isConnected || existing?.isCurrentlyConnected == true
        )
    }

    private func matches(name: String) -> Bool {
        guard let nameContains, !nameContains.isEmpty else {
            return true
        }
        return name.lowercased().contains(nameContains.lowercased())
    }

    private func finish() {
        let devices = discoveredByID.values.sorted { lhs, rhs in
            if lhs.isCurrentlyConnected != rhs.isCurrentlyConnected {
                return lhs.isCurrentlyConnected && !rhs.isCurrentlyConnected
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        finish(with: .success(devices))
    }

    private func finish(throwing error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<[BossAppleDiscoveredDevice], Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        central.stopScan()
        guard let continuation else {
            return
        }
        self.continuation = nil
        switch result {
        case .success(let devices):
            continuation.resume(returning: devices)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

extension AppleBossDeviceDiscovery: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        handleState(central.state)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        addDevice(id: peripheral.identifier, name: peripheral.name ?? advertisedName, isConnected: false)
    }
}
