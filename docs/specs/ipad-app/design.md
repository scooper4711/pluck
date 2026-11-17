# iPad app: design

## Targets
- `PluckUI` (library) holds the SwiftUI app for both platforms: `PluckApp`, the
  views and the commands. Platform code sits behind `#if os(macOS)` /
  `#if os(iOS)`, mostly in files of its own; the iPad's start with `Pad`.
- `Pluck` (Mac executable) is `main.swift` calling `PluckApp.main()`, so
  `scripts/build-app.sh` and the release keep building `Pluck`.
- `ios/Pluck.xcodeproj` (scheme `Pluck-iPad`) is the iPad app. Its only source
  is `ios/App/PluckMain.swift`; it links `PluckUI` from the local package.
  Signing, the version from git (`scripts/version.sh`) and the App Group
  entitlement follow Mapsmith's `ios/` folder. `TARGETED_DEVICE_FAMILY` is 1,2: the
  iPad and the iPhone (R8.2).
- `PluckKit` builds for both. `SystemPasteboard` is `NSPasteboard` or
  `UIPasteboard`; `PasteboardWriter` and `StatBlockExport` write to either, and
  `FormFieldReader` measures with `NSFont` or `UIFont`. The updater is compiled
  for the Mac only (R6.4).
- The privacy manifest is `ios/App/PrivacyInfo.xcprivacy`, a file of the iPad
  app's synchronized folder, which `scripts/build-app.sh` copies into the Mac
  bundle (R8.4).

## What is shared, and what each platform has of its own
Shared: `DocumentDetail` (the empty window, the grid or the text, the status
bar), `DocumentOpening` (the password prompt and drops), `PageSidebar`,
`StatBlockStrip`, `TextOutputView` and `HTMLPreviewView` (each a
representable for either platform), `SettingsView`, `ScrollkeeperBrowser`,
`OpenRecentMenu` and `DocumentCommands`.

Three types exist once per platform with the same surface, so the shared views
use whichever is compiled:

| Type | Mac | iPad |
| --- | --- | --- |
| `AppActions` | modal panels, `DocumentRouter` | says what to present, in `PadPresenter` |
| `ImageGrid` | `NSCollectionView` | `LazyVGrid` |
| `PluckToolbar` | every control in the toolbar | the common ones, the rest in a More menu |

## Scenes
- Mac: unchanged (`WindowGroup(for: URL.self)`, the Open from Scrollkeeper
  window, the Settings scene).
- iPad: one `WindowGroup` whose `PadRootView` owns a `PluckModel` and a
  `PadPresenter`. The presenter holds what the window presents: the file
  browser and what it was opened for (`FileRequest`), the text file being
  saved, Quick Look's files, the three sheets and the last error. `AppActions`
  only sets these, and `PadRootView` presents them. `AboutWindow` is a second
  scene for the menu bar's About item.

## Files the app may only read in place
`AppActions.open` hands the URL to `PadPresenter.access`, which starts
security-scoped access and stops it for the PDF shown before. The PDF is read
as its pages are needed, so access lasts while it is shown. Exporting images
starts and stops access to the chosen folder around the export.

## Sharing PDFs to Pluck
`ios/Info.plist` lists PDF as a document type (viewer, alternate handler) with
`LSSupportsOpeningDocumentsInPlace`, which puts Pluck in the share sheet for a
PDF. The system hands the file to `onOpenURL`.

## Open Recent
`BookmarkedRecentDocuments` (PluckKit) is the iPad's `RecentDocumentStore`: a
bookmark for each PDF in the user defaults, newest first, at most ten. A
bookmark made while the app has access to a file carries the permission to read
it again. One that no longer resolves is left out. `PluckApp` owns the one
`RecentDocuments`; a window notes its PDF when the scan finishes, as on the Mac.

## Selection
A `List` selects several rows by touch only in edit mode, so the iPad's sidebar
toggles `PluckModel.selectedPages` on a tap and draws the selection itself. The
grid does the same for images. An image's menu calls `selectForMenu` first, so
on an unselected image it acts on that image alone.

`SelectAllResponder`, a view behind the grid, takes the keyboard while the grid
is shown and answers ⌘A with a key command that has priority over the system's.
The text view and text fields take the keyboard when tapped, and ⌘A is then
theirs. The responder takes the keyboard again when the selection changes.

## Output
- Copy: `UIPasteboard` items by type identifier, PNG and TIFF for an image; the
  stat block data, HTML and plain text for stat blocks.
- Drag: `ImageDrag` registers a WebP file representation and PNG data on an
  `NSItemProvider`, each made when a drop asks for it. The files are written
  under the temporary folder and removed at the next launch.
- Export of images: the file browser picks a folder and `ImageExporter` writes
  into it. Export of text: the text is written to a temporary file, which
  `.fileMover` moves where the user chooses.
- Quick Look: `.quickLookPreview` on the PNGs of `previewSelection()`.

## Scrollkeeper on the iPad
As in Mapsmith: `PadLauncher` takes no requests, checks for Scrollkeeper with
`canOpenURL("scrollkeeper://")` (listed in `LSApplicationQueriesSchemes`) and
opens it with `UIApplication.open`. The bridge then reads only the shared
library, and `ScrollkeeperBrowser` says Download in Scrollkeeper for a title
not on disk.

## Testing
- Unit tests cover what was added to `PluckKit`: tap selection and the
  bookmarked recent documents. The pasteboard and font code is tested on the
  Mac; its iPad branches are exercised by the UI tests.
- `ios/UITests` runs in an iPad simulator against `UITestSample`, a two-page
  PDF the debug build draws (launch argument `-UITestSample`): the layout in
  both orientations, selection, edits, copying, the image menu, text mode, ⌘A,
  Open Recent and the sheets. Each keeps screenshots in the test results.

## Known limits
- The simulator build is unsigned and has no App Group, so Open from
  Scrollkeeper with a real library is checked on a device.
- After a sheet with a text field closes, ⌘A reaches the grid again only once
  the selection changes.
- With two Pluck windows side by side, each keeps its own PDF; a PDF shared to
  Pluck opens in the window the system chooses.

## iPhone
`PadContentView` reads the horizontal size class itself, outside the split
view, since the columns are compact on the iPad too. The split view collapses
on a compact window; `PadPresenter.compactColumn`, its
`preferredCompactColumn`, starts on the detail so a PDF's images show first.
The sidebar then has a Done button that sets it back to the detail, and Show
Page in Sidebar sets it to the sidebar as well as showing the column.

`PluckToolbar` takes `isCompact`: on a compact window the mode's commands go in
a `.bottomBar` group instead of beside the More menu, which leaves the top bar
Open, the switch and More. The UI tests run on an iPhone simulator with
`make iphone-uitests`; the tests that need the sidebar beside the grid skip
there, and `PhoneLayoutUITests` covers R9.
