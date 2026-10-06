import CoreGraphics
import Foundation

enum PDFDocumentOpener {
    /// Opens and unlocks a PDF. Each caller gets its own `CGPDFDocument`, which is not thread-safe.
    static func open(_ url: URL, password: String = "") throws -> CGPDFDocument {
        guard let document = CGPDFDocument(url as CFURL) else {
            throw PluckError.cannotOpenDocument(url)
        }
        // Many PDFs are encrypted with an empty user password purely to carry permissions.
        let isUnlocked = document.isUnlocked
            || document.unlockWithPassword("")
            || document.unlockWithPassword(password)
        guard isUnlocked else { throw PluckError.passwordRequired }
        return document
    }
}
