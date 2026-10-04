import PluckKit
import SwiftUI

struct PluckCommands: Commands {
    let router: DocumentRouter
    @ObservedObject var recents: RecentDocuments
    /// The frontmost document window's commands; `nil` when no document window has focus.
    @FocusedValue(\.documentActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { router.open(DocumentPanel.choosePDFs()) }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(recents.urls, id: \.self) { url in
                    Button(url.lastPathComponent) { router.open([url]) }
                }
                Divider()
                Button("Clear Menu", action: recents.clear)
                    .disabled(recents.urls.isEmpty)
            }
        }
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
        }
    }
}

struct SettingsView: View {
    @AppStorage(WebPOptions.losslessDefaultsKey) private var isLossless = false
    @AppStorage(WebPOptions.qualityDefaultsKey) private var quality = WebPOptions.defaultQuality
    @AppStorage(TextRenderOptions.obsidianCalloutsDefaultsKey) private var usesObsidianCallouts = false

    var body: some View {
        Form {
            Section("WebP Export") {
                Toggle("Lossless", isOn: $isLossless)
                Slider(value: $quality, in: 10...100, step: 5) {
                    Text("Quality: \(Int(quality))")
                }
                .disabled(isLossless)
                Text("Transparency is always kept. Lossless files are exact but much larger for photos.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Text") {
                Toggle("Write Markdown info boxes as Obsidian callouts", isOn: $usesObsidianCallouts)
                Text("Off: a plain block quote. On: “> [!info] Title”, and “> [!quote]” for read-aloud text.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
    }
}
