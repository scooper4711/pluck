import Foundation

/// The markup extracted text is delivered in.
public enum TextFormat: String, CaseIterable, Identifiable, Sendable {
    case plain
    case markdown
    case html

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .plain: "Plain Text"
        case .markdown: "Markdown"
        case .html: "HTML"
        }
    }

    public var fileExtension: String {
        switch self {
        case .plain: "txt"
        case .markdown: "md"
        case .html: "html"
        }
    }
}

public struct TextRenderOptions: Equatable, Sendable {
    public static let obsidianCalloutsDefaultsKey = "textObsidianCallouts"

    /// Writes Markdown info boxes as Obsidian callouts (`> [!info] Title`) instead of plain quotes.
    public var usesObsidianCallouts: Bool

    public init(usesObsidianCallouts: Bool = false) {
        self.usesObsidianCallouts = usesObsidianCallouts
    }

    public init(defaults: UserDefaults) {
        self.init(usesObsidianCallouts: defaults.bool(forKey: Self.obsidianCalloutsDefaultsKey))
    }
}

/// Writes blocks out as plain text, Markdown or HTML. Every paragraph is a single line.
public struct TextRenderer: Sendable {
    public let format: TextFormat
    public let options: TextRenderOptions

    public init(format: TextFormat, options: TextRenderOptions = TextRenderOptions()) {
        self.format = format
        self.options = options
    }

    public func render(_ blocks: [TextBlock]) -> String {
        switch format {
        case .plain: PlainTextWriter.render(blocks)
        case .markdown: MarkdownWriter(options: options).render(blocks)
        case .html: HTMLWriter.render(blocks)
        }
    }
}

/// Joins rendered blocks with a blank line between them, but keeps list items together.
private func joinedBlocks(_ blocks: [TextBlock], _ render: (TextBlock) -> String) -> String {
    var output = ""
    for (index, block) in blocks.enumerated() {
        if index > 0 { output += isListItem(block) && isListItem(blocks[index - 1]) ? "\n" : "\n\n" }
        output += render(block)
    }
    return output
}

private func isListItem(_ block: TextBlock) -> Bool {
    if case .listItem = block { true } else { false }
}

/// A run split into the spaces around it and the text between. Emphasis markers must hug the
/// text, so both markup writers put the spaces outside them.
private struct EmphasisParts {
    let leading: String
    let core: String
    let trailing: String

    init(of run: TextRun) {
        let leading = String(run.text.prefix { $0 == " " })
        let isBlank = leading.count == run.text.count
        trailing = isBlank ? "" : String(run.text.reversed().prefix { $0 == " " })
        core = String(run.text.dropFirst(leading.count).dropLast(trailing.count))
        self.leading = leading
    }
}

private enum PlainTextWriter {
    static func render(_ blocks: [TextBlock]) -> String {
        joinedBlocks(blocks) { block in
            switch block {
            case .heading(_, let runs), .paragraph(let runs): runs.text
            case .listItem(let runs): "• " + runs.text
            case .box(let box): render(box.blocks)
            }
        }
    }
}

private struct MarkdownWriter {
    private static let escaped: Set<Character> = ["\\", "*", "_", "`", "[", "]", "<"]

    let options: TextRenderOptions

    func render(_ blocks: [TextBlock]) -> String {
        joinedBlocks(blocks) { block in
            switch block {
            case .heading(let level, let runs):
                // A heading is already emphasised; only its italics are kept.
                String(repeating: "#", count: level) + " "
                    + inline(runs.map { TextRun($0.text, isItalic: $0.isItalic) })
            case .paragraph(let runs): protectingLineStart(inline(runs))
            case .listItem(let runs): "- " + inline(runs)
            case .box(let box): quote(box)
            }
        }
    }

    private func quote(_ box: TextBox) -> String {
        var blocks = box.blocks
        var lines: [String] = []
        if options.usesObsidianCallouts {
            var title = ""
            if case .heading(_, let runs) = blocks.first {
                title = " " + runs.text
                blocks.removeFirst()
            }
            lines.append("[!\(box.kind == .sidebar ? "info" : "quote")]" + title)
        }
        lines += render(blocks).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
    }

    private func inline(_ runs: [TextRun]) -> String {
        runs.map { run in
            let marker = run.isBold && run.isItalic ? "***" : run.isBold ? "**" : run.isItalic ? "*" : ""
            let parts = EmphasisParts(of: run)
            guard !marker.isEmpty, !parts.core.isEmpty else { return escape(run.text) }
            return parts.leading + marker + escape(parts.core) + marker + parts.trailing
        }.joined()
    }

    private func escape(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            if Self.escaped.contains(character) { result.append("\\") }
            result.append(character)
        }
    }

    /// Stops a paragraph that happens to begin like a heading, quote or list from becoming one.
    private func protectingLineStart(_ text: String) -> String {
        let startsBlock = ["# ", "> ", "- ", "+ "].contains { text.hasPrefix($0) }
        let digits = text.prefix { $0.isNumber }
        let startsNumberedItem = !digits.isEmpty && text.dropFirst(digits.count).hasPrefix(". ")
        if startsNumberedItem { return digits + "\\" + text.dropFirst(digits.count) }
        return startsBlock ? "\\" + text : text
    }
}

private enum HTMLWriter {
    static func render(_ blocks: [TextBlock]) -> String {
        var output: [String] = []
        var listItems: [String] = []
        func flushList() {
            if !listItems.isEmpty { output.append("<ul>\n" + listItems.joined(separator: "\n") + "\n</ul>") }
            listItems = []
        }
        for block in blocks {
            if case .listItem(let runs) = block {
                listItems.append("<li>" + inline(runs) + "</li>")
                continue
            }
            flushList()
            output.append(render(block))
        }
        flushList()
        return output.joined(separator: "\n")
    }

    private static func render(_ block: TextBlock) -> String {
        switch block {
        case .heading(let level, let runs):
            "<h\(level)>" + inline(runs.map { TextRun($0.text, isItalic: $0.isItalic) }) + "</h\(level)>"
        case .paragraph(let runs), .listItem(let runs):
            "<p>" + inline(runs) + "</p>"
        case .box(let box):
            wrap(render(box.blocks), in: box.kind == .sidebar ? "aside" : "blockquote")
        }
    }

    private static func wrap(_ content: String, in tag: String) -> String {
        "<\(tag)>\n\(content)\n</\(tag)>"
    }

    private static func inline(_ runs: [TextRun]) -> String {
        runs.map { run in
            let parts = EmphasisParts(of: run)
            guard !parts.core.isEmpty else { return escape(run.text) }
            var text = escape(parts.core)
            if run.isItalic { text = "<em>\(text)</em>" }
            if run.isBold { text = "<strong>\(text)</strong>" }
            return parts.leading + text + parts.trailing
        }.joined()
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
