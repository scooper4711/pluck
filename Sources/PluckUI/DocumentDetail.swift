import AppNotices
import PluckKit
import SwiftUI

/// What a window shows beside the page navigator: the way in when no PDF is open, and otherwise the PDF's
/// images or its text, over the status bar.
struct DocumentDetail: View {
    @Bindable var model: PluckModel
    let actions: AppActions
    let thumbnailSize: Double
    /// Whether a file is being dragged over the window, which outlines the empty window.
    let isDropTargeted: Bool
    let openFromScrollkeeper: () -> Void

    /// Read here so that changing the setting redraws the text.
    @AppStorage(TextRenderOptions.obsidianCalloutsDefaultsKey) private var usesObsidianCallouts = false

    var body: some View {
        switch model.phase {
        case .empty, .passwordRequired:
            EmptyWindowView(
                title: "Open a PDF", symbol: "photo.on.rectangle.angled",
                message: "Drop a PDF here to pull out its images.", isDropTargeted: isDropTargeted,
                open: actions.chooseDocuments, openFromScrollkeeper: openFromScrollkeeper)
        case .failed(let message):
            ContentUnavailableView("Couldn’t Open the PDF", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        case .scanning, .ready:
            switch model.mode {
            case .images: imageGrid
            case .text: textOutput
            }
        }
    }

    private var imageGrid: some View {
        ImageGrid(model: model, actions: actions, thumbnailSize: thumbnailSize)
            .overlay {
                if model.phase == .ready, model.visibleImages.isEmpty {
                    ContentUnavailableView("No Images", systemImage: "photo",
                                           description: Text("Nothing to show for the selected pages."))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar(model: model) }
    }

    private var textOutput: some View {
        textView
            .id(usesObsidianCallouts)
            .safeAreaInset(edge: .top, spacing: 0) { StatBlockStrip(model: model) }
            .overlay {
                if !model.isLoadingText, model.visibleText.isEmpty {
                    ContentUnavailableView("No Text", systemImage: "text.alignleft",
                                           description: Text("Nothing to show for the selected pages."))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar(model: model) }
    }

    /// HTML is shown rendered; the other formats are shown as the text they are.
    @ViewBuilder private var textView: some View {
        if model.textFormat == .html {
            HTMLPreviewView(markup: model.visibleText)
        } else {
            TextOutputView(text: model.visibleText)
        }
    }
}

private struct StatusBar: View {
    let model: PluckModel

    var body: some View {
        HStack(spacing: 12) {
            Text(model.mode == .images ? imageSummary : textSummary)
            if let progress {
                ProgressView(value: Double(progress.done), total: Double(max(model.pageCount, 1)))
                    .frame(width: 120)
                Text("\(progress.label) page \(progress.done) of \(model.pageCount)")
            }
            Spacer()
            Text(model.statusMessage)
        }
        .lineLimit(1)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// The work still running for the mode on show, if any.
    private var progress: (label: String, done: Int)? {
        switch model.mode {
        case .images: model.phase == .scanning ? ("Scanning", model.scannedPageCount) : nil
        case .text: model.isLoadingText ? ("Reading", model.pageTexts.count) : nil
        }
    }

    private var imageSummary: String {
        var parts = ["\(model.visibleImages.count) images"]
        if !model.selectedImages.isEmpty { parts.append("\(model.selectedImages.count) selected") }
        if model.library.failureCount > 0 { parts.append("\(model.library.failureCount) unreadable") }
        return parts.joined(separator: " · ")
    }

    private var textSummary: String {
        let pages = model.visibleTextPageCount
        let words = model.visibleText.split { $0.isWhitespace }.count
        return "\(pages) \(pages == 1 ? "page" : "pages") · \(words) words · \(model.textFormat.displayName)"
    }
}

/// Asks for the password of a protected PDF, and opens the PDFs dropped on the window.
struct DocumentOpening: ViewModifier {
    let model: PluckModel
    let actions: AppActions
    @Binding var isDropTargeted: Bool
    @State private var password = ""

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in openDropped(urls) } isTargeted: { isDropTargeted = $0 }
            .alert("Password Required", isPresented: isAskingForPassword) {
                SecureField("Password", text: $password)
                Button("Open", action: submitPassword)
                Button("Cancel", role: .cancel) { password = "" }
            } message: {
                Text("“\(model.documentURL?.lastPathComponent ?? "This PDF")” is password-protected.")
            }
    }

    private var isAskingForPassword: Binding<Bool> {
        Binding {
            if case .passwordRequired = model.phase { true } else { false }
        } set: { _ in
            // The sheet closes by answering it, which moves the model on from asking.
        }
    }

    private func submitPassword() {
        actions.unlock(password: password)
        password = ""
    }

    private func openDropped(_ urls: [URL]) -> Bool {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        actions.open(pdfs)
        return !pdfs.isEmpty
    }
}

extension ExtractedImage {
    /// The line under an image in the grid: its pixel size and the page, or number of pages, it is on.
    var caption: String {
        let pages = pageIndexes.count == 1 ? "p. \((pageIndexes.first ?? 0) + 1)" : "\(pageIndexes.count) pages"
        return "\(pixelWidth) × \(pixelHeight) · \(pages)"
    }
}
