import CoreGraphics
import Foundation

/// The operands of the operator being handled. They pop in reverse order, so each accessor
/// takes the last remaining operand(s).
struct PDFOperands {
    let scanner: CGPDFScannerRef

    func number() -> CGFloat? {
        var value: CGPDFReal = 0
        return CGPDFScannerPopNumber(scanner, &value) ? value : nil
    }

    /// Pops up to `count` numbers and returns them in the order they were written.
    func numbers(count: Int = .max) -> [CGFloat] {
        var values: [CGFloat] = []
        while values.count < count, let value = number() { values.append(value) }
        return values.reversed()
    }

    func matrix() -> CGAffineTransform? {
        let values = numbers(count: 6)
        guard values.count == 6 else { return nil }
        return CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
    }

    func name() -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFScannerPopName(scanner, &value), let value else { return nil }
        return String(cString: value)
    }

    func string() -> Data? {
        var value: CGPDFStringRef?
        guard CGPDFScannerPopString(scanner, &value), let value, let bytes = CGPDFStringGetBytePtr(value)
        else { return nil }
        return Data(bytes: bytes, count: CGPDFStringGetLength(value))
    }

    func textArray() -> [PDFTextPiece] {
        var value: CGPDFArrayRef?
        guard CGPDFScannerPopArray(scanner, &value), let value else { return [] }
        let array = PDFArray(ref: value)
        return (0..<array.count).compactMap { index in
            guard let element = array[index] else { return nil }
            if let bytes = element.bytes { return .string(bytes) }
            return element.number.map(PDFTextPiece.adjustment)
        }
    }
}

/// Maps PDF operators to `PDFContentInterpreter` methods. Core Graphics wants plain C function
/// pointers, so each entry is a closure that captures nothing and finds the interpreter through
/// the scanner's context pointer.
enum PDFOperatorTable {
    private typealias Interpreter = PDFContentInterpreter
    private typealias Handler = @convention(c) (CGPDFScannerRef, UnsafeMutableRawPointer?) -> Void

    static func make() -> CGPDFOperatorTableRef {
        let table = CGPDFOperatorTableCreate()!
        for (name, handler) in stateHandlers + pathHandlers + textHandlers {
            CGPDFOperatorTableSetCallback(table, name, handler)
        }
        return table
    }

    private static func target(_ info: UnsafeMutableRawPointer?) -> Interpreter? {
        info.map { Unmanaged<Interpreter>.fromOpaque($0).takeUnretainedValue() }
    }

    private static let stateHandlers: [(String, Handler)] = [
        ("q", { _, info in target(info)?.saveState() }),
        ("Q", { _, info in target(info)?.restoreState() }),
        ("cm", { scanner, info in target(info)?.concatenate(PDFOperands(scanner: scanner)) }),
        ("w", { scanner, info in target(info)?.setLineWidth(PDFOperands(scanner: scanner)) }),
        ("g", { scanner, info in target(info)?.setFillColor(PDFOperands(scanner: scanner), isSubtractive: false) }),
        ("rg", { scanner, info in target(info)?.setFillColor(PDFOperands(scanner: scanner), isSubtractive: false) }),
        ("k", { scanner, info in target(info)?.setFillColor(PDFOperands(scanner: scanner), isSubtractive: true) }),
        ("sc", { scanner, info in target(info)?.setGenericFillColor(PDFOperands(scanner: scanner)) }),
        ("scn", { scanner, info in target(info)?.setGenericFillColor(PDFOperands(scanner: scanner)) }),
        ("Do", { scanner, info in target(info)?.paintXObject(PDFOperands(scanner: scanner)) }),
        ("EI", { _, info in target(info)?.addImage() })
    ]

    private static let pathHandlers: [(String, Handler)] = [
        ("m", { scanner, info in target(info)?.addPoints(PDFOperands(scanner: scanner), count: 1) }),
        ("l", { scanner, info in target(info)?.addPoints(PDFOperands(scanner: scanner), count: 1) }),
        ("c", { scanner, info in target(info)?.addPoints(PDFOperands(scanner: scanner), count: 3) }),
        ("v", { scanner, info in target(info)?.addPoints(PDFOperands(scanner: scanner), count: 2) }),
        ("y", { scanner, info in target(info)?.addPoints(PDFOperands(scanner: scanner), count: 2) }),
        ("re", { scanner, info in target(info)?.addRectangle(PDFOperands(scanner: scanner)) }),
        ("f", { _, info in target(info)?.paintPath(fills: true) }),
        ("F", { _, info in target(info)?.paintPath(fills: true) }),
        ("f*", { _, info in target(info)?.paintPath(fills: true) }),
        ("B", { _, info in target(info)?.paintPath(fills: true) }),
        ("B*", { _, info in target(info)?.paintPath(fills: true) }),
        ("b", { _, info in target(info)?.paintPath(fills: true) }),
        ("b*", { _, info in target(info)?.paintPath(fills: true) }),
        ("S", { _, info in target(info)?.paintPath(fills: false) }),
        ("s", { _, info in target(info)?.paintPath(fills: false) }),
        ("n", { _, info in target(info)?.discardPath() })
    ]

    private static let textHandlers: [(String, Handler)] = [
        ("BT", { _, info in target(info)?.beginText() }),
        ("Tf", { scanner, info in target(info)?.setFont(PDFOperands(scanner: scanner)) }),
        ("Tc", { scanner, info in target(info)?.setTextState(PDFOperands(scanner: scanner), \.characterSpacing) }),
        ("Tw", { scanner, info in target(info)?.setTextState(PDFOperands(scanner: scanner), \.wordSpacing) }),
        ("Tz", { scanner, info in target(info)?.setTextState(PDFOperands(scanner: scanner), \.horizontalScale) }),
        ("TL", { scanner, info in target(info)?.setTextState(PDFOperands(scanner: scanner), \.leading) }),
        ("Td", { scanner, info in target(info)?.moveLine(PDFOperands(scanner: scanner), setsLeading: false) }),
        ("TD", { scanner, info in target(info)?.moveLine(PDFOperands(scanner: scanner), setsLeading: true) }),
        ("Tm", { scanner, info in target(info)?.setTextMatrix(PDFOperands(scanner: scanner)) }),
        ("T*", { _, info in target(info)?.nextLine() }),
        ("Tj", { scanner, info in target(info)?.showString(PDFOperands(scanner: scanner)) }),
        ("TJ", { scanner, info in target(info)?.showArray(PDFOperands(scanner: scanner)) }),
        ("'", { scanner, info in
            target(info)?.nextLine()
            target(info)?.showString(PDFOperands(scanner: scanner))
        }),
        ("\"", { scanner, info in target(info)?.showStringWithSpacing(PDFOperands(scanner: scanner)) })
    ]
}
