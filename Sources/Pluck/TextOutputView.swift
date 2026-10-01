import AppKit
import SwiftUI

/// The text mode's main view: the extracted text in the chosen format, selectable and searchable,
/// with each paragraph on one (soft-wrapped) line.
struct TextOutputView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        // Plain text only, so copying a selection gives exactly the characters shown.
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize + 1)
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.drawsBackground = false
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }
}
