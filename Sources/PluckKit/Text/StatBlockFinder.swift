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
    /// The horizontal rules inside the block, which divide its sections.
    var rules: [CGRect] = []
}

/// Finds Pathfinder stat blocks on a page. A block opens with a header line in capitals: the
/// name on the left, and on the right a type and level such as `CREATURE 2`, `HAZARD 3` or
/// `OBSTACLE 1`. Trait boxes may follow, then entries that each begin with a bold label.
/// A type this finder does not know is accepted when the header is underlined.
struct StatBlockFinder {
    private static let levelPattern = #"[A-Z]{3,} ?[–−-]?\d+$"#
    private static let knownTypes = ["LEVEL", "CREATURE", "HAZARD", "OBSTACLE"]
    /// A gap taller than this share of a line ends the block: a blank line always does.
    private static let maximumGap: CGFloat = 0.8
    private static let maximumDescriptionLines = 3
    private static let coreLabels = ["Perception", "AC", "HP", "Stealth", "Disable", "Chase Points"]

    let body: BodyStyle

    /// Splits the fragments into stat block regions and everything else.
    func partition(
        _ fragments: [TextFragment], rules: [CGRect]
    ) -> (regions: [StatBlockRegion], rest: [TextFragment]) {
        let headers = fragments.indices.compactMap { header(endingAt: $0, in: fragments) }
            .filter { $0.isKnownType || isUnderlined($0.frame, by: rules) }
        var used = Set<Int>()
        var regions: [StatBlockRegion] = []
        for header in headers {
            let lowerLimit = headers
                .filter { $0.frame.minY > header.frame.minY && overlapsHorizontally($0.frame, header.frame) }
                .map(\.frame.minY).min() ?? .infinity
            let candidates = fragments.indices.filter { index in
                let frame = fragments[index].frame
                // A header squeezed by an illustration is narrower than the lines below it, so
                // lines only have to start under the header, not end under it.
                return !used.contains(index) && !headers.contains { $0.indexes.contains(index) }
                    && frame.minX >= header.frame.minX - 2 && frame.minX < header.frame.maxX
                    && frame.minY >= header.frame.maxY - 2 && frame.minY < lowerLimit
            }
            guard var region = region(for: header, candidates: candidates, in: fragments, used: &used)
            else { continue }
            used.formUnion(header.indexes)
            region.rules = rules.filter { $0.intersects(region.frame.insetBy(dx: -4, dy: -8)) }
            regions.append(region)
        }
        return (regions, fragments.indices.filter { !used.contains($0) }.map { fragments[$0] })
    }

    /// How many of the lines that follow a stat block in reading order still belong to it.
    ///
    /// Where the block has a typeface of its own, lines in that typeface do. Where it shares
    /// the body's typeface, only geometry can tell: the lines must be in the next column, and
    /// the block must have been cut off (it ended on a rule, which a description follows, or in
    /// mid-sentence). Then it runs to the first blank line.
    func continuationLength(of region: StatBlockRegion, in lines: [TextFragment]) -> Int {
        let hasOwnTypeface = region.entryStyle.family != body.family
        guard hasOwnTypeface || isCutOff(region, before: lines) else { return 0 }
        var previous: TextFragment?
        return lines.prefix { line in
            defer { previous = line }
            let style = line.style
            let gap = previous.map { line.frame.minY - $0.frame.maxY } ?? 0
            return style.family == region.entryStyle.family && abs(style.size - region.entryStyle.size) <= 0.6
                && (hasOwnTypeface || gap <= line.frame.height * Self.maximumGap)
        }.count
    }

    private func isCutOff(_ region: StatBlockRegion, before lines: [TextFragment]) -> Bool {
        guard let last = region.segments.last?.last, let next = lines.first,
              next.frame.minY < last.frame.minY else { return false }
        let endsOnRule = region.rules.contains { $0.midY > last.frame.midY }
        let endsSentence = last.text.last.map { ".!?:”\"".contains($0) } ?? false
        return endsOnRule || !endsSentence
    }

    // MARK: - Headers

    private struct Header {
        let title: String
        let levelLabel: String
        let frame: CGRect
        let indexes: [Int]

        var isKnownType: Bool { StatBlockFinder.knownTypes.contains { levelLabel.hasPrefix($0) } }
    }

    /// A rule just beneath the header and about as wide.
    private func isUnderlined(_ header: CGRect, by rules: [CGRect]) -> Bool {
        rules.contains { rule in
            let overlap = min(rule.maxX, header.maxX) - max(rule.minX, header.minX)
            return rule.minY > header.maxY - 5 && rule.minY < header.maxY + 6 && overlap >= header.width * 0.6
        }
    }

    /// A header whose level label ends the fragment at `index`. The name is either the start of
    /// the same fragment or the bold text to its left on the same line.
    private func header(endingAt index: Int, in fragments: [TextFragment]) -> Header? {
        let level = fragments[index]
        guard let label = level.text.range(of: Self.levelPattern, options: .regularExpression), level.style.isBold,
              !level.text.contains(where: \.isLowercase) else { return nil }
        let ownName = level.text[..<label.lowerBound].trimmingCharacters(in: .whitespaces)
        if !ownName.isEmpty {
            return Header(title: ownName, levelLabel: String(level.text[label]), frame: level.frame, indexes: [index])
        }
        let names = fragments.indices.filter { other in
            other != index && fragments[other].frame.maxX <= level.frame.minX && fragments[other].style.isBold
                && sharesBaseline(fragments[other].frame, level.frame)
                && !fragments[other].text.contains(where: \.isLowercase)
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
                entryStyle = line.characters.last?.style ?? line.style
            }
            lines.append(line)
            taken += row
            previous = line.frame
        }
        // After the trait boxes there may be a line or two of description ("Variant pirate"),
        // but a real stat block soon reaches an entry with a bold label.
        let opening = lines.filter { $0.text.contains(where: \.isLowercase) }.prefix(Self.maximumDescriptionLines + 1)
        guard let entryStyle, opening.contains(where: { $0.characters.first?.style.isBold == true }),
              !header.isKnownType || lines.contains(where: opensCoreEntry) else { return nil }
        used.formUnion(taken)
        return StatBlockRegion(
            title: header.title, levelLabel: header.levelLabel,
            frame: lines.reduce(header.frame) { $0.union($1.frame) }, segments: [lines], entryStyle: entryStyle)
    }

    /// Every stat block has one of these entries. An encounter roster has the same header line
    /// but only a page reference and an initiative beneath it.
    private func opensCoreEntry(_ line: TextFragment) -> Bool {
        guard line.characters.first?.style.isBold == true else { return false }
        return Self.coreLabels.contains { line.text.hasPrefix($0 + " ") }
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
