import SwiftUI
import WebKit

/// The text mode's view for HTML: the markup rendered as a page. Copying a selection puts the
/// markup of that selection on the pasteboard, not the rendered text.
struct HTMLPreviewView: NSViewRepresentable {
    /// The HTML to show: block elements only, with no `<html>` or `<body>` wrapper.
    let markup: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.allowsMagnification = true
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_: WKWebView, context: Context) {
        context.coordinator.show(markup)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        /// Pages arrive one at a time while a document is read; reloading for each would flicker.
        private static let settleDelay: Duration = .milliseconds(120)

        weak var webView: WKWebView?
        private var shown: String?
        private var pending: Task<Void, Never>?

        func show(_ markup: String) {
            guard markup != shown else { return }
            shown = markup
            pending?.cancel()
            pending = Task { [weak self] in
                try? await Task.sleep(for: Self.settleDelay)
                guard !Task.isCancelled else { return }
                self?.webView?.loadHTMLString(HTMLPreviewPage.document(around: markup), baseURL: nil)
            }
        }

        /// The preview shows only the page it was given: text from a PDF never takes it anywhere else.
        func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            action.navigationType == .other && action.targetFrame?.isMainFrame == true ? .allow : .cancel
        }
    }
}

/// The page the preview wraps around the extracted markup. Its styling is for display only and
/// is never part of what is copied or exported.
enum HTMLPreviewPage {
    static func document(around markup: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><style>\(style)</style></head>
        <body>
        \(markup)
        <script>\(copyScript)</script>
        </body></html>
        """
    }

    /// Replaces what a copy puts on the pasteboard with the selection's own HTML source.
    private static let copyScript = """
        document.addEventListener('copy', event => {
            const selection = window.getSelection();
            if (!selection.rangeCount || selection.isCollapsed) { return; }
            const holder = document.createElement('div');
            for (let index = 0; index < selection.rangeCount; index++) {
                holder.appendChild(selection.getRangeAt(index).cloneContents());
            }
            event.clipboardData.setData('text/plain', holder.innerHTML.trim());
            event.preventDefault();
        });
        """

    private static let style = """
        :root { color-scheme: light dark; --accent: #5d0000; --trim: #d8c483; }
        body { font: 14px/1.5 -apple-system, sans-serif; margin: 18px 22px; max-width: 46em; }
        h1, h2, h3, h4 { line-height: 1.2; margin: 1.2em 0 0.4em; }
        p { margin: 0.6em 0; }
        blockquote { margin: 1em 0; padding: 0.1em 1em; border-left: 3px solid #2e7d5b;
                     color: #2e7d5b; }
        .callout { margin: 1em 0; padding: 0.2em 1em; border-radius: 6px;
                   background: rgba(127, 127, 127, 0.14); border-left: 4px solid rgba(127, 127, 127, 0.6); }
        .statblock { margin: 1.2em 0; padding: 0.3em 0 0.5em; border-top: 2px solid var(--accent);
                     border-bottom: 2px solid var(--accent); }
        .statblock h3 { display: flex; justify-content: space-between; margin: 0.2em 0;
                        text-transform: uppercase; }
        .statblock .traits { display: flex; flex-wrap: wrap; list-style: none; margin: 0 0 0.4em; padding: 0; }
        .statblock .traits li { background: var(--accent); color: white; border: 2px solid var(--trim);
                                font-size: 11px; font-weight: bold; padding: 1px 7px; text-transform: uppercase; }
        .statblock p { margin: 1px 0; padding-left: 1.2em; text-indent: -1.2em; }
        .statblock hr { border: 0; border-top: 1px solid var(--accent); margin: 4px 0; }
        """
}
