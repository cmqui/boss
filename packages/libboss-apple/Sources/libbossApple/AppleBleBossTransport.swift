@preconcurrency import CoreBluetooth
import Foundation
import libboss

public struct AppleBossScanFilter: Sendable {
    public var peripheralIdentifier: UUID?
    public var nameContains: String?
    public var scanTimeout: Duration

    public init(
        peripheralIdentifier: UUID? = nil,
        nameContains: String? = nil,
        scanTimeout: Duration = .seconds(10)
    ) {
        self.peripheralIdentifier = peripheralIdentifier
        self.nameContains = nameContains
        self.scanTimeout = scanTimeout
    }

    fileprivate func matches(_ peripheral: CBPeripheral, advertisementName: String?) -> Bool {
        if let peripheralIdentifier, peripheral.identifier != peripheralIdentifier {
            return false
        }

        guard let nameContains, !nameContains.isEmpty else {
            return true
        }

        let candidates = [advertisementName, peripheral.name].compactMap { $0?.lowercased() }
        return candidates.contains { $0.contains(nameContains.lowercased()) }
    }
}

public enum AppleBossCharacteristicPreference: String, Sendable {
    case automatic
    case unsecure
    case secure
}

public enum AppleBleBossTransportError: Error, Equatable {
    case bluetoothUnavailable
    case bluetoothUnauthorized
    case bluetoothUnsupported
    case scanTimedOut
    case peripheralDisconnected
    case boseServiceNotFound
    case boseCharacteristicNotFound
    case notificationNotSupported
    case transportClosed
    case transportNotReady
}

private actor SendGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        await lock()
        defer { unlock() }
        return try await operation()
    }

    private func lock() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func unlock() {
        if let continuation = waiters.first {
            waiters.removeFirst()
            continuation.resume()
        } else {
            isLocked = false
        }
    }
}

public final class AppleBleBossTransport: NSObject, BossBleTransport, @unchecked Sendable {
    public let incomingFrames: AsyncThrowingStream<Data, Error>

    public var attMTU: Int {
        stateQueue.sync {
            resolvedATTMTU
        }
    }

    private let filter: AppleBossScanFilter
    private let characteristicPreference: AppleBossCharacteristicPreference
    private let stateQueue: DispatchQueue
    private let sendGate = SendGate()
    private let frameContinuation: AsyncThrowingStream<Data, Error>.Continuation
    private lazy var central = CBCentralManager(delegate: self, queue: stateQueue)

    private var startContinuation: CheckedContinuation<Void, Error>?
    private var writeContinuation: CheckedContinuation<Void, Error>?
    private var readyToSendContinuation: CheckedContinuation<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var activePeripheral: CBPeripheral?
    private var activeWriteCharacteristic: CBCharacteristic?
    private var activeWriteType: CBCharacteristicWriteType = .withResponse
    private var notifyingCharacteristicUUIDs = Set<CBUUID>()
    private var pendingNotificationCharacteristicUUIDs = Set<CBUUID>()
    private var resolvedATTMTU = 23
    private var isClosed = false
    private var closeError: Error?
    private var rejectedPeripheralIdentifiers = Set<UUID>()
    private var shouldResumeScanningAfterDisconnect = false
    private let debugLoggingEnabled = ProcessInfo.processInfo.environment["LIBBOSS_APPLE_DEBUG"] == "1"
    private let packetLoggingEnabled = ProcessInfo.processInfo.environment["LIBBOSS_APPLE_DEBUG_PACKETS"] == "1"

    public static func connect(
        filter: AppleBossScanFilter = AppleBossScanFilter(),
        characteristicPreference: AppleBossCharacteristicPreference = .automatic
    ) async throws -> AppleBleBossTransport {
        let transport = AppleBleBossTransport(filter: filter, characteristicPreference: characteristicPreference)
        try await transport.start()
        return transport
    }

