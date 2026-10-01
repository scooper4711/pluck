import Foundation

/// Every failure Pluck reports, each naming the operation that failed and why.
public enum PluckError: Error, Equatable {
    case cannotOpenDocument(URL)
    case passwordRequired
    case unsupportedImage(reason: String)
    case renderingFailed(operation: String)
    case encodingFailed(format: String, reason: String)
    case imageNotFound(page: Int, occurrence: Int)
    case noDocument(operation: String)
}

extension PluckError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cannotOpenDocument(let url):
            "Opening “\(url.lastPathComponent)” failed: it is not a readable PDF."
        case .passwordRequired:
            "Opening the PDF failed: it needs a password."
        case .unsupportedImage(let reason):
            "Decoding a PDF image failed: \(reason)."
        case .renderingFailed(let operation):
            "Rendering failed while \(operation)."
        case .encodingFailed(let format, let reason):
            "Encoding \(format) failed: \(reason)."
        case .imageNotFound(let page, let occurrence):
            "Loading image \(occurrence + 1) on page \(page + 1) failed: the page no longer paints it."
        case .noDocument(let operation):
            "Cannot \(operation): no PDF is open."
        }
    }
}
