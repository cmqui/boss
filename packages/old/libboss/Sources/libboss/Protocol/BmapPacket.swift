import Foundation

public struct BmapPacket: Equatable, Sendable {
    public static let headerSize = 4

    public let functionBlock: BmapFunctionBlock
    public let function: BmapFunction
    public let deviceID: Int
    public let port: Int
    public let `operator`: BmapOperator
    public let payload: Data

    public init(
        functionBlock: BmapFunctionBlock,
        function: BmapFunction,
        deviceID: Int = 0,
        port: Int = 0,
        operator: BmapOperator,
        payload: Data = Data()
    ) {
        self.functionBlock = functionBlock
        self.function = function
        self.deviceID = deviceID
        self.port = port
        self.operator = `operator`
        self.payload = payload
    }
}
