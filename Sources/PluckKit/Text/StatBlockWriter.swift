import Foundation

/// Writes a stat block as plain text or as HTML.
enum StatBlockWriter {
    static func plainText(_ block: StatBlock) -> String {
        var lines = ["\(block.displayName) — \(block.level)"]
        if !block.traits.isEmpty { lines.append(block.traits.map(traitName).joined(separator: ", ")) }
        lines += block.entries.map { entry in
            let text = ActionGlyph.replacing(in: entry.text, with: \.symbol)
            return [entry.name, text].filter { !$0.isEmpty }.joined(separator: " ")
        }
        return lines.joined(separator: "\n")
    }

    /// A `div.statblock` holding a heading, a list of traits, and a paragraph per entry, with a
    /// rule between the block's sections.
    static func html(_ block: StatBlock, inline: ([TextRun]) -> String) -> String {
        var lines = ["<div class=\"statblock\">"]
        lines.append("<h3>\(escape(block.displayName)) <span class=\"level\">\(escape(block.level))</span></h3>")
        if !block.traits.isEmpty {
            let items = block.traits.map { "<li>\(escape(traitName($0)))</li>" }
            lines += ["<ul class=\"traits\">"] + items + ["</ul>"]
        }
        lines += entryLines(block, inline: inline)
        lines.append("</div>")
        return lines.joined(separator: "\n")
    }

    /// A stat block for rich-text apps such as Pages and Mail, which ignore the preview's styles:
    /// a heading, the traits on one line, and a paragraph per entry with its label in bold.
    static func pastedHTML(_ block: StatBlock, inline: ([TextRun]) -> String) -> String {
        var lines = ["<h3>\(escape(block.displayName)) — \(escape(block.level))</h3>"]
        if !block.traits.isEmpty {
            lines.append("<p>\(escape(block.traits.map(traitName).joined(separator: ", ")))</p>")
        }
        lines += entryLines(block, inline: inline)
        return lines.joined(separator: "\n")
    }

    /// A paragraph per entry, with its label in bold and a rule between the block's sections.
    private static func entryLines(_ block: StatBlock, inline: ([TextRun]) -> String) -> [String] {
        var lines: [String] = []
        for (index, section) in block.sections.filter({ !$0.isEmpty }).enumerated() {
            if index > 0 { lines.append("<hr>") }
            lines += section.map { entry in
                let label = entry.name.isEmpty ? "" : "<strong>\(escape(entry.name))</strong> "
                return "<p>\(label)\(inline(entry.runs))</p>"
            }
        }
        return lines
    }

