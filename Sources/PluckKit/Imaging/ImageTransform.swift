import CoreGraphics
import Foundation

/// A single step the user can apply to an image.
public enum ImageEdit: CaseIterable, Sendable {
    case rotateLeft
    case rotateRight
    case flipHorizontal
    case flipVertical
}

/// One of the eight right-angle orientations: mirror left-to-right, then turn clockwise.
public struct ImageTransform: Hashable, Sendable {
    public static let identity = ImageTransform()

    public private(set) var isMirrored = false
    public private(set) var quarterTurns = 0

    public init() {}

    public var isIdentity: Bool { self == .identity }

    private var swapsDimensions: Bool { quarterTurns % 2 == 1 }

    /// The orientation reached by performing `edit` on an image already in this orientation.
    public func applying(_ edit: ImageEdit) -> ImageTransform {
        var result = self
        switch edit {
        case .rotateRight:
            result.quarterTurns = (quarterTurns + 1) % 4
        case .rotateLeft:
            result.quarterTurns = (quarterTurns + 3) % 4
        case .flipHorizontal:
            // A mirror applied after a turn equals the opposite turn applied after the mirror.
            result.isMirrored.toggle()
            result.quarterTurns = (4 - quarterTurns) % 4
        case .flipVertical:
            result = applying(.flipHorizontal).applying(.rotateRight).applying(.rotateRight)
        }
        return result
    }

    public func apply(to image: RasterImage) throws -> RasterImage {
        guard !isIdentity else { return image }
        return try RasterImage(cgImage: apply(to: image.makeCGImage()))
    }

    public func apply(to image: CGImage) throws -> CGImage {
        guard !isIdentity else { return image }
        let width = swapsDimensions ? image.height : image.width
        let height = swapsDimensions ? image.width : image.height
        guard let context = CGContext.rgba(width: width, height: height, data: nil) else {
            throw PluckError.renderingFailed(operation: "creating a canvas to rotate an image")
        }
        context.interpolationQuality = .none
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: -CGFloat(quarterTurns) * .pi / 2)
        context.scaleBy(x: isMirrored ? -1 : 1, y: 1)
        context.draw(image, in: CGRect(
            x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
            width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let transformed = context.makeImage() else {
            throw PluckError.renderingFailed(operation: "rotating an image")
        }
        return transformed
    }
}