    private init(filter: AppleBossScanFilter, characteristicPreference: AppleBossCharacteristicPreference) {
        self.filter = filter
        self.characteristicPreference = characteristicPreference
        self.stateQueue = DispatchQueue(label: "dev.libboss.apple.transport")
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: Data.self, throwing: Error.self)
        self.incomingFrames = stream
        self.frameContinuation = continuation
        super.init()
    }

    public func send(_ frame: Data) async throws {
        try await sendGate.withLock {
            if let error = stateQueue.sync(execute: { closeError }) {
                throw error
            }

            let writeContext = try stateQueue.sync { () -> WriteContext in
                guard !isClosed else {
                    throw AppleBleBossTransportError.transportClosed
                }
                guard let peripheral = activePeripheral, let characteristic = activeWriteCharacteristic else {
                    throw AppleBleBossTransportError.transportNotReady
                }
                return WriteContext(
                    peripheral: peripheral,
                    characteristic: characteristic,
                    writeType: activeWriteType
                )
            }

            if writeContext.writeType == .withoutResponse {
                await awaitWriteWithoutResponseCapacityIfNeeded(for: writeContext.peripheral)
                packetDebug("writing \(frame.hexString) to \(writeContext.characteristic.uuid.uuidString) type=withoutResponse")
                writeContext.peripheral.writeValue(frame, for: writeContext.characteristic, type: .withoutResponse)
                return
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                stateQueue.async {
                    self.writeContinuation = continuation
                    self.packetDebug("writing \(frame.hexString) to \(writeContext.characteristic.uuid.uuidString) type=withResponse")
                    writeContext.peripheral.writeValue(frame, for: writeContext.characteristic, type: .withResponse)
                }
            }
        }
    }

    public func close() async {
        stateQueue.async {
            guard !self.isClosed else {
                return
            }

            self.debug("closing transport")
            self.isClosed = true
            self.timeoutTask?.cancel()
            self.timeoutTask = nil
            self.startContinuation?.resume(throwing: AppleBleBossTransportError.transportClosed)
            self.startContinuation = nil
            self.writeContinuation?.resume(throwing: AppleBleBossTransportError.transportClosed)
            self.writeContinuation = nil
            self.readyToSendContinuation?.resume()
            self.readyToSendContinuation = nil

            if let peripheral = self.activePeripheral {
                self.central.cancelPeripheralConnection(peripheral)
            } else {
                self.debug("finishing frame stream cleanly because no active peripheral remains during close")
                self.frameContinuation.finish()
            }
        }
    }

    private func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async {
                self.startContinuation = continuation
                _ = self.central
                self.armScanTimeout()
                self.handleManagerState(self.central.state)
            }
        }
    }

    private func armScanTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else {
                return
            }
            try? await Task.sleep(for: self.filter.scanTimeout)
            self.stateQueue.async {
                guard self.startContinuation != nil, self.activePeripheral == nil else {
                    return
                }
                self.finishStart(with: AppleBleBossTransportError.scanTimedOut)
            }
        }
    }

    private func handleManagerState(_ state: CBManagerState) {
        guard !isClosed else {
            return
        }

        switch state {
        case .poweredOn:
            attemptKnownPeripheralRecoveryOrScan()
        case .unauthorized:
            finishStart(with: AppleBleBossTransportError.bluetoothUnauthorized)
        case .unsupported:
            finishStart(with: AppleBleBossTransportError.bluetoothUnsupported)
        case .poweredOff, .resetting:
            finishStart(with: AppleBleBossTransportError.bluetoothUnavailable)
        case .unknown:
            break
        @unknown default:
            finishStart(with: AppleBleBossTransportError.bluetoothUnavailable)
        }
    }

    private func finishStart(with error: Error) {
        debug("finishStart with error: \(error)")
        timeoutTask?.cancel()
        timeoutTask = nil
        central.stopScan()
        startContinuation?.resume(throwing: error)
        startContinuation = nil
        closeError = error
        frameContinuation.finish(throwing: error)
    }

    private func finishStartSuccess() {
        timeoutTask?.cancel()
        timeoutTask = nil
        central.stopScan()
        startContinuation?.resume()
        startContinuation = nil
    }

    private func resumeScanning() {
        guard startContinuation != nil, activePeripheral == nil else {
            return
        }
        debug("starting scan")
        central.scanForPeripherals(withServices: nil)
    }

    private func attemptKnownPeripheralRecoveryOrScan() {
        guard startContinuation != nil, activePeripheral == nil else {
            return
        }

        if let peripheralIdentifier = filter.peripheralIdentifier {
            let restored = central.retrievePeripherals(withIdentifiers: [peripheralIdentifier])
            if let peripheral = restored.first(where: { !rejectedPeripheralIdentifiers.contains($0.identifier) }) {
                debug("restored peripheral by identifier \(peripheral.identifier.uuidString)")
                connect(peripheral)
                return
            }
        }

        let serviceUUID = CBUUID(nsuuid: BoseUUIDs.service)
        let connected = central.retrieveConnectedPeripherals(withServices: [serviceUUID])
        if let peripheral = connected.first(where: { candidate in
            !rejectedPeripheralIdentifiers.contains(candidate.identifier) &&
            filter.matches(candidate, advertisementName: nil)
        }) {
            debug("reused connected peripheral \(peripheral.identifier.uuidString) name=\(peripheral.name ?? "<unknown>")")
            connect(peripheral)
            return
        }

        resumeScanning()
    }

    private func rejectCurrentPeripheralAndResumeScan() {
        guard let peripheral = activePeripheral else {
            resumeScanning()
            return
        }

        debug("rejecting peripheral \(peripheral.identifier.uuidString) name=\(peripheral.name ?? "<unknown>")")
        rejectedPeripheralIdentifiers.insert(peripheral.identifier)
        shouldResumeScanningAfterDisconnect = true
        activeWriteCharacteristic = nil
        notifyingCharacteristicUUIDs.removeAll()
        pendingNotificationCharacteristicUUIDs.removeAll()
        central.cancelPeripheralConnection(peripheral)
    }

    private func connect(_ peripheral: CBPeripheral) {
        debug("connecting peripheral \(peripheral.identifier.uuidString) name=\(peripheral.name ?? "<unknown>")")
        activePeripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral)
    }

    private func debug(_ message: String) {
        guard debugLoggingEnabled else {
            return
        }
        fputs("[libboss-apple] \(message)\n", stderr)
    }

    private func packetDebug(_ message: String) {
        guard packetLoggingEnabled else {
            return
        }
        fputs("[libboss-apple] \(message)\n", stderr)
    }

    private func selectWriteCharacteristic(from characteristics: [CBCharacteristic]) -> CBCharacteristic? {
        let unsecure = CBUUID(nsuuid: BoseUUIDs.unsecureCharacteristic)
        let secure = CBUUID(nsuuid: BoseUUIDs.secureCharacteristic)
        let orderedCandidates: [CBUUID]
        switch characteristicPreference {
        case .automatic, .unsecure:
            orderedCandidates = [unsecure, secure]
        case .secure:
            orderedCandidates = [secure, unsecure]
        }

        for uuid in orderedCandidates {
            if let characteristic = characteristics.first(where: { $0.uuid == uuid }),
               characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                return characteristic
            }
        }

        return nil
    }

    private func awaitWriteWithoutResponseCapacityIfNeeded(for peripheral: CBPeripheral) async {
        let needsWait = stateQueue.sync {
            !peripheral.canSendWriteWithoutResponse
        }
        guard needsWait else {
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stateQueue.async {
                if peripheral.canSendWriteWithoutResponse {
                    continuation.resume()
                } else {
                    self.readyToSendContinuation = continuation
                }
            }
        }
    }
}

