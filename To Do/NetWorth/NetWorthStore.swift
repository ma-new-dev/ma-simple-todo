import Foundation

/// Reads `networth.json` from Compass's iCloud Documents container.
///
/// The container is `iCloud.com.matodoapp.todo` (the same one CloudKit uses), exposed on
/// the Mac at `~/Library/Mobile Documents/iCloud~com~matodoapp~todo/Documents/`. The
/// folder only appears once the app has touched it, so the first load writes a README.
/// The last good file is cached locally so the tab still shows numbers offline.
@Observable
@MainActor
final class NetWorthStore {
    static let shared = NetWorthStore()

    nonisolated static let containerID = "iCloud.com.matodoapp.todo"
    nonisolated static let fileName = "networth.json"

    var summary: NetWorthSummary?
    var lastError: String?
    var isLoading = false

    private var cacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("networth-cache.json")
    }

    init() {
        if let cacheURL, let data = try? Data(contentsOf: cacheURL) {
            summary = try? JSONDecoder().decode(NetWorthSummary.self, from: data)
        }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let result = await Task.detached(priority: .userInitiated) { () -> Result<Data?, Error> in
            // Resolving the ubiquity container can block, so it stays off the main actor.
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: NetWorthStore.containerID) else {
                return .failure(StoreError.iCloudUnavailable)
            }
            let documents = container.appendingPathComponent("Documents", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
                let readme = documents.appendingPathComponent("README.txt")
                if !FileManager.default.fileExists(atPath: readme.path) {
                    try Data(NetWorthStore.readme.utf8).write(to: readme)
                }

                let file = documents.appendingPathComponent(NetWorthStore.fileName)
                // iCloud may hold only a placeholder until asked to download.
                try? FileManager.default.startDownloadingUbiquitousItem(at: file)
                var coordinated: Data?
                var coordinationError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
                    coordinated = try? Data(contentsOf: url)
                }
                return .success(coordinated)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let data?):
            do {
                let decoded = try JSONDecoder().decode(NetWorthSummary.self, from: data)
                summary = decoded
                lastError = nil
                if let cacheURL {
                    try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: cacheURL)
                }
            } catch {
                lastError = "networth.json couldn't be read: \(error.localizedDescription)"
            }
        case .success(nil):
            if summary == nil { lastError = StoreError.noFileYet.localizedDescription }
        case .failure(let error):
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    enum StoreError: LocalizedError {
        case iCloudUnavailable
        case noFileYet

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable: "iCloud Drive is off or unavailable on this device."
            case .noFileYet: "No summary yet. It appears after the next Portfolio Tracker refresh on your Mac."
            }
        }
    }

    nonisolated static let readme = """
    Compass reads networth.json from this folder for its Net Worth tab.
    A scheduled task on the Mac writes it after each Portfolio Tracker refresh.
    Format: see docs/networth.md in the ma-simple-todo repository.
    """
}
