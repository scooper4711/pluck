# Pluck

<img src="Resources/AppIcon.png" width="128" alt="Pluck icon">

A native macOS utility that opens a PDF and offers up every image inside it.

- **Page navigator** — thumbnails of every page down the left. Select one or
  more pages to see only their images; select none to see them all.
- **Real images** — extracted at their native resolution with transparency
  intact (soft masks, stencil masks, colour-key masks), not re-rendered.
- **No duplicates** — an image repeated across pages (borders, backgrounds)
  is shown once, labelled with how many pages use it.
- **Several PDFs at once** — each in its own window, with File ▸ Open Recent.
- **Multi-select** — click, ⌘/⇧-click, rubber-band or ⌘A.
- **Rotate and flip** — ⌘L / ⌘R and the Image menu; edits carry through to
  whatever leaves the app.
- **Get them out** — ⌘C copies (PNG/TIFF), dragging to Finder drops `.webp`
  files, and ⌘E / ⇧⌘E exports the selection or everything shown as WebP.
- **Settings** (⌘,) — WebP quality, or lossless.

## Build

Requires Xcode 16 or later on macOS 15 or later.

```sh
scripts/build-app.sh             # builds dist/Pluck.app
scripts/build-app.sh --install   # ...and copies it to /Applications
```

`swift run Pluck` runs it unbundled for development.

## Test

```sh
swift test
swiftlint --strict
```

The tests write their own PDFs object by object (`Tests/PluckKitTests/Support/PDFBuilder.swift`),
so every colour space, mask type and nesting case is exercised deterministically.

## Layout

- `Sources/PluckKit` — extraction, de-duplication, edits, encoding, export and the `PluckModel`.
- `Sources/Pluck` — the SwiftUI/AppKit shell.
- `scripts/make-icon.sh` — regenerates the icon from `scripts/make-icon.swift`.
- `.kiro/specs/pdf-image-extractor` — requirements, design and known limits.
