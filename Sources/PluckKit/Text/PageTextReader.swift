import CoreGraphics
import Foundation
import PDFKit

/// Reads a page's characters and positions from PDFKit, gives each its real font from the
/// page's drawing commands, and groups them into fragments.
struct PageTextReader {
    /// Text smaller than this is hidden production marking, not content.
    private static let minimumSize: CGFloat = 4
    private static let maximumSize: CGFloat = 400
    /// PDFKit's character boxes are about this many times the font size tall.
    private static let lineHeightFactor: CGFloat = 1.2
    /// A gap wider than this share of the line height separates two fragments.
    private static let gapFactor: CGFloat = 0.7

    let page: PDFPage
    let graphics: PageGraphics

    private let cropBox: CGRect
    private let spanIndex: FontSpanIndex

    init(page: PDFPage, graphics: PageGraphics) {
        self.page = page
        self.graphics = graphics
        cropBox = page.bounds(for: .cropBox)
        spanIndex = FontSpanIndex(graphics.fontSpans)
    }

    /// Converts a rectangle from PDF page coordinates to reading coordinates.
    func readingRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX - cropBox.minX, y: cropBox.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    func fragments() -> [TextFragment] {
        guard let string = page.string as NSString? else { return [] }
        var builder = FragmentBuilder(gapFactor: Self.gapFactor)
        var overprints = OverprintedSpans(graphics.fontSpans)
        var index = 0
        while index < string.length {
            let range = string.rangeOfComposedCharacterSequence(at: index)
            index = range.upperBound
            let text = string.substring(with: range)
            if text.unicodeScalars.allSatisfy(CharacterSet.newlines.contains) {
                builder.endFragment()
            } else if let frame = page.selection(for: range)?.bounds(for: page), isSensible(frame),
                      overprints.admit(frame) {
                add(text, frame: frame, to: &builder)
            }
        }
        builder.endFragment()
        return builder.fragments
    }

    /// PDFKit occasionally reports an empty, infinite or page-sized box for a character.
    private func isSensible(_ frame: CGRect) -> Bool {
        !frame.isEmpty && !frame.isInfinite && frame.height <= Self.maximumSize * 2
            && cropBox.insetBy(dx: -cropBox.width, dy: -cropBox.height).contains(frame)
    }

    private func add(_ text: String, frame: CGRect, to builder: inout FragmentBuilder) {
        let style = spanIndex.style(at: frame) ?? fallbackStyle(for: frame)
        guard style.size >= Self.minimumSize else { return }
        builder.add(StyledCharacter(text: text, style: style), frame: readingRect(frame))
    }

    /// For a character no drawing command covers, only its size can be told, from its box.
    /// PDFKit's own styled text is not consulted: building it hangs on some pages.
    private func fallbackStyle(for frame: CGRect) -> CharacterStyle {
        CharacterStyle(fontName: "", size: frame.height / Self.lineHeightFactor, isBold: false, isItalic: false)
    }
}

/// The stretches of baseline where the page paints the same string twice in the same place:
/// outlined and shadowed type is drawn as two copies, and PDFKit reports both. The first copy's
/// characters are let through; once it has been read to its end, or the text jumps back to the
/// start, everything else there is the second copy.
private struct OverprintedSpans {
    private struct Region {
        let box: CGRect
        let endX: CGFloat
        let size: CGFloat
        var lastMinX = -CGFloat.infinity
        var isRead = false
    }

    private var regions: [Region] = []

    init(_ spans: [FontSpan]) {
        let horizontal = spans.filter(\.isHorizontal)
        for (index, span) in horizontal.enumerated() {
            let isRepeat = horizontal[..<index].contains { Self.coincide($0, span) }
            let alreadyKnown = regions.contains { $0.box.contains(span.start) && abs($0.endX - span.end.x) < 3 }
            guard isRepeat, !alreadyKnown else { continue }
            let box = CGRect(
                x: span.start.x - 3, y: span.start.y - span.size * 0.35,
                width: span.end.x - span.start.x + 6, height: span.size * 1.3)
            regions.append(Region(box: box, endX: span.end.x, size: span.size))
        }
    }

