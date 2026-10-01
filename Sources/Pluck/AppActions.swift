import AppKit
import PluckKit
import UniformTypeIdentifiers

/// The user-facing commands, shared by the menus, toolbar and context menu.
@MainActor
struct AppActions {
    let model: PluckModel

    func chooseDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL, password: String = "") {
        Task { await model.open(url, password: password) }
    }

    func apply(_ edit: ImageEdit) {
        model.apply(edit)
    }

    func copySelection() {
        guard !model.selectedImages.isEmpty else { return }
        perform { try await model.copySelection() }
    }

    func exportSelection() {
        guard !model.selectedImages.isEmpty, let directory = chooseExportDirectory() else { return }
        perform { try await model.exportSelection(to: directory) }
    }

    func exportVisible() {
        guard !model.visibleImages.isEmpty, let directory = chooseExportDirectory() else { return }
        perform { try await model.exportVisible(to: directory) }
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
