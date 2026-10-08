# Pluck — PDF image extractor: requirements

Pluck is a personal native macOS utility that opens a PDF and offers every
image inside it for copying, dragging out, or exporting as WebP.

## R1 Open a PDF
- R1.1 Open through File ▸ Open…, by dropping a PDF on the window, or via
  Finder's "Open With".
- R1.2 A password-protected PDF prompts for its password.
- R1.3 A file that is not a readable PDF reports an error instead of failing
  silently.
- R1.4 Several PDFs can be open at once, each in its own window, as in
  Preview. Opening a PDF that is already open brings its window forward.
- R1.5 File ▸ Open Recent lists recently opened PDFs and can be cleared.

## R2 Page navigator
- R2.1 The left-hand navigator lists every page of the PDF with a thumbnail.
- R2.2 Pages are multi-selectable.
- R2.5 Right-clicking an image offers "Show Page in Sidebar", which scrolls
  the navigator to the page the image is on and marks it briefly. The page
  selection is not changed. For an image on several pages, repeating the
  command steps through them.
- R2.4 Thumbnails fill the navigator's width, growing as it is widened, so a
  page can be read beside its extracted text.
- R2.3 With one page selected, the main view shows only the images on that
  page. With several pages selected it shows the images on those pages. With
  no page selected it shows every image in the document.

## R3 Image extraction
- R3.1 Images are extracted at their native pixel resolution, not re-rendered
  from the page.
- R3.2 Only images a page actually paints are attributed to it, including
  those painted through form XObjects, tiling patterns and inline images.
- R3.3 Transparency is honored: soft masks, stencil masks, color-key masks
  and stencil images all produce an alpha channel.
- R3.3a Colors match the page: CMYK images, JPEG-compressed ones included,
  follow the image's color space and `Decode` array, so none comes out as a
  negative.
- R3.4 An image that cannot be decoded is skipped and counted, never fatal.

## R4 Duplicate detection
- R4.1 Images whose decoded pixels are identical are shown once, however
  many pages or PDF objects they appear in (e.g. page-border decorations).
- R4.2 A de-duplicated image belongs to every page it appears on.
- R4.3 Only exact matches count. Images that merely look alike (re-encoded,
  resized or cropped copies) are different images and are all shown.

## R5 Selection and editing
- R5.1 Images are multi-selectable (click, ⌘/⇧-click, rubber band, ⌘A).
- R5.2 Selected images can be rotated left/right by 90° and flipped
  horizontally/vertically; edits compose and apply to copy, drag and export.

## R6 Output
- R6.1 Copy puts the selected images on the pasteboard, alpha intact.
- R6.2 Dragging images out to Finder creates WebP files; other apps receive
  image data.
- R6.3 Export writes the selected (or all shown) images as WebP files into a
  chosen folder without overwriting existing files.
- R6.4 WebP export keeps the alpha channel; quality and lossless mode are
  configurable in Settings.

## R7 Packaging
- R7.1 Ships as a `.app` bundle with its own name and icon.
- R7.2 Automated tests cover the major workflows (open, page filter,
  de-duplication, transparency, edit, copy, export). An 80% coverage bar is
  explicitly not required for this project.
