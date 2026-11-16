import PluckKit
import SwiftUI

/// The WebP and text settings: the Mac's Settings window, and a sheet on the iPad.
struct SettingsView: View {
    @AppStorage(WebPOptions.losslessDefaultsKey) private var isLossless = false
    @AppStorage(WebPOptions.qualityDefaultsKey) private var quality = WebPOptions.defaultQuality
    @AppStorage(TextRenderOptions.obsidianCalloutsDefaultsKey) private var usesObsidianCallouts = false
    #if !APP_STORE && os(macOS)
    @AppStorage(AppUpdater.checksAtLaunchKey) private var checksForUpdatesAtLaunch = true
    #endif

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
            #if !APP_STORE && os(macOS)
            updatesSection
            #endif
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 400)
        #endif
    }

    #if !APP_STORE && os(macOS)
    private var updatesSection: some View {
        Section("Updates") {
            Toggle("Check for updates when Pluck opens", isOn: $checksForUpdatesAtLaunch)
            Text("Pluck asks GitHub whether a newer version has been released, and tells you only when there "
                 + "is one. Pluck › Check for Updates… checks at any time.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
    #endif
}
