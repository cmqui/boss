import CBossRustFFI
import Foundation

enum AppleBoseUUIDs {
    static let service = UUID(uuidString: String(cString: boss_ble_service_uuid()))!
    static let secureCharacteristic = UUID(uuidString: String(cString: boss_ble_secure_characteristic_uuid()))!
    static let unsecureCharacteristic = UUID(uuidString: String(cString: boss_ble_unsecure_characteristic_uuid()))!
}
