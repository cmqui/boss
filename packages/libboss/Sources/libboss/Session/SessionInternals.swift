import Foundation

extension Duration {
    var millisecondsValue: Int {
        let components = self.components
        return Int(components.seconds * 1_000) + Int(components.attoseconds / 1_000_000_000_000_000)
    }
}

func withThrowingTimeout<T: Sendable>(
    _ timeout: Duration,
    timeoutError: Error,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw timeoutError
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
