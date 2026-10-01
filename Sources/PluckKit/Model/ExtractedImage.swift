import CoreGraphics
import Foundation

/// One distinct picture found in a PDF, however many times the PDF paints it.
public struct ExtractedImage: Identifiable, @unchecked Sendable {
    /// Hash of the decoded pixels; equal pictures share an id.
    public let id: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let thumbnail: CGImage
    /// Where the full-resolution pixels can be decoded from again.
    public let locator: ImageLocator
    /// Every page that paints this picture, ascending.
    public internal(set) var pageIndexes: [Int] = []

    public var longestSide: Int { max(pixelWidth, pixelHeight) }
}