extension AppleBleBossTransport: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        handleManagerState(central.state)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard activePeripheral == nil else {
            return
        }
        guard !rejectedPeripheralIdentifiers.contains(peripheral.identifier) else {
            return
        }

        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard filter.matches(peripheral, advertisementName: advertisedName) else {
            return
        }

        debug(
            "discovered peripheral \(peripheral.identifier.uuidString) name=\(peripheral.name ?? advertisedName ?? "<unknown>") " +
            "advertisedName=\(advertisedName ?? "<none>")"
        )
        connect(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        debug("connected peripheral \(peripheral.identifier.uuidString)")
        peripheral.discoverServices([CBUUID(nsuuid: BoseUUIDs.service)])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        debug("failed to connect peripheral \(peripheral.identifier.uuidString): \(String(describing: error))")
        activePeripheral = nil
        rejectedPeripheralIdentifiers.insert(peripheral.identifier)
        if startContinuation != nil {
            attemptKnownPeripheralRecoveryOrScan()
            return
        }
        finishStart(with: error ?? AppleBleBossTransportError.peripheralDisconnected)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        debug("disconnected peripheral \(peripheral.identifier.uuidString): \(String(describing: error))")
        let shouldResume = shouldResumeScanningAfterDisconnect
        shouldResumeScanningAfterDisconnect = false
        activePeripheral = nil
        activeWriteCharacteristic = nil
        notifyingCharacteristicUUIDs.removeAll()
        pendingNotificationCharacteristicUUIDs.removeAll()

        if shouldResume, startContinuation != nil {
            attemptKnownPeripheralRecoveryOrScan()
            return
        }

        timeoutTask?.cancel()
        timeoutTask = nil
        let disconnectError = error ?? (isClosed ? nil : AppleBleBossTransportError.peripheralDisconnected)
        closeError = disconnectError ?? AppleBleBossTransportError.transportClosed
        writeContinuation?.resume(throwing: disconnectError ?? AppleBleBossTransportError.transportClosed)
        writeContinuation = nil
        readyToSendContinuation?.resume()
        readyToSendContinuation = nil

        if let disconnectError {
            debug("finishing frame stream with disconnect error: \(disconnectError)")
            frameContinuation.finish(throwing: disconnectError)
        } else {
            debug("finishing frame stream cleanly after disconnect")
            frameContinuation.finish()
        }

        if startContinuation != nil {
            finishStart(with: disconnectError ?? AppleBleBossTransportError.peripheralDisconnected)
        }
    }
}

