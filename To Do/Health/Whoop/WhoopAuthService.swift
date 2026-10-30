import AuthenticationServices
import Foundation
import UIKit

/// Drives the OAuth authorization-code flow in a system sign-in sheet.
@MainActor
final class WhoopAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WhoopAuthService()

    /// Presents WHOOP's sign-in, then exchanges the returned code for a token pair.
    func connect() async throws {
        guard let clientID = KeychainStore.get(.whoopClientID),
              let clientSecret = KeychainStore.get(.whoopClientSecret)
        else { throw WhoopError.missingCredentials }

        let state = UUID().uuidString

        var components = URLComponents(string: WhoopAPI.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: WhoopAPI.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: WhoopAPI.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]

        let callback = try await presentSignIn(url: components.url!)

        guard let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        else { throw WhoopError.badCallback }

        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw WhoopError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw WhoopError.badCallback
        }

        let tokens = try await WhoopAPI.postToken(fields: [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": WhoopAPI.redirectURI,
        ])

        await WhoopTokenStore.shared.store(tokens)
    }

    private func presentSignIn(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(WhoopAPI.callbackScheme)
            ) { callbackURL, error in
                if let error {
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    continuation.resume(throwing: cancelled ? WhoopError.authCancelled : error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: WhoopError.badCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            // Keep the shared cookie jar so a WHOOP web session doesn't force a
            // password entry every time.
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let key = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) {
                return key
            }
            guard let scene = scenes.first else {
                preconditionFailure("No window scene available to present WHOOP sign-in")
            }
            return UIWindow(windowScene: scene)
        }
    }
}
