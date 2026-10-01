import CoreGraphics
import Foundation

/// One string drawn in one font: where its baseline starts and ends on the page.
struct FontSpan {
    let fontName: String
    let isBold: Bool
    let isItalic: Bool
    /// The font size as it appears on the page, after every scaling.
    let size: CGFloat
    let start: CGPoint
    let end: CGPoint

    /// Sideways and slanted text is left to PDFKit's own guess at the font.
    var isHorizontal: Bool { abs(start.y - end.y) < 1 && end.x >= start.x }
}

/// What a page draws around its text, in PDF page coordinates (origin bottom-left).
struct PageGraphics {
    /// Each run of text and the font it is set in.
    var fontSpans: [FontSpan] = []
    /// Filled shapes and outlined frames big enough to sit behind a block of text.
    var panels: [CGRect] = []
    /// Where images are placed.
    var images: [CGRect] = []
    /// Thin horizontal lines, which can fence off a passage of text.
    var rules: [CGRect] = []
}

/// The part of PDF's graphics state that decides where text and shapes land.
struct PDFGraphicsState {
    var transform = CGAffineTransform.identity
    var lineWidth: CGFloat = 1
    /// White fills are ignored: on a white page they do not frame anything.
    var fillsWhite = false

    var font: PDFFontMetrics?
    var fontSize: CGFloat = 0
    var characterSpacing: CGFloat = 0
    var wordSpacing: CGFloat = 0
    var horizontalScale: CGFloat = 1
    var leading: CGFloat = 0
}

/// The bounding box of the path under construction, in page coordinates.
struct PDFPathBounds {
    private(set) var box = CGRect.null

    mutating func add(_ point: CGPoint, transform: CGAffineTransform) {
        let placed = point.applying(transform)
        box = box.union(CGRect(origin: placed, size: .zero))
    }

    mutating func add(_ rect: CGRect, transform: CGAffineTransform) {
        for corner in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
            add(corner, transform: transform)
        }
    }

    mutating func reset() {
        box = .null
    }
}
