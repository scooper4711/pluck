# Text extraction: design

All in `PluckKit/Text`; the app adds a mode switch, a format picker and a
read-only text view.

## Pipeline, per page

1. **`PDFContentInterpreter`** walks the content stream tracking the graphics
   and text state. It does not decode text. It reports, in page coordinates,
   each shown string's font and baseline extent (`FontSpan`, using the font's
   own glyph widths in `PDFFontMetrics`), filled or outlined shapes
   (`panels`), image placements, and thin horizontal `rules`.
2. **`PageTextReader`** takes characters and their boxes from PDFKit, gives
   each the font of the span its box sits on, and groups them into
   `TextFragment`s: runs on one baseline with no wide gap. PDFKit alone is not
   enough: it substitutes fonts it does not have, losing bold and italic, and
   its `attributedString` hangs on some pages, so it is never asked for one.
3. **`BoxFinder`** assigns fragments to boxes. Candidates are panels and
   images (sidebars) and the area between two matching rules (callouts). Text
   must lie wholly inside and fill the candidate, which separates a sidebar's
   background from an illustration that text merely wraps around. Rules that
   fence mixed text (list rows) are ignored. A lone rule closes or opens a
   callout that continues on the neighbouring page.
4. **`ColumnAnalyzer`** orders the loose fragments and the boxes (as single
   items) by finding gutters: vertical strips separating items that stand
   side by side. Items crossing a gutter either have a band to themselves
   (read in place) or float beside the columns (read after them).
5. **`ParagraphBuilder`** turns each column's lines into headings, list items
   and paragraphs. A new paragraph starts at a change of typeface or size, a
   vertical gap, an indent or short line after a finished sentence, or a bold
   lead-in. Indents and short lines beside an illustration are discounted.
   A paragraph left open at the foot of a column rejoins its continuation.

## Stat blocks

`StatBlockFinder` runs before box and column analysis and claims each stat
block's fragments, so that the rules dividing a block's sections are not taken
for callouts. A block runs from its header down its column until a heading, a
return to the body typeface, or a blank line; lines in the block's typeface at
the top of the next column are moved back into it. `StatBlockParser` splits
the lines into entries: a bold label at the left edge opens one, as does a
bold label pushed aside by an illustration, unless it is a label that only
occurs inside entries (`Damage`, `Fort`, `Cantrips`, a spell level).
`StatBlockYAMLWriter` maps entries onto the Fantasy Statblocks fields.

Paizo's action glyphs arrive from PDFKit as `[one-action]` and similar: one
glyph reported as several characters that all share the glyph's box. The
fragment builder keeps characters with the same box together; without that,
the wide two-action glyph looks like the text jumping backwards and splits its
line into pieces. The tokens become `pf2:` codes in Markdown and symbols in
HTML and plain text.

An encounter roster ("DOCKHAND (2) … CREATURE 0", a page reference, an
initiative) has the same header as a stat block; a block of a known type must
contain one of Perception, AC, HP, Stealth, Disable or Chase Points to count.
A header of an unknown type must be underlined instead.

The rules inside a block divide its sections, so unlabelled text straight
after one starts a description entry rather than continuing the entry above.
When the document's body text shares the stat blocks' typeface, a block is
only continued into the next column if it was visibly cut off: it ended on a
rule or in mid-sentence. The continuation then runs to the first blank line.

## Overprinted text

Outlined and shadowed type is painted twice, and PDFKit reports both copies.
`OverprintedSpans` finds font spans that coincide, lets the first copy's
characters through, and drops what follows in the same place. Matching
characters by their boxes alone is not safe: a ligature's letters share one
box, so "ff" would lose an f.

## HTML preview

The app shows HTML in a `WKWebView` (`HTMLPreviewView`) wrapped in a page that
supplies display-only styling. A `copy` handler in that page replaces the
pasteboard contents with the selection's own markup.

`DocumentProfile` samples pages once for what is true of the whole document:
the body font, text repeated in the same place (running headers and footers),
and hyphenated compounds seen unbroken, whose hyphens are therefore real.

`TextFlow.join` rejoins paragraphs and callouts across consecutive pages.
`TextRenderer` writes `[TextBlock]` as plain text, Markdown or HTML.

## Known limits

- A stat block that carries on over a page break loses its tail to ordinary
  paragraphs, and some blocks that wrap tightly around art lose entries.
- Hazards use the creature layout's fields; the plugin has a separate hazard
  layout that is not targeted.
- The `source` field is only filled when the PDF declares a real title.
- Tables come out as lines or columns of text, not as tables.
- A callout is only found when rules fence it; a sidebar only when something
  is drawn behind or around it.
- Rotated text falls back to size-only styling.
- Heading levels come from type size relative to the body text, so they are
  consistent within a document but not a true outline.
