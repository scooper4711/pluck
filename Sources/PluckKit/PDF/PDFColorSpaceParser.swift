import CoreGraphics
import Foundation

/// A PDF color space translated to Core Graphics.
struct PDFColorSpace {
    let cgColorSpace: CGColorSpace
    /// True when samples are ink amounts standing in for a Separation/DeviceN space,
    /// so a sample of 1 means dark rather than light.
    var isInkAmount = false

    /// Samples stored per pixel; an indexed image stores a single palette index.
    var componentCount: Int {
        cgColorSpace.model == .indexed ? 1 : cgColorSpace.numberOfComponents
    }
}

/// Translates the `ColorSpace` entry of a PDF image into a `PDFColorSpace`.
struct PDFColorSpaceParser {
    private static let maximumNesting = 4

    /// Resolves a color space named in a content stream's resources; only inline images need it.
    var namedResource: (String) -> PDFObject? = { _ in nil }

    func parse(_ object: PDFObject) throws -> PDFColorSpace {
        try parse(object, nesting: 0)
    }

    private func parse(_ object: PDFObject, nesting: Int) throws -> PDFColorSpace {
        guard nesting < Self.maximumNesting else { throw unsupported("color spaces nested too deeply") }
        if let name = object.name { return try namedSpace(name, nesting: nesting) }
        guard let array = object.array, let family = array[0]?.name else {
            throw unsupported("malformed color space")
        }
        switch family {
        case "ICCBased": return try iccBased(array, nesting: nesting)
        case "Indexed", "I": return try indexed(array, nesting: nesting)
        case "Lab": return lab(array)
        case "Separation": return try inkFallback(componentCount: 1, alternate: array[2], nesting: nesting)
        case "DeviceN":
            return try inkFallback(componentCount: array[1]?.array?.count ?? 0, alternate: array[2], nesting: nesting)
        default: return try namedSpace(family, nesting: nesting)
        }
    }

    private func namedSpace(_ name: String, nesting: Int) throws -> PDFColorSpace {
        switch name {
        case "DeviceGray", "G", "CalGray": return PDFColorSpace(cgColorSpace: CGColorSpaceCreateDeviceGray())
        case "DeviceRGB", "RGB", "CalRGB": return PDFColorSpace(cgColorSpace: .standardRGB)
        case "DeviceCMYK", "CMYK": return PDFColorSpace(cgColorSpace: CGColorSpaceCreateDeviceCMYK())
        default:
            guard let resource = namedResource(name) else { throw unsupported("color space \(name)") }
            return try parse(resource, nesting: nesting + 1)
        }
    }

    private func deviceSpace(componentCount: Int) throws -> PDFColorSpace {
        switch componentCount {
        case 1: PDFColorSpace(cgColorSpace: CGColorSpaceCreateDeviceGray())
        case 3: PDFColorSpace(cgColorSpace: .standardRGB)
        case 4: PDFColorSpace(cgColorSpace: CGColorSpaceCreateDeviceCMYK())
        default: throw unsupported("color space with \(componentCount) components")
        }
    }

    private func iccBased(_ array: PDFArray, nesting: Int) throws -> PDFColorSpace {
        guard let stream = array[1]?.stream, let componentCount = stream.dictionary?.object("N")?.integer else {
            throw unsupported("ICC color space without a profile")
        }
        if let profile = stream.data()?.bytes, let space = CGColorSpace(iccData: profile),
           space.numberOfComponents == componentCount {
            return PDFColorSpace(cgColorSpace: space)
        }
        if let alternate = stream.dictionary?.object("Alternate"),
           let space = try? parse(alternate, nesting: nesting + 1), space.componentCount == componentCount {
            return space
        }
        return try deviceSpace(componentCount: componentCount)
    }

    private func indexed(_ array: PDFArray, nesting: Int) throws -> PDFColorSpace {
        guard let baseObject = array[1], let lastIndex = array[2]?.integer, (0...255).contains(lastIndex),
              let lookup = array[3], var table = lookup.bytes ?? (lookup.stream?.data()?.bytes as Data?)
        else { throw unsupported("malformed indexed color space") }
        let base = try parse(baseObject, nesting: nesting + 1)
        let requiredLength = (lastIndex + 1) * base.componentCount
        if table.count < requiredLength { table.append(Data(count: requiredLength - table.count)) }
        let space = table.withUnsafeBytes { bytes in
            CGColorSpace(
                indexedBaseSpace: base.cgColorSpace, last: lastIndex,
                colorTable: bytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        guard let space else { throw unsupported("indexed color space Core Graphics rejects") }
        return PDFColorSpace(cgColorSpace: space)
    }

    private func lab(_ array: PDFArray) -> PDFColorSpace {
        let parameters = array[1]?.dictionary
        let whitePoint = parameters?.object("WhitePoint")?.array?.numbers ?? []
        let blackPoint = parameters?.object("BlackPoint")?.array?.numbers ?? []
        let range = parameters?.object("Range")?.array?.numbers ?? []
        let space = CGColorSpace(
            labWhitePoint: whitePoint.count == 3 ? whitePoint : [0.9642, 1, 0.8249],
            blackPoint: blackPoint.count == 3 ? blackPoint : [0, 0, 0],
            range: range.count == 4 ? range : [-100, 100, -100, 100])
        return PDFColorSpace(cgColorSpace: space ?? .standardRGB)
    }

    /// Approximates a Separation/DeviceN space without evaluating its tint function:
    /// a single ink is drawn as gray, and inks that line up with the alternate space use it directly.
    private func inkFallback(componentCount: Int, alternate: PDFObject?, nesting: Int) throws -> PDFColorSpace {
        if componentCount == 1 {
            return PDFColorSpace(cgColorSpace: CGColorSpaceCreateDeviceGray(), isInkAmount: true)
        }
        guard let alternate, let space = try? parse(alternate, nesting: nesting + 1),
              space.componentCount == componentCount
        else { throw unsupported("\(componentCount)-ink color space") }
        return space
    }

    private func unsupported(_ reason: String) -> PluckError {
        .unsupportedImage(reason: reason)
    }
}
