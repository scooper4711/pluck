import Foundation

/// A creature or hazard stat block in the Pathfinder Second Edition layout.
public struct StatBlock: Equatable, Sendable {
    /// One labelled line of the block, such as `Perception +6; darkvision`.
    public struct Entry: Equatable, Sendable {
        /// The bold label that opens the entry: `Perception`, `AC`, `Melee`.
        public var name: String
        /// Everything after the label.
        public var runs: [TextRun]

        public init(name: String, runs: [TextRun]) {
            self.name = name
            self.runs = runs
        }

        public var text: String { runs.text.trimmingCharacters(in: .whitespaces) }
    }

    /// The name as printed, usually in capitals: `GWIBBLE`.
    public var name: String
    /// The kind and level, normalised: `Creature 1`, `Hazard 3`.
    public var level: String
    /// The trait boxes as printed: rarity, alignment, size, then the rest.
    public var traits: [String]
    public var entries: [Entry]
    /// The subtier the block belongs to in an organised-play scenario, such as `1-2`.
    public var variant: String?
    /// The document the block came from.
    public var source: String?

    public init(
        name: String, level: String, traits: [String] = [], entries: [Entry] = [],
        variant: String? = nil, source: String? = nil
    ) {
        self.name = name
        self.level = level
        self.traits = traits
        self.entries = entries
        self.variant = variant
        self.source = source
    }

    /// The name in title case, with the subtier appended when there is one: `Gwibble (1-2)`.
    public var displayName: String {
        let titled = name.lowercased().split(separator: " ").map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
        return variant.map { "\(titled) (\($0))" } ?? titled
    }

    /// The entries in the block's three printed sections: everything before `AC`, the
    /// defences up to `Speed`, and `Speed` onwards.
    public var sections: [[Entry]] {
        let defenseStart = entries.firstIndex { $0.name == "AC" } ?? entries.count
        let offenseStart = entries.firstIndex { $0.name == "Speed" } ?? entries.count
        let middleEnd = max(defenseStart, offenseStart)
        return [Array(entries[..<defenseStart]), Array(entries[defenseStart..<middleEnd]),
                Array(entries[middleEnd...])]
    }

    public func entry(named name: String) -> Entry? {
        entries.first { $0.name == name }
    }
}

/// The tokens Paizo PDFs yield for action glyphs, and how each is written elsewhere.
enum ActionGlyph: String, CaseIterable {
    case one = "[one-action]"
    case two = "[two-actions]"
    case three = "[three-actions]"
    case reaction = "[reaction]"
    case free = "[free-action]"

    /// The Fantasy Statblocks inline code that draws the glyph.
    var statblockCode: String {
        switch self {
        case .one: "`pf2:1`"
        case .two: "`pf2:2`"
        case .three: "`pf2:3`"
        case .reaction: "`pf2:r`"
        case .free: "`pf2:0`"
        }
    }

    /// A plain-text stand-in, as used in Paizo's own text-only material.
    var symbol: String {
        switch self {
        case .one: "◆"
        case .two: "◆◆"
        case .three: "◆◆◆"
        case .reaction: "⤾"
        case .free: "◇"
        }
    }

    /// A private-use character standing in for the glyph while text around it is escaped.
    private var placeholder: String {
        String(UnicodeScalar(0xE000 + (Self.allCases.firstIndex(of: self) ?? 0)).map(Character.init) ?? " ")
    }

    /// Escapes `text` for a markup language and writes its glyph tokens with `replacement`,
    /// keeping the replacement itself out of the escaping.
    static func rendering(
        _ text: String, escape: (String) -> String, with replacement: (ActionGlyph) -> String
    ) -> String {
        let escaped = escape(replacing(in: text, with: \.placeholder))
        return allCases.reduce(escaped) { $0.replacingOccurrences(of: $1.placeholder, with: replacement($1)) }
    }

    /// Replaces each glyph token. Some PDFs letter-space the token ("[ t w o - a c t i o n s ]"),
    /// so spaces between its characters are allowed.
    static func replacing(in text: String, with replacement: (ActionGlyph) -> String) -> String {
        allCases.reduce(text) { result, glyph in
            let pattern = glyph.rawValue.map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: " ?")
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return result }
            let template = NSRegularExpression.escapedTemplate(for: replacement(glyph))
            return expression.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
    }
}
