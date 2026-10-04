import PluckKit
import SwiftUI

/// The stat blocks on the shown pages, above the text: click one to copy it, drag it into another app such
/// as Combat Pad, or copy them all.
struct StatBlockStrip: View {
    let model: PluckModel

    var body: some View {
        let blocks = model.visibleStatBlocks
        if !blocks.isEmpty {
            HStack(spacing: 8) {
                Label("Stat blocks", systemImage: "list.bullet.rectangle")
                    .font(.callout.bold())
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            chip(for: block)
                        }
                    }
                }
                Button("Copy All") { model.copyStatBlocks(blocks) }
                    .help("Copy every stat block on these pages")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    private func chip(for block: StatBlock) -> some View {
        Button {
            model.copyStatBlocks([block])
        } label: {
            Text("\(block.displayName) · \(block.level)")
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .onDrag { StatBlockExport.itemProvider(for: [block]) }
        .help("Click to copy, or drag into Combat Pad")
        .contextMenu {
            Button("Copy Stat Block") { model.copyStatBlocks([block]) }
        }
    }
}
