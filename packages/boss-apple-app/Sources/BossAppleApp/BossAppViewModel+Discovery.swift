import Foundation
import libbossApple

extension BossAppViewModel {
    func startDiscoveryLoopIfNeeded(forceImmediateRefresh: Bool = false) {
        guard discoveryTask == nil else {
            return
        }
        appScreen = .waitingForDevice
        discoveryTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer { self.discoveryTask = nil }

            if forceImmediateRefresh {
                await self.refreshAvailableDevices()
            }

            while !Task.isCancelled && self.appScreen == .waitingForDevice {
                await self.refreshAvailableDevices()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func cancelDiscoveryLoop() {
        discoveryTask?.cancel()
        discoveryTask = nil
    }

    func refreshAvailableDevices() async {
        guard !isBusy, !isConnectingSelectedDevice else {
            return
        }
        loadState = .loading("Scanning for Bose devices")
        waitingStatusMessage = usesMockDeviceBackend
            ? "Loading the mock QC Ultra 2 HP device..."
            : "Scanning for a nearby Bose device..."
        Self.log("Starting: Device discovery scan")

        do {
            let devices = try await discoveryProvider.discoverDevices(
                connection: BossAppleConnectionOptions(
                    nameContains: nameFilter,
                    scanTimeout: .seconds(4)
                )
            )
            guard !isConnectingSelectedDevice else {
                Self.log("Ignoring discovery results because a selected device is already connecting")
                return
            }
            availableDevices = devices
            if selectedDiscoveredDeviceID == nil || !devices.contains(where: { $0.id == selectedDiscoveredDeviceID }) {
                selectedDiscoveredDeviceID = devices.first?.id
            }
            if devices.count == 1, let device = devices.first, !isManualDeviceSelection {
                waitingStatusMessage = usesMockDeviceBackend
                    ? "Found mock \(device.name). Opening controls..."
                    : "Found \(device.name). Opening controls..."
                loadState = .idle
                connect(to: device)
                return
            }
            waitingStatusMessage = devices.isEmpty
                ? (usesMockDeviceBackend
                    ? "No mock Bose devices are available right now. Retrying automatically..."
                    : "No Bose devices found yet. Retrying automatically...")
                : (usesMockDeviceBackend
                    ? "Select the mock Bose device to open its controls."
                    : "Select a Bose device to open its controls.")
            loadState = .idle
            Self.log("Completed: Device discovery scan (\(devices.count) devices)")
        } catch {
            guard !isConnectingSelectedDevice else {
                Self.log("Ignoring discovery error because a selected device is already connecting")
                return
            }
            let description = Self.describe(error)
            waitingStatusMessage = waitingMessage(for: error, description: description)
            loadState = .idle
            Self.log("Device discovery scan failed | \(description)")
        }
    }

    func connect(to device: BossAppleDiscoveredDevice) {
        cancelDiscoveryLoop()
        cancelBackgroundLoad()
        clearDiscoveryBusyState()
        isConnectingSelectedDevice = true
        isManualDeviceSelection = false
        selectedDiscoveredDeviceID = device.id
        selectedDeviceIdentifier = device.id
        deviceName = device.name
        waitingStatusMessage = usesMockDeviceBackend
            ? "Opening mock controls for \(device.name)..."
            : "Found \(device.name). Opening controls..."
        run(usesMockDeviceBackend ? "Opening mock device" : "Connecting to \(device.name)") {
            await self.clearSession()
            let session = self.makeSession()
            do {
                try await self.reloadAllState(using: session)
                self.isConnectingSelectedDevice = false
                self.appScreen = .workspace
                self.waitingStatusMessage = self.usesMockDeviceBackend ? "Connected to mock device." : "Connected."
                self.startBackgroundLoad(using: session)
            } catch {
                self.isConnectingSelectedDevice = false
                self.selectedDeviceIdentifier = nil
                await self.clearSession()
                self.enterWaitingMode(message: Self.describe(error))
                self.startDiscoveryLoopIfNeeded()
                throw error
            }
        }
    }

    func enterWaitingMode(message: String) {
        isConnectingSelectedDevice = false
        appScreen = .waitingForDevice
        waitingStatusMessage = message
    }

    func clearDiscoveryBusyState() {
        guard case .loading(let label) = loadState,
              label == "Scanning for Bose devices" else {
            return
        }
        loadState = .idle
    }

    public var shouldShowDevicePickerCard: Bool {
        isManualDeviceSelection || availableDevices.count > 1
    }

    func resetWorkspaceState() {
        cancelBackgroundLoad()
        audioModes = []
        customProfileModes = []
        currentAudioModeIndex = nil
        settings = nil
        equalizer = nil
        deviceName = "Bose Device"
        deviceVariantName = nil
        firmwareVersion = nil
        wearDetectionEnabled = nil
        autoAwareEnabled = nil
        autoPlayPauseEnabled = nil
        autoAnswerEnabled = nil
        volumeControlValue = nil
        lastResultMessage = nil
        hasDetachedSettingsDraft = false
        hasDetachedEqualizerDraft = false
    }

    func waitingMessage(for error: Error, description: String) -> String {
        if let error = error as? AppleBleBossTransportError {
            switch error {
            case .scanTimedOut:
                return "No Bose device found yet. Retrying automatically..."
            case .bluetoothUnavailable:
                return "Bluetooth is unavailable. Waiting for it to come back..."
            case .bluetoothUnauthorized:
                return "Bluetooth access is not authorized. Grant access and the app will retry."
            case .bluetoothUnsupported:
                return bluetoothUnsupportedMessage
            default:
                return description
            }
        }
        return description
    }

    var bluetoothUnsupportedMessage: String {
#if os(iOS)
        #if targetEnvironment(simulator)
            return "Bluetooth isn't available in the iOS Simulator. Run Boss on a physical iPhone or iPad to scan for devices."
        #else
            return "Bluetooth isn't available on this device."
        #endif
#elseif os(macOS)
        return "Bluetooth is unsupported on this Mac."
#else
        return "Bluetooth isn't supported on this device."
#endif
    }
}
