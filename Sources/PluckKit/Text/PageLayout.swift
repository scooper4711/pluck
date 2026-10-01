import CoreGraphics
import Foundation

/// Arranges a page's fragments into reading order: text is sorted into boxes, the boxes and the
/// remaining text into columns, and each column into lines.
struct PageLayout {
    /// A panel holding no more text than this is a caption or label, not a passage set apart.
    private static let captionLength = 60

    let pageSize: CGSize
    let body: BodyStyle

    func flow(fragments: [TextFragment], panels: [CGRect], rules: [CGRect]) -> [FlowElement] {
        // Stat blocks are claimed first: the rules inside them divide sections, not callouts.
        let finder = StatBlockFinder(body: body)
        let (regions, rest) = finder.partition(fragments)
        let otherRules = rules.filter { rule in
            !regions.contains { $0.frame.insetBy(dx: -4, dy: -4).intersects(rule) }
        }
        let items = BoxFinder(pageSize: pageSize, body: body).partition(rest, panels: panels, rules: otherRules)
        return absorbingContinuations(flow(of: items + regions.map(LayoutItem.statBlock)), finder: finder)
    }

    /// Moves the lines that carry a stat block on into the next column back into the block.
    private func absorbingContinuations(_ elements: [FlowElement], finder: StatBlockFinder) -> [FlowElement] {
        var result: [FlowElement] = []
        for element in elements {
            guard case .lines(let lines) = element, case .statBlock(var region) = result.last else {
                result.append(element)
                continue
            }
            let continuation = Array(lines.prefix { finder.continues(region, with: $0) })
            if !continuation.isEmpty {
                region.segments.append(continuation)
                result[result.count - 1] = .statBlock(region)
            }
            if continuation.count < lines.count { result.append(.lines(Array(lines.dropFirst(continuation.count)))) }
        }
        return result
    }

    private func flow(of items: [LayoutItem]) -> [FlowElement] {
        ColumnAnalyzer().columns(of: items).flatMap(elements)
    }

    /// Turns one column into runs of lines, interrupted by any boxes standing in it.
    private func elements(in column: [LayoutItem]) -> [FlowElement] {
        var elements: [FlowElement] = []
        var pending: [TextFragment] = []
        func flushLines() {
            if !pending.isEmpty { elements.append(.lines(lines(from: pending))) }
            pending = []
        }
        for item in column {
            switch item {
            case .fragment(let fragment):
                pending.append(fragment)
            case .box(let box):
                flushLines()
                let inner = flow(of: box.fragments.map(LayoutItem.fragment))
                let length = box.fragments.reduce(0) { $0 + $1.characters.count }
                let isCaption = box.kind == .sidebar && length <= Self.captionLength
                elements += isCaption ? inner : [.box(box.kind, inner)]
            case .statBlock(let region):
                flushLines()
                elements.append(.statBlock(region))
            }
        }
        flushLines()
        return elements
    }

    /// Merges fragments that share a baseline into single lines.
    private func lines(from fragments: [TextFragment]) -> [TextFragment] {
        var rows: [[TextFragment]] = []
        for fragment in fragments {
            if let last = rows.last?.last, sharesBaseline(last.frame, fragment.frame) {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map(TextFragment.line)
    }

    private func sharesBaseline(_ first: CGRect, _ second: CGRect) -> Bool {
        min(first.maxY, second.maxY) - max(first.minY, second.minY) > min(first.height, second.height) * 0.5
    }
}
