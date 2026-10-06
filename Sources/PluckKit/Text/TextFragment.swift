import CoreGraphics
import Foundation

/// The font a character is set in.
struct CharacterStyle: Hashable {
    var fontName: String
    var size: CGFloat
    var isBold: Bool
    var isItalic: Bool

    /// The font name without its weight or slant: `SabonLTStd-Bold` belongs to `SabonLTStd`.
    var family: String { fontName.split(separator: "-").first.map(String.init) ?? fontName }
}

struct StyledCharacter {
    let text: String
    let style: CharacterStyle
}

/// A run of characters on one baseline with no large gap: a line, or a line's share of a column.
///
/// Frames use reading coordinates: origin at the page's top-left, y growing downwards.
struct TextFragment {
    var frame: CGRect
    var characters: [StyledCharacter]

    var text: String { characters.map(\.text).joined() }

    /// The style most of the fragment is set in.
    var style: CharacterStyle {
        let counts = Dictionary(grouping: characters, by: \.style).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key
            ?? CharacterStyle(fontName: "", size: frame.height, isBold: false, isItalic: false)
    }

    var runs: [TextRun] {
        var runs: [TextRun] = []
        for character in characters {
            runs.appendMerging(TextRun(
                character.text, isBold: character.style.isBold, isItalic: character.style.isItalic))
        }
        return runs
    }

    /// The same characters in the plain face of a document's body text.
    func restyled(as body: BodyStyle) -> TextFragment {
        let style = CharacterStyle(fontName: body.family, size: body.size, isBold: false, isItalic: false)
        return TextFragment(frame: frame, characters: characters.map { StyledCharacter(text: $0.text, style: style) })
    }

    /// Joins fragments that sit on the same baseline into one line, left to right.
    static func line(from fragments: [TextFragment]) -> TextFragment {
        let ordered = fragments.sorted { $0.frame.minX < $1.frame.minX }
        var line = ordered[0]
        for fragment in ordered.dropFirst() {
            line.characters.append(StyledCharacter(text: " ", style: fragment.characters[0].style))
            line.characters.append(contentsOf: fragment.characters)
            line.frame = line.frame.union(fragment.frame)
        }
        return line
    }
}

/// Text in reading order, before it is broken into paragraphs.
indirect enum FlowElement {
    /// Consecutive lines of one column, top to bottom.
    case lines([TextFragment])
    case box(TextBox.Kind, [FlowElement])
    case statBlock(StatBlockRegion)
}
