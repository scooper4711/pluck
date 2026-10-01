import CoreGraphics
import Foundation

/// The font most of a document's running text is set in; headings are judged against it.
struct BodyStyle: Hashable {
    var family: String
    var size: CGFloat
}

/// Turns lines in reading order into headings, list items and paragraphs, joining each
/// paragraph's lines into one.
struct ParagraphBuilder {
    private static let sentenceEnders: Set<Character> = [".", "!", "?", ":", "”", "\"", "’", ")", "…"]
    private static let bullets: Set<Character> = ["•", "▪", "◆", "‣", "●", "■"]
    /// How far in a line must start, in font sizes, to count as indented.
    private static let indentFactor: CGFloat = 0.35

    let body: BodyStyle
    /// Illustrations that text may wrap around, which make a line short or pushed in for no
    /// reason of its own.
    var obstacles: [CGRect] = []
    /// Hyphenated words seen whole in the document, lower-cased: their hyphens are real.
    var compounds: Set<String> = []
    /// The document's title, recorded on each stat block as its source.
    var source: String?

    func blocks(from flow: [FlowElement]) -> [TextBlock] {
        var blocks: [TextBlock] = []
        // Where the last paragraph is, so one that continues in the next column can rejoin it.
        var openParagraph: Int?
        for element in flow {
            switch element {
            case .statBlock(let region):
                var statBlock = StatBlockParser(isCompound: isCompound).parse(region)
                statBlock.variant = subtier(in: blocks)
                statBlock.source = source
                blocks.append(.statBlock(statBlock))
            case .box(let kind, let inner):
                let box = TextBlock.box(TextBox(kind: kind, blocks: self.blocks(from: inner)))
                // A callout that runs from the foot of one column to the head of the next is one passage.
                if let last = blocks.last,
                   let merged = TextFlow.continuingBox(last, with: box, isCompound: isCompound) {
                    blocks[blocks.count - 1] = merged
                } else {
                    blocks.append(box)
                }
            case .lines(let lines):
                append(lines, to: &blocks, openParagraph: &openParagraph)
            }
        }
        return blocks
    }

