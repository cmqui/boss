import Foundation

public struct BootstrappedDevice: Equatable, Sendable {
    public let bmapVersion: BmapVersionInfo
    public let productID: UInt16
    public let productName: String
    public let productVariant: ProductIDVariant
    public let supportedFunctionBlocks: FunctionBlockSet
    public let transportKind: BossTransportKind
    public let defaultDeviceID: Int
    public let defaultPort: Int

    public init(
        bmapVersion: BmapVersionInfo,
        productID: UInt16,
        productName: String,
        productVariant: ProductIDVariant,
        supportedFunctionBlocks: FunctionBlockSet,
        transportKind: BossTransportKind,
        defaultDeviceID: Int,
        defaultPort: Int
    ) {
        self.bmapVersion = bmapVersion
        self.productID = productID
        self.productName = productName
        self.productVariant = productVariant
        self.supportedFunctionBlocks = supportedFunctionBlocks
        self.transportKind = transportKind
        self.defaultDeviceID = defaultDeviceID
        self.defaultPort = defaultPort
    }
}
