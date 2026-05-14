import Foundation
import libboss

struct UsageError: LocalizedError {
    let message: String
    let isHelp: Bool

    init(_ message: String, isHelp: Bool = false) {
        self.message = message
        self.isHelp = isHelp
    }

    var errorDescription: String? { message }
}

enum BossctlError: LocalizedError {
    case responseStreamEnded
    case responseTimedOut(seconds: Int64)
    case unexpectedResponse(String)
    case bmapErrorResponse(context: String, payloadHex: String)
    case unsupportedSetting(String)
    case modeChangeNotObserved(targetIndex: Int, observedIndex: Int)
    case settingsConfigNotObserved(expected: String, observed: String)

    var errorDescription: String? {
        switch self {
        case .responseStreamEnded:
            return "Response stream ended before a matching packet was received"
        case .responseTimedOut(let seconds):
            return "Timed out waiting for a matching response after \(seconds) seconds"
        case .unexpectedResponse(let operatorName):
            return "Unexpected response operator: \(operatorName)"
        case .bmapErrorResponse(let context, let payloadHex):
            if let errorCode = BossctlCLI.bmapErrorCode(from: payloadHex) {
                return "BMAP error response for \(context): payload=\(payloadHex) (\(errorCode.description))"
            }
            return "BMAP error response for \(context): payload=\(payloadHex)"
        case .unsupportedSetting(let settingName):
            return "Setting is not exposed by this device/session: \(settingName)"
        case .modeChangeNotObserved(let targetIndex, let observedIndex):
            return "Mode change was not observed: target=\(targetIndex), observed=\(observedIndex)"
        case .settingsConfigNotObserved(let expected, let observed):
            return "Audio mode settings update was not observed: expected \(expected), observed \(observed)"
        }
    }

    var isTimeout: Bool {
        if case .responseTimedOut = self {
            return true
        }
        return false
    }
}