extension AppleBleBossTransport: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            finishStart(with: error)
            return
        }

        let serviceUUIDs = peripheral.services?.map { $0.uuid.uuidString } ?? []
        debug("discovered services for \(peripheral.identifier.uuidString): \(serviceUUIDs)")
        guard let service = peripheral.services?.first(where: { $0.uuid == CBUUID(nsuuid: BoseUUIDs.service) }) else {
            rejectCurrentPeripheralAndResumeScan()
            return
        }

        peripheral.discoverCharacteristics(
            [
                CBUUID(nsuuid: BoseUUIDs.unsecureCharacteristic),
                CBUUID(nsuuid: BoseUUIDs.secureCharacteristic),
            ],
            for: service
        )
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            finishStart(with: error)
            return
        }

        let characteristicUUIDs = service.characteristics?.map { $0.uuid.uuidString } ?? []
        let characteristicDetails = service.characteristics?.map {
            "\($0.uuid.uuidString):\($0.properties.propertyNames.joined(separator: "|"))"
        } ?? []
        debug("discovered characteristics for \(service.uuid.uuidString): \(characteristicUUIDs)")
        debug("characteristic properties: \(characteristicDetails)")
        guard let characteristics = service.characteristics,
              let writeCharacteristic = selectWriteCharacteristic(from: characteristics) else {
            rejectCurrentPeripheralAndResumeScan()
            return
        }

        activeWriteCharacteristic = writeCharacteristic
        activeWriteType = writeCharacteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse

        let notifyCharacteristics = characteristics.filter { $0.properties.contains(.notify) }
        guard !notifyCharacteristics.isEmpty else {
            rejectCurrentPeripheralAndResumeScan()
            return
        }

        notifyingCharacteristicUUIDs.removeAll()
        pendingNotificationCharacteristicUUIDs = Set(notifyCharacteristics.map(\.uuid))
        debug("selected write characteristic \(writeCharacteristic.uuid.uuidString) type=\(activeWriteType == .withResponse ? "withResponse" : "withoutResponse")")
        for characteristic in notifyCharacteristics {
            debug("enabling notifications on \(characteristic.uuid.uuidString)")
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            finishStart(with: error)
            return
        }

        guard characteristic.isNotifying else {
            finishStart(with: AppleBleBossTransportError.notificationNotSupported)
            return
        }

        notifyingCharacteristicUUIDs.insert(characteristic.uuid)
        pendingNotificationCharacteristicUUIDs.remove(characteristic.uuid)
        guard pendingNotificationCharacteristicUUIDs.isEmpty else {
            debug("notifications enabled on \(characteristic.uuid.uuidString), waiting for \(pendingNotificationCharacteristicUUIDs.count) more")
            return
        }

        let mtu = peripheral.maximumWriteValueLength(for: activeWriteType) + 3
        resolvedATTMTU = max(4, mtu)
        let notifyingUUIDs = notifyingCharacteristicUUIDs.map(\.uuidString).sorted()
        debug("notifications enabled on \(notifyingUUIDs), attMTU=\(resolvedATTMTU)")
        finishStartSuccess()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            debug("finishing frame stream from didUpdateValueFor error on \(characteristic.uuid.uuidString): \(error)")
            frameContinuation.finish(throwing: error)
            return
        }

        guard notifyingCharacteristicUUIDs.contains(characteristic.uuid),
              let value = characteristic.value,
              !value.isEmpty else {
            return
        }

        packetDebug("notification \(characteristic.uuid.uuidString): \(value.hexString)")
        frameContinuation.yield(value)
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let continuation = writeContinuation else {
            return
        }

        writeContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        readyToSendContinuation?.resume()
        readyToSendContinuation = nil
    }
}

private struct WriteContext: @unchecked Sendable {
    let peripheral: CBPeripheral
    let characteristic: CBCharacteristic
    let writeType: CBCharacteristicWriteType
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}

private extension CBCharacteristicProperties {
    var propertyNames: [String] {
        var names: [String] = []
        if contains(.broadcast) { names.append("broadcast") }
        if contains(.read) { names.append("read") }
        if contains(.writeWithoutResponse) { names.append("writeWithoutResponse") }
        if contains(.write) { names.append("write") }
        if contains(.notify) { names.append("notify") }
        if contains(.indicate) { names.append("indicate") }
        if contains(.authenticatedSignedWrites) { names.append("authenticatedSignedWrites") }
        if contains(.extendedProperties) { names.append("extendedProperties") }
        if contains(.notifyEncryptionRequired) { names.append("notifyEncryptionRequired") }
        if contains(.indicateEncryptionRequired) { names.append("indicateEncryptionRequired") }
        return names
    }
}
