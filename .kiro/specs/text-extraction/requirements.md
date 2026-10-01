# Text extraction: requirements

Pluck offers the text of a PDF the way it offers its images, with structure
that plain copy-and-paste from Preview or Acrobat loses.

## R1 Modes
- R1.1 The main view has two modes, Images and Text; Images works as before.
- R1.2 The page navigator filters Text as it does Images: the selected pages,
  or the whole document when none is selected.

## R2 Reading order and structure
- R2.1 Columns are read one after the other; a full-width heading is read
  before the columns beneath it.
- R2.2 Text wrapped around an illustration stays in its column and paragraph.
- R2.3 Info boxes are kept whole and set apart: sidebars on a filled or
  outlined panel, and passages fenced by rules (read-aloud text).
- R2.4 A paragraph is one line, however many lines, columns or pages it
  spanned. A word hyphenated at a line end is mended; a real hyphen is kept.
- R2.5 Headings are recognised by type size, and bold and italic runs by the
  fonts the PDF actually uses.
- R2.6 Running headers, footers and page numbers are left out.
- R2.7 Text the PDF paints twice in the same place (outlined or shadowed
  type) is read once.
- R2.8 Paizo's action glyphs are written as `pf2:` codes in Markdown and as
  symbols (◆, ◆◆, ◆◆◆, ⤾, ◇) in HTML and plain text.

## R4 Pathfinder stat blocks
- R4.1 A creature or hazard stat block (name and `LEVEL n` / `CREATURE n` /
  `HAZARD n` header, trait boxes, bold-labelled entries) is recognised and kept
  as one block, including when it carries on in the next column or wraps
  around an illustration.
- R4.2 Markdown writes it as a `statblock` code block for the Obsidian plugin
  Fantasy Statblocks in its Basic Pathfinder 2e Layout, following the
  conventions of the user's vault (rarity in `rare_03`, alignment written as
  traits, strikes titled `**Melee** \`pf2:1\` Weapon`).
- R4.3 HTML writes it as `div.statblock` with a heading, a trait list, a
  paragraph per entry and a rule between sections. Plain text lists the
  entries one per line.
- R4.4 In an organised-play scenario the subtier named by the heading above
  is appended to the name, as in `Gwibble (1-2)`.

## R3 Output
- R3.1 Three formats: plain text, Markdown, HTML.
- R3.2 Any selection of the text can be copied; Copy All copies everything
  shown; Export saves it as `.txt`, `.md` or `.html`.
- R3.3 Markdown info boxes can optionally be written as Obsidian callouts.
- R3.4 In HTML an info box is a `div` with class `callout`; read-aloud text is
  a `blockquote`.
- R3.5 The HTML format is shown rendered, not as markup. Copying, whether all
  of it or a selection, still copies the markup.
