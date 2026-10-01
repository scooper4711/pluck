import CoreGraphics
import Foundation

/// Walks a page's content stream keeping just enough graphics state to report where each font
/// is used and which shapes could frame a block of text. It does not decode the text itself;
/// PDFKit does that, and the two are matched up by position.
final class PDFContentInterpreter {
    private static let maximumNesting = 12
    /// A rule is at most this thick and at least this long, in points.
    private static let ruleThickness: CGFloat = 3
    private static let ruleLength: CGFloat = 30
    private static let minimumPanelSide: CGFloat = 14

    private(set) var graphics = PageGraphics()

    private var state = PDFGraphicsState()
    private var savedStates: [PDFGraphicsState] = []
    private var path = PDFPathBounds()
    private var textMatrix = CGAffineTransform.identity
    private var lineMatrix = CGAffineTransform.identity
    private var fonts: [PDFDictionary: PDFFontMetrics] = [:]
    private var contentStreams: [CGPDFContentStreamRef] = []
    private var scannedForms: Set<PDFStream> = []
    private lazy var operatorTable = PDFOperatorTable.make()

    static func graphics(of page: CGPDFPage) -> PageGraphics {
        let interpreter = PDFContentInterpreter()
        let contentStream = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(contentStream) }
        interpreter.scan(contentStream)
        CGPDFOperatorTableRelease(interpreter.operatorTable)
        return interpreter.graphics
    }

    private func scan(_ contentStream: CGPDFContentStreamRef) {
        guard contentStreams.count < Self.maximumNesting else { return }
        contentStreams.append(contentStream)
        defer { contentStreams.removeLast() }
        let scanner = CGPDFScannerCreate(contentStream, operatorTable, Unmanaged.passUnretained(self).toOpaque())
        defer { CGPDFScannerRelease(scanner) }
        CGPDFScannerScan(scanner)
    }

    private func resource(_ category: String, _ name: String) -> PDFObject? {
        for contentStream in contentStreams.reversed() {
            if let object = CGPDFContentStreamGetResource(contentStream, category, name) {
                return PDFObject(ref: object)
            }
        }
        return nil
    }
}

// MARK: - Graphics state and shapes

extension PDFContentInterpreter {
    func saveState() {
        savedStates.append(state)
    }

    func restoreState() {
        if let saved = savedStates.popLast() { state = saved }
    }

    func concatenate(_ operands: PDFOperands) {
        guard let matrix = operands.matrix() else { return }
        state.transform = matrix.concatenating(state.transform)
    }

    func setLineWidth(_ operands: PDFOperands) {
        state.lineWidth = operands.number() ?? state.lineWidth
    }

    func setFillColor(_ operands: PDFOperands, isSubtractive: Bool) {
        let components = operands.numbers()
        let blank: CGFloat = isSubtractive ? 0 : 1
        state.fillsWhite = !components.isEmpty && components.allSatisfy { abs($0 - blank) < 0.02 }
    }

    /// `sc`/`scn` do not say which colour space they are in; three components are taken as RGB
    /// and four as CMYK. Anything else (a tint, a pattern) is assumed to be visible.
    func setGenericFillColor(_ operands: PDFOperands) {
        _ = operands.name()
        let components = operands.numbers()
        switch components.count {
        case 3: state.fillsWhite = components.allSatisfy { $0 > 0.98 }
        case 4: state.fillsWhite = components.allSatisfy { $0 < 0.02 }
        default: state.fillsWhite = false
        }
    }

    func addPoints(_ operands: PDFOperands, count: Int) {
        let values = operands.numbers(count: count * 2)
        guard values.count == count * 2 else { return }
        for index in 0..<count {
            path.add(CGPoint(x: values[index * 2], y: values[index * 2 + 1]), transform: state.transform)
        }
    }

    func addRectangle(_ operands: PDFOperands) {
        let values = operands.numbers(count: 4)
        guard values.count == 4 else { return }
        path.add(CGRect(x: values[0], y: values[1], width: values[2], height: values[3]), transform: state.transform)
    }

    func paintPath(fills: Bool) {
        defer { path.reset() }
        guard !path.box.isNull else { return }
        let box = fills ? path.box : path.box.insetBy(dx: -state.lineWidth / 2, dy: -state.lineWidth / 2)
        if box.height <= Self.ruleThickness, box.width >= Self.ruleLength {
            graphics.rules.append(box)
        } else if min(box.width, box.height) >= Self.minimumPanelSide, !(fills && state.fillsWhite) {
            graphics.panels.append(box)
        }
    }

    func discardPath() {
        path.reset()
    }

    func paintXObject(_ operands: PDFOperands) {
        guard let name = operands.name(), let stream = resource("XObject", name)?.stream else { return }
        switch stream.dictionary?.object("Subtype")?.name {
        case "Image": addImage()
        case "Form": scanForm(stream)
        default: break
        }
    }

    /// An image always fills the unit square of the current coordinate system.
    func addImage() {
        var bounds = PDFPathBounds()
        bounds.add(CGRect(x: 0, y: 0, width: 1, height: 1), transform: state.transform)
        graphics.images.append(bounds.box)
    }

