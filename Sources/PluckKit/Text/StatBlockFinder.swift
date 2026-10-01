import CoreGraphics
import Foundation

/// The part of a column a stat block occupies, before its lines are interpreted.
struct StatBlockRegion {
    /// The name as printed in the header line.
    var title: String
    /// The header's right-hand label, such as `LEVEL 1` or `CREATURE –1`.
    var levelLabel: String
    var frame: CGRect
    /// The block's lines. A block that carries on in another column has a segment for each,
    /// since each column has its own left edge to measure hanging indents from.
    var segments: [[TextFragment]]
    /// The font the block's entries are set in.
    var entryStyle: CharacterStyle
}

/// Finds Pathfinder stat blocks on a page. A block opens with a header line, the name on the
/// left and `LEVEL n` (or `CREATURE n`, `HAZARD n`) on the right, followed by trait boxes in
/// capitals and then entries that each begin with a bold label.
struct StatBlockFinder {
    private static let levelPattern = #"(LEVEL|CREATURE|HAZARD) ?[–−-]?\d+$"#
    /// A gap taller than this many lines ends the block.
    private static let maximumGap: CGFloat = 2.5

    let body: BodyStyle

    /// Splits the fragments into stat block regions and everything else.
    func partition(_ fragments: [TextFragment]) -> (regions: [StatBlockRegion], rest: [TextFragment]) {
        let headers = fragments.indices.compactMap { header(endingAt: $0, in: fragments) }
        var used = Set<Int>()
        var regions: [StatBlockRegion] = []
        for header in headers {
            let lowerLimit = headers
                .filter { $0.frame.minY > header.frame.minY && overlapsHorizontally($0.frame, header.frame) }
                .map(\.frame.minY).min() ?? .infinity
            let candidates = fragments.indices.filter { index in
                let frame = fragments[index].frame
                return !used.contains(index) && !headers.contains { $0.indexes.contains(index) }
                    && frame.minX >= header.frame.minX - 2 && frame.maxX <= header.frame.maxX + 2
                    && frame.minY >= header.frame.maxY - 2 && frame.minY < lowerLimit
            }
            guard let region = region(for: header, candidates: candidates, in: fragments, used: &used) else { continue }
            used.formUnion(header.indexes)
            regions.append(region)
        }
        return (regions, fragments.indices.filter { !used.contains($0) }.map { fragments[$0] })
    }

    /// Whether lines that follow a stat block in reading order still belong to it: set in the
    /// block's own typeface when that differs from the body text.
    func continues(_ region: StatBlockRegion, with line: TextFragment) -> Bool {
        let style = line.style
        return region.entryStyle.family != body.family && style.family == region.entryStyle.family
            && abs(style.size - region.entryStyle.size) <= 0.6
    }

    // MARK: - Headers

    private struct Header {
        let title: String
        let levelLabel: String
        let frame: CGRect
        let indexes: [Int]
    }

    /// A header whose level label ends the fragment at `index`. The name is either the start of
    /// the same fragment or the bold text to its left on the same line.
    private func header(endingAt index: Int, in fragments: [TextFragment]) -> Header? {
        let level = fragments[index]
        guard let label = level.text.range(of: Self.levelPattern, options: .regularExpression), level.style.isBold
        else { return nil }
        let ownName = level.text[..<label.lowerBound].trimmingCharacters(in: .whitespaces)
        if !ownName.isEmpty {
            return Header(title: ownName, levelLabel: String(level.text[label]), frame: level.frame, indexes: [index])
        }
        let names = fragments.indices.filter { other in
            other != index && fragments[other].frame.maxX <= level.frame.minX && fragments[other].style.isBold
                && sharesBaseline(fragments[other].frame, level.frame)
        }.sorted { fragments[$0].frame.minX < fragments[$1].frame.minX }
        guard !names.isEmpty else { return nil }
        return Header(
            title: names.map { fragments[$0].text }.joined(separator: " "), levelLabel: level.text,
            frame: names.reduce(level.frame) { $0.union(fragments[$1].frame) }, indexes: names + [index])
    }

    // MARK: - Regions

    private func region(
        for header: Header, candidates: [Int], in fragments: [TextFragment], used: inout Set<Int>
    ) -> StatBlockRegion? {
        var lines: [TextFragment] = []
        var taken: [Int] = []
        var entryStyle: CharacterStyle?
        var previous = header.frame
        for row in rows(of: candidates, in: fragments) {
            let line = TextFragment.line(from: row.map { fragments[$0] })
            guard line.frame.minY - previous.maxY <= line.frame.height * Self.maximumGap else { break }
            if let entryStyle {
                guard belongs(line, to: entryStyle) else { break }
            } else if line.text.contains(where: \.isLowercase) {
                // The first line that is not a row of trait boxes must open an entry.
                guard line.characters.first?.style.isBold == true else { break }
                entryStyle = line.characters.last?.style ?? line.style
            }
            lines.append(line)
            taken += row
            previous = line.frame
        }
        guard let entryStyle else { return nil }
        used.formUnion(taken)
        return StatBlockRegion(
            title: header.title, levelLabel: header.levelLabel,
            frame: lines.reduce(header.frame) { $0.union($1.frame) }, segments: [lines], entryStyle: entryStyle)
    }

    /// A line stays in the block unless it is a heading or has returned to the body typeface.
    private func belongs(_ line: TextFragment, to entryStyle: CharacterStyle) -> Bool {
        let style = line.style
        if style.size > entryStyle.size * 1.2 { return false }
        return !(style.family == body.family && entryStyle.family != body.family)
    }

    private func rows(of indexes: [Int], in fragments: [TextFragment]) -> [[Int]] {
        var rows: [[Int]] = []
        for index in indexes.sorted(by: { fragments[$0].frame.minY < fragments[$1].frame.minY }) {
            if let last = rows.last?.last, sharesBaseline(fragments[last].frame, fragments[index].frame) {
                rows[rows.count - 1].append(index)
            } else {
                rows.append([index])
            }
        }
        return rows
    }

    private func sharesBaseline(_ first: CGRect, _ second: CGRect) -> Bool {
        min(first.maxY, second.maxY) - max(first.minY, second.minY) > min(first.height, second.height) * 0.5
    }

    private func overlapsHorizontally(_ first: CGRect, _ second: CGRect) -> Bool {
        min(first.maxX, second.maxX) > max(first.minX, second.minX)
    }
}
