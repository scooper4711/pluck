import CoreGraphics
import Foundation

/// One painting of an image by a page's content.
struct PDFImageOccurrence {
    let stream: PDFStream
    /// Inline image data lives in the content stream and is only valid while it is being scanned.
    let isInline: Bool
    /// Looks up a resource (category, name) visible to the content that painted the image.
    let resource: (String, String) -> PDFObject?
}

/// Finds the images a page actually paints by walking its content stream, descending into
/// form XObjects and tiling patterns. Images that merely sit in a shared resource dictionary
/// are not reported.
enum PDFPageScanner {
    /// Calls `visit` for each image in painting order. Occurrences must be consumed inside `visit`.
    static func scan(_ page: CGPDFPage, visit: @escaping (PDFImageOccurrence) -> Void) {
        let context = PDFScanContext(visit: visit)
        let contentStream = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(contentStream) }
        context.scan(contentStream)
    }
}

private final class PDFScanContext {
    private static let maximumNesting = 12

    private let visit: (PDFImageOccurrence) -> Void
    private let operatorTable: CGPDFOperatorTableRef
    /// Forms and patterns already walked, so repeats and reference cycles are scanned once.
    private var scannedContainers: Set<PDFStream> = []
    /// The content streams being walked, outermost first.
    private var contentStreams: [CGPDFContentStreamRef] = []

    init(visit: @escaping (PDFImageOccurrence) -> Void) {
        self.visit = visit
        operatorTable = Self.makeOperatorTable()
    }

    deinit {
        CGPDFOperatorTableRelease(operatorTable)
    }

    func scan(_ contentStream: CGPDFContentStreamRef) {
        guard contentStreams.count < Self.maximumNesting else { return }
        contentStreams.append(contentStream)
        defer { contentStreams.removeLast() }
        let scanner = CGPDFScannerCreate(contentStream, operatorTable, Unmanaged.passUnretained(self).toOpaque())
        defer { CGPDFScannerRelease(scanner) }
        CGPDFScannerScan(scanner)
    }

    private static func makeOperatorTable() -> CGPDFOperatorTableRef {
        let table = CGPDFOperatorTableCreate()!
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            PDFScanContext.from(info)?.paintXObject(scanner)
        }
        CGPDFOperatorTableSetCallback(table, "EI") { scanner, info in
            PDFScanContext.from(info)?.paintInlineImage(scanner)
        }
        for setColor in ["scn", "SCN"] {
            CGPDFOperatorTableSetCallback(table, setColor) { scanner, info in
                PDFScanContext.from(info)?.selectPattern(scanner)
            }
        }
        return table
    }

    private static func from(_ info: UnsafeMutableRawPointer?) -> PDFScanContext? {
        info.map { Unmanaged<PDFScanContext>.fromOpaque($0).takeUnretainedValue() }
    }

    private func paintXObject(_ scanner: CGPDFScannerRef) {
        guard let stream = poppedResource(scanner, category: "XObject")?.stream else { return }
        switch stream.dictionary?.object("Subtype")?.name {
        case "Image":
            visit(PDFImageOccurrence(stream: stream, isInline: false, resource: resource))
        case "Form":
            scanContainer(stream, parent: CGPDFScannerGetContentStream(scanner))
        default:
            break
        }
    }

    private func paintInlineImage(_ scanner: CGPDFScannerRef) {
        var stream: CGPDFStreamRef?
        guard CGPDFScannerPopStream(scanner, &stream), let stream else { return }
        visit(PDFImageOccurrence(stream: PDFStream(ref: stream), isInline: true, resource: resource))
    }

    /// `scn` with a name operand selects a pattern; a tiling pattern has content of its own.
    private func selectPattern(_ scanner: CGPDFScannerRef) {
        guard let pattern = poppedResource(scanner, category: "Pattern")?.stream else { return }
        scanContainer(pattern, parent: CGPDFScannerGetContentStream(scanner))
    }

    private func poppedResource(_ scanner: CGPDFScannerRef, category: String) -> PDFObject? {
        var name: UnsafePointer<CChar>?
        guard CGPDFScannerPopName(scanner, &name), let name else { return nil }
        return resource(category, String(cString: name))
    }

    /// Resolves a resource from the innermost content stream outwards, because a form or pattern
    /// with no resources of its own uses those of whatever painted it.
    private func resource(_ category: String, _ name: String) -> PDFObject? {
        for contentStream in contentStreams.reversed() {
            if let object = CGPDFContentStreamGetResource(contentStream, category, name) {
                return PDFObject(ref: object)
            }
        }
        return nil
    }

    private func scanContainer(_ stream: PDFStream, parent: CGPDFContentStreamRef) {
        guard scannedContainers.insert(stream).inserted, let dictionary = stream.dictionary else { return }
        // Core Graphics needs some dictionary here; a container with no resources gets its own
        // dictionary, which has no resource categories, so `resource` falls back to the parent's.
        let resources = dictionary.object("Resources")?.dictionary ?? dictionary
        let contentStream = CGPDFContentStreamCreateWithStream(stream.ref, resources.ref, parent)
        defer { CGPDFContentStreamRelease(contentStream) }
        scan(contentStream)
    }
}
