# iPad app: requirements

Pluck also runs on the iPad. It reads the same images, text and stat blocks out
of a PDF as the Mac app (the `pdf-image-extractor` and `text-extraction` specs),
with the same extraction code; what differs is how the user gets around by touch
and how things leave the app.

## R1 Opening a PDF
- R1.1 With no PDF open, the window offers Open… and Open from Scrollkeeper…,
  as on the Mac.
- R1.2 Open… shows the system file browser for PDFs. The file is read in place;
  it is not copied into Pluck.
- R1.3 Pluck is registered as an app that opens PDFs, so the share sheet of
  Files, Mail, Safari and other apps offers it for a PDF ("Open in Pluck"). The
  PDF opens in the window, replacing the PDF shown.
- R1.4 A PDF dropped on the window opens, as on the Mac.
- R1.5 A window shows one PDF at a time; opening another replaces it.
- R1.7 Open Recent, in the toolbar's Open menu and the menu bar's File menu,
  lists the ten PDFs opened last, newest first, and can be cleared. The list is
  kept between launches and shared by every window. A PDF that has since been
  moved or deleted drops off it.
- R1.6 A password-protected PDF prompts for its password, and a file that is
  not a readable PDF reports an error, as on the Mac.
- R1.8 Close, in the toolbar's Open menu and the menu bar's File menu, closes
  the PDF shown and returns the window to R1.1. It is unavailable when no PDF
  is open.

## R2 Pages
- R2.1 The sidebar lists every page with a thumbnail and its image count.
- R2.2 Tapping a page selects it and tapping it again deselects it, so several
  pages can be selected without a keyboard. Show All Pages clears the selection.
- R2.3 The main view shows the images, or the text, of the selected pages, or of
  every page when none is selected, as on the Mac.

## R3 Images
- R3.1 The images are shown in a grid over a checkerboard, each with its pixel
  size and page, as on the Mac. The grid's thumbnails come in three sizes, and
  images below a chosen size can be hidden.
- R3.2 Tapping an image selects it and tapping it again deselects it. Select All
  and Deselect All are in the toolbar's menu.
- R3.3 Selected images can be rotated and flipped, from the toolbar and from an
  image's menu; the edits carry through to whatever leaves the app.
- R3.4 Touching and holding an image opens its menu: Copy, Quick Look, Export…,
  Show Page in Sidebar, and the rotations and flips. On an image that isn't
  selected the menu acts on that image alone, which becomes the selection.
- R3.5 Copy puts the selected images on the pasteboard as PNG and TIFF, alpha
  intact.
- R3.6 Quick Look previews the selected images, rotated and flipped as shown;
  its share button saves or sends them.
- R3.7 Export writes the selected, or all the shown, images as WebP files into a
  folder chosen in the system file browser, without replacing existing files.
- R3.8 An image can be dragged into another app: Files receives a WebP file,
  apps that take pictures receive PNG data. A drag carries the image it starts
  on.

## R4 Text and stat blocks
- R4.1 The Images/Text switch, the three text formats and the HTML preview work
  as on the Mac. The text can be selected and copied in part.
- R4.2 Copy All copies the text shown; Export saves it as a file through the
  system file browser.
- R4.3 The stat blocks on the shown pages are listed above the text. Tapping one
  copies it; it can be dragged into another app; Copy All copies them all. What
  is copied is the same as on the Mac: the structured block, HTML and plain
  text, so Turnkeeper on the iPad can paste it.

## R5 Open from Scrollkeeper
- R5.1 Open from Scrollkeeper… lists the titles with a PDF from Scrollkeeper's
  library in the Tableside Toolkit's App Group, with covers and the same search
  as on the Mac.
- R5.2 A title Scrollkeeper has downloaded opens straight from the shared
  folder. A title with several PDFs opens the last of them (R1.5).
- R5.3 Scrollkeeper on the iPad takes no requests from other apps, so for a
  title not downloaded yet the button says Download in Scrollkeeper and brings
  Scrollkeeper forward.
- R5.4 The list is read again when Pluck comes back to the foreground and when
  Scrollkeeper says its library changed.
- R5.5 When there is no shared library (Scrollkeeper isn't installed or hasn't
  loaded the library yet), the sheet says so and offers to open Scrollkeeper,
  or to get it when it isn't installed.

## R6 Settings, About and updates
- R6.1 Settings… in the toolbar's menu shows the WebP and text settings of the
  Mac app in a sheet.
- R6.2 About Pluck, in the toolbar's menu and the menu bar's app menu, shows the
  notice Paizo's Community Use Policy prescribes, the trademark line, where to
  reach the author, and libwebp's credit with its license in full.
- R6.3 The toolbar's menu links to the privacy policy.
- R6.4 The iPad app has no updater: it is updated by the App Store or by
  installing a newer build.

## R7 Keyboard and menu bar
- R7.1 With a hardware keyboard, and in the iPad's menu bar, the Mac's commands
  and shortcuts work where they apply: Open… (⌘O), Open from Scrollkeeper…
  (⇧⌘O), Images (⌘1), Text (⌘2), Copy All Stat Blocks (⌥⌘C), Export Selected…
  (⌘E), Export All Shown… (⇧⌘E), Rotate Left (⌘L), Rotate Right (⌘R), the
  flips and Quick Look (⌘Y).
- R7.2 Select All (⌘A) selects every image shown. Over the text, and in a
  search field, it selects the text instead, as the system does.

## R8 Layout and packaging
- R8.1 The sidebar, grid, text and toolbar fit in landscape and portrait.
- R8.2 The iPad app is for the iPad only; it is not offered for the iPhone.
- R8.3 The Mac app keeps working as before.
- R8.4 The iPad app declares the same privacy manifest as the Mac app and
  collects nothing.
