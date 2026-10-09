import Foundation
import Testing
@testable import PluckKit

/// Answers requests for registered addresses with a canned status and body, without touching the network.
/// Addresses nobody registered fail as if the network were down.
final class StubWeb: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: (status: Int, body: Data)] = [:]

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubWeb.self]
        return URLSession(configuration: configuration)
    }()

    static func on(_ address: String, status: Int = 200, body: Data) {
        lock.withLock { replies[address] = (status, body) }
    }

    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let address = request.url?.absoluteString ?? ""
        guard let reply = Self.lock.withLock({ Self.replies[address] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // Replies are delivered at once in startLoading, so there is nothing to stop.
    }
}

@Suite struct AppVersionTests {
    @Test(arguments: [
        ("v0.10.0", "0.9.3"), ("1.0.1", "1.0"), ("v2", "1.99.99"), ("0.2.0", "v0.1.0"), ("1.2.3-rc.1", "1.2.2")
    ])
    func newerVersionsCompareGreater(newer: String, older: String) {
        #expect(AppVersion(newer) > AppVersion(older))
        #expect(AppVersion(older) < AppVersion(newer))
    }

    @Test(arguments: [("1.0", "v1.0.0"), ("v0.1.0", "0.1"), ("1.2.3-rc.1", "1.2.3"), ("", "0")])
    func equivalentVersionsAreEqual(first: String, second: String) {
        #expect(AppVersion(first) == AppVersion(second))
        #expect(!(AppVersion(first) < AppVersion(second)))
    }

    @Test func describesItself() {
        #expect(AppVersion(" v0.10.2 ").description == "0.10.2")
        #expect(AppVersion("nonsense").description == "0")
    }
}

