import CoreGraphics
import Foundation

/// A framed area of the page and the text inside it.
struct LayoutBox {
    var frame: CGRect
    var kind: TextBox.Kind
    var fragments: [TextFragment]
}

/// Something the column analysis places as a unit: a fragment of text, or a whole box.
enum LayoutItem {
    case fragment(TextFragment)
    case box(LayoutBox)
    case statBlock(StatBlockRegion)

    var frame: CGRect {
        switch self {
        case .fragment(let fragment): fragment.frame
        case .box(let box): box.frame
        case .statBlock(let region): region.frame
        }
    }
}

/// Decides which text sits inside an info box. A box is a filled or outlined panel, an image
/// used as a background, or the space between two matching horizontal rules.
struct BoxFinder {
    private static let minimumSize = CGSize(width: 50, height: 14)
    /// A panel covering more of the page than this is the page's own background.
    private static let maximumPageShare: CGFloat = 0.5
    /// A "box" holding more of the page's text than this is not setting anything apart.
    private static let maximumTextShare: CGFloat = 0.7
    private static let minimumWidthShare: CGFloat = 0.5
    private static let minimumHeightShare: CGFloat = 0.4
    private static let ruleTolerance: CGFloat = 3
    private static let adjacency: CGFloat = 6

    let pageSize: CGSize
    let body: BodyStyle

    /// Splits the fragments into boxes and the text left outside them.
    func partition(_ fragments: [TextFragment], panels: [CGRect], rules: [CGRect]) -> [LayoutItem] {
        let candidates = panels.filter(isPlausiblePanel).map { ($0, TextBox.Kind.sidebar) }
            + ruledAreas(rules, around: fragments).map { ($0, TextBox.Kind.callout) }
        var boxes = candidates.map { LayoutBox(frame: $0.0, kind: $0.1, fragments: []) }
        var loose: [TextFragment] = []
        for fragment in fragments {
            if let index = smallestBox(containing: fragment, in: boxes) {
                boxes[index].fragments.append(fragment)
            } else {
                loose.append(fragment)
            }
        }
        // Judged before merging, so stray words over an illustration cannot ride along with
        // a real box nested in it, such as the illustration's caption.
        loose += boxes.filter { !fillsWidth(of: $0) }.flatMap(\.fragments)
        let limit = Int(CGFloat(fragments.count) * Self.maximumTextShare)
        var kept: [LayoutBox] = []
        for box in merged(boxes.filter { !$0.fragments.isEmpty && fillsWidth(of: $0) }) {
            if box.fragments.count > max(limit, 1) && fragments.count > 3 {
                loose.append(contentsOf: box.fragments)
            } else {
                kept.append(box)
            }
        }
        return loose.map(LayoutItem.fragment) + kept.map(LayoutItem.box)
    }

    /// The text of a real box fills it; a few lines straying over an illustration do not.
    private func fillsWidth(of box: LayoutBox) -> Bool {
        let text = box.fragments.reduce(CGRect.null) { $0.union($1.frame) }
        return text.width >= box.frame.width * Self.minimumWidthShare
            && text.height >= box.frame.height * Self.minimumHeightShare
    }

    private func isPlausiblePanel(_ rect: CGRect) -> Bool {
        rect.width >= Self.minimumSize.width && rect.height >= Self.minimumSize.height
            && rect.width * rect.height <= pageSize.width * pageSize.height * Self.maximumPageShare
    }

    /// The passages fenced off by rules. Usually that is the area between two matching rules.
    /// A passage that runs over a page break has only one: the rule that closes it at the top of
    /// a column, or opens it at the bottom.
    private func ruledAreas(_ rules: [CGRect], around fragments: [TextFragment]) -> [CGRect] {
        var areas: [CGRect] = []
        var unused = rules.sorted { $0.minY < $1.minY }
        while !unused.isEmpty {
            let top = unused.removeFirst()
            if let index = unused.firstIndex(where: { matches($0, top) }),
               let area = fencedArea(from: top, to: unused[index], fragments) {
                areas.append(area)
                unused.remove(at: index)
            } else {
                areas += openAreas(beside: top, fragments)
            }
        }
        return areas
    }

