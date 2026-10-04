import Foundation

/// A stretch of text in one weight and slant.
public struct TextRun: Equatable, Sendable, Codable {
    public var text: String
    public var isBold: Bool
    public var isItalic: Bool

    public init(_ text: String, isBold: Bool = false, isItalic: Bool = false) {
        self.text = text
        self.isBold = isBold
        self.isItalic = isItalic
    }
}

/// Text set apart from the main flow of a page.
public struct TextBox: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A panel with its own background or border: a sidebar or info box.
        case sidebar
        /// A passage fenced off by rules above and below, such as read-aloud text.
        case callout
    }

    public var kind: Kind
    public var blocks: [TextBlock]

    public init(kind: Kind, blocks: [TextBlock]) {
        self.kind = kind
        self.blocks = blocks
    }
}

/// One structural unit of extracted text, in reading order.
public indirect enum TextBlock: Equatable, Sendable {
    case heading(level: Int, runs: [TextRun])
    /// A whole paragraph, already joined into a single line of text.
    case paragraph([TextRun])
    case listItem([TextRun])
    case box(TextBox)
    case statBlock(StatBlock)

    /// The block's text without styling; a box or stat block has none of its own.
    public var plainText: String {
        switch self {
        case .heading(_, let runs), .paragraph(let runs), .listItem(let runs): runs.map(\.text).joined()
        case .box, .statBlock: ""
        }
    }
}

extension Array where Element == TextRun {
    /// Appends a run, merging it into the last one when the styling matches.
    mutating func appendMerging(_ run: TextRun) {
        guard !run.text.isEmpty else { return }
        if let last, last.isBold == run.isBold, last.isItalic == run.isItalic {
            self[count - 1].text += run.text
        } else {
            append(run)
        }
    }

    var text: String { map(\.text).joined() }
}

/// Joins the per-page results of consecutive pages into one flow.
public enum TextFlow {
    private static let sentenceEnders: Set<Character> = [".", "!", "?", ":", "”", "\"", "’", ")", "…"]

    /// Concatenates pages, merging a paragraph cut by a page break back into one.
    public static func join(_ pages: [[TextBlock]]) -> [TextBlock] {
        var result: [TextBlock] = []
        for page in pages {
            var blocks = page[...]
            if let first = blocks.first, let last = result.last,
               let merged = continuingBox(last, with: first, requiringLowercase: true) {
                result[result.count - 1] = merged
                blocks = blocks.dropFirst()
            } else if let first = blocks.first, let position = result.lastIndex(where: isParagraph),
                      let merged = continuing(result[position], with: first) {
                result[position] = merged
                blocks = blocks.dropFirst()
            }
            result.append(contentsOf: blocks)
        }
        return result
    }

    /// Two callouts as one, if the first breaks off mid-sentence and the second carries on: a
    /// passage split by the end of a column or page.
    static func continuingBox(
        _ first: TextBlock, with second: TextBlock, requiringLowercase: Bool = false,
        isCompound: (String, String) -> Bool = { _, _ in false }
    ) -> TextBlock? {
        guard case .box(let head) = first, case .box(let tail) = second,
              head.kind == .callout, tail.kind == .callout,
              let lastBlock = head.blocks.last, let firstBlock = tail.blocks.first,
              let joined = continuing(
                lastBlock, with: firstBlock, requiringLowercase: requiringLowercase, isCompound: isCompound)
        else { return nil }
        return .box(TextBox(kind: .callout, blocks: head.blocks.dropLast() + [joined] + tail.blocks.dropFirst()))
    }

    /// The two paragraphs as one, if the first stops mid-sentence and the second carries on.
    /// Across a page break the second must also start in lower case, since nothing else is known
    /// about it; within a page the caller has already checked it is not indented.
    static func continuing(
        _ first: TextBlock, with second: TextBlock, requiringLowercase: Bool = true,
        isCompound: (String, String) -> Bool = { _, _ in false }
    ) -> TextBlock? {
        guard case .paragraph(let head) = first, case .paragraph(let tail) = second,
              let lastCharacter = head.text.last, let firstCharacter = tail.text.first,
              !sentenceEnders.contains(lastCharacter) else { return nil }
        guard firstCharacter.isLowercase || !requiringLowercase else { return nil }
        return .paragraph(joining(head, tail, isCompound: isCompound))
    }

    /// Joins two lines of one paragraph: a hyphen that split a word is removed, an em dash
    /// needs no space after it, and anything else gets a single space. `isCompound` says
    /// whether the two halves around a line-end hyphen form a word that keeps its hyphen.
    static func joining(
        _ head: [TextRun], _ tail: [TextRun], isCompound: (String, String) -> Bool = { _, _ in false }
    ) -> [TextRun] {
        var result = head
        guard var last = result.popLast() else { return tail }
        while last.text.last == " " { last.text.removeLast() }
        if last.text.hasSuffix("\u{AD}") || splitsWord(last.text, tail.text, isCompound: isCompound) {
            last.text.removeLast()
        } else if !last.text.hasSuffix("—"), !last.text.hasSuffix("-") {
            last.text += " "
        }
        result.append(last)
        tail.forEach { result.appendMerging($0) }
        return result
    }

    /// True when the hyphen ending `head` only marks a word broken across lines.
    private static func splitsWord(_ head: String, _ tail: String, isCompound: (String, String) -> Bool) -> Bool {
        guard head.hasSuffix("-"), tail.first?.isLowercase ?? false else { return false }
        let firstHalf = head.dropLast().reversed().prefix { $0.isLetter }.reversed()
        let secondHalf = tail.prefix { $0.isLetter }
        return !firstHalf.isEmpty && !isCompound(String(firstHalf), String(secondHalf))
    }

    private static func isParagraph(_ block: TextBlock) -> Bool {
        if case .paragraph = block { true } else { false }
    }
}
