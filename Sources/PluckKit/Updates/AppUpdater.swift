import Foundation
import Observation

/// Why an update check or download did not finish.
public enum UpdateError: Error, Equatable, LocalizedError {
    case http(status: Int)
    case unreadableAnswer
    case noDiskImage(version: String)

    public var errorDescription: String? {
        switch self {
        case let .http(status):
            "Checking for updates failed: GitHub answered with status \(status)."
        case .unreadableAnswer:
            "Checking for updates failed: GitHub's answer was not in the expected form."
        case let .noDiskImage(version):
            "Version \(version) is available, but it has no disk image attached. See the releases page on GitHub."
        }
    }
}

/// Where an update check stands.
public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(version: String)
    /// A newer version exists; nothing has been downloaded.
    case available(version: String)
    case downloading(version: String)
    case downloaded(version: String, file: URL)
    case failed(message: String)

    /// True while the check or the download is under way.
    public var isBusy: Bool {
        switch self {
        case .checking, .downloading: true
        default: false
        }
    }

    /// True when there is something to tell or ask the user.
    public var isResult: Bool {
        switch self {
        case .upToDate, .available, .downloaded, .failed: true
        default: false
        }
    }
}

/// The app whose releases are checked: its name for messages, and its GitHub repository.
public struct UpdateProduct: Sendable {
    public let name: String
    /// `owner/name` on GitHub.
    public let repository: String

    public init(name: String, repository: String) {
        self.name = name
        self.repository = repository
    }

    var latestReleaseURL: URL? { URL(string: "https://api.github.com/repos/\(repository)/releases/latest") }
}

/// Checks GitHub for a newer release and, when the user agrees, downloads its disk image.
@MainActor
@Observable
public final class AppUpdater {
    /// The user default that turns the check when the app opens on or off; on unless set.
    public static let checksAtLaunchKey = "checksForUpdatesAtLaunch"

    public private(set) var state = UpdateState.idle
    public let product: UpdateProduct

    private let session: URLSession
    private let currentVersion: AppVersion
    private let downloadsDirectory: URL
    /// The disk image of the release that was found, kept until the user decides.
    private var offered: GitHubAsset?

    public init(product: UpdateProduct, currentVersion: String, downloadsDirectory: URL,
                session: URLSession = .shared) {
        self.product = product
        self.currentVersion = AppVersion(currentVersion)
        self.downloadsDirectory = downloadsDirectory
        self.session = session
    }

    /// The updater for the running app: its bundle version and the user's Downloads folder.
    public static func live(product: UpdateProduct) -> AppUpdater {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return AppUpdater(product: product, currentVersion: version ?? "0", downloadsDirectory: downloads)
    }

    /// Whether to check when the app opens: when the user has not turned it off, and only for a released
    /// version, since a build without one (0.0.0) would always find an update.
    public func checksAtLaunch(in defaults: UserDefaults) -> Bool {
        let isOn = defaults.object(forKey: Self.checksAtLaunchKey) as? Bool ?? true
        return isOn && currentVersion > AppVersion("0")
    }

    /// Asks GitHub for the latest release and reports whether it is newer. Nothing is downloaded.
    public func checkForUpdate() async {
        guard !state.isBusy else { return }
        state = .checking
        offered = nil
        do {
            guard let release = try await fetchLatestRelease(), release.version > currentVersion else {
                state = .upToDate(version: currentVersion.description)
                return
            }
            guard let diskImage = release.diskImage else {
                throw UpdateError.noDiskImage(version: release.version.description)
            }
            offered = diskImage
            state = .available(version: release.version.description)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    /// The check made when the app opens: it speaks up only when a newer version exists. Being up to date, or
    /// being unable to reach GitHub, is not worth interrupting for.
    public func checkForUpdateQuietly() async {
        await checkForUpdate()
        if case .available = state { return }
        dismiss()
    }

    /// Downloads the disk image of the version that was offered into the Downloads folder.
    public func downloadUpdate() async {
        guard case let .available(version) = state, let asset = offered, let source = URL(string: asset.address)
        else { return }
        state = .downloading(version: version)
        let destination = downloadsDirectory.appending(path: asset.name)
        do {
            let (file, response) = try await session.download(from: source)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard (200..<300).contains(status) else { throw UpdateError.http(status: status) }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: file, to: destination)
            state = .downloaded(version: version, file: destination)
        } catch {
            state = .failed(message: "Downloading the update failed: \(error.localizedDescription)")
        }
    }

    /// Clears a result once the user has seen it or declined the download.
    public func dismiss() {
        if state.isResult { state = .idle }
    }

    // MARK: Wording

    public var title: String {
        switch state {
        case .idle: ""
        case .checking: "Checking for updates…"
        case .upToDate: "\(product.name) is up to date"
        case let .available(version): "\(product.name) \(version) is available"
        case let .downloading(version): "Downloading \(product.name) \(version)…"
        case let .downloaded(version, _): "\(product.name) \(version) has been downloaded"
        case .failed: "The update check did not finish"
        }
    }

    public var message: String {
        switch state {
        case .idle, .checking, .downloading: ""
        case let .upToDate(version): "You have version \(version), which is the newest."
        case .available: "Would you like to download it? The disk image goes into your Downloads folder."
        case let .downloaded(_, file):
            "The disk image \(file.lastPathComponent) is in your Downloads folder. Open it, quit \(product.name), "
                + "and drag the new version to Applications."
        case let .failed(message): message
        }
    }

    // MARK: GitHub

    /// The latest release, or nil when none has been published yet (GitHub then answers 404).
    private func fetchLatestRelease() async throws -> GitHubRelease? {
        guard let url = product.latestReleaseURL else { throw UpdateError.unreadableAnswer }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw UpdateError.http(status: status) }
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            throw UpdateError.unreadableAnswer
        }
        return release
    }
}

/// The part of GitHub's description of a release that the updater reads.
private struct GitHubRelease: Decodable {
    let tag: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case assets
    }

    var version: AppVersion { AppVersion(tag) }

    var diskImage: GitHubAsset? { assets.first { $0.name.lowercased().hasSuffix(".dmg") } }
}

private struct GitHubAsset: Decodable {
    let name: String
    let address: String

    enum CodingKeys: String, CodingKey {
        case name
        case address = "browser_download_url"
    }
}
