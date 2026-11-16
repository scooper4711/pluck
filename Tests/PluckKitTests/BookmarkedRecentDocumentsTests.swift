import Foundation
@testable import PluckKit
import Testing

/// The iPad's Open Recent list, kept as bookmarks in the app's settings.
@MainActor
@Suite("Bookmarked recent documents")
struct BookmarkedRecentDocumentsTests {
    private let defaults: UserDefaults
    private let store: BookmarkedRecentDocuments
    private let folder: URL

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "PluckTests-\(UUID().uuidString)"))
        store = BookmarkedRecentDocuments(defaults: defaults)
        folder = try TemporaryDirectory.make()
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = folder.appending(path: name)
        try Data("%PDF".utf8).write(to: url)
        return url
    }

    private var names: [String] { store.urls.map(\.lastPathComponent) }

    @Test("A noted PDF heads the list, and noting it again moves it up without repeating it")
    func noting() throws {
        let first = try makeFile("First.pdf")
        let second = try makeFile("Second.pdf")
        #expect(store.urls.isEmpty)

        store.note(first)
        store.note(second)
        #expect(names == ["Second.pdf", "First.pdf"])
        store.note(first)
        #expect(names == ["First.pdf", "Second.pdf"])
    }

    @Test("The list survives a relaunch, feeds Open Recent, and can be cleared")
    func persistence() throws {
        store.note(try makeFile("Kept.pdf"))

        let recents = RecentDocuments(store: BookmarkedRecentDocuments(defaults: defaults))
        #expect(recents.urls.map(\.lastPathComponent) == ["Kept.pdf"])
        recents.clear()
        #expect(store.urls.isEmpty)
    }

    @Test("A PDF that was deleted drops off the list, and one that never existed is not listed")
    func missingFiles() throws {
        let deleted = try makeFile("Deleted.pdf")
        store.note(deleted)
        store.note(try makeFile("Present.pdf"))
        try FileManager.default.removeItem(at: deleted)
        #expect(names == ["Present.pdf"])

        store.note(folder.appending(path: "Never.pdf"))
        #expect(names == ["Present.pdf"])
    }

    @Test("The list keeps only the most recent documents")
    func limit() throws {
        for index in 0...RecentDocuments.maximumCount {
            store.note(try makeFile("File \(index).pdf"))
        }
        #expect(store.urls.count == RecentDocuments.maximumCount)
        #expect(names.first == "File \(RecentDocuments.maximumCount).pdf")
        #expect(!names.contains("File 0.pdf"))
    }
}
