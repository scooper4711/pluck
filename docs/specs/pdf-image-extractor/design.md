# Pluck — design

## Shape

A Swift package with three targets:

| Target | Role |
| --- | --- |
| `PluckKit` | All logic: PDF scanning, image decoding, de-duplication, edits, WebP/PNG encoding, export, pasteboard, and the observable `PluckModel`. |
| `Pluck` | Thin SwiftUI/AppKit shell: split view, page sidebar, image grid, menus, panels. |
| `PluckKitTests` | Swift Testing suite driving `PluckKit` against PDFs it writes by hand. |

`scripts/build-app.sh` builds the release binary and assembles `build/Pluck.app`, signed ad hoc with
`Resources/Pluck.entitlements` (R7.6): the App Sandbox, network client (GitHub's update check, and WebKit,
whose web content process won't start without it), read-write access to files the user picks, and the
Downloads folder for updates. `Resources/container-migration.plist` goes into the bundle; on the first
sandboxed launch macOS moves the preferences into the container.

## Extraction pipeline

1. **Scan** (`PDFPageScanner`) — walk a page's content stream with
   `CGPDFScanner`, reporting each image actually painted: `Do` on image
   XObjects, recursion into form XObjects and tiling patterns (`scn`/`SCN`),
   and inline images (`EI`). Walking painted content rather than the resource
   dictionary matters because many PDFs share one resource dictionary across
   every page.
2. **Decode** (`PDFImageDecoder`) — turn an image stream into a
   `RasterImage` (8-bit sRGB, straight alpha). JPEG/JPEG 2000 streams go
   through ImageIO. ImageIO reads a four-color (CMYK) JPEG as Photoshop writes
   it, flipping samples an Adobe marker says are inverted; in a PDF the samples
   mean what they say unless the image's `Decode` array inverts them, so such
   images are rebuilt from ImageIO's samples in the PDF's color space with that
   `Decode` array (otherwise they come out as negatives). Raw samples are wrapped in a `CGImage` using the parsed
   color space (`PDFColorSpaceParser`), bit depth and `Decode` array. The
   alpha channel comes from `SMask`, a stencil `Mask` stream, a color-key
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
- A drag carries a WebP file promise per image (`NSFilePromiseProvider`) plus
  PNG data for apps that take pictures rather than files, such as Flip Map
  Printer. The PNG is attached to the drag's pasteboard items through an
  `NSPasteboardItemDataProvider` once the drag begins, and rendered only if a
  drop asks for it. Adding the type by subclassing the promise provider does
  not work: the type is advertised but the data is never requested.

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

## Updates

`PluckKit/Updates`: `AppUpdater` asks GitHub's `releases/latest` for the
repository, compares the tag with the bundle version (`AppVersion`, number by
number) and offers the release's `.dmg`. A 404, which GitHub answers before the
first release, counts as up to date. Builds without a version (0.0.0) skip the
launch check, which would otherwise always find an update. The app shows results
in app-modal alerts (`UpdateAlerts`), so they appear once however many windows
are open; the launch check follows the user default `checksForUpdatesAtLaunch`,
on unless turned off in Settings.

## Preview

`ImageCollectionView.keyDown` hands Space to the window, which renders the
selection with `PluckModel.previewSelection()` (the same `RenderRequest` as Copy)
to PNGs in a new temporary folder and shows them with SwiftUI's
`quickLookPreview`.

## Open from Scrollkeeper

`ScrollkeeperBridge` (PluckKit) holds the window's state. `requestIndex()` opens
`scrollkeeper://index?app=pluck` in the background through `ApplicationLauncher`
(the app's `WorkspaceLauncher` wraps `NSWorkspace`; tests use a fake).
Scrollkeeper writes the list and opens it with Pluck; `AppDelegate` passes files
with the `scrollkeeperindex` extension to `receive(_:)` and the rest to the
document router. `Info.plist` imports the file's type,
`io.github.scooper4711.scrollkeeper.index`, and lists it as a document type, so
Launch Services can open it with Pluck. `ScrollkeeperIndex` mirrors the format
Scrollkeeper defines in its `docs/specs/app-handoff/design.md` and refuses a
newer format version. `open(_:)` asks in the background and records a
`ScrollkeeperRequest`; `Info.plist` registers the `pluck` URL scheme, and the
status links (`isStatusLink`) go to `receiveStatus(_:)`, which moves the request
through requested, downloading, opening or failed, or marks a failed list
request (empty SKU). `ScrollkeeperWindow` is a separate `Window` scene.
Mapsmith has the same search; when a third app needs it, it moves into a shared
package.

## Known limits

- Separation/DeviceN color spaces are approximated (tint functions are not
  evaluated).
- Soft-mask `Matte` pre-blending is not undone.
- Images inside Type 3 fonts and annotations are not reported.
