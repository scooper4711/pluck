import CoreGraphics
import Foundation

/// Puts the items of a page into reading order by finding its columns.
///
/// The page is cut recursively. A gutter is a vertical strip that separates items stacked side
/// by side. Items that cross the gutter either have a band of the page to themselves (a
/// full-width heading: read in place, between what is above and below it) or float beside the
/// columns (a caption between two columns: read after them).
struct ColumnAnalyzer {
    private static let gutterWidth: CGFloat = 7
    private static let step: CGFloat = 2
    /// At least one side of a gutter needs this many items standing next to something on the other.
    private static let minimumSideBySide = 2

    /// Returns the items grouped into columns, in reading order; each group reads top to bottom.
    func columns(of items: [LayoutItem]) -> [[LayoutItem]] {
        guard items.count > 1, let gutter = bestGutter(in: items) else {
            return items.isEmpty ? [] : [topToBottom(items)]
        }
        let crossing = items.filter { $0.frame.minX < gutter.maxX && $0.frame.maxX > gutter.minX }
        let others = items.filter { !($0.frame.minX < gutter.maxX && $0.frame.maxX > gutter.minX) }
        if crossing.isEmpty {
            return columns(of: others.filter { $0.frame.maxX <= gutter.minX })
                + columns(of: others.filter { $0.frame.minX >= gutter.maxX })
        }
        return bands(crossing: crossing, others: others)
    }

    /// Splits the region at each crossing item that has a band to itself, and reads the rest
    /// of the crossing items after the columns they sit between.
    private func bands(crossing: [LayoutItem], others: [LayoutItem]) -> [[LayoutItem]] {
        let dividers = crossing.filter { divider in !others.contains { overlapsVertically($0.frame, divider.frame) } }
        let floats = crossing.filter { float in others.contains { overlapsVertically($0.frame, float.frame) } }
        var result: [[LayoutItem]] = []
        var remaining = others
        var endsWithDivider = false
        for divider in topToBottom(dividers) {
            let above = remaining.filter { $0.frame.midY < divider.frame.minY }
            remaining.removeAll { $0.frame.midY < divider.frame.minY }
            result += columns(of: above)
            // Consecutive dividers are lines of the same full-width passage.
            if above.isEmpty, endsWithDivider {
                result[result.count - 1].append(divider)
            } else {
                result.append([divider])
            }
            endsWithDivider = true
        }
        result += columns(of: remaining)
        if !floats.isEmpty { result.append(topToBottom(floats)) }
        return result
    }

    /// The vertical strip that best separates side-by-side items: the one crossed by the fewest
    /// items, and among equals the middle of the widest clear run.
    private func bestGutter(in items: [LayoutItem]) -> CGRect? {
        let bounds = items.reduce(CGRect.null) { $0.union($1.frame) }
        var best: (crossings: Int, run: [CGFloat])?
        var run: [CGFloat] = []
        var runCrossings = -1
        for position in stride(from: bounds.minX, through: bounds.maxX - Self.gutterWidth, by: Self.step) {
            let crossings = separation(at: position, in: items)
            if crossings != runCrossings {
                best = better(best, (runCrossings, run))
                run = []
                runCrossings = crossings ?? -1
            }
            if crossings != nil { run.append(position) }
        }
        best = better(best, (runCrossings, run))
        guard let best, let first = best.run.first, let last = best.run.last else { return nil }
        return CGRect(x: first, y: bounds.minY, width: last - first + Self.gutterWidth, height: bounds.height)
    }

    private func better(
        _ current: (crossings: Int, run: [CGFloat])?, _ candidate: (crossings: Int, run: [CGFloat])
    ) -> (crossings: Int, run: [CGFloat])? {
        guard candidate.crossings >= 0, !candidate.run.isEmpty else { return current }
        guard let current else { return candidate }
        if candidate.crossings != current.crossings {
            return candidate.crossings < current.crossings ? candidate : current
        }
        return candidate.run.count > current.run.count ? candidate : current
    }

    /// How many items cross a strip starting at `position`, or `nil` if the strip does not
    /// separate items that stand side by side.
    private func separation(at position: CGFloat, in items: [LayoutItem]) -> Int? {
        let strip = position...(position + Self.gutterWidth)
        let left = items.filter { $0.frame.maxX <= strip.lowerBound }
        let right = items.filter { $0.frame.minX >= strip.upperBound }
        guard left.count >= Self.minimumSideBySide, right.count >= Self.minimumSideBySide else { return nil }
        let leftBeside = left.count { item in right.contains { overlapsVertically($0.frame, item.frame) } }
        let rightBeside = right.count { item in left.contains { overlapsVertically($0.frame, item.frame) } }
        // One side may be a single tall item, such as a box standing beside several lines.
        guard max(leftBeside, rightBeside) >= Self.minimumSideBySide, min(leftBeside, rightBeside) >= 1
        else { return nil }
        return items.count - left.count - right.count
    }

    private func overlapsVertically(_ first: CGRect, _ second: CGRect) -> Bool {
        min(first.maxY, second.maxY) - max(first.minY, second.minY) > min(first.height, second.height) * 0.5
    }

    /// Orders items by row, and left to right within a row of items on the same line.
    private func topToBottom(_ items: [LayoutItem]) -> [LayoutItem] {
        var rows: [[LayoutItem]] = []
        for item in items.sorted(by: { $0.frame.minY < $1.frame.minY }) {
            if let last = rows.last?.last, overlapsVertically(last.frame, item.frame) {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows.flatMap { $0.sorted { $0.frame.minX < $1.frame.minX } }
    }
}
