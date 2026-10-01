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

## R3 Output
- R3.1 Three formats: plain text, Markdown, HTML.
- R3.2 Any selection of the text can be copied; Copy All copies everything
  shown; Export saves it as `.txt`, `.md` or `.html`.
- R3.3 Markdown info boxes can optionally be written as Obsidian callouts.