    /// The subtier named by the nearest heading above, as in "Encounter F (Subtier 1–2)".
    private func subtier(in blocks: [TextBlock]) -> String? {
        for block in blocks.reversed() {
            guard case .heading(_, let runs) = block,
                  let match = runs.text.range(of: #"Subtier \d+[–-]\d+"#, options: .regularExpression)
            else { continue }
            return runs.text[match].dropFirst("Subtier ".count).replacingOccurrences(of: "–", with: "-")
        }
        return nil
    }

    private func append(_ lines: [TextFragment], to blocks: inout [TextBlock], openParagraph: inout Int?) {
        let leftEdge = lines.map(\.frame.minX).min() ?? 0
        for (offset, group) in grouped(lines).enumerated() {
            let block = self.block(from: group)
            if offset == 0, let index = openParagraph, !isIndented(group[0], from: leftEdge, columnEdge: leftEdge),
               let merged = TextFlow.continuing(
                   blocks[index], with: block, requiringLowercase: false, isCompound: isCompound) {
                blocks[index] = merged
                continue
            }
            blocks.append(block)
            if case .paragraph = block { openParagraph = blocks.count - 1 } else { openParagraph = nil }
        }
    }

    // MARK: - Grouping lines

    /// Splits a column's lines wherever a new heading, list item or paragraph begins.
    private func grouped(_ lines: [TextFragment]) -> [[TextFragment]] {
        let edges = (lines.map(\.frame.minX).min() ?? 0)...(lines.map(\.frame.maxX).max() ?? 0)
        var groups: [[TextFragment]] = []
        for line in lines {
            if let previous = groups.last?.last, !startsNewBlock(line, after: previous, columnEdges: edges) {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups
    }

    private func startsNewBlock(
        _ line: TextFragment, after previous: TextFragment, columnEdges: ClosedRange<CGFloat>
    ) -> Bool {
        let style = line.style
        let previousStyle = previous.style
        if headingLevel(of: line) != headingLevel(of: previous) { return true }
        if style.family != previousStyle.family || abs(style.size - previousStyle.size) > 0.6 { return true }
        if isListItem(line) { return true }
        let gap = line.frame.minY - previous.frame.maxY
        if gap > previous.frame.height * 0.6 || gap < -previous.frame.height { return true }
        guard headingLevel(of: line) == nil else { return false }
        let endsShort = endsShort(previous, rightEdge: columnEdges.upperBound)
        // A bold lead-in ("Treasure:") opens a paragraph when the line before it had finished.
        if startsBoldAfterPlain(line, previous), endsShort || endsSentence(previous) { return true }
        guard endsSentence(previous) else { return false }
        let startsLowercase = line.text.first?.isLowercase ?? false
        return isIndented(line, from: previous.frame.minX, columnEdge: columnEdges.lowerBound)
            || (endsShort && !startsLowercase)
    }

    private func startsBoldAfterPlain(_ line: TextFragment, _ previous: TextFragment) -> Bool {
        line.characters.first?.style.isBold == true && previous.characters.last?.style.isBold == false
    }

    /// A line that starts further in than `edge`, unless an illustration pushed it there.
    private func isIndented(_ line: TextFragment, from edge: CGFloat, columnEdge: CGFloat) -> Bool {
        guard line.frame.minX > edge + line.style.size * Self.indentFactor else { return false }
        let margin = CGRect(
            x: columnEdge, y: line.frame.minY, width: line.frame.minX - columnEdge, height: line.frame.height)
        return !obstacles.contains { $0.intersects(margin) }
    }

    /// A line that stops well before the column's edge, unless an illustration cut it short.
    private func endsShort(_ line: TextFragment, rightEdge: CGFloat) -> Bool {
        guard line.frame.maxX < rightEdge - line.style.size * 1.5 else { return false }
        let margin = CGRect(
            x: line.frame.maxX, y: line.frame.minY, width: rightEdge - line.frame.maxX, height: line.frame.height)
        return !obstacles.contains { $0.intersects(margin) }
    }

    private func endsSentence(_ line: TextFragment) -> Bool {
        line.text.last.map(Self.sentenceEnders.contains) ?? false
    }

    private func isCompound(_ firstHalf: String, _ secondHalf: String) -> Bool {
        compounds.contains("\(firstHalf)-\(secondHalf)".lowercased())
    }

    // MARK: - Classifying lines

    private func block(from lines: [TextFragment]) -> TextBlock {
        let runs = lines.dropFirst().reduce(lines[0].runs) { TextFlow.joining($0, $1.runs, isCompound: isCompound) }
        if let level = headingLevel(of: lines[0]) {
            return .heading(level: level, runs: runs)
        }
        return isListItem(lines[0]) ? .listItem(withoutBullet(runs)) : .paragraph(runs)
    }

    /// A heading is noticeably larger than the body text, or a short bold line in another typeface.
    private func headingLevel(of line: TextFragment) -> Int? {
        let style = line.style
        let text = line.text
        let ratio = style.size / body.size
        if ratio >= 1.15, text.count <= 150 {
            return ratio >= 2.2 ? 1 : ratio >= 1.6 ? 2 : 3
        }
        let isAllBold = line.characters.allSatisfy { $0.style.isBold || $0.text == " " }
        let isDisplayLine = isAllBold && style.family != body.family && ratio >= 0.95 && text.count <= 80
        return isDisplayLine && !endsSentence(line) ? 4 : nil
    }

    private func isListItem(_ line: TextFragment) -> Bool {
        line.text.first.map(Self.bullets.contains) ?? false
    }

    private func withoutBullet(_ runs: [TextRun]) -> [TextRun] {
        var runs = runs
        guard !runs.isEmpty else { return runs }
        runs[0].text = String(runs[0].text.dropFirst().drop(while: \.isWhitespace))
        return runs.filter { !$0.text.isEmpty }
    }
}
