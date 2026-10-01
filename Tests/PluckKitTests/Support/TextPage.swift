import CoreGraphics
import Foundation
@testable import PluckKit

/// Builds a US Letter page of text for layout tests. Positions are given the way a reader sees
/// them: `top` is the distance of a line's baseline from the top of the page.
struct TextPage {
    enum Font: String, CaseIterable {
        case regular = "Courier"
        case bold = "Courier-Bold"
        case italic = "Courier-Oblique"
        /// A second typeface, for text that is set apart from the body.
        case display = "Helvetica-Bold"
        case sans = "Helvetica"

        var resourceName: String { "F\(Self.allCases.firstIndex(of: self)! + 1)" }
    }

    static let size = CGSize(width: 612, height: 792)
    static let leftColumn: CGFloat = 72
    static let rightColumn: CGFloat = 330
    static let leading: CGFloat = 12

    private var content = ""

    /// Draws text starting at `x`. Several `(text, font)` pieces continue on the same baseline.
    mutating func line(_ pieces: [(String, Font)], x: CGFloat, top: CGFloat, size: CGFloat = 10) {
        content += "BT 1 0 0 1 \(x) \(Self.size.height - top) Tm\n"
        for (text, font) in pieces {
            let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
            content += "/\(font.resourceName) \(size) Tf (\(escaped)) Tj\n"
        }
        content += "ET\n"
    }

    mutating func line(_ text: String, x: CGFloat, top: CGFloat, font: Font = .regular, size: CGFloat = 10) {
        line([(text, font)], x: x, top: top, size: size)
    }

    /// Draws consecutive lines and returns the `top` for whatever follows them.
    @discardableResult
    mutating func lines(_ texts: [String], x: CGFloat, top: CGFloat, font: Font = .regular) -> CGFloat {
        for (index, text) in texts.enumerated() {
            line(text, x: x, top: top + CGFloat(index) * Self.leading, font: font)
        }
        return top + CGFloat(texts.count) * Self.leading
    }

    /// Fills a grey panel whose top edge is `top` points down the page.
    mutating func panel(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) {
        content += "0.8 g \(x) \(Self.size.height - top - height) \(width) \(height) re f 0 g\n"
    }

    mutating func rule(x: CGFloat, top: CGFloat, width: CGFloat) {
        content += "\(x) \(Self.size.height - top) m \(x + width) \(Self.size.height - top) l S\n"
    }

    func add(to builder: PDFBuilder) {
        let fonts = Font.allCases
            .map { "/\($0.resourceName) << /Type /Font /Subtype /Type1 /BaseFont /\($0.rawValue) >>" }
            .joined(separator: " ")
        builder.addPage(
            resources: "/Font << \(fonts) >>", content: Data(content.utf8),
            mediaBox: "0 0 \(Int(Self.size.width)) \(Int(Self.size.height))")
    }

    /// Builds a PDF from the pages and extracts each page's blocks.
    static func blocks(of pages: [TextPage]) throws -> [[TextBlock]] {
        let builder = PDFBuilder()
        pages.forEach { $0.add(to: builder) }
        let source = try PDFTextSource(url: builder.write())
        return (0..<source.pageCount).map(source.blocks)
    }

    static func blocks(_ build: (inout TextPage) -> Void) throws -> [TextBlock] {
        var page = TextPage()
        build(&page)
        return try blocks(of: [page])[0]
    }
}

extension TextBlock {
    /// A compact description for assertions: `h2:Title`, `p:Text`, `li:Text`, `sidebar[…]`.
    var summary: String {
        switch self {
        case .heading(let level, let runs): "h\(level):\(runs.map(\.text).joined())"
        case .paragraph(let runs): "p:\(runs.map(\.text).joined())"
        case .listItem(let runs): "li:\(runs.map(\.text).joined())"
        case .box(let box): "\(box.kind)[\(box.blocks.map(\.summary).joined(separator: " | "))]"
        }
    }
}
