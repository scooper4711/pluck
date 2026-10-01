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
        for segment in region.segments {
            let leftEdge = segment.map(\.frame.minX).min() ?? 0
            for line in segment {
                if entries.isEmpty, !line.text.contains(where: \.isLowercase) {
                    traits += line.text.split(separator: " ").map(String.init)
                } else if opensEntry(line, leftEdge: leftEdge) || entries.isEmpty {
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

    /// `LEVEL –1` and `CREATURE –1` both become `Creature -1`; `HAZARD 3` becomes `Hazard 3`.
    static func level(from label: String) -> String {
        let kind = label.hasPrefix("HAZARD") ? "Hazard" : "Creature"
        let digits = label.filter(\.isNumber)
        let isNegative = label.contains { "–−-".contains($0) }
        return "\(kind) \(isNegative ? "-" : "")\(digits)"
    }
}
