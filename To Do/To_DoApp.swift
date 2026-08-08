//
//  To_DoApp.swift
//  To Do
//
//  Created by Mukul Arora on 28/02/26.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct To_DoApp: App {
    // fileprivate so StorageBootstrap, below, can read it.
    fileprivate static let cloudKitContainerID = "iCloud.com.matodoapp.todo"

    @State private var storageWarningMessage: String?
    @State private var eraseDataErrorMessage: String?
    private let launchArguments = ProcessInfo.processInfo.arguments
    private let storage: StorageBootstrap

    init() {
        storage = StorageBootstrap.make()
        if case .ready(_, let warning) = storage {
            _storageWarningMessage = State(initialValue: warning)
        }
    }

    var body: some Scene {
        WindowGroup {
            switch storage {
            case .ready(let container, _):
                mainInterface(container: container)
                    .modelContainer(container)
            case .failed(let message):
                StorageFailureView(message: message)
            }
        }
    }

    // MARK: - Interface

    @ViewBuilder
    private func mainInterface(container: ModelContainer) -> some View {
        ContentView(
            onEraseAllData: { eraseAllData(in: container) },
            initialTab: isScreenshotMode ? screenshotInitialTab : 0,
            initialCRMTab: isScreenshotMode ? screenshotInitialCRMTab : 0,
            autoSelectFirstList: isScreenshotMode ? screenshotAutoSelectList : false
        )
        .onAppear {
            if isScreenshotMode {
                SampleData.inject(into: container.mainContext)
            }
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
        .alert(
            "Couldn't Erase Data",
            isPresented: Binding(
                get: { eraseDataErrorMessage != nil },
                set: { shouldShow in
                    if !shouldShow {
                        eraseDataErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                eraseDataErrorMessage = nil
            }
        } message: {
            Text(eraseDataErrorMessage ?? "")
        }
    }

    // MARK: - Erase All Data

    private func eraseAllData(in container: ModelContainer) {
        let context = container.mainContext
        do {
            try context.delete(model: TaskItem.self)
            try context.delete(model: TodoList.self)
            try context.delete(model: Interaction.self)
            try context.delete(model: Contact.self)
            try context.save()
        } catch {
            eraseDataErrorMessage = """
            Your data could not be erased, so nothing was removed. Please try again.
            Error: \(error.localizedDescription)
            """
            return
        }

        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        NotificationService.shared.clearBadge()
    }

    // MARK: - Screenshot mode

    private var isScreenshotMode: Bool {
        launchArguments.contains("SCREENSHOT_MODE")
    }

    private var screenshotScreen: String {
        if let idx = launchArguments.firstIndex(of: "SCREENSHOT_SCREEN"),
           idx + 1 < launchArguments.count {
            return launchArguments[idx + 1]
        }
        return "lists"
    }

    private var screenshotInitialTab: Int {
        switch screenshotScreen {
        case "crm_dashboard", "crm_contacts": return 1
        default: return 0
        }
    }

    private var screenshotInitialCRMTab: Int {
        screenshotScreen == "crm_contacts" ? 1 : 0
    }

    private var screenshotAutoSelectList: Bool {
        screenshotScreen == "tasks_detail"
    }
}

// MARK: - Storage

fileprivate enum StorageBootstrap {
    /// The store opened. `warning` is set when CloudKit was unavailable and the app fell
    /// back to local-only storage, so the user can be told sync is off.
    case ready(container: ModelContainer, warning: String?)
    /// Neither the CloudKit-backed nor the local-only store could be opened.
    case failed(message: String)

    static func make() -> StorageBootstrap {
        let launchArguments = ProcessInfo.processInfo.arguments
        let isInMemoryStore = launchArguments.contains("UITEST_IN_MEMORY_STORE")
        let schema = Schema([
            TodoList.self,
            TaskItem.self,
            Contact.self,
            Interaction.self,
        ])
        let cloudKitConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isInMemoryStore,
            cloudKitDatabase: isInMemoryStore ? .none : .private(To_DoApp.cloudKitContainerID)
        )
        let localOnlyConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isInMemoryStore,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [cloudKitConfiguration])
            return .ready(container: container, warning: nil)
        } catch let cloudKitError {
            do {
                // Fall back to local-only storage if CloudKit-backed setup fails.
                let localContainer = try ModelContainer(for: schema, configurations: [localOnlyConfiguration])
                return .ready(
                    container: localContainer,
                    warning: """
                    Cloud sync initialization failed, so this device is using local-only storage.
                    Existing data on this device is still retained and will stay available here.
                    Error: \(cloudKitError.localizedDescription)
                    """
                )
            } catch {
                // Previously a fatalError. A launch crash tells the user nothing and loses
                // the underlying error; an explanation they can screenshot is more useful.
                return .failed(message: error.localizedDescription)
            }
        }
    }
}

/// Shown when no store could be opened at all. The app cannot function without one, but
/// crashing on launch is strictly worse than explaining why.
private struct StorageFailureView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Can't Open Your Data", systemImage: "externaldrive.badge.xmark")
        } description: {
            VStack(spacing: 12) {
                Text("Folio couldn't open its local database, so it can't start.")
                Text("Restarting your device often clears this. If it keeps happening, reinstalling the app will fix it — your data will be restored from iCloud if sync was on.")
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .multilineTextAlignment(.center)
        }
        .padding()
    }
}
