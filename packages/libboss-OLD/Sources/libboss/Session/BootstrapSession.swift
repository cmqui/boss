import Foundation

public final class BootstrapSession: @unchecked Sendable {
    private let link: any BossLink
    private let configuration: SessionConfiguration

    public init(link: any BossLink, configuration: SessionConfiguration = SessionConfiguration()) {
        self.link = link
        self.configuration = configuration
    }

    public func bootstrap() async throws -> BootstrappedDevice {
        let session = BossPacketSession(link: link)
        defer { session.invalidate() }

        let versionPacket = ProductInfoCommands.bmapVersion(
            deviceID: configuration.defaultDeviceID,
            port: configuration.defaultPort
        )

        let versionResponse: BmapPacket
        do {
            versionResponse = try await session.responsePacket(
                for: versionPacket,
                matching: versionPacket.function,
                timeout: configuration.firstVersionTimeout,
                timeoutError: BootstrapTimeoutError.bmapVersion(timeoutMilliseconds: configuration.firstVersionTimeout.millisecondsValue)
            )
        } catch is BootstrapTimeoutError {
            versionResponse = try await session.responsePacket(
                for: versionPacket,
                matching: versionPacket.function,
                timeout: configuration.retryVersionTimeout,
                timeoutError: BootstrapTimeoutError.bmapVersion(timeoutMilliseconds: configuration.retryVersionTimeout.millisecondsValue)
            )
        }
        let versionInfo = try ProductInfoParser.parseBmapVersion(from: versionResponse)

        let productRequest = ProductInfoCommands.productIDVariant(
            deviceID: configuration.defaultDeviceID,
            port: configuration.defaultPort
        )
        let productPacket = try await session.responsePacket(
            for: productRequest,
            matching: productRequest.function,
            timeout: configuration.requestTimeout,
            timeoutError: BootstrapTimeoutError.packet(function: productRequest.function.name, timeoutMilliseconds: configuration.requestTimeout.millisecondsValue)
        )
        let productVariant = try ProductInfoParser.parseProductIDVariant(from: productPacket)

        let blockRequest = ProductInfoCommands.allFunctionBlocksGet(
            deviceID: configuration.defaultDeviceID,
            port: configuration.defaultPort
        )
        let blocksPacket = try await session.responsePacket(
            for: blockRequest,
            matching: blockRequest.function,
            timeout: configuration.requestTimeout,
            timeoutError: BootstrapTimeoutError.packet(function: blockRequest.function.name, timeoutMilliseconds: configuration.requestTimeout.millisecondsValue)
        )
        let functionBlocks = try ProductInfoParser.parseFunctionBlocks(from: blocksPacket)

        return BootstrappedDevice(
            bmapVersion: versionInfo,
            productID: productVariant.productID,
            productName: productVariant.product?.displayName ?? "Unknown Bose Product",
            productVariant: productVariant,
            supportedFunctionBlocks: functionBlocks,
            transportKind: link.transportKind,
            defaultDeviceID: configuration.defaultDeviceID,
            defaultPort: configuration.defaultPort
        )
    }
}
