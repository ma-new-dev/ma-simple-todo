import Foundation

enum WhoopError: LocalizedError {
    case missingCredentials
    case notConnected
    case authCancelled
    case badCallback
    case stateMismatch
    case http(status: Int, body: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Add your WHOOP client ID and secret in Settings first."
        case .notConnected:
            "Not connected to WHOOP. Tap Connect in Settings."
        case .authCancelled:
            "Sign-in was cancelled."
        case .badCallback:
            "WHOOP returned an unexpected sign-in response."
        case .stateMismatch:
            "Sign-in response did not match the request. Try again."
        case .http(let status, let body):
            "WHOOP returned \(status). \(body.prefix(200))"
        case .decoding(let detail):
            "Could not read WHOOP's response. \(detail)"
        }
    }
}

/// Owns the OAuth token pair and guarantees only one refresh is ever in flight.
///
/// This matters more than it looks. WHOOP invalidates the previous refresh token
/// every time you use one, so two concurrent refreshes race: the loser writes a
/// token that has already been revoked and the next call fails as if the user had
/// signed out. Every token read goes through `validAccessToken()`, and concurrent
/// callers join the same refresh rather than starting their own..
actor WhoopTokenStore {
    static let shared = WhoopTokenStore()

    /// Refresh this long before the token actually expires.
    private let refreshMargin: TimeInterval = 120

    private var refreshInFlight: Task<String, Error>?

    // MARK: State

    nonisolated var isConnected: Bool {
        KeychainStore.get(.whoopRefreshToken) != nil
    }

    nonisolated var hasClientCredentials: Bool {
        KeychainStore.get(.whoopClientID) != nil && KeychainStore.get(.whoopClientSecret) != nil
    }

    func store(_ response: WhoopTokenResponse) {
        KeychainStore.set(response.accessToken, for: .whoopAccessToken)
        // A refresh response may omit the refresh token; keep the existing one if so.
        if let refresh = response.refreshToken {
            KeychainStore.set(refresh, for: .whoopRefreshToken)
        }
        let expiry = Date().addingTimeInterval(response.expiresIn)
        KeychainStore.set(String(expiry.timeIntervalSince1970), for: .whoopExpiresAt)
    }

    func disconnect() {
        refreshInFlight?.cancel()
        refreshInFlight = nil
        KeychainStore.delete(.whoopAccessToken)
        KeychainStore.delete(.whoopRefreshToken)
        KeychainStore.delete(.whoopExpiresAt)
    }

    // MARK: Access

    /// Returns a usable access token, refreshing first if it is expired or close to it.
    func validAccessToken() async throws -> String {
        // Someone else is already refreshing — wait for their result rather than
        // starting a second refresh that would invalidate theirs.
        if let existing = refreshInFlight {
            return try await existing.value
        }

        if let token = KeychainStore.get(.whoopAccessToken), !isExpiringSoon {
            return token
        }

        guard KeychainStore.get(.whoopRefreshToken) != nil else {
            throw WhoopError.notConnected
        }

        let task = Task { try await self.performRefresh() }
        refreshInFlight = task
        do {
            let token = try await task.value
            refreshInFlight = nil
            return token
        } catch {
            refreshInFlight = nil
            throw error
        }
    }

    private var isExpiringSoon: Bool {
        guard let raw = KeychainStore.get(.whoopExpiresAt), let seconds = Double(raw) else {
            return true
        }
        return Date(timeIntervalSince1970: seconds).timeIntervalSinceNow < refreshMargin
    }

    private func performRefresh() async throws -> String {
        guard let clientID = KeychainStore.get(.whoopClientID),
              let clientSecret = KeychainStore.get(.whoopClientSecret)
        else { throw WhoopError.missingCredentials }

        guard let refreshToken = KeychainStore.get(.whoopRefreshToken) else {
            throw WhoopError.notConnected
        }

        let response = try await WhoopAPI.postToken(fields: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "client_secret": clientSecret,
            // `offline` must be sent on the refresh too, not only the initial
            // authorization — omitting it here is a documented way to lose the
            // refresh token mid-chain..
            "scope": "offline",
        ])

        store(response)
        return response.accessToken
    }
}
