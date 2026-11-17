#if os(iOS)
import PluckKit
import SwiftUI
import UniformTypeIdentifiers

/// What the system file browser was opened for.
enum FileRequest {
    case openPDF
    case exportSelection
    case exportVisible

    /// A PDF to open, or a folder to export into.
    var contentTypes: [UTType] {
        switch self {
        case .openPDF: [.pdf]
        case .exportSelection, .exportVisible: [.folder]
        }
    }
}

/// What an iPad window is presenting: its sheets, the file browser, Quick Look and the last error. The Mac asks
/// with modal panels where it stands; on the iPad the window presents, so the commands only say what to show.
@MainActor
@Observable
final class PadPresenter {
    var isChoosingFile = false
    private(set) var fileRequest = FileRequest.openPDF
    var isShowingScrollkeeper = false
    var isShowingSettings = false
    var isShowingAbout = false
    var errorMessage: String?
    /// The selected images Quick Look shows, as temporary PNGs.
    var previewFile: URL?
    var previewFiles: [URL] = []
    /// The text written to a temporary file, waiting to be moved where the user chooses.
    private(set) var textFile: URL?
    var isSavingTextFile = false
    var columnVisibility = NavigationSplitViewVisibility.automatic
    /// The column a collapsed split view shows, on the iPhone: the images or text first, Back to the pages.
    var compactColumn = NavigationSplitViewColumn.detail
    /// The open PDF, while it is one the app may read only between starting and stopping access to it.
    @ObservationIgnored private var accessedDocument: URL?

    func choose(_ request: FileRequest) {
        fileRequest = request
        isChoosingFile = true
    }

    func save(textFile file: URL) {
        textFile = file
        isSavingTextFile = true
    }

    /// Keeps a PDF from Files or another app readable while it is shown: its pages are read as they are needed,
    /// not all at once. Access to the PDF shown before ends.
    func access(_ url: URL) {
        endAccess()
        accessedDocument = url.startAccessingSecurityScopedResource() ? url : nil
    }

    /// Ends access to the PDF shown, once it is closed.
    func endAccess() {
        accessedDocument?.stopAccessingSecurityScopedResource()
        accessedDocument = nil
    }
}

/// The user-facing commands on the iPad, shared by the toolbar, the menus and the menu bar. It has the Mac's
/// `AppActions` surface, so the shared views call either.
@MainActor
struct AppActions {
    let model: PluckModel
    let presenter: PadPresenter
    /// The Open Recent list, which every window shares.
    let recents: RecentDocuments

    func chooseDocuments() {
        presenter.choose(.openPDF)
    }

    func openFromScrollkeeper() {
        presenter.isShowingScrollkeeper = true
    }

    /// A window shows one PDF, so of several only the last opens.
    func open(_ urls: [URL]) {
        guard let url = urls.last else { return }
        presenter.isShowingScrollkeeper = false
        presenter.access(url)
        Task { await model.open(url) }
    }

    /// Closes the PDF, leaving the window empty.
    func close() {
        model.close()
        presenter.endAccess()
    }

    /// Retries this window's password-protected PDF.
    func unlock(password: String) {
        guard let url = model.documentURL else { return }
        Task { await model.open(url, password: password) }
    }

    func apply(_ edit: ImageEdit) {
        model.apply(edit)
    }

    func copySelection() {
        guard !model.selectedImages.isEmpty else { return }
        perform { try await model.copySelection() }
    }

    func quickLook() {
        guard !model.selectedImages.isEmpty else { return }
        perform {
            let files = try await model.previewSelection()
            presenter.previewFiles = files
            presenter.previewFile = files.first
        }
    }

    /// Export in whichever mode is showing: the selected images, or the text.
    func exportSelection() {
        guard model.mode == .images else { return exportText() }
        if !model.selectedImages.isEmpty { presenter.choose(.exportSelection) }
    }

    func exportVisible() {
        guard model.mode == .images else { return exportText() }
        if !model.visibleImages.isEmpty { presenter.choose(.exportVisible) }
    }

    /// Shows the page in the sidebar, which is hidden in portrait, and on the iPhone a screen of its own.
    func revealPageOfSelectedImage() {
        presenter.columnVisibility = .all
        presenter.compactColumn = .sidebar
        model.revealPageOfSelectedImage()
    }

    func copyText() {
        model.copyText()
    }

    func copyStatBlocks() {
        model.copyStatBlocks(model.visibleStatBlocks)
    }

    /// Writes the text to a temporary file, which the file browser then moves where the user chooses.
    func exportText() {
        guard !model.visibleText.isEmpty else { return }
        perform {
            let folder = FileManager.default.temporaryDirectory.appending(path: "Export/\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: model.textFileName)
            try model.exportText(to: file)
            // Nothing is exported until the user has chosen where.
            model.statusMessage = ""
            presenter.save(textFile: file)
        }
    }

    func show(_ mode: PluckModel.Mode) {
        model.mode = mode
    }

    /// Takes the file browser's answer: the PDF to open, or the folder to export into.
    func finishChoosing(_ result: Result<URL, any Error>) {
        switch (presenter.fileRequest, result) {
        case let (_, .failure(error)): presenter.errorMessage = error.localizedDescription
        case let (.openPDF, .success(url)): open([url])
        case let (.exportSelection, .success(folder)): export(into: folder) { try await model.exportSelection(to: $0) }
        case let (.exportVisible, .success(folder)): export(into: folder) { try await model.exportVisible(to: $0) }
        }
    }

    func finishSavingText(_ result: Result<URL, any Error>) {
        switch result {
        case let .success(url): model.statusMessage = "Exported text to “\(url.lastPathComponent)”"
        case let .failure(error): presenter.errorMessage = error.localizedDescription
        }
    }

    /// The folder is one the user picked, which the app may write into only between starting and stopping access.
    private func export(into folder: URL, _ write: @escaping @MainActor (URL) async throws -> [URL]) {
        perform {
            let isScoped = folder.startAccessingSecurityScopedResource()
            defer { if isScoped { folder.stopAccessingSecurityScopedResource() } }
            _ = try await write(folder)
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                presenter.errorMessage = error.localizedDescription
            }
        }
    }
}
#endif
