import Combine
import Foundation
import Observation

/// Hands PDFs the user asked for (File ▸ Open, Open Recent, Finder, a drop) to whichever window
/// picks them up first, and knows whether any document window is open.
@MainActor
@Observable
public final class DocumentRouter {
    /// Documents waiting for a window, oldest first.
    public private(set) var pendingURLs: [URL] = []
    private var documentWindows: Set<UUID> = []

    public init() {}

    /// True while at least one window shows a document; the empty launch window closes then.
    public var hasDocumentWindows: Bool { !documentWindows.isEmpty }

    public func open(_ urls: [URL]) {
        pendingURLs.append(contentsOf: urls)
    }

    /// Takes every pending document; each is handed out exactly once.
    public func claimPending() -> [URL] {
        defer { pendingURLs = [] }
        return pendingURLs
    }

    public func documentWindowDidAppear(_ window: UUID) {
        documentWindows.insert(window)
    }

    public func documentWindowDidClose(_ window: UUID) {
        documentWindows.remove(window)
    }
}

/// Where the list of recently opened documents is kept.
@MainActor
public protocol RecentDocumentStore {
    var urls: [URL] { get }
    func note(_ url: URL)
    func clear()
}

/// The File ▸ Open Recent list. An `ObservableObject` so `PluckCommands` can watch it with
/// `@ObservedObject`.
@MainActor
public final class RecentDocuments: ObservableObject {
    public static let maximumCount = 10

    /// Most recently opened first.
    @Published public private(set) var urls: [URL]
    private let store: RecentDocumentStore

    public init(store: RecentDocumentStore) {
        self.store = store
        urls = Array(store.urls.prefix(Self.maximumCount))
    }

    /// Moves a document that was just opened to the top of the list.
    public func note(_ url: URL) {
        // The list is kept here rather than re-read, because the system store updates late.
        urls = Array(([url] + urls.filter { $0 != url }).prefix(Self.maximumCount))
        store.note(url)
    }

    public func clear() {
        urls = []
        store.clear()
    }
}
