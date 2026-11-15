import Foundation
import PluckKit
import TablesideShared
import Testing

/// Open from Scrollkeeper (R8) as Pluck configures tabletop-kit's bridge, which has its own tests there.
@MainActor
@Suite final class PluckScrollkeeperTests {
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

    private static func edition(_ path: String, isFolder: Bool = false) -> ScrollkeeperLibrary.Edition {
        ScrollkeeperLibrary.Edition(name: path, path: path, isFolder: isFolder, downloaded: true)
    }

    private func loadedBridge() -> ScrollkeeperBridge {
        let bridge = ScrollkeeperBridge(configuration: .pluck, launcher: launcher, libraryFolder: folder)
        bridge.requestIndex()
        return bridge
    }

    private func entries(of bridge: ScrollkeeperBridge) throws -> [ScrollkeeperIndex.Entry] {
        guard case let .loaded(index) = bridge.state else { throw LibraryTestError.notLoaded }
        return index.titles
    }

    @Test func listsTheTitlesWithPDFsFromTheLibraryWithTheirKinds() throws {
        try write([
            Self.title("BOOK", cover: "Covers/BOOK.jpg", editions: [Self.edition("Book/Book.pdf")]),
            Self.title("PACK", kind: "Society Scenarios", editions: [Self.edition("Pack/Pack", isFolder: true)]),
            Self.title("AUDIO", editions: [Self.edition("Audio/Audio.mp3")]),
            Self.title("ART", editions: [Self.edition("Art/Art.jpg")])
        ])

        let entries = try entries(of: loadedBridge())
        #expect(entries.map(\.sku) == ["BOOK", "PACK"])
        #expect(entries[1].subtitle == "Society Scenarios")
        #expect(entries[0].coverURL == folder.appending(path: "Covers/BOOK.jpg"))
        #expect(launcher.backgroundURLs.isEmpty)
    }

    @Test func opensOnlyThePDFsOnDiskStraightFromTheSharedFolder() throws {
        try addFile("Pack/Pack/map.jpg")
        try addFile("Pack/Pack/scenario.pdf")
        try write([Self.title("PACK", editions: [Self.edition("Pack/Pack", isFolder: true)])])
        let bridge = loadedBridge()
        var opened: [URL] = []
        bridge.openDocuments = { opened += $0 }

        bridge.open(try #require(try entries(of: bridge).first))

        #expect(opened.map(\.lastPathComponent) == ["scenario.pdf"])
        #expect(launcher.backgroundURLs.isEmpty)
        #expect(bridge.requests.isEmpty)
    }

    @Test func asksScrollkeeperAsPluckForTheListAndForATitle() throws {
        let bridge = loadedBridge()
        #expect(bridge.state == .waiting)

        bridge.open(ScrollkeeperIndex.Entry(sku: "BOOK", title: "Book", downloaded: false))

        #expect(launcher.backgroundURLs.map(\.absoluteString)
            == ["scrollkeeper://index?app=pluck", "scrollkeeper://open?sku=BOOK&app=pluck"])
    }

    @Test func asksForOneTitleAtATimeAndFollowsItsStatusLinks() throws {
        let bridge = loadedBridge()
        bridge.open(ScrollkeeperIndex.Entry(sku: "FIRST", title: "First", downloaded: false))
        bridge.open(ScrollkeeperIndex.Entry(sku: "BOOK", title: "Book", downloaded: false))
        let done = try #require(URL(string: "pluck://handoff?sku=BOOK&state=done"))

        #expect(bridge.isStatusLink(done))
        bridge.receiveStatus(done)

        #expect(bridge.requests == ["BOOK": ScrollkeeperRequest(sku: "BOOK", opens: true, phase: .done)])
    }
}

@MainActor
final class FakeLauncher: ApplicationLauncher {
    var backgroundURLs: [URL] = []

    func isInstalled(_: String) -> Bool { true }
    func openInBackground(_ url: URL) { backgroundURLs.append(url) }
    func launch(_: String) {}
}

enum LibraryTestError: Error {
    case notLoaded
}
