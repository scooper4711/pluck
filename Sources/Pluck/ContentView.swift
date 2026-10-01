import PluckKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: PluckModel
    let actions: AppActions

    @AppStorage("thumbnailSize") private var thumbnailSize = 180.0
    @State private var password = ""

    var body: some View {
        NavigationSplitView {
            PageSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 150, ideal: 190, max: 320)
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
                Button("Open…", action: actions.chooseDocument)
            }
        case .failed(let message):
            ContentUnavailableView("Couldn’t Open the PDF", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        case .scanning, .ready:
            imageGrid
        }
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

    private var isAskingForPassword: Binding<Bool> {
        Binding {
            if case .passwordRequired = model.phase { true } else { false }
        } set: { _ in }
    }

    private func submitPassword() {
        guard let url = model.documentURL else { return }
        actions.open(url, password: password)
        password = ""
    }

    private func openDropped(_ urls: [URL]) -> Bool {
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return false }
        actions.open(url)
        return true
    }
}

private struct StatusBar: View {
    let model: PluckModel

    var body: some View {
        HStack(spacing: 12) {
            Text(summary)
            if model.phase == .scanning {
                ProgressView(value: Double(model.scannedPageCount), total: Double(max(model.pageCount, 1)))
                    .frame(width: 120)
                Text("Scanning page \(model.scannedPageCount) of \(model.pageCount)")
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

    private var summary: String {
        var parts = ["\(model.visibleImages.count) images"]
        if !model.selectedImages.isEmpty { parts.append("\(model.selectedImages.count) selected") }
        if model.library.failureCount > 0 { parts.append("\(model.library.failureCount) unreadable") }
        return parts.joined(separator: " · ")
    }
}
