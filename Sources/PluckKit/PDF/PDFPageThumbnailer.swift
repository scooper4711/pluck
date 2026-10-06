import CoreGraphics
import Foundation
import PDFKit

/// Renders small previews of whole pages for the navigator. PDFKit draws them, because Core
/// Graphics leaves out annotations and with them whatever has been typed into a form.
public final class PDFPageThumbnailer: @unchecked Sendable {
    private let document: PDFDocument
    private let lock = NSLock()

    public init(url: URL, password: String = "") throws {
        guard let document = PDFDocument(url: url) else { throw PluckError.cannotOpenDocument(url) }
        guard !document.isLocked || document.unlock(withPassword: "") || document.unlock(withPassword: password)
        else { throw PluckError.passwordRequired }
        self.document = document
    }

    public func thumbnail(ofPageAt index: Int, maximumDimension: Int) throws -> CGImage {
        try lock.withLock {
            guard let page = document.page(at: index) else {
                throw PluckError.renderingFailed(operation: "finding page \(index + 1)")
            }
            let pageSize = Self.displaySize(of: page)
            let size = Self.fittedSize(pageSize, maximumDimension: CGFloat(maximumDimension))
            guard let context = CGContext.rgba(width: Int(size.width), height: Int(size.height), data: nil) else {
                throw PluckError.renderingFailed(operation: "creating a canvas for page \(index + 1)")
            }
            context.setFillColor(.white)
            context.fill(CGRect(origin: .zero, size: size))
            context.scaleBy(x: size.width / pageSize.width, y: size.height / pageSize.height)
            // PDFKit moves the crop box to the origin and applies the page's rotation itself.
            page.draw(with: .cropBox, to: context)
            guard let image = context.makeImage() else {
                throw PluckError.renderingFailed(operation: "drawing page \(index + 1)")
            }
            return image
        }
    }

    /// The page scaled, up or down, so that its longer side is `maximumDimension` pixels.
    private static func fittedSize(_ box: CGSize, maximumDimension: CGFloat) -> CGSize {
        let scale = maximumDimension / max(box.width, box.height, 1)
        return CGSize(width: max(1, (box.width * scale).rounded()), height: max(1, (box.height * scale).rounded()))
    }

    /// The crop box as displayed, with the page's rotation applied.
    private static func displaySize(of page: PDFPage) -> CGSize {
        let box = page.bounds(for: .cropBox).size
        return page.rotation % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
    }
}