    /// Traits are printed in capitals; alignments stay that way (`LE`), the rest become words.
    static func traitName(_ trait: String) -> String {
        trait.count <= 2 ? trait : trait.prefix(1) + trait.dropFirst().lowercased()
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Writes a stat block as a `statblock` code block for the Obsidian plugin Fantasy Statblocks,
/// using its Basic Pathfinder 2e Layout.
struct StatBlockYAMLWriter {
    private static let rarities: Set<String> = ["COMMON", "UNCOMMON", "RARE", "UNIQUE"]
    private static let sizes: Set<String> = ["TINY", "SMALL", "MEDIUM", "LARGE", "HUGE", "GARGANTUAN"]
    private static let alignments: [String: [String]] = [
        "LG": ["lawful", "good"], "NG": ["good"], "CG": ["chaotic", "good"],
        "LN": ["lawful"], "N": [], "CN": ["chaotic"],
        "LE": ["lawful", "evil"], "NE": ["evil"], "CE": ["chaotic", "evil"]
    ]
    /// Entries that have a field of their own rather than a place in an abilities list.
    private static let dedicated: Set<String> = [
        "Perception", "Stealth", "Languages", "Skills", "Str", "AC", "HP", "Speed"
    ]

    let block: StatBlock

    func render() -> String {
        (["```statblock"] + header + traits + senses + defenses + abilities + ["```"]).joined(separator: "\n")
    }

    private var header: [String] {
        var lines = ["columns: 2", "forcecolumns: true", "layout: Basic Pathfinder 2e Layout"]
        if let source = block.source { lines.append("source: \(quoted(source))") }
        lines += ["name: \(quoted(block.displayName))", "level: \(quoted(block.level))"]
        return lines
    }

    /// Rarity, size and traits. An alignment is written as its traits, the way the layout's
    /// other notes do, so `LE` becomes `lawful` and `evil`.
    private var traits: [String] {
        var lines: [String] = []
        var names: [String] = []
        var size: String?
        for trait in block.traits {
            if Self.rarities.contains(trait) {
                lines.append("rare_03: [[\(StatBlockWriter.traitName(trait))]]")
            } else if Self.sizes.contains(trait) {
                size = StatBlockWriter.traitName(trait)
            } else {
                names += Self.alignments[trait] ?? [trait.lowercased()]
            }
        }
        lines.append("alignment: \"\"")
        if let size { lines.append("size: \(quoted(size))") }
        lines += names.sorted().enumerated().map { String(format: "trait_%02d: [[%@]]", $0.offset + 1, $0.element) }
        return lines
    }

    private var senses: [String] {
        var lines: [String] = []
        if let perception = block.entry(named: "Perception") {
            if let modifier = Self.numbers(in: perception.text).first { lines.append("modifier: \(modifier)") }
            lines += ["perception:"] + item(name: "Perception", desc: inline(perception.runs))
        } else if let stealth = block.entry(named: "Stealth") {
            // A hazard is noticed against its Stealth, which takes Perception's place.
            if let modifier = Self.numbers(in: stealth.text).first { lines.append("modifier: \(modifier)") }
            lines += ["perception:", "  - name: \"\""] + item(name: "Stealth", desc: inline(stealth.runs))
        }
        if let languages = block.entry(named: "Languages") { lines.append("languages: \(quoted(languages.text))") }
        if let skills = block.entry(named: "Skills") {
            lines += ["skills:"] + item(name: "Skills", desc: inline(skills.runs))
        }
        if let abilities = block.entry(named: "Str") {
            let modifiers = Self.numbers(in: abilities.text).prefix(6).map(String.init)
            lines.append("abilityMods: [\(modifiers.joined(separator: ", "))]")
        }
        if let source = block.source { lines.append("sourcebook: \(quoted("_\(source)_"))") }
        return lines
    }

    private var defenses: [String] {
        var lines: [String] = []
        if let speed = block.entry(named: "Speed") { lines.append("speed: \(quoted(speed.text))") }
        if let armor = block.entry(named: "AC") {
            if let value = Self.numbers(in: armor.text).first { lines.append("ac: \(value)") }
            lines += ["armorclass:", "  - name: AC", "    desc: \(quoted(inline(armor.runs)))"]
        }
        if let health = block.entry(named: "HP") {
            if let value = Self.numbers(in: health.text).first { lines.append("hp: \(value)") }
            lines += ["health:", "  - name: \"\"", "  - name: HP", "    desc: \(quoted(inline(health.runs)))"]
        }
        return lines
    }

    /// The entries without a field of their own, in the layout's three lists: before the
    /// defences, between them and Speed, and after Speed.
    private var abilities: [String] {
        var sections = block.sections + [[], [], []]
        // A hazard's Disable entry is printed before its defences but belongs with them.
        sections[1] = sections[0].filter { $0.name == "Disable" } + sections[1]
        sections[0].removeAll { $0.name == "Disable" }
        let keys = ["abilities_top", "abilities_mid", "attacks"]
        var lines: [String] = []
        for (index, key) in keys.enumerated() {
            let entries = sections[index].filter { !Self.dedicated.contains($0.name) }
            lines += ["\(key):", "  - name: \"\""]
            lines += entries.flatMap { key == "attacks" ? attack($0) : ability($0) }
        }
        return lines
    }

    private func ability(_ entry: StatBlock.Entry) -> [String] {
        let body = inline(entry.runs)
        // An action glyph straight after the name belongs with the name.
        if let glyph = body.range(of: #"^`pf2:.` ?"#, options: .regularExpression) {
            let code = body[glyph].trimmingCharacters(in: .whitespaces)
            return item(name: "\(entry.name) \(code)", desc: String(body[glyph.upperBound...]))
        }
        return item(name: entry.name, desc: body)
    }

    /// A strike is titled with its weapon, and its damage goes on a line of its own.
    private func attack(_ entry: StatBlock.Entry) -> [String] {
        let body = inline(entry.runs)
        guard ["Melee", "Ranged"].contains(entry.name),
              let bonus = body.range(of: #" [+–−-]\d"#, options: .regularExpression) else { return ability(entry) }
        // "`pf2:1` shortsword" becomes "`pf2:1` Shortsword": the weapon's name is capitalised.
        var words = body[..<bonus.lowerBound].split(separator: " ").map(String.init)
        if let index = words.firstIndex(where: { !$0.hasPrefix("`") }) {
            words[index] = words[index].prefix(1).uppercased() + words[index].dropFirst()
        }
        let weapon = words.joined(separator: " ")
        let details = body[bonus.lowerBound...].dropFirst()
            .replacingOccurrences(of: ", __Damage__", with: "\n__Damage__")
            .replacingOccurrences(of: ", __Effect__", with: "\n__Effect__")
        return item(name: "**\(entry.name)** \(weapon)", desc: details)
    }

    private func item(name: String, desc: String) -> [String] {
        ["  - name: \(quoted(name))", "    desc: \(quoted(desc))"]
    }

    /// Bold as `__text__` and italic as `_text_`, which the plugin renders, with action glyphs
    /// as its `pf2:` codes.
    private func inline(_ runs: [TextRun]) -> String {
        let text = runs.map { run -> String in
            let core = run.text.trimmingCharacters(in: .whitespaces)
            let marker = Self.emphasisMarker(of: run)
            guard !marker.isEmpty, !core.isEmpty else { return run.text }
            let leading = run.text.prefix { $0 == " " }
            let trailing = run.text.hasSuffix(" ") ? " " : ""
            return leading + marker + core + marker + trailing
        }.joined()
        return ActionGlyph.replacing(in: text, with: \.statblockCode).trimmingCharacters(in: .whitespaces)
    }

    private static func emphasisMarker(of run: TextRun) -> String {
        switch (run.isBold, run.isItalic) {
        case (true, true): "___"
        case (true, false): "__"
        case (false, true): "_"
        case (false, false): ""
        }
    }

    private func quoted(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    /// The signed whole numbers in a string, reading Paizo's en dash as a minus sign.
    private static func numbers(in text: String) -> [Int] {
        var numbers: [Int] = []
        var current = ""
        for character in text + " " {
            if character.isNumber {
                current.append(character)
            } else if "+–−-".contains(character), current.isEmpty || current == "-" {
                current = character == "+" ? "" : "-"
            } else {
                if let number = Int(current) { numbers.append(number) }
                current = ""
            }
        }
        return numbers
    }
}
