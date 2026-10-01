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
        flow(of: BoxFinder(pageSize: pageSize, body: body).partition(fragments, panels: panels, rules: rules))
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
