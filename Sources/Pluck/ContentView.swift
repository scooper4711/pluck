import PluckKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: PluckModel
    let actions: AppActions

    @AppStorage("thumbnailSize") private var thumbnailSize = 180.0
    /// Read here so that changing the setting redraws the text.
    @AppStorage(TextRenderOptions.obsidianCalloutsDefaultsKey) private var usesObsidianCallouts = false
    @State private var password = ""

    var body: some View {
        NavigationSplitView {
            PageSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 150, ideal: 190, max: 900)
        } detail: {
            detail
        }
        .navigationTitle(model.documentURL?.lastPathComponent ?? "Pluck")
        .toolbar { PluckToolbar(model: model, actions: actions, thumbnailSize: $thumbnailSize) }
        .dropDestination(for: URL.self) { urls, _ in openDropped(urls) }
        .alert("Password Required", isPresented: isAskingForPassword) {
            SecureField("Password", text: $password)
            Button("Open", action: submitPassword)
            Button("Cancel", role: .cancel) { password = "" }
        } message: {
            Text("“\(model.documentURL?.lastPathComponent ?? "This PDF")” is password-protected.")
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.phase {
        case .empty, .passwordRequired:
            ContentUnavailableView {
                Label("Open a PDF", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("Drop a PDF here to pull out its images.")
            } actions: {
                Button("Open…", action: actions.chooseDocuments)
            }
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

    private var imageGrid: some View {
        ImageGridView(
            images: model.visibleImages, transforms: model.transforms, selection: $model.selectedImageIDs,
            thumbnailSize: thumbnailSize, actions: actions)
            .overlay {
                if model.phase == .ready, model.visibleImages.isEmpty {
                    ContentUnavailableView("No Images", systemImage: "photo",
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

    private var isAskingForPassword: Binding<Bool> {
        Binding {
            if case .passwordRequired = model.phase { true } else { false }
        } set: { _ in }
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
