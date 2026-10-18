import Foundation
@testable import PluckKit
import Testing

/// Open from Scrollkeeper (R8): asking for the list, reading it, and asking for a title.
@MainActor
@Suite struct ScrollkeeperBridgeTests {
    private let launcher = FakeLauncher()

    @Test func asksScrollkeeperInTheBackgroundForTheList() {
        let bridge = ScrollkeeperBridge(launcher: launcher)
        bridge.requestIndex()
        #expect(bridge.state == .waiting)
        #expect(launcher.backgroundURLs.map(\.absoluteString) == ["scrollkeeper://index?app=pluck"])
    }

    @Test func saysWhenScrollkeeperIsNotInstalled() {
        launcher.installed = false
        let bridge = ScrollkeeperBridge(launcher: launcher)
        bridge.requestIndex()
        #expect(bridge.state == .notInstalled)
        #expect(launcher.backgroundURLs.isEmpty)
    }

    @Test func readsTheListScrollkeeperHandsOver() throws {
        let bridge = ScrollkeeperBridge(launcher: launcher)
        bridge.receive(try Self.write(Self.json(version: 1)))
        guard case let .loaded(index) = bridge.state else {
            Issue.record("Expected a loaded list, got \(bridge.state)")
            return
        }
        #expect(index.titles.map(\.sku) == ["PZO90200E", "PZO2101E"])
        #expect(index.titles[0].subtitle == "Adventure Paths · Seven Dooms #200")
        #expect(!index.titles[1].downloaded)
    }

    @Test func refusesAListInANewerFormat() throws {
        let bridge = ScrollkeeperBridge(launcher: launcher)
        bridge.receive(try Self.write(Self.json(version: 2)))
        #expect(bridge.state == .unsupportedVersion)
    }

    @Test func saysWhenTheListCannotBeRead() throws {
        let bridge = ScrollkeeperBridge(launcher: launcher)
        bridge.receive(try Self.write("not json"))
        #expect(bridge.state == .unreadable)
        bridge.receive(try Self.write(#"{"formatVersion": 1}"#))
        #expect(bridge.state == .unreadable)
    }

    @Test func asksScrollkeeperInTheBackgroundToOpenATitle() {
        let bridge = ScrollkeeperBridge(launcher: launcher)
        bridge.open(ScrollkeeperIndex.Entry(sku: "PZO2101E", title: "Core", kind: "Rulebooks"))
        bridge.launchScrollkeeper()
        #expect(launcher.backgroundURLs.map(\.absoluteString) == ["scrollkeeper://open?sku=PZO2101E&app=pluck"])
        #expect(bridge.request == ScrollkeeperRequest(sku: "PZO2101E", phase: .requested))
        #expect(launcher.launched == [ScrollkeeperBridge.bundleIdentifier])
    }

    @Test func followsTheStatusScrollkeeperReports() throws {
        let bridge = ScrollkeeperBridge(launcher: launcher)
        bridge.open(ScrollkeeperIndex.Entry(sku: "PZO1", title: "Core", kind: "Rulebooks", downloaded: false))
        let status = { (query: String) in try #require(URL(string: "pluck://handoff?sku=PZO1&\(query)")) }

        bridge.receiveStatus(try status("state=downloading&fraction=0.42"))
        #expect(bridge.request?.phase == .downloading(0.42))
        bridge.receiveStatus(try #require(URL(string: "pluck://handoff?sku=OTHER&state=done")))
        #expect(bridge.request?.phase == .downloading(0.42))
        bridge.receiveStatus(try status("state=sideways"))
        #expect(bridge.request?.phase == .downloading(0.42))
        bridge.receiveStatus(try status("state=done"))
        #expect(bridge.request?.phase == .opening)
        bridge.receiveStatus(try status("state=failed&reason=Signed%20out"))
        #expect(bridge.request?.phase == .failed("Signed out"))
        #expect(bridge.request?.phase.isFailure == true)
    }

    @Test func showsWhyScrollkeeperCouldNotSendTheList() throws {
        let bridge = ScrollkeeperBridge(launcher: launcher)
        bridge.requestIndex()
        bridge.receiveStatus(try #require(URL(string: "pluck://handoff?sku=&state=failed&reason=Sign%20in")))
        #expect(bridge.state == .failed("Sign in"))
    }

    @Test func tellsAStatusLinkFromOtherLinks() throws {
        #expect(ScrollkeeperBridge.isStatusLink(try #require(URL(string: "pluck://handoff?sku=A&state=done"))))
        #expect(!ScrollkeeperBridge.isStatusLink(try #require(URL(string: "pluck://other"))))
        #expect(!ScrollkeeperBridge.isStatusLink(URL(filePath: "/x/core.pdf")))
    }

    @Test(arguments: [("seven", ["PZO90200E"]), ("RULE core", ["PZO2101E"]), ("", ["PZO90200E", "PZO2101E"]),
                      ("adventure dooms", ["PZO90200E"]), ("bestiary", [])])
    func searchesTitleTypeAndSeries(query: String, expected: [String]) throws {
        let bridge = ScrollkeeperBridge(launcher: launcher)
        bridge.receive(try Self.write(Self.json(version: 1)))
        guard case let .loaded(index) = bridge.state else { return }
        #expect(index.search(query).map(\.sku) == expected)
    }

    @Test func tellsTheListFromAPDF() {
        #expect(ScrollkeeperIndex.isIndexFile(URL(filePath: "/x/pluck.scrollkeeperindex")))
        #expect(!ScrollkeeperIndex.isIndexFile(URL(filePath: "/x/core.pdf")))
    }

    private static func json(version: Int) -> String {
        """
        {"formatVersion": \(version), "generatedAt": "2026-10-18T18:00:00Z", "titles": [
          {"sku": "PZO90200E", "title": "Seven Dooms for Sandpoint", "kind": "Adventure Paths",
           "series": "Seven Dooms", "number": 200, "downloaded": true},
          {"sku": "PZO2101E", "title": "Core Rulebook", "kind": "Rulebooks", "downloaded": false}
        ]}
        """
    }

    private static func write(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).\(ScrollkeeperIndex.fileExtension)")
        try Data(text.utf8).write(to: url)
        return url
    }
}

@MainActor
private final class FakeLauncher: ApplicationLauncher {
    var installed = true
    var openedURLs: [URL] = []
    var backgroundURLs: [URL] = []
    var launched: [String] = []

    func isInstalled(_: String) -> Bool { installed }
    func open(_ url: URL) { openedURLs.append(url) }
    func openInBackground(_ url: URL) { backgroundURLs.append(url) }
    func launch(_ bundleIdentifier: String) { launched.append(bundleIdentifier) }
}