    /// The area between two rules, if what it holds is one uniform passage. Rules that separate
    /// the rows of a list hold mixed text (a heading, then details) and are left alone.
    private func fencedArea(from top: CGRect, to bottom: CGRect, _ fragments: [TextFragment]) -> CGRect? {
        let area = CGRect(x: top.minX, y: top.maxY, width: top.width, height: bottom.minY - top.maxY)
        guard area.height >= Self.minimumSize.height, area.height <= pageSize.height * 0.6 else { return nil }
        return isUniform(fragments.filter { area.insetBy(dx: -2, dy: -2).contains($0.frame) }) ? area : nil
    }

    /// The column above or below a lone rule, when all of it is set apart from the body text.
    private func openAreas(beside rule: CGRect, _ fragments: [TextFragment]) -> [CGRect] {
        let above = CGRect(x: rule.minX, y: 0, width: rule.width, height: rule.minY)
        let below = CGRect(x: rule.minX, y: rule.maxY, width: rule.width, height: pageSize.height - rule.maxY)
        return [above, below].compactMap { strip in
            let inside = fragments.filter { strip.insetBy(dx: -2, dy: -2).contains($0.frame) }
            guard inside.count >= 2, isUniform(inside), let style = inside.first?.style,
                  style.family != body.family, abs(style.size - body.size) <= body.size * 0.15 else { return nil }
            return strip.intersection(inside.reduce(CGRect.null) { $0.union($1.frame) }.insetBy(dx: -4, dy: -4))
        }
    }

    private func isUniform(_ fragments: [TextFragment]) -> Bool {
        guard let style = fragments.first?.style else { return false }
        return fragments.allSatisfy { $0.style.family == style.family && abs($0.style.size - style.size) <= 0.6 }
    }

    private func matches(_ rule: CGRect, _ other: CGRect) -> Bool {
        abs(rule.minX - other.minX) <= Self.ruleTolerance && abs(rule.width - other.width) <= Self.ruleTolerance
            && rule.minY > other.maxY
    }

    private func smallestBox(containing fragment: TextFragment, in boxes: [LayoutBox]) -> Int? {
        // Text merely wrapped around an illustration pokes into its bounds; text in a box lies wholly inside.
        return boxes.indices
            .filter { boxes[$0].frame.insetBy(dx: -2, dy: -2).contains(fragment.frame) }
            .min { boxes[$0].frame.width * boxes[$0].frame.height < boxes[$1].frame.width * boxes[$1].frame.height }
    }

    /// Fuses boxes that are really one: a panel nested in another, or a title bar sitting
    /// directly on top of its body.
    private func merged(_ boxes: [LayoutBox]) -> [LayoutBox] {
        var result: [LayoutBox] = []
        for box in boxes.sorted(by: { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }) {
            if let index = result.firstIndex(where: { belongTogether($0.frame, box.frame) }) {
                result[index].frame = result[index].frame.union(box.frame)
                result[index].fragments.append(contentsOf: box.fragments)
                if box.kind == .sidebar { result[index].kind = .sidebar }
            } else {
                result.append(box)
            }
        }
        return result
    }

    private func belongTogether(_ larger: CGRect, _ smaller: CGRect) -> Bool {
        if larger.insetBy(dx: -2, dy: -2).contains(CGPoint(x: smaller.midX, y: smaller.midY)) { return true }
        let overlap = min(larger.maxX, smaller.maxX) - max(larger.minX, smaller.minX)
        let verticalGap = max(larger.minY, smaller.minY) - min(larger.maxY, smaller.maxY)
        return overlap >= min(larger.width, smaller.width) * 0.8 && verticalGap <= Self.adjacency
    }
}
