//
//  To_DoApp.swift
//  To Do
//
//  Created by Mukul Arora on 28/02/26.
//

import SwiftUI
import SwiftData
import AuthenticationServices

@main
struct To_DoApp: App {
    private static let cloudKitContainerID = "iCloud.com.matodoapp.todo"
    @AppStorage("isSignedIn") private var isSignedIn = false
    @AppStorage("signedInEmail") private var signedInEmail = ""
    @AppStorage("appleUserID") private var appleUserID = ""

    @State private var authErrorMessage: String?
    @State private var storageWarningMessage: String?
    private let launchArguments = ProcessInfo.processInfo.arguments
    private let storageBootstrap: StorageBootstrap

    init() {
        let bootstrap = StorageBootstrap.make()
        storageBootstrap = bootstrap
        _storageWarningMessage = State(initialValue: bootstrap.warningMessage)
    }

    private var sharedModelContainer: ModelContainer {
        storageBootstrap.container
    }

    fileprivate static func makeCloudKitModelContainer() -> StorageBootstrap {
        let launchArguments = ProcessInfo.processInfo.arguments
        let isInMemoryStore = launchArguments.contains("UITEST_IN_MEMORY_STORE")
        let schema = Schema([
            TodoList.self,
            TaskItem.self,
        ])
        let cloudKitConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isInMemoryStore,
            cloudKitDatabase: isInMemoryStore ? .none : .private(Self.cloudKitContainerID)
        )
        let localOnlyConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isInMemoryStore,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [cloudKitConfiguration])
            return StorageBootstrap(container: container, warningMessage: nil)
        } catch let cloudKitError {
            do {
                // Fall back to local-only storage if CloudKit-backed container setup fails.
                let localContainer = try ModelContainer(for: schema, configurations: [localOnlyConfiguration])
                return StorageBootstrap(
                    container: localContainer,
                    warningMessage: """
                    CloudKit initialization failed, so this device is using local-only storage.
                    Existing data on this device is still retained and will stay available here.
                    Error: \(cloudKitError.localizedDescription)
                    """
                )
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if shouldSkipAuth || isSignedIn {
                    ContentView(userEmail: displayedEmail, onSignOut: signOut)
                } else {
                    SignInView(handleSignInResult: handleSignInResult)
                }
            }
            .alert(
                "Sign In Error",
                isPresented: Binding(
                    get: { authErrorMessage != nil },
                    set: { shouldShow in
                        if !shouldShow {
                            authErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    authErrorMessage = nil
                }
            } message: {
                Text(authErrorMessage ?? "Unknown error")
            }
            .task {
                await validateStoredAppleCredentialIfNeeded()
            }
            .alert(
                "Cloud Sync Disabled",
                isPresented: Binding(
                    get: { storageWarningMessage != nil },
                    set: { shouldShow in
                        if !shouldShow {
                            storageWarningMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    storageWarningMessage = nil
                }
            } message: {
                Text(storageWarningMessage ?? "")
            }
        }
        .modelContainer(sharedModelContainer)
    }

    private var shouldSkipAuth: Bool {
        launchArguments.contains("UITEST_DISABLE_AUTH")
    }

    private var displayedEmail: String {
        signedInEmail.isEmpty ? "Apple User" : signedInEmail
    }

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                authErrorMessage = AppleAuthError.invalidCredential.errorDescription
                return
            }

            appleUserID = credential.user

            if let email = credential.email, !email.isEmpty {
                signedInEmail = email
            } else if signedInEmail.isEmpty {
                signedInEmail = "Apple User"
            }

            isSignedIn = true
            authErrorMessage = nil

        case .failure(let error):
            if let appleError = error as? ASAuthorizationError, appleError.code == .canceled {
                return
            }
            authErrorMessage = error.localizedDescription
        }
    }

    private func signOut() {
        signedInEmail = ""
        appleUserID = ""
        isSignedIn = false
    }

    private func validateStoredAppleCredentialIfNeeded() async {
        guard !shouldSkipAuth else { return }
        guard isSignedIn, !appleUserID.isEmpty else { return }

        let provider = ASAuthorizationAppleIDProvider()

        do {
            let state = try await credentialState(for: appleUserID, provider: provider)
            if state != .authorized {
                signOut()
            }
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    private func credentialState(
        for userID: String,
        provider: ASAuthorizationAppleIDProvider
    ) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        try await withCheckedThrowingContinuation { continuation in
            provider.getCredentialState(forUserID: userID) { state, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: state)
            }
        }
    }
}

fileprivate struct StorageBootstrap {
    let container: ModelContainer
    let warningMessage: String?

    static func make() -> StorageBootstrap {
        To_DoApp.makeCloudKitModelContainer()
    }
}

private struct SignInView: View {
    let handleSignInResult: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("To Do")
                .font(.largeTitle.bold())

            Text("Sign in with Apple to sync your lists securely across devices.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("TestFlight installs on new devices work normally, but cross-device sync requires the same Apple ID signed into iCloud on each device. Updating the app on an existing device keeps its current data.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleSignInResult(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: 320, minHeight: 44, maxHeight: 44)
            .accessibilityIdentifier("appleSignInButton")
        }
        .padding()
    }
}

enum AppleAuthError: LocalizedError {
    case invalidCredential

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Unable to read Apple ID credential from sign-in response."
        }
    }
}
