import Foundation

extension BossAppleController {
    static func verifyCurrentAudioMode(
        on link: BossAppleLink,
        targetIndex: Int,
        timeoutPerAttempt: Duration,
        attempts: Int,
        retryDelay: Duration,
        fallbackError: Error? = nil
    ) async throws -> Int {
        var lastError: Error = fallbackError ?? BossAppleControlError.responseTimedOut(seconds: timeoutPerAttempt.components.seconds)
        var lastObservedIndex: Int?
        for attempt in 0..<attempts {
            do {
                let currentIndex = try await requiredCurrentAudioMode(on: link, timeout: timeoutPerAttempt)
                lastObservedIndex = currentIndex
                if currentIndex == targetIndex {
                    return currentIndex
                }
            } catch {
                lastError = error
            }
            if attempt < attempts - 1 {
                try await Task.sleep(for: retryDelay)
            }
        }
        if let lastObservedIndex {
            throw BossAppleControlError.modeChangeNotObserved(targetIndex: targetIndex, observedIndex: lastObservedIndex)
        }
        throw fallbackError ?? lastError
    }

    static func verifyCurrentAudioModeAfterReconnect(
        connection: BossAppleConnectionOptions,
        targetIndex: Int,
        fallbackError: Error
    ) async throws -> Int {
        var lastError: Error = fallbackError
        for attempt in 0..<4 {
            do {
                return try await withConnectedLinkRetrying(
                    connection,
                    shouldRetry: { error, preference in
                        guard preference == .unsecure else {
                            return false
                        }
                        return shouldFallbackForAudioModeWrite(error)
                    }
                ) { link in
                    try await verifyCurrentAudioMode(
                        on: link,
                        targetIndex: targetIndex,
                        timeoutPerAttempt: .seconds(3),
                        attempts: 3,
                        retryDelay: .milliseconds(750),
                        fallbackError: fallbackError
                    )
                }
            } catch {
                lastError = error
                if attempt < 3 {
                    try await Task.sleep(for: .seconds(1))
                }
            }
        }
        throw lastError
    }

    static func shouldFallbackForAudioModeWrite(_ error: Error) -> Bool {
        if let error = error as? BossAppleControlError {
            switch error {
            case .responseTimedOut, .responseStreamEnded:
                return true
            default:
                return false
            }
        }
        if let error = error as? BossAppleLinkError, error == .unexpectedStreamTermination {
            return true
        }
        return false
    }

    static func retrySecureCharacteristicIfNeeded(_ error: Error, _ preference: AppleBossCharacteristicPreference) -> Bool {
        guard preference == .unsecure else {
            return false
        }
        if case BossAppleControlError.responseTimedOut = error {
            return true
        }
        if case BossAppleControlError.bmapErrorResponse(_, let payloadHex) = error {
            switch bmapErrorCode(from: payloadHex) {
            case .insecureTransport?, .fblockNotSupp?, .funcNotSupp?:
                return true
            default:
                break
            }
        }
        return false
    }

    static func isRecoverableAudioModeSettingsConfigError(_ error: Error) -> Bool {
        if shouldFallbackForAudioModeWrite(error) {
            return true
        }
        if let error = error as? BossAppleControlError {
            switch error {
            case .settingsConfigNotObserved:
                return true
            case .bmapErrorResponse(_, let payloadHex):
                return bmapErrorCode(from: payloadHex) == .insecureTransport ||
                    bmapErrorCode(from: payloadHex) == .timeout ||
                    bmapErrorCode(from: payloadHex) == .busy
            default:
                return false
            }
        }
        return false
    }

    static func isRecoverableEqualizerError(_ error: Error) -> Bool {
        if shouldFallbackForAudioModeWrite(error) {
            return true
        }
        if let error = error as? BossAppleControlError {
            switch error {
            case .equalizerNotObserved:
                return true
            case .bmapErrorResponse(_, let payloadHex):
                return bmapErrorCode(from: payloadHex) == .insecureTransport ||
                    bmapErrorCode(from: payloadHex) == .timeout ||
                    bmapErrorCode(from: payloadHex) == .busy
            default:
                return false
            }
        }
        return false
    }

    static func isVerificationInconclusiveError(_ error: Error) -> Bool {
        if shouldFallbackForAudioModeWrite(error) {
            return true
        }
        if let error = error as? BossAppleControlError {
            switch error {
            case .bmapErrorResponse(_, let payloadHex):
                return bmapErrorCode(from: payloadHex) == .insecureTransport
            default:
                return false
            }
        }
        return false
    }

    static func isCompositeInPlaceDetectionUnsupported(_ error: Error) -> Bool {
        guard let error = unavailableSettingReason(error) else {
            return false
        }
        switch error {
        case .functionUnsupported, .operatorUnsupported:
            return true
        default:
            return false
        }
    }

    static func unavailableSettingReason(_ error: Error) -> BossAppleSettingUnavailableReason? {
        if let error = error as? BossAppleControlError {
            switch error {
            case .responseTimedOut:
                return .timedOut
            case .responseStreamEnded:
                return .responseStreamEnded
            case .bmapErrorResponse(_, let payloadHex):
                switch bmapErrorCode(from: payloadHex) {
                case .fblockNotSupp?, .funcNotSupp?:
                    return .functionUnsupported
                case .opNotSupp?:
                    return .operatorUnsupported
                case .dataUnavailable?:
                    return .dataUnavailable
                case .insecureTransport?:
                    return .insecureTransport
                case let code:
                    return .bmapError(code)
                }
            default:
                return nil
            }
        }
        if let error = error as? BossAppleLinkError, error == .unexpectedStreamTermination {
            return .unexpectedStreamTermination
        }
        return nil
    }

    static func isUnavailableSettingReadError(_ error: Error) -> Bool {
        unavailableSettingReason(error) != nil
    }

    static func bmapErrorCode(from payloadHex: String) -> BossAppleBmapErrorCode? {
        bossBmapErrorCode(from: payloadHex)
    }

    static func validatedEqualizerRequests(
        _ update: BossAppleEqualizerSettingsPatch,
        current: BossAppleEqualizerSettings
    ) throws -> [(BossAppleEqualizerBand, Int)] {
        try update.requestedLevels.map { band, level in
            guard let range = current.range(for: band) else {
                throw BossAppleControlError.unsupportedOperation(
                    "This device/session does not expose the \(band.displayName) equalizer band over BMAP"
                )
            }
            guard (range.minLevel...range.maxLevel).contains(level) else {
                throw BossAppleControlError.unsupportedOperation(
                    "Requested \(band.displayName) equalizer level \(level) is outside the supported range \(range.minLevel)...\(range.maxLevel)"
                )
            }
            return (band, level)
        }
    }

    static func describe(_ update: BossAppleEqualizerSettingsPatch) -> String {
        update.requestedLevels
            .map { "\($0.0.displayName)=\($0.1)" }
            .joined(separator: ",")
    }

    static func describe(_ settings: BossAppleEqualizerSettings) -> String {
        settings.ranges
            .map { "\($0.band.displayName)=\($0.currentLevel)[\($0.minLevel)...\($0.maxLevel)]" }
            .joined(separator: ",")
    }

    static func describe(_ config: BossAppleAudioModeSettingsConfig) -> String {
        "cnc=\(config.cncLevel),autoCNC=\(config.autoCNCEnabled),spatial=\(config.spatialAudioMode.displayName),wind=\(config.windBlockEnabled),anc=\(config.ancToggleEnabled)"
    }

    static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}