    private func scanForm(_ stream: PDFStream) {
        guard scannedForms.insert(stream).inserted, let dictionary = stream.dictionary,
              let parent = contentStreams.last else { return }
        defer { scannedForms.remove(stream) }
        saveState()
        defer { restoreState() }
        let matrix = dictionary.object("Matrix")?.array?.numbers ?? []
        if matrix.count == 6 {
            let formTransform = CGAffineTransform(
                a: matrix[0], b: matrix[1], c: matrix[2], d: matrix[3], tx: matrix[4], ty: matrix[5])
            state.transform = formTransform.concatenating(state.transform)
        }
        let resources = dictionary.object("Resources")?.dictionary ?? dictionary
        let contentStream = CGPDFContentStreamCreateWithStream(stream.ref, resources.ref, parent)
        defer { CGPDFContentStreamRelease(contentStream) }
        scan(contentStream)
    }
}

// MARK: - Text

extension PDFContentInterpreter {
    func beginText() {
        textMatrix = .identity
        lineMatrix = .identity
    }

    func setFont(_ operands: PDFOperands) {
        let size = operands.number()
        guard let name = operands.name() else { return }
        state.fontSize = size ?? state.fontSize
        state.font = resource("Font", name)?.dictionary.map(metrics)
    }

    private func metrics(for font: PDFDictionary) -> PDFFontMetrics {
        if let known = fonts[font] { return known }
        let metrics = PDFFontMetrics(font: font)
        fonts[font] = metrics
        return metrics
    }

    func setTextState(_ operands: PDFOperands, _ keyPath: WritableKeyPath<PDFGraphicsState, CGFloat>) {
        guard let value = operands.number() else { return }
        state[keyPath: keyPath] = keyPath == \.horizontalScale ? value / 100 : value
    }

    func moveLine(_ operands: PDFOperands, setsLeading: Bool) {
        let values = operands.numbers(count: 2)
        guard values.count == 2 else { return }
        if setsLeading { state.leading = -values[1] }
        moveLine(byX: values[0], y: values[1])
    }

    func nextLine() {
        moveLine(byX: 0, y: -state.leading)
    }

    private func moveLine(byX x: CGFloat, y: CGFloat) {
        lineMatrix = CGAffineTransform(translationX: x, y: y).concatenating(lineMatrix)
        textMatrix = lineMatrix
    }

    func setTextMatrix(_ operands: PDFOperands) {
        guard let matrix = operands.matrix() else { return }
        lineMatrix = matrix
        textMatrix = matrix
    }

    func showString(_ operands: PDFOperands) {
        guard let bytes = operands.string() else { return }
        show([.string(bytes)])
    }

    /// The `"` operator: set word and character spacing, move to the next line, show a string.
    func showStringWithSpacing(_ operands: PDFOperands) {
        guard let bytes = operands.string() else { return }
        let spacing = operands.numbers(count: 2)
        if spacing.count == 2 { (state.wordSpacing, state.characterSpacing) = (spacing[0], spacing[1]) }
        nextLine()
        show([.string(bytes)])
    }

    func showArray(_ operands: PDFOperands) {
        show(operands.textArray())
    }

    /// Records where the pieces start and end, advancing the text position as a renderer would.
    private func show(_ pieces: [PDFTextPiece]) {
        guard let font = state.font else { return }
        let start = baselinePoint
        for piece in pieces {
            switch piece {
            case .string(let bytes): advance(over: bytes, font: font)
            case .adjustment(let amount): advance(by: -amount / 1000 * state.fontSize * state.horizontalScale)
            }
        }
        let placement = textMatrix.concatenating(state.transform)
        let scale = hypot(placement.c, placement.d)
        graphics.fontSpans.append(FontSpan(
            fontName: font.name, isBold: font.isBold, isItalic: font.isItalic,
            size: state.fontSize * scale, start: start, end: baselinePoint))
    }

    private var baselinePoint: CGPoint {
        CGPoint.zero.applying(textMatrix.concatenating(state.transform))
    }

    private func advance(over bytes: Data, font: PDFFontMetrics) {
        var index = bytes.startIndex
        while index < bytes.endIndex {
            var code = Int(bytes[index])
            if font.bytesPerCode == 2, index + 1 < bytes.endIndex { code = code << 8 | Int(bytes[index + 1]) }
            index += font.bytesPerCode
            // Word spacing applies only to the single-byte space character.
            let wordSpacing = font.bytesPerCode == 1 && code == 32 ? state.wordSpacing : 0
            let width = font.width(ofCode: code) * state.fontSize + state.characterSpacing + wordSpacing
            advance(by: width * state.horizontalScale)
        }
    }

    private func advance(by distance: CGFloat) {
        textMatrix = CGAffineTransform(translationX: distance, y: 0).concatenating(textMatrix)
    }
}

/// A piece of a `TJ` array: a string to show, or a kerning adjustment in thousandths.
enum PDFTextPiece {
    case string(Data)
    case adjustment(CGFloat)
}
