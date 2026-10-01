# Pluck — design

## Shape

A Swift package with three targets:

| Target | Role |
| --- | --- |
| `PluckKit` | All logic: PDF scanning, image decoding, de-duplication, edits, WebP/PNG encoding, export, pasteboard, and the observable `PluckModel`. |
| `Pluck` | Thin SwiftUI/AppKit shell: split view, page sidebar, image grid, menus, panels. |
| `PluckKitTests` | Swift Testing suite driving `PluckKit` against PDFs it writes by hand. |

`scripts/build-app.sh` builds the release binary and assembles `dist/Pluck.app`.

## Extraction pipeline

1. **Scan** (`PDFPageScanner`) — walk a page's content stream with
   `CGPDFScanner`, reporting each image actually painted: `Do` on image
   XObjects, recursion into form XObjects and tiling patterns (`scn`/`SCN`),
   and inline images (`EI`). Walking painted content rather than the resource
   dictionary matters because many PDFs share one resource dictionary across
   every page.
2. **Decode** (`PDFImageDecoder`) — turn an image stream into a
   `RasterImage` (8-bit sRGB, straight alpha). JPEG/JPEG 2000 streams go
   through ImageIO; raw samples are wrapped in a `CGImage` using the parsed
   colour space (`PDFColorSpaceParser`), bit depth and `Decode` array. The
   alpha channel comes from `SMask`, a stencil `Mask` stream, a colour-key
   `Mask` array, or the image being a stencil itself.
3. **De-duplicate** (`ImageLibrary`) — the image identity is the SHA-256 of
   its decoded pixels. The library keeps one `ExtractedImage` per identity and
   records every page it appears on. `PDFImageSource` also remembers which
   stream produced which identity, so a border repeated on 300 pages is only
   decoded once.

Only a thumbnail of each image stays in memory. Full-resolution pixels are
re-decoded on demand from an `ImageLocator` (page index + occurrence index).

## Editing

`ImageTransform` models the eight orientations as "mirror, then N clockwise
quarter turns". `applying(_:)` composes a new `ImageEdit` on top. The transform
is applied to thumbnails for display and to full-size pixels on output.

## Output

- `WebPEncoder` wraps libwebp (statically linked through SwiftPM); ImageIO
  cannot write WebP.
- `ImageExporter` renders a `RenderRequest` and writes a uniquely named
  `.webp`; used by both Export and drag-out file promises.
- `PasteboardWriter` puts PNG + TIFF per image on the pasteboard, because
  few apps accept WebP pasted.

## Concurrency

`PDFImageSource` and `PDFPageThumbnailer` each own a private `CGPDFDocument`
guarded by a lock, so they can be called synchronously from drag callbacks and
from detached tasks. `PluckModel` is `@MainActor` and scans one page per
detached task so the UI fills in progressively.

## Windows

`WindowGroup(for: URL.self)` gives one window per PDF, each with its own
`PluckModel`; SwiftUI brings the existing window forward when a URL is opened
twice. Every open request (File ▸ Open, Open Recent, Finder, a drop) goes
through `DocumentRouter`: whichever window sees the pending URLs first opens a
window for each. The empty window shown at launch closes as soon as any
document window exists. File-open events are taken from the app delegate, not
SwiftUI's `onOpenURL`, which loses files when several arrive together.

`RecentDocuments` backs File ▸ Open Recent with the system recent-documents
list (so the Dock menu shows them too) but keeps its own ordered copy, because
the system list updates late.

## UI

`NavigationSplitView`: a SwiftUI `List` of pages (multi-select) and an
`NSCollectionView` grid. The grid is AppKit because it provides rubber-band
selection and multi-item drag with file promises.

## Known limits

- Separation/DeviceN colour spaces are approximated (tint functions are not
  evaluated).
- Soft-mask `Matte` pre-blending is not undone.
- Images inside Type 3 fonts and annotations are not reported.
