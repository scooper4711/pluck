import PluckKit
import SwiftUI

/// The navigator: every page of the PDF, multi-selectable to filter the image grid.
struct PageSidebar: View {
    @Bindable var model: PluckModel

    var body: some View {
        List(selection: $model.selectedPages) {
            ForEach(0..<model.pageCount, id: \.self) { pageIndex in
                PageRow(model: model, pageIndex: pageIndex)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.selectedPages.isEmpty {
                Button("Show All Pages") { model.selectedPages = [] }
                    .buttonStyle(.link)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(.bar)
            }
        }
    }
}

private struct PageRow: View {
    let model: PluckModel
    let pageIndex: Int

    @State private var thumbnail: CGImage?

    var body: some View {
        VStack(spacing: 4) {
            preview
                .frame(height: 150)
                .frame(maxWidth: .infinity)
            Text("Page \(pageIndex + 1)")
                .font(.callout)
            Text(imageCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .task(id: model.documentURL) {
            thumbnail = await model.pageThumbnail(at: pageIndex)
        }
    }

    @ViewBuilder private var preview: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 2)
                .resizable()
                .scaledToFit()
                .shadow(radius: 1.5, y: 0.5)
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(.quaternary)
                .aspectRatio(0.77, contentMode: .fit)
        }
    }

    private var imageCountLabel: String {
        guard pageIndex < model.scannedPageCount else { return "…" }
        let count = model.library.imageCount(onPage: pageIndex)
        return count == 1 ? "1 image" : "\(count) images"
    }
}
