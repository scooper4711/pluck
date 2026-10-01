import AppKit
import PluckKit
import UniformTypeIdentifiers

/// The user-facing commands, shared by the menus, toolbar and context menu.
@MainActor
struct AppActions {
    let model: PluckModel
    let router: DocumentRouter

    func chooseDocuments() {
        router.open(DocumentPanel.choosePDFs())
    }

    /// Shows each PDF in a window of its own.
    func open(_ urls: [URL]) {
        router.open(urls)
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

    /// Export in whichever mode is showing: the selected images, or the text.
    func exportSelection() {
        guard model.mode == .images else { return exportText() }
        guard !model.selectedImages.isEmpty, let directory = chooseExportDirectory() else { return }
        perform { try await model.exportSelection(to: directory) }
    }

    func exportVisible() {
        guard model.mode == .images else { return exportText() }
        guard !model.visibleImages.isEmpty, let directory = chooseExportDirectory() else { return }
        perform { try await model.exportVisible(to: directory) }
    }

    func copyText() {
        model.copyText()
    }

    func exportText() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.textFileName
        panel.allowedContentTypes = [UTType(filenameExtension: model.textFormat.fileExtension) ?? .plainText]
        guard !model.visibleText.isEmpty, panel.runModal() == .OK, let url = panel.url else { return }
        perform { try model.exportText(to: url) }
    }

    func show(_ mode: PluckModel.Mode) {
        model.mode = mode
    }

    private func chooseExportDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose a folder for the WebP files"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}

@MainActor
enum DocumentPanel {
    /// Asks the user for PDFs to open; empty if they cancel.
    static func choosePDFs() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        return panel.runModal() == .OK ? panel.urls : []
    }
}
