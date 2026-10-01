import Foundation
@testable import PluckKit
import Testing

@MainActor
@Suite("Opening several documents")
struct DocumentRouterTests {
    private let router = DocumentRouter()
    private let first = URL(fileURLWithPath: "/tmp/first.pdf")
    private let second = URL(fileURLWithPath: "/tmp/second.pdf")

    @Test("Pending documents are handed out once, in the order they were opened")
    func claimOnce() {
        router.open([first])
        router.open([second])

        #expect(router.claimPending() == [first, second])
        #expect(router.pendingURLs.isEmpty)
        #expect(router.claimPending().isEmpty)
    }

    @Test("The router knows whether any document window is open")
    func documentWindows() {
        let windows = [UUID(), UUID()]
        #expect(!router.hasDocumentWindows)

        windows.forEach(router.documentWindowDidAppear)
        router.documentWindowDidClose(windows[0])
        #expect(router.hasDocumentWindows)

        router.documentWindowDidClose(windows[1])
        #expect(!router.hasDocumentWindows)
    }

    @Test("Documents open independently of each other")
    func independentModels() async throws {
        let models = [PluckModel(), PluckModel()]
        for (model, color) in zip(models, [Color.red, Color.blue]) {
            let builder = PDFBuilder()
            builder.addPage(painting: [builder.addSolidImage(color)])
            await model.open(try builder.write())
        }
        models[0].selectedImageIDs = Set(models[0].visibleImages.map(\.id))
        models[0].apply(.rotateRight)

        #expect(models[0].visibleImages.map(\.id) != models[1].visibleImages.map(\.id))
        #expect(models[1].transforms.isEmpty && models[1].selectedImages.isEmpty)
    }

    @Test("Open Recent lists documents newest first and can be cleared")
    func recentDocuments() {
        let store = FakeRecentStore(urls: [first])
        let recents = RecentDocuments(store: store)
        #expect(recents.urls == [first])

        recents.note(second)
        recents.note(first)
        #expect(recents.urls == [first, second])

        recents.clear()
        #expect(recents.urls.isEmpty && store.urls.isEmpty)
    }
}

@MainActor
private final class FakeRecentStore: RecentDocumentStore {
    private(set) var urls: [URL]

    init(urls: [URL]) {
        self.urls = urls
    }

    func note(_ url: URL) {
        urls.removeAll { $0 == url }
        urls.insert(url, at: 0)
    }

    func clear() {
        urls = []
    }
}
