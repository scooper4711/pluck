import Foundation

/// The de-duplicated images of a document, in order of first appearance.
public struct ImageLibrary: Sendable {
    public private(set) var images: [ExtractedImage] = []
    public private(set) var failureCount = 0
    private var positionByID: [String: Int] = [:]

    public init() {}

    /// Records the images found on a page, merging any already seen elsewhere.
    public mutating func add(_ result: PageScanResult, pageIndex: Int) {
        failureCount += result.failureCount
        for image in result.images {
            let position = positionByID[image.id] ?? append(image)
            if images[position].pageIndexes.last != pageIndex {
                images[position].pageIndexes.append(pageIndex)
            }
        }
    }

    /// The images painted by any of the given pages; no pages means the whole document.
    public func images(onPages pageIndexes: Set<Int>) -> [ExtractedImage] {
        guard !pageIndexes.isEmpty else { return images }
        return images.filter { !pageIndexes.isDisjoint(with: $0.pageIndexes) }
    }

    public func imageCount(onPage pageIndex: Int) -> Int {
        images.count { $0.pageIndexes.contains(pageIndex) }
    }

    public func image(withID id: String) -> ExtractedImage? {
        positionByID[id].map { images[$0] }
    }

    private mutating func append(_ image: ExtractedImage) -> Int {
        images.append(image)
        positionByID[image.id] = images.count - 1
        return images.count - 1
    }
}
