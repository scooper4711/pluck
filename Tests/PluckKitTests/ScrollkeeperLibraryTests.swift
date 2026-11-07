import Foundation
@testable import PluckKit
import TablesideShared
import Testing

/// Open from Scrollkeeper (R8) with the library Scrollkeeper shares in the App Group.
@MainActor
@Suite final class ScrollkeeperLibraryTests {
    private let launcher = FakeLauncher()
    private let folder = FileManager.default.temporaryDirectory.appending(path: "Scrollkeeper-" + UUID().uuidString)
    private var files: URL { folder.appending(path: "Files") }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(isShared: Bool = true, _ titles: [ScrollkeeperLibrary.Title]) throws {
        let library = ScrollkeeperLibrary(generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                          downloadFolder: .init(isShared: isShared), titles: titles)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try library.encoded().write(to: folder.appending(path: ScrollkeeperLibrary.fileName))
    }

    private func addFile(_ path: String) throws {
        let file = files.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: file)
    }

    private static func title(_ sku: String, kind: String = "Adventures", cover: String? = nil,
                              editions: [ScrollkeeperLibrary.Edition]) -> ScrollkeeperLibrary.Title {
        ScrollkeeperLibrary.Title(sku: sku, title: "Title \(sku)", kind: kind, gameSystem: "Pathfinder 2E",
                                  cover: cover, downloaded: editions.contains(where: \.downloaded),
                                  editions: editions)
    }

    private static func edition(_ path: String, isFolder: Bool = false,
                                downloaded: Bool = true) -> ScrollkeeperLibrary.Edition {
        ScrollkeeperLibrary.Edition(name: path, path: path, isFolder: isFolder, downloaded: downloaded)
    }

    private func loadedBridge() -> ScrollkeeperBridge {
        let bridge = ScrollkeeperBridge(launcher: launcher, libraryFolder: folder)
        bridge.requestIndex()
        return bridge
    }

    private func entries(of bridge: ScrollkeeperBridge) throws -> [ScrollkeeperIndex.Entry] {
        guard case let .loaded(index) = bridge.state else { throw LibraryTestError.notLoaded }
        return index.titles
    }

    @Test func listsTheTitlesWithPDFsFromTheLibraryWithoutAskingScrollkeeper() throws {
        try write([
            Self.title("BOOK", cover: "Covers/BOOK.jpg", editions: [Self.edition("Book/Book.pdf")]),
            Self.title("PACK", kind: "Society Scenarios", editions: [Self.edition("Pack/Pack", isFolder: true)]),
            Self.title("AUDIO", editions: [Self.edition("Audio/Audio.mp3")])
        ])

        let entries = try entries(of: loadedBridge())
        #expect(entries.map(\.sku) == ["BOOK", "PACK"])
        #expect(entries[1].subtitle == "Society Scenarios")
        #expect(entries[0].coverURL == folder.appending(path: "Covers/BOOK.jpg"))
        #expect(launcher.backgroundURLs.isEmpty)
    }

    @Test func opensPDFsOnDiskStraightFromTheSharedFolder() throws {
        try addFile("Pack/Pack/map.jpg")
        try addFile("Pack/Pack/scenario.pdf")
        try write([Self.title("PACK", editions: [Self.edition("Pack/Pack", isFolder: true)])])
        let bridge = loadedBridge()
        var opened: [URL] = []
        bridge.openDocuments = { opened += $0 }

        bridge.open(try #require(try entries(of: bridge).first))

        #expect(opened.map(\.lastPathComponent) == ["scenario.pdf"])
        #expect(launcher.backgroundURLs.isEmpty)
        #expect(bridge.request == nil)
    }

    @Test func asksScrollkeeperForTitlesNotInTheSharedFolder() throws {
        try write(isShared: false, [Self.title("BOOK", editions: [Self.edition("Book/Book.pdf")])])
        let bridge = loadedBridge()

        bridge.open(try #require(try entries(of: bridge).first))

        #expect(launcher.backgroundURLs.map(\.absoluteString) == ["scrollkeeper://open?sku=BOOK&app=pluck"])
    }

    @Test func asksScrollkeeperForTheListWhenThereIsNoneToRead() throws {
        let bridge = loadedBridge()
        #expect(bridge.state == .waiting)
        #expect(launcher.backgroundURLs.map(\.absoluteString) == ["scrollkeeper://index?app=pluck"])
    }

    @Test func followsTheLibraryOnlyWhileShowingIt() throws {
        try write([Self.title("BOOK", editions: [Self.edition("Book/Book.pdf")])])
        let bridge = loadedBridge()
        try write([Self.title("BOOK", editions: []), Self.title("NEW", editions: [Self.edition("New/New.pdf")])])

        bridge.refreshLibrary()
        #expect(try entries(of: bridge).map(\.sku) == ["NEW"])

        bridge.receive(try Self.handedOverIndex())
        try write([])
        bridge.refreshLibrary()
        #expect(try entries(of: bridge).map(\.sku) == ["HANDED"])
    }

    private static func handedOverIndex() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).\(ScrollkeeperIndex.fileExtension)")
        let json = """
            {"formatVersion": 1, "generatedAt": "2026-10-18T18:00:00Z",
             "titles": [{"sku": "HANDED", "title": "Handed", "kind": "Rulebooks", "downloaded": true}]}
            """
        try Data(json.utf8).write(to: url)
        return url
    }
}

enum LibraryTestError: Error {
    case notLoaded
}
