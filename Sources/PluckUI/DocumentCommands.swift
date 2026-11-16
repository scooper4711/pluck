import PluckKit
import SwiftUI

/// The menu commands that act on the frontmost document window, on the Mac and in the iPad's menu bar.
struct DocumentCommands: Commands {
    /// The frontmost document window's commands; `nil` when no document window has focus.
    @FocusedValue(\.documentActions) private var actions

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Copy All Stat Blocks") { actions?.copyStatBlocks() }
                .keyboardShortcut("c", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .importExport) {
            Button("Export Selected…") { actions?.exportSelection() }
                .keyboardShortcut("e")
            Button("Export All Shown…") { actions?.exportVisible() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandGroup(before: .sidebar) {
            Button("Images") { actions?.show(.images) }
                .keyboardShortcut("1")
            Button("Text") { actions?.show(.text) }
                .keyboardShortcut("2")
            Divider()
        }
        CommandMenu("Image") {
            Button("Rotate Left") { actions?.apply(.rotateLeft) }
                .keyboardShortcut("l")
            Button("Rotate Right") { actions?.apply(.rotateRight) }
                .keyboardShortcut("r")
            Divider()
            Button("Flip Horizontal") { actions?.apply(.flipHorizontal) }
            Button("Flip Vertical") { actions?.apply(.flipVertical) }
            #if os(iOS)
            // The Mac's grid has these built in: ⌘A, a click on the background, and Space.
            Divider()
            // ⌘A is the system's Edit ▸ Select All, which reaches the images through the grid's `SelectAllResponder`.
            Button("Select All Images") { actions?.model.selectAllVisibleImages() }
            Button("Deselect All Images") { actions?.model.selectedImageIDs = [] }
            Button("Quick Look") { actions?.quickLook() }
                .keyboardShortcut("y")
            #endif
        }
    }
}

extension FocusedValues {
    /// The commands of the frontmost document window, for the menu bar.
    @Entry var documentActions: AppActions?
}

enum AppLinks {
    // A literal URL that is known to parse.
    // swiftlint:disable:next force_unwrapping
    static let privacyPolicy = URL(string: "https://github.com/scooper4711/pluck/blob/main/PRIVACY.md")!
}
