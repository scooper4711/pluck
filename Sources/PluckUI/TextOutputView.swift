import SwiftUI

#if os(macOS)
import AppKit

/// The text mode's main view: the extracted text in the chosen format, selectable and searchable,
/// with each paragraph on one (soft-wrapped) line.
struct TextOutputView: NSViewRepresentable {
    let text: String

    func makeNSView(context _: Context) -> NSScrollView {
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

    func updateNSView(_ scrollView: NSScrollView, context _: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }
}
#else
import UIKit

/// The text mode's main view on the iPad: the extracted text in the chosen format, selectable and searchable
/// (⌘F with a keyboard), with each paragraph on one (soft-wrapped) line.
struct TextOutputView: UIViewRepresentable {
    let text: String

    func makeUIView(context _: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isFindInteractionEnabled = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        textView.backgroundColor = .clear
        return textView
    }

    func updateUIView(_ textView: UITextView, context _: Context) {
        guard textView.text != text else { return }
        textView.text = text
    }
}
#endif
