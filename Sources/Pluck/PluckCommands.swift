import PluckKit
import SwiftUI

struct PluckCommands: Commands {
    let actions: AppActions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…", action: actions.chooseDocument)
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .importExport) {
            Button("Export Selected…", action: actions.exportSelection)
                .keyboardShortcut("e")
            Button("Export All Shown…", action: actions.exportVisible)
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandMenu("Image") {
            Button("Rotate Left") { actions.apply(.rotateLeft) }
                .keyboardShortcut("l")
            Button("Rotate Right") { actions.apply(.rotateRight) }
                .keyboardShortcut("r")
            Divider()
            Button("Flip Horizontal") { actions.apply(.flipHorizontal) }
            Button("Flip Vertical") { actions.apply(.flipVertical) }
        }
    }
}

struct SettingsView: View {
    @AppStorage(WebPOptions.losslessDefaultsKey) private var isLossless = false
    @AppStorage(WebPOptions.qualityDefaultsKey) private var quality = WebPOptions.defaultQuality

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
        }
        .formStyle(.grouped)
        .frame(width: 400)
    }
}
