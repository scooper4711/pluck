import CoreGraphics
import CoreText
import Foundation

/// The parts of a PDF font needed to follow text across a page: its real name, which says whether
/// it is bold or italic, and its glyph widths, which say how far each string advances.
final class PDFFontMetrics {
    private static let defaultWidth: CGFloat = 0.5
    private static let monospacedWidth: CGFloat = 0.6

    /// The font's name without the subset prefix (`ABCDEF+`).
    let name: String
    let isBold: Bool
    let isItalic: Bool
    /// Composite fonts address glyphs with two bytes; simple fonts with one.
    let bytesPerCode: Int

    /// Glyph widths as a fraction of the font size.
    private let widths: [Int: CGFloat]
    private let fallbackWidth: CGFloat

    init(font: PDFDictionary) {
        let subtype = font.object("Subtype")?.name
        let descendant = font.object("DescendantFonts")?.array?[0]?.dictionary
        let descriptor = (descendant ?? font).object("FontDescriptor")?.dictionary
        let baseName = font.object("BaseFont")?.name ?? font.object("Name")?.name ?? "Unknown"
        name = baseName.split(separator: "+").last.map(String.init) ?? baseName
        (isBold, isItalic) = Self.traits(name: name, descriptor: descriptor)
        bytesPerCode = subtype == "Type0" ? 2 : 1
        if let descendant {
            widths = Self.compositeWidths(descendant)
            fallbackWidth = (descendant.object("DW")?.number ?? 1000) / 1000
        } else {
            // Type 3 fonts measure glyphs in their own space rather than in thousandths.
            let scale = subtype == "Type3" ? font.object("FontMatrix")?.array?[0]?.number ?? 0.001 : 0.001
            let declared = Self.simpleWidths(font, scale: scale)
            widths = declared.isEmpty ? Self.systemWidths(forFontNamed: name) : declared
            fallbackWidth = descriptor?.object("MissingWidth")?.number.map { $0 * scale }
                ?? (name.contains("Courier") ? Self.monospacedWidth : Self.defaultWidth)
        }
    }

    func width(ofCode code: Int) -> CGFloat {
        widths[code] ?? fallbackWidth
    }

    /// Reads weight and slant from the name, backed up by the descriptor's flags.
    private static func traits(name: String, descriptor: PDFDictionary?) -> (isBold: Bool, isItalic: Bool) {
        let lowered = name.lowercased()
        let flags = descriptor?.object("Flags")?.integer ?? 0
        let weight = descriptor?.object("FontWeight")?.number ?? 400
        let boldWords = ["bold", "black", "heavy", "semibold", "demi"]
        let italicWords = ["italic", "oblique"]
        let isBold = boldWords.contains(where: lowered.contains) || weight >= 600 || flags & (1 << 18) != 0
        let isItalic = italicWords.contains(where: lowered.contains) || lowered.hasSuffix("-it")
            || flags & (1 << 6) != 0
        return (isBold, isItalic)
    }

    private static func simpleWidths(_ font: PDFDictionary, scale: CGFloat) -> [Int: CGFloat] {
        guard let first = font.object("FirstChar")?.integer, let list = font.object("Widths")?.array?.numbers
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.enumerated().map { (first + $0.offset, $0.element * scale) })
    }

    /// Widths for a font that declares none, which the standard fonts (Helvetica, Times, Courier)
    /// are allowed to do: measured from the system's font of the same name, if it has one.
    private static func systemWidths(forFontNamed name: String) -> [Int: CGFloat] {
        let unitsPerEm: CGFloat = 1000
        let font = CTFontCreateWithName(name as CFString, unitsPerEm, nil)
        guard CTFontCopyPostScriptName(font) as String == name else { return [:] }
        var widths: [Int: CGFloat] = [:]
        for code in 32...255 {
            var character = UniChar(code)
            var glyph = CGGlyph(0)
            guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { continue }
            widths[code] = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, nil, 1) / unitsPerEm
        }
        return widths
    }

    /// A composite font's `W` array mixes two forms: `first [w1 w2 …]` and `first last w`.
    private static func compositeWidths(_ descendant: PDFDictionary) -> [Int: CGFloat] {
        guard let entries = descendant.object("W")?.array else { return [:] }
        var widths: [Int: CGFloat] = [:]
        var index = 0
        while index + 1 < entries.count, let first = entries[index]?.integer {
            if let list = entries[index + 1]?.array?.numbers {
                for (offset, width) in list.enumerated() { widths[first + offset] = width / 1000 }
                index += 2
            } else if let last = entries[index + 1]?.integer, let width = entries[index + 2]?.number, last >= first {
                for code in first...min(last, first + 65_535) { widths[code] = width / 1000 }
                index += 3
            } else {
                break
            }
        }
        return widths
    }
}
