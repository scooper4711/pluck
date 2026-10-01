import CoreGraphics
import Foundation

// Core Graphics exposes every PDF object as the same untyped `OpaquePointer`.
// These wrappers give each kind its own type and optional-returning accessors.

struct PDFObject {
    let ref: CGPDFObjectRef

    var integer: Int? {
        var value: CGPDFInteger = 0
        return CGPDFObjectGetValue(ref, .integer, &value) ? Int(value) : nil
    }

    /// Integers convert too; Core Graphics widens them when a real is requested.
    var number: CGFloat? {
        var value: CGPDFReal = 0
        return CGPDFObjectGetValue(ref, .real, &value) ? value : nil
    }

    var bool: Bool? {
        var value: CGPDFBoolean = 0
        return CGPDFObjectGetValue(ref, .boolean, &value) ? value != 0 : nil
    }

    var name: String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFObjectGetValue(ref, .name, &value), let value else { return nil }
        return String(cString: value)
    }

    var array: PDFArray? {
        var value: CGPDFArrayRef?
        guard CGPDFObjectGetValue(ref, .array, &value), let value else { return nil }
        return PDFArray(ref: value)
    }

    var dictionary: PDFDictionary? {
        var value: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(ref, .dictionary, &value), let value else { return nil }
        return PDFDictionary(ref: value)
    }

    var stream: PDFStream? {
        var value: CGPDFStreamRef?
        guard CGPDFObjectGetValue(ref, .stream, &value), let value else { return nil }
        return PDFStream(ref: value)
    }

    /// The bytes of a string object.
    var bytes: Data? {
        var value: CGPDFStringRef?
        guard CGPDFObjectGetValue(ref, .string, &value), let value,
              let pointer = CGPDFStringGetBytePtr(value) else { return nil }
        return Data(bytes: pointer, count: CGPDFStringGetLength(value))
    }
}

struct PDFArray {
    let ref: CGPDFArrayRef

    var count: Int { CGPDFArrayGetCount(ref) }

    var numbers: [CGFloat] { (0..<count).compactMap { self[$0]?.number } }

    subscript(index: Int) -> PDFObject? {
        var object: CGPDFObjectRef?
        guard index < count, CGPDFArrayGetObject(ref, index, &object), let object else { return nil }
        return PDFObject(ref: object)
    }
}

struct PDFDictionary: Hashable {
    let ref: CGPDFDictionaryRef

    /// Returns the value under the first key present. Inline images abbreviate their keys
    /// (`W` for `Width`), so callers pass every spelling.
    func object(_ keys: String...) -> PDFObject? {
        for key in keys {
            var object: CGPDFObjectRef?
            if CGPDFDictionaryGetObject(ref, key, &object), let object { return PDFObject(ref: object) }
        }
        return nil
    }
}

struct PDFStream: Hashable {
    let ref: CGPDFStreamRef

    var dictionary: PDFDictionary? { CGPDFStreamGetDictionary(ref).map(PDFDictionary.init) }

    /// The stream's bytes with every filter Core Graphics understands already removed.
    /// JPEG and JPEG 2000 payloads are returned still encoded, as `format` reports.
    func data() -> (bytes: CFData, format: CGPDFDataFormat)? {
        var format = CGPDFDataFormat.raw
        guard let bytes = CGPDFStreamCopyData(ref, &format) else { return nil }
        return (bytes, format)
    }
}
