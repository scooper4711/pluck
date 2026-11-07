import Foundation
import TablesideShared
import Observation

/// What Pluck needs from the system to work with another app. The app uses `NSWorkspace`; tests use a fake.
@MainActor
public protocol ApplicationLauncher {
    func isInstalled(_ bundleIdentifier: String) -> Bool
    func open(_ url: URL)
    /// Opens the URL without bringing its app to the front.
    func openInBackground(_ url: URL)
    func launch(_ bundleIdentifier: String)
}

/// The title Pluck asked Scrollkeeper to open, and how that is going.
public struct ScrollkeeperRequest: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case requested
        case downloading(Double)
        /// Downloaded; its PDFs are on their way.
        case opening
        case failed(String)
    }

    public var sku: String
    public var phase: Phase
}

extension ScrollkeeperRequest.Phase {
    public var isFailure: Bool {
        if case .failed = self { true } else { false }
    }
}

/// Scrollkeeper as Pluck sees it: Pluck reads the list of titles from Scrollkeeper's folder in the App Group, or
/// asks for it and has it handed over as a file (which a sandboxed app may then read), and asks Scrollkeeper to open
/// a title, whose PDFs Scrollkeeper opens in Pluck. A title already in the shared folder opens straight from there.
@MainActor
@Observable
public final class ScrollkeeperBridge {
    public enum State: Equatable, Sendable {
        case idle
        case notInstalled
        /// Asked for the list; Scrollkeeper may still be starting or loading its library.
        case waiting
        case unsupportedVersion
        case unreadable
        /// Scrollkeeper couldn't send the list, for the reason it gives.
        case failed(String)
        case loaded(ScrollkeeperIndex)
    }

    public static let bundleIdentifier = "io.github.scooper4711.Scrollkeeper"
    public static let downloadPage = URL(string: "https://github.com/scooper4711/scrollkeeper/releases/latest")!

    public private(set) var state = State.idle
    public private(set) var request: ScrollkeeperRequest?
    /// Opens the PDFs of a title that is on disk, which needs no request.
    @ObservationIgnored public var openDocuments: ([URL]) -> Void = { _ in }
    @ObservationIgnored private let launcher: ApplicationLauncher
    /// Scrollkeeper's folder in the App Group; nil when Pluck isn't in the group.
    @ObservationIgnored private let libraryFolder: URL?
    /// True while the list shown was read from the library list, which is read again when it changes.
    @ObservationIgnored private var isShowingLibrary = false

    public init(launcher: ApplicationLauncher, libraryFolder: URL? = nil) {
        self.launcher = launcher
        self.libraryFolder = libraryFolder
    }

    /// Reads the list of titles from Scrollkeeper's library list, or when there is none, asks Scrollkeeper,
    /// staying in the background, to hand it over.
    public func requestIndex() {
        guard launcher.isInstalled(Self.bundleIdentifier) else {
            state = .notInstalled
            return
        }
        if readLibrary() { return }
        state = .waiting
        launcher.openInBackground(Self.requestURL(host: "index", sku: nil))
    }

    /// Reads the library list again after Scrollkeeper says it changed, while the list shown came from it.
    public func refreshLibrary() {
        guard isShowingLibrary else { return }
        _ = readLibrary()
    }

    /// Reads the list Scrollkeeper handed over.
    public func receive(_ file: URL) {
        isShowingLibrary = false
        guard let data = try? Data(contentsOf: file),
              let header = try? Self.decoder.decode(FormatHeader.self, from: data) else {
            state = .unreadable
            return
        }
        guard header.formatVersion <= ScrollkeeperIndex.supportedFormatVersion else {
            state = .unsupportedVersion
            return
        }
        guard let index = try? Self.decoder.decode(ScrollkeeperIndex.self, from: data) else {
            state = .unreadable
            return
        }
        state = .loaded(index)
    }

    /// Opens the title's PDFs when they are in the shared folder; otherwise asks Scrollkeeper, staying in the
    /// background, to download the title when needed and open its PDFs in Pluck. Scrollkeeper reports how that goes
    /// with status links (`receiveStatus`).
    public func open(_ entry: ScrollkeeperIndex.Entry) {
        guard entry.localFiles.isEmpty else {
            openDocuments(entry.localFiles)
            return
        }
        request = ScrollkeeperRequest(sku: entry.sku, phase: .requested)
        launcher.openInBackground(Self.requestURL(host: "open", sku: entry.sku))
    }

    /// True for a link in which Scrollkeeper reports how a request is going.
    public static func isStatusLink(_ url: URL) -> Bool {
        url.scheme == statusScheme && url.host == "handoff"
    }

    /// Takes a status link: `pluck://handoff?sku=…&state=downloading|done|failed[&fraction=…][&reason=…]`.
    public func receiveStatus(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value ?? "" }
        let sku = value("sku")
        if sku.isEmpty, value("state") == "failed" {
            state = .failed(value("reason"))
            return
        }
        guard request?.sku == sku, let phase = Self.phase(state: value("state"), items: value) else { return }
        request?.phase = phase
    }

    private static func phase(state: String, items value: (String) -> String) -> ScrollkeeperRequest.Phase? {
        switch state {
        case "downloading": .downloading(Double(value("fraction")) ?? 0)
        case "done": .opening
        case "failed": .failed(value("reason"))
        default: nil
        }
    }

    private static let statusScheme = "pluck"

    /// True when the library list was read: one Pluck understands, in the App Group.
    private func readLibrary() -> Bool {
        guard let folder = libraryFolder, case let .loaded(library) = ScrollkeeperLibrary.read(from: folder)
        else { return false }
        state = .loaded(library.pluckIndex(in: folder))
        isShowingLibrary = true
        return true
    }

    /// Brings Scrollkeeper forward, so the user can sign in and load their library.
    public func launchScrollkeeper() {
        launcher.launch(Self.bundleIdentifier)
    }

    static func requestURL(host: String, sku: String?) -> URL {
        var components = URLComponents()
        components.scheme = "scrollkeeper"
        components.host = host
        components.queryItems = (sku.map { [URLQueryItem(name: "sku", value: $0)] } ?? [])
            + [URLQueryItem(name: "app", value: "pluck")]
        return components.url!
    }

    private struct FormatHeader: Decodable {
        var formatVersion: Int
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
