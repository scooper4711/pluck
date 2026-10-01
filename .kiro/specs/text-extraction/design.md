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

`DocumentProfile` samples pages once for what is true of the whole document:
the body font, text repeated in the same place (running headers and footers),
and hyphenated compounds seen unbroken, whose hyphens are therefore real.

`TextFlow.join` rejoins paragraphs and callouts across consecutive pages.
`TextRenderer` writes `[TextBlock]` as plain text, Markdown or HTML.

## Known limits

- Tables come out as lines or columns of text, not as tables.
- A callout is only found when rules fence it; a sidebar only when something
  is drawn behind or around it.
- Rotated text falls back to size-only styling.
- Heading levels come from type size relative to the body text, so they are
  consistent within a document but not a true outline.
