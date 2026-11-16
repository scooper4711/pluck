import Foundation

/// The recent-documents list where the system keeps none, as on the iPad: a bookmark for each PDF, in the
/// app's settings. A bookmark of a file from Files or another app carries the permission to read it again, so
/// make it while the file is open. A PDF that has since been moved away or deleted drops off the list.
@MainActor
public struct BookmarkedRecentDocuments: RecentDocumentStore {
    public static let defaultsKey = "recentDocumentBookmarks"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Most recently opened first.
    public var urls: [URL] {
        bookmarks.compactMap(Self.url)
    }

    public func note(_ url: URL) {
        guard let bookmark = try? url.bookmarkData() else { return }
        let others = bookmarks.filter { Self.url(from: $0).map(Self.isSameFile(as: url)) == false }
        defaults.set(Array(([bookmark] + others).prefix(RecentDocuments.maximumCount)), forKey: Self.defaultsKey)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private var bookmarks: [Data] {
        defaults.array(forKey: Self.defaultsKey) as? [Data] ?? []
    }

    private static func url(from bookmark: Data) -> URL? {
        var isStale = false
        return try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
    }

    /// A bookmark may resolve to another spelling of the path it was made from (`/private/var` for `/var`).
    private static func isSameFile(as url: URL) -> (URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        return { $0.resolvingSymlinksInPath().path == path }
    }
}
