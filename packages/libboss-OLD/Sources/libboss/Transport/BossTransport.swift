import Foundation

public enum BossTransportKind: String, Equatable, Sendable {
    case ble
    case stream
}

public protocol BossTransport: Sendable {
    func send(_ frame: Data) async throws
    var incomingFrames: AsyncThrowingStream<Data, Error> { get }
    func close() async
}

public protocol BossBleTransport: BossTransport {
    var attMTU: Int { get }
}
