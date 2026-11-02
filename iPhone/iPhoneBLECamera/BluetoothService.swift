import Foundation
import CoreBluetooth
import Combine

/// iPhone advertises a private BLE GATT service; Windows is the central/client.
/// No camera data passes through Bluetooth: only short control messages.
final class BluetoothService: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    static let serviceID = CBUUID(string: "E919BC34-11B2-4BEA-B102-DC37195206AD")
    static let commandID = CBUUID(string: "E919BC34-11B2-4BEA-B102-DC37195206AE")
    static let statusID  = CBUUID(string: "E919BC34-11B2-4BEA-B102-DC37195206AF")

    @Published private(set) var displayState = "Starting Bluetooth..."
    @Published private(set) var connectedComputer = false
    let sessionPIN: String

    weak var camera: CameraService?
    private var peripheral: CBPeripheralManager!
    private var commandCharacteristic: CBMutableCharacteristic!
    private var statusCharacteristic: CBMutableCharacteristic!
    private var authorizedCentral: UUID?
    private var subscribedCentrals: [CBCentral] = []
    private var foreground = true
    func setForeground(_ active: Bool) {
        foreground = active
        if !active {
            peripheral.stopAdvertising()
            authorizedCentral = nil
            pendingMessages.removeAll()
        } else if peripheral.state == .poweredOn, statusCharacteristic != nil {
            guard foreground else { return }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceID],
                                         CBAdvertisementDataLocalNameKey: "iPhoneCam"])
        }
    }
    private var latestStatus = "HELLO"
    private var pendingMessages: [Data] = []
    private var failedPins = 0
    private var lockUntil: Date?

    override init() {
        sessionPIN = String(Int.random(in: 100000...999999))
        super.init()
        peripheral = CBPeripheralManager(delegate: self, queue: .main)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state != .poweredOn {
            authorizedCentral = nil
            subscribedCentrals.removeAll()
            pendingMessages.removeAll()
            statusCharacteristic = nil
            commandCharacteristic = nil
            connectedComputer = false
        }
        switch peripheral.state {
        case .poweredOn:
            configureService()
        case .poweredOff:
            displayState = "Bluetooth is off on this iPhone"
        case .unauthorized:
            displayState = "Allow Bluetooth permission in Settings"
        case .unsupported:
            displayState = "Bluetooth LE unsupported"
        default:
            displayState = "Bluetooth unavailable"
        }
    }

    private func configureService() {
        guard statusCharacteristic == nil else { return }
        commandCharacteristic = CBMutableCharacteristic(
            type: Self.commandID, properties: [.write], value: nil, permissions: [.writeable]
        )
        statusCharacteristic = CBMutableCharacteristic(
            type: Self.statusID, properties: [.read, .notify], value: nil, permissions: [.readable]
        )
        let service = CBMutableService(type: Self.serviceID, primary: true)
        service.characteristics = [commandCharacteristic, statusCharacteristic]
        peripheral.add(service)
        displayState = "Creating Bluetooth camera service..."
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didAdd service: CBService, error: Error?) {
        if let error = error {
            displayState = "BLE service error: \(error.localizedDescription)"
            return
        }
        // Keep the 128-bit service UUID in the foreground advertisement.
        guard foreground else { return }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceID],
            CBAdvertisementDataLocalNameKey: "iPhoneCam"
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            displayState = "BLE advertising error: \(error.localizedDescription)"
        } else {
            displayState = "Discoverable as iPhoneCam. Keep app open."
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == Self.statusID else { return }
        pendingMessages.removeAll()
        subscribedCentrals.removeAll { $0.identifier == central.identifier }
        subscribedCentrals.append(central)
        connectedComputer = true
        send("HELLO:ENTER_PIN")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        pendingMessages.removeAll()
        subscribedCentrals.removeAll { $0.identifier == central.identifier }
        if authorizedCentral == central.identifier { authorizedCentral = nil }
        connectedComputer = !subscribedCentrals.isEmpty
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == Self.statusID else {
            peripheral.respond(to: request, withResult: .readNotPermitted)
            return
        }
        let bytes = Data(latestStatus.utf8)
        guard request.offset <= bytes.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = bytes.subdata(in: request.offset..<bytes.count)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard foreground, request.offset == 0, (request.value?.count ?? 0) <= 64 else {
                peripheral.respond(to: request, withResult: .writeNotPermitted)
                continue
            }
            guard request.characteristic.uuid == Self.commandID,
                  let bytes = request.value,
                  let command = String(data: bytes, encoding: .utf8) else {
                peripheral.respond(to: request, withResult: .writeNotPermitted)
                continue
            }
            peripheral.respond(to: request, withResult: .success)
            process(command, central: request.central.identifier)
        }
    }

    private func process(_ command: String, central identifier: UUID) {
        guard foreground else { send("ERR:FOREGROUND_REQUIRED"); return }
        guard subscribedCentrals.contains(where: { $0.identifier == identifier }) else { return }
        if let owner = authorizedCentral, owner != identifier { return }
        if command.hasPrefix("AUTH:") {
            if let lockUntil = lockUntil, Date() < lockUntil {
                send("ERR:AUTH_LOCKED")
                return
            }
            if String(command.dropFirst(5)) == sessionPIN {
                authorizedCentral = identifier
                failedPins = 0
                lockUntil = nil
                send("OK:AUTH")
            } else {
                failedPins += 1
                if failedPins >= 5 {
                    lockUntil = Date().addingTimeInterval(120)
                    failedPins = 0
                    send("ERR:AUTH_LOCKED")
                } else {
                    send("ERR:AUTH_BAD_PIN")
                }
            }
            return
        }
        guard authorizedCentral == identifier else { send("ERR:AUTH_REQUIRED"); return }
        camera?.execute(command) { [weak self] response in self?.send(response) }
    }

    func send(_ text: String) {
        latestStatus = text
        guard !subscribedCentrals.isEmpty else { return }
        let recipients = subscribedCentrals.filter { authorizedCentral == nil || $0.identifier == authorizedCentral }
        guard let size = recipients.map({ $0.maximumUpdateValueLength }).min(), size > 0 else { return }
        let bytes = Array((text + "\n").utf8)
        for offset in stride(from: 0, to: bytes.count, by: size) {
            pendingMessages.append(Data(bytes[offset..<min(offset + size, bytes.count)]))
        }
        if pendingMessages.count > 256 { pendingMessages.removeAll(); return }
        transmitPending()
    }

    private func transmitPending() {
        guard !subscribedCentrals.isEmpty else { return }
        while let packet = pendingMessages.first {
            if peripheral.updateValue(packet, for: statusCharacteristic, onSubscribedCentrals: subscribedCentrals.filter { authorizedCentral == nil || $0.identifier == authorizedCentral }) {
                pendingMessages.removeFirst()
            } else {
                break
            }
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        transmitPending()
    }
}