    /// False for a character that belongs to a second copy.
    mutating func admit(_ frame: CGRect) -> Bool {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let index = regions.firstIndex(where: { $0.box.contains(center) }) else { return true }
        let region = regions[index]
        if region.isRead || frame.minX < region.lastMinX - region.size * 0.2 {
            regions[index].isRead = true
            return false
        }
        regions[index].lastMinX = frame.minX
        if frame.maxX >= region.endX - region.size * 0.15 { regions[index].isRead = true }
        return true
    }

    /// Two spans in the same font that start and end within a shadow's offset of each other.
    private static func coincide(_ first: FontSpan, _ second: FontSpan) -> Bool {
        let tolerance = max(2.5, first.size * 0.12)
        return first.fontName == second.fontName && abs(first.size - second.size) < 0.1
            && abs(first.start.x - second.start.x) <= tolerance && abs(first.start.y - second.start.y) <= tolerance
            && abs(first.end.x - second.end.x) <= tolerance && second.end.x - second.start.x > second.size
    }
}

/// Finds the font span under a character quickly, by bucketing spans on their baseline.
private struct FontSpanIndex {
    private var spansByBaseline: [Int: [FontSpan]] = [:]

    init(_ spans: [FontSpan]) {
        for span in spans where span.isHorizontal {
            spansByBaseline[Int(span.start.y.rounded(.down)), default: []].append(span)
        }
    }

    /// The style of the span whose baseline runs through the character's box (page coordinates).
    func style(at frame: CGRect) -> CharacterStyle? {
        let expectedBaseline = frame.minY + frame.height * 0.2
        var best: (span: FontSpan, distance: CGFloat)?
        for bucket in Int(frame.minY.rounded(.down)) - 1...Int(frame.maxY.rounded(.up)) {
            for span in spansByBaseline[bucket] ?? [] where covers(span, frame) {
                let distance = abs(span.start.y - expectedBaseline)
                if distance < best?.distance ?? .infinity { best = (span, distance) }
            }
        }
        return best.map {
            CharacterStyle(fontName: $0.span.fontName, size: $0.span.size, isBold: $0.span.isBold,
                           isItalic: $0.span.isItalic)
        }
    }

    private func covers(_ span: FontSpan, _ frame: CGRect) -> Bool {
        span.start.y >= frame.minY - 1 && span.start.y <= frame.maxY
            && frame.midX >= span.start.x - 1 && frame.midX <= span.end.x + 1
    }
}

/// Accumulates characters into fragments, starting a new one at a line break or a wide gap.
private struct FragmentBuilder {
    let gapFactor: CGFloat
    private(set) var fragments: [TextFragment] = []

    private var characters: [StyledCharacter] = []
    /// The box of the visible characters; trailing spaces are not counted.
    private var inkFrame = CGRect.null
    private var lastFrame = CGRect.null

    init(gapFactor: CGFloat) {
        self.gapFactor = gapFactor
    }

    mutating func add(_ character: StyledCharacter, frame: CGRect) {
        if startsNewFragment(frame) { endFragment() }
        // Layout marks such as a right-align tab come through as control characters (a backspace
        // after a stat block's name, for one). They separate words, so they count as spaces.
        let isSpace = character.text.unicodeScalars.allSatisfy {
            CharacterSet.whitespaces.contains($0) || CharacterSet.controlCharacters.contains($0)
        }
        if isSpace {
            if !characters.isEmpty, characters.last?.text != " " {
                characters.append(StyledCharacter(text: " ", style: character.style))
            }
        } else {
            characters.append(character)
            inkFrame = inkFrame.union(frame)
        }
        lastFrame = frame
    }

    mutating func endFragment() {
        while characters.last?.text == " " { characters.removeLast() }
        if !characters.isEmpty { fragments.append(TextFragment(frame: inkFrame, characters: characters)) }
        characters = []
        inkFrame = .null
        lastFrame = .null
    }

    private func startsNewFragment(_ frame: CGRect) -> Bool {
        guard !lastFrame.isNull else { return false }
        // One glyph can stand for several characters (a ligature, or an action symbol read as
        // "[two-actions]"); they all share its box and must stay together.
        if abs(frame.minX - lastFrame.minX) < 0.01, abs(frame.width - lastFrame.width) < 0.01 { return false }
        let height = min(frame.height, lastFrame.height)
        let changesBaseline = abs(frame.minY - lastFrame.minY) > height * 0.5
        let gap = frame.minX - lastFrame.maxX
        return changesBaseline || gap > height * gapFactor || gap < -height
    }
}
