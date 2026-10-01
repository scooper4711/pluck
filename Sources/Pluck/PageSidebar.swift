import PluckKit
import SwiftUI

/// The navigator: every page of the PDF, multi-selectable to filter the image grid.
struct PageSidebar: View {
    @Bindable var model: PluckModel

    /// The pixel size thumbnails are drawn at, stepped so that dragging the divider does not
    /// redraw every page at every width.
    @State private var thumbnailPixels = 400
    /// The page just scrolled to on request, marked for a moment so it can be picked out.
    @State private var highlightedPage: Int?

    var body: some View {
        ScrollViewReader { scroller in
            pageList
                .onChange(of: model.pageReveal) { _, reveal in
                    guard let reveal else { return }
                    highlight(reveal.pageIndex)
                    Task { await scroll(scroller, toTopOf: reveal.pageIndex) }
                }
        }
    }

    /// Puts a page's row at the top of the list. Rows that have not been shown yet only have
    /// estimated heights, so the first jump can land short; a second, once the rows around the
    /// target exist, lands exactly.
    private func scroll(_ scroller: ScrollViewProxy, toTopOf pageIndex: Int) async {
        scroller.scrollTo(pageIndex, anchor: .top)
        try? await Task.sleep(for: .milliseconds(150))
        scroller.scrollTo(pageIndex, anchor: .top)
    }

    private func highlight(_ pageIndex: Int) {
        highlightedPage = pageIndex
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if highlightedPage == pageIndex { withAnimation { highlightedPage = nil } }
        }
    }

    private var pageList: some View {
        List(selection: $model.selectedPages) {
            ForEach(0..<model.pageCount, id: \.self) { pageIndex in
                PageRow(model: model, pageIndex: pageIndex, thumbnailPixels: thumbnailPixels)
                    .overlay {
                        if highlightedPage == pageIndex {
                            RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2)
                        }
                    }
            }
        }
        .onGeometryChange(for: Int.self) { proxy in
            Self.thumbnailPixels(forWidth: proxy.size.width)
        } action: { pixels in
            thumbnailPixels = pixels
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

extension PageSidebar {
    private static let pixelStep = 400.0

    /// Enough pixels for a portrait page filling the sidebar on a Retina display.
    static func thumbnailPixels(forWidth width: CGFloat) -> Int {
        let needed = width * 2 * 1.45
        return Int(min(2400, max(pixelStep, (needed / pixelStep).rounded(.up) * pixelStep)))
    }
}

private struct PageRow: View {
    let model: PluckModel
    let pageIndex: Int
    let thumbnailPixels: Int

    @State private var thumbnail: CGImage?

    private struct ThumbnailRequest: Equatable {
        let document: URL?
        let pixels: Int
    }

    var body: some View {
        VStack(spacing: 4) {
            // No fixed height: the preview is as wide as the sidebar allows and as tall as that makes it.
            preview
                .frame(maxWidth: .infinity)
            Text("Page \(pageIndex + 1)")
                .font(.callout)
            Text(imageCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .task(id: ThumbnailRequest(document: model.documentURL, pixels: thumbnailPixels)) {
            thumbnail = await model.pageThumbnail(at: pageIndex, maximumDimension: thumbnailPixels) ?? thumbnail
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
