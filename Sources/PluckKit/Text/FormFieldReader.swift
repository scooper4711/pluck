import AppKit
import PDFKit

/// Reads what has been typed into a page's form fields. PDFKit leaves these values out of the
/// page's text because annotations draw them, not the page itself. Each value is laid out the
/// way a viewer would draw it in its field: wrapped to the field's width, one fragment a line.
struct FormFieldReader {
    /// The gap between a field's border and its text.
    private static let padding: CGFloat = 2
    /// A line of text takes about this many times the font size, as in PDFKit's character boxes.
    private static let lineHeightFactor: CGFloat = 1.2
    /// PDFKit's own choice for a field that names no font or asks for automatic sizing.
    private static let defaultFont = NSFont(name: "Helvetica", size: 12) ?? .systemFont(ofSize: 12)
    /// Annotation flags (ISO 32000 table 165): Hidden (bit 2) and NoView (bit 6).
    private static let hiddenFlags = 1 << 1 | 1 << 5

    let page: PDFPage
    /// Converts a rectangle from PDF page coordinates to reading coordinates.
    let readingRect: (CGRect) -> CGRect

    func fragments() -> [TextFragment] {
        page.annotations.filter(Self.isFilledField).flatMap(fragments)
    }

    private static func isFilledField(_ annotation: PDFAnnotation) -> Bool {
        let value = annotation.widgetStringValue ?? ""
        // PDFKit's `shouldDisplay` ignores the Hidden flag, so the flags are read directly.
        let flags = annotation.value(forAnnotationKey: .flags) as? Int ?? 0
        return flags & hiddenFlags == 0 && [.text, .choice].contains(annotation.widgetFieldType)
            && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func fragments(of field: PDFAnnotation) -> [TextFragment] {
        let font = field.font ?? Self.defaultFont
        let style = Self.style(of: font)
        let lines = lines(of: field, font: font)
        let lineHeight = font.pointSize * Self.lineHeightFactor
        let firstTop = field.isMultiline
            ? field.bounds.maxY - Self.padding
            : field.bounds.midY + lineHeight / 2
        return lines.enumerated().map { index, line in
            let width = Self.width(of: line, in: font)
            let frame = CGRect(
                x: Self.lineStart(width: width, in: field), y: firstTop - CGFloat(index + 1) * lineHeight,
                width: width, height: lineHeight)
            return TextFragment(
                frame: readingRect(frame), characters: line.map { StyledCharacter(text: String($0), style: style) })
        }
    }

    private func lines(of field: PDFAnnotation, font: NSFont) -> [String] {
        let value = field.widgetStringValue ?? ""
        guard field.isMultiline else { return [value.replacingOccurrences(of: "\n", with: " ")] }
        let available = field.bounds.width - Self.padding * 2
        return value.components(separatedBy: .newlines)
            .flatMap { Self.wrap($0, toWidth: available, in: font) }
            .filter { !$0.isEmpty }
    }

    /// Breaks a paragraph between words so that each line fits the width, as a viewer would.
    private static func wrap(_ paragraph: String, toWidth available: CGFloat, in font: NSFont) -> [String] {
        var lines: [String] = []
        var line = ""
        for word in paragraph.split(separator: " ", omittingEmptySubsequences: true) {
            let candidate = line.isEmpty ? String(word) : "\(line) \(word)"
            if !line.isEmpty, width(of: candidate, in: font) > available {
                lines.append(line)
                line = String(word)
            } else {
                line = candidate
            }
        }
        lines.append(line)
        return lines
    }

    private static func lineStart(width: CGFloat, in field: PDFAnnotation) -> CGFloat {
        switch field.alignment {
        case .center: field.bounds.midX - width / 2
        case .right: field.bounds.maxX - padding - width
        default: field.bounds.minX + padding
        }
    }

    private static func width(of text: String, in font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private static func style(of font: NSFont) -> CharacterStyle {
        let traits = font.fontDescriptor.symbolicTraits
        return CharacterStyle(
            fontName: font.fontName, size: font.pointSize,
            isBold: traits.contains(.bold), isItalic: traits.contains(.italic))
    }
}