@MainActor
@Suite struct AppUpdaterTests {
    /// Each test has its own repository and download host, so the shared stub never mixes their replies.
    let product = UpdateProduct(name: "Pluck", repository: "test/\(UUID().uuidString)")
    let downloads: URL = {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
    var releaseAddress: String { "https://api.github.com/repos/\(product.repository)/releases/latest" }
    var downloadAddress: String { "https://downloads.example/\(product.repository)/Pluck-0.2.0.dmg" }

    func makeUpdater(running version: String = "0.1.0") -> AppUpdater {
        AppUpdater(product: product, currentVersion: version, downloadsDirectory: downloads, session: StubWeb.session)
    }

    func publish(tag: String, assets: [String] = ["Pluck-0.2.0.dmg"]) throws {
        let list = assets.map { ["name": $0, "browser_download_url": downloadAddress] }
        let release: [String: Any] = ["tag_name": tag, "assets": list]
        StubWeb.on(releaseAddress, body: try JSONSerialization.data(withJSONObject: release))
        StubWeb.on(downloadAddress, body: Data("disk image bytes".utf8))
    }

    @Test func offersANewerReleaseWithoutDownloadingIt() async throws {
        try publish(tag: "v0.2.0", assets: ["notes.txt", "Pluck-0.2.0.dmg"])
        let updater = makeUpdater()
        await updater.checkForUpdate()
        #expect(updater.state == .available(version: "0.2.0") && updater.state.isResult)
        #expect(updater.title == "Pluck 0.2.0 is available")
        #expect(updater.message.hasPrefix("Would you like to download it?"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: downloads.path).isEmpty)
    }

    @Test func downloadsTheOfferedDiskImageToTheDownloadsFolder() async throws {
        try publish(tag: "v0.2.0")
        let updater = makeUpdater()
        await updater.checkForUpdate()
        await updater.downloadUpdate()
        let file = downloads.appending(path: "Pluck-0.2.0.dmg")
        #expect(updater.state == .downloaded(version: "0.2.0", file: file))
        #expect(try String(contentsOf: file, encoding: .utf8) == "disk image bytes")
        #expect(updater.title == "Pluck 0.2.0 has been downloaded")
        #expect(updater.message.contains("Pluck-0.2.0.dmg") && updater.message.contains("quit Pluck"))
    }

    @Test func downloadsNothingUntilAVersionIsOffered() async {
        let updater = makeUpdater()
        await updater.downloadUpdate()
        #expect(updater.state == .idle && updater.title.isEmpty && updater.message.isEmpty)
    }

    @Test func reportsADownloadThatFails() async throws {
        try publish(tag: "v0.2.0")
        StubWeb.on(downloadAddress, status: 404, body: Data())
        let updater = makeUpdater()
        await updater.checkForUpdate()
        await updater.downloadUpdate()
        guard case let .failed(message) = updater.state else { Issue.record("not failed"); return }
        #expect(message.hasPrefix("Downloading the update failed") && message.contains("404"))
    }

    @Test(arguments: ["v0.1.0", "0.0.9"])
    func saysWhenTheAppIsUpToDate(tag: String) async throws {
        try publish(tag: tag)
        let updater = makeUpdater()
        await updater.checkForUpdate()
        #expect(updater.state == .upToDate(version: "0.1.0"))
        #expect(updater.title == "Pluck is up to date" && updater.message.contains("0.1.0"))
    }

    @Test func isUpToDateWhileNoReleaseHasBeenPublished() async {
        StubWeb.on(releaseAddress, status: 404, body: Data())
        let updater = makeUpdater()
        await updater.checkForUpdate()
        #expect(updater.state == .upToDate(version: "0.1.0"))
    }

    @Test func reportsAReleaseWithoutADiskImage() async throws {
        try publish(tag: "v0.2.0", assets: ["notes.txt"])
        let updater = makeUpdater()
        await updater.checkForUpdate()
        #expect(updater.state == .failed(message: UpdateError.noDiskImage(version: "0.2.0").localizedDescription))
        #expect(updater.title == "The update check did not finish" && updater.message.contains("0.2.0"))
    }

    @Test func reportsGitHubsErrorsAndUnreadableAnswers() async {
        let updater = makeUpdater()
        StubWeb.on(releaseAddress, status: 403, body: Data())
        await updater.checkForUpdate()
        #expect(updater.state == .failed(message: UpdateError.http(status: 403).localizedDescription))
        StubWeb.on(releaseAddress, body: Data("not json".utf8))
        await updater.checkForUpdate()
        #expect(updater.state == .failed(message: UpdateError.unreadableAnswer.localizedDescription))
    }

    @Test func staysQuietAtLaunchUnlessThereIsAnUpdate() async throws {
        let updater = makeUpdater()
        await updater.checkForUpdateQuietly()
        #expect(updater.state == .idle)
        try publish(tag: "v0.1.0")
        await updater.checkForUpdateQuietly()
        #expect(updater.state == .idle)
        try publish(tag: "v0.2.0")
        await updater.checkForUpdateQuietly()
        #expect(updater.state == .available(version: "0.2.0"))
    }

    @Test func dismissingClearsOnlyAResult() async throws {
        try publish(tag: "v0.2.0")
        let updater = makeUpdater()
        updater.dismiss()
        #expect(updater.state == .idle)
        await updater.checkForUpdate()
        updater.dismiss()
        #expect(updater.state == .idle)
    }

    @Test func describesTheBusyStates() {
        #expect(UpdateState.checking.isBusy && !UpdateState.checking.isResult)
        #expect(UpdateState.downloading(version: "1").isBusy && !UpdateState.idle.isBusy)
    }

    @Test func checksAtLaunchOnlyForReleasedVersionsWhenSwitchedOn() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        #expect(makeUpdater().checksAtLaunch(in: defaults))
        #expect(!makeUpdater(running: "0.0.0").checksAtLaunch(in: defaults))
        defaults.set(false, forKey: AppUpdater.checksAtLaunchKey)
        #expect(!makeUpdater().checksAtLaunch(in: defaults))
    }

    @Test func makesTheUpdaterForTheRunningApp() {
        let updater = AppUpdater.live(product: product)
        #expect(updater.product.name == "Pluck" && updater.state == .idle)
    }
}
