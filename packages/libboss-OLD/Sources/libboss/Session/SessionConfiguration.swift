import Foundation

public struct SessionConfiguration: Equatable, Sendable {
    public let defaultDeviceID: Int
    public let defaultPort: Int
    public let firstVersionTimeout: Duration
    public let retryVersionTimeout: Duration
    public let requestTimeout: Duration

    public init(
        defaultDeviceID: Int = 0,
        defaultPort: Int = 0,
        firstVersionTimeout: Duration = .milliseconds(2000),
        retryVersionTimeout: Duration = .milliseconds(50000),
        requestTimeout: Duration = .milliseconds(5000)
    ) {
        self.defaultDeviceID = defaultDeviceID
        self.defaultPort = defaultPort
        self.firstVersionTimeout = firstVersionTimeout
        self.retryVersionTimeout = retryVersionTimeout
        self.requestTimeout = requestTimeout
    }
}
