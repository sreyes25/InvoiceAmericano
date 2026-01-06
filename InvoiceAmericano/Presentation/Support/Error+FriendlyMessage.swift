import Foundation

extension Error {
    /// Returns true when the error (or one of its underlying errors) indicates the device is offline
    /// or cannot reach the network. Covers common URL loading error codes.
    var isOfflineError: Bool {
        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain {
            let offlineCodes: [URLError.Code] = [
                .notConnectedToInternet,
                .networkConnectionLost,
                .timedOut,
                .cannotFindHost,
                .cannotConnectToHost,
                .dataNotAllowed,
                .internationalRoamingOff
            ]
            if offlineCodes.contains(URLError.Code(rawValue: nsError.code)) {
                return true
            }
        }

        // Check underlying error recursively
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error,
           underlying.isOfflineError {
            return true
        }
        return false
    }

    /// Provides a user-facing error message with an offline-specific variant.
    var friendlyMessage: String {
        if isOfflineError {
            return "You’re offline. Check your connection and try again."
        }
        return localizedDescription
    }
}
