import CoreGraphics
import Foundation

/// Reads the lines of a stat block region into its name, level, traits and entries.
struct StatBlockParser {
    /// How far in a line must start, in font sizes, to be a continuation of the entry above.
    private static let hangFactor: CGFloat = 0.35
    /// A hanging indent is never deeper than this many font sizes.
    private static let maximumHangFactor: CGFloat = 1.5
    private static let innerLabels: Set<String> = [
        "Damage", "Effect", "Cantrips", "Constant", "Trigger", "Requirements", "Requirement", "Frequency",
        "Critical Success", "Success", "Failure", "Critical Failure", "Fort", "Ref", "Will",
        "Dex", "Con", "Int", "Wis", "Cha", "Immunities", "Weaknesses", "Resistances", "Hardness",
        "Saving Throw", "Maximum Duration", "Onset"
    ]

    /// Says whether two halves around a line-end hyphen form a word that keeps its hyphen.
    var isCompound: (String, String) -> Bool = { _, _ in false }

    func parse(_ region: StatBlockRegion) -> StatBlock {
        var traits: [String] = []
        var entries: [[TextRun]] = []
        var previous: TextFragment?
        for segment in region.segments {
            let leftEdge = segment.map(\.frame.minX).min() ?? 0
            for (offset, line) in segment.enumerated() {
                let followsRule = previous.map { hasRule(in: region, after: $0, before: offset == 0 ? nil : line) }
                defer { previous = line }
                if entries.isEmpty, !line.text.contains(where: \.isLowercase) {
                    traits += line.text.split(separator: " ").map(String.init)
                } else if entries.isEmpty || opensEntry(line, leftEdge: leftEdge)
                            || opensDescription(line, leftEdge: leftEdge, followsRule: followsRule ?? false,
                                                after: entries.last) {
                    entries.append(line.runs)
                } else {
                    entries[entries.count - 1] = TextFlow.joining(
                        entries[entries.count - 1], line.runs, isCompound: isCompound)
                }
            }
        }
        return StatBlock(
            name: region.title, level: Self.level(from: region.levelLabel), traits: traits,
            entries: entries.map(Self.entry))
    }

    /// An entry starts with a bold label at the left edge; its other lines hang indented. A line
    /// pushed further in than a hanging indent has been moved aside by an illustration, so its
    /// bold label opens an entry too, unless the label is one that only appears inside entries.
    private func opensEntry(_ line: TextFragment, leftEdge: CGFloat) -> Bool {
        guard line.characters.first?.style.isBold == true else { return false }
        let indent = line.frame.minX - leftEdge
        if indent <= line.style.size * Self.hangFactor { return true }
        let label = line.runs.first?.text.trimmingCharacters(in: .whitespaces) ?? ""
        return indent > line.style.size * Self.maximumHangFactor && !Self.isInnerLabel(label)
    }

    /// Text without a label starts an entry of its own when it comes straight after a rule, or
    /// stands at the left edge where a labelled entry's other lines would hang indented.
    /// Further lines of the same unlabelled text are not new entries.
    private func opensDescription(
        _ line: TextFragment, leftEdge: CGFloat, followsRule: Bool, after entry: [TextRun]?
    ) -> Bool {
        guard line.characters.first?.style.isBold == false else { return false }
        if followsRule { return true }
        let isAtEdge = line.frame.minX <= leftEdge + line.style.size * Self.hangFactor
        return isAtEdge && entry?.first?.isBold == true
    }

    /// Whether a rule lies between two lines. With no next line to bound it (the next line is
    /// in another column), any rule below the previous line counts.
    private func hasRule(in region: StatBlockRegion, after previous: TextFragment, before line: TextFragment?) -> Bool {
        region.rules.contains { rule in
            rule.midY > previous.frame.midY && (line.map { rule.midY < $0.frame.midY } ?? true)
        }
    }

    /// Labels that sit inside an entry, such as the `Damage` of a strike or the saves after `AC`.
    private static func isInnerLabel(_ label: String) -> Bool {
        innerLabels.contains { label == $0 || label.hasPrefix($0 + " ") }
            || label.range(of: #"^(\d+(st|nd|rd|th)|Stage \d+)$"#, options: .regularExpression) != nil
    }

    /// Splits an entry into its leading bold label and the rest.
    private static func entry(from runs: [TextRun]) -> StatBlock.Entry {
        guard let first = runs.first, first.isBold else {
            return StatBlock.Entry(name: "", runs: runs)
        }
        var rest = Array(runs.dropFirst())
        if !rest.isEmpty { rest[0].text = String(rest[0].text.drop(while: \.isWhitespace)) }
        return StatBlock.Entry(name: first.text.trimmingCharacters(in: .whitespaces), runs: rest)
    }

    /// `LEVEL –1` and `CREATURE –1` both become `Creature -1`; `HAZARD 3` becomes `Hazard 3`,
    /// and any other type keeps its own name: `OBSTACLE 1` becomes `Obstacle 1`.
    static func level(from label: String) -> String {
        let type = String(label.prefix { $0.isLetter })
        let kind = type == "LEVEL" ? "Creature" : type.prefix(1) + type.dropFirst().lowercased()
        let digits = label.filter(\.isNumber)
        let isNegative = label.contains { "–−-".contains($0) }
        return "\(kind) \(isNegative ? "-" : "")\(digits)"
    }
}
