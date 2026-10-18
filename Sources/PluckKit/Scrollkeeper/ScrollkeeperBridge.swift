import Foundation
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

/// Scrollkeeper as Pluck sees it: Pluck asks for the list of titles, Scrollkeeper hands it over as a file
/// (which a sandboxed app may then read), and Pluck asks it to open a title, whose PDFs Scrollkeeper opens
/// in Pluck.
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
    @ObservationIgnored private let launcher: ApplicationLauncher

    public init(launcher: ApplicationLauncher) {
        self.launcher = launcher
    }

    /// Asks Scrollkeeper, staying in the background, to hand over the list of titles.
    public func requestIndex() {
        guard launcher.isInstalled(Self.bundleIdentifier) else {
            state = .notInstalled
            return
        }
        state = .waiting
        launcher.openInBackground(Self.requestURL(host: "index", sku: nil))
    }

    /// Reads the list Scrollkeeper handed over.
    public func receive(_ file: URL) {
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

    /// Asks Scrollkeeper, staying in the background, to download the title when needed and open its PDFs in
    /// Pluck. Scrollkeeper reports how it goes with status links (`receiveStatus`).
    public func open(_ entry: ScrollkeeperIndex.Entry) {
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
