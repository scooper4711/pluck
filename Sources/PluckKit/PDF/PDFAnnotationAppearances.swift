import CoreGraphics
import Foundation

/// The appearance streams that draw a page's annotations. Filled-in form fields keep their
/// text and pictures here, outside the page's own content stream.
enum PDFAnnotationAppearances {
    /// Annotation flags (ISO 32000 table 165): Hidden (bit 2) and NoView (bit 6).
    private static let hiddenFlags = 1 << 1 | 1 << 5

    /// The normal appearance of each annotation that is shown on screen, in page order.
    static func visibleStreams(of page: CGPDFPage) -> [PDFStream] {
        guard let annotations = page.dictionary.map(PDFDictionary.init)?.object("Annots")?.array else { return [] }
        return (0..<annotations.count).compactMap { annotations[$0]?.dictionary.flatMap(normalAppearance) }
    }

    /// A button keeps one appearance per state; `AS` names the one being shown.
    private static func normalAppearance(of annotation: PDFDictionary) -> PDFStream? {
        let flags = annotation.object("F")?.integer ?? 0
        guard flags & hiddenFlags == 0, let normal = annotation.object("AP")?.dictionary?.object("N") else {
            return nil
        }
        if let stream = normal.stream { return stream }
        guard let state = annotation.object("AS")?.name else { return nil }
        return normal.dictionary?.object(state)?.stream
    }
}
