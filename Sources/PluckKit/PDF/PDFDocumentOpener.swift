import CoreGraphics
import Foundation

enum PDFDocumentOpener {
    /// Opens and unlocks a PDF. Each caller gets its own `CGPDFDocument`, which is not thread-safe.
    static func open(_ url: URL, password: String = "") throws -> CGPDFDocument {
        guard let document = CGPDFDocument(url as CFURL) else {
            throw PluckError.cannotOpenDocument(url)
        }
        // Many PDFs are encrypted with an empty user password purely to carry permissions.
        let isUnlocked = document.isUnlocked
            || document.unlockWithPassword("")
            || document.unlockWithPassword(password)
        guard isUnlocked else { throw PluckError.passwordRequired }
        return document
    }
}

/// Renders small previews of whole pages for the navigator.
public final class PDFPageThumbnailer: @unchecked Sendable {
    private let document: CGPDFDocument
    private let lock = NSLock()

    public init(url: URL, password: String = "") throws {
        document = try PDFDocumentOpener.open(url, password: password)
    }

    public func thumbnail(ofPageAt index: Int, maximumDimension: Int) throws -> CGImage {
        try lock.withLock {
            guard let page = document.page(at: index + 1) else {
                throw PluckError.renderingFailed(operation: "finding page \(index + 1)")
            }
            let size = Self.fittedSize(of: page, maximumDimension: CGFloat(maximumDimension))
            guard let context = CGContext.rgba(width: Int(size.width), height: Int(size.height), data: nil) else {
                throw PluckError.renderingFailed(operation: "creating a canvas for page \(index + 1)")
            }
            let canvas = CGRect(origin: .zero, size: size)
            context.setFillColor(.white)
            context.fill(canvas)
            // The drawing transform only ever shrinks a page, so enlarging is done separately.
            let pageSize = Self.displaySize(of: page)
            context.scaleBy(x: size.width / pageSize.width, y: size.height / pageSize.height)
            context.concatenate(page.getDrawingTransform(
                .cropBox, rect: CGRect(origin: .zero, size: pageSize), rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            guard let image = context.makeImage() else {
                throw PluckError.renderingFailed(operation: "drawing page \(index + 1)")
            }
            return image
        }
    }

    /// The page scaled, up or down, so that its longer side is `maximumDimension` pixels.
    private static func fittedSize(of page: CGPDFPage, maximumDimension: CGFloat) -> CGSize {
        let box = displaySize(of: page)
        let scale = maximumDimension / max(box.width, box.height, 1)
        return CGSize(width: max(1, (box.width * scale).rounded()), height: max(1, (box.height * scale).rounded()))
    }

    /// The crop box as displayed, with the page's rotation applied.
    private static func displaySize(of page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.cropBox).size
        return page.rotationAngle % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
    }
}
