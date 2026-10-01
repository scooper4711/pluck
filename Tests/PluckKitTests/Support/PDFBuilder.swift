import Foundation

/// Writes small PDFs object by object, so tests control exactly how each image is stored.
final class PDFBuilder {
    private static let catalogID = 1
    private static let pageTreeID = 2

    /// Object bodies; object `n` lives at index `n - 1`. The first two are filled in by `build()`.
    private var bodies: [Data] = [Data(), Data()]
    private var pageIDs: [Int] = []

    @discardableResult
    func addObject(_ body: String) -> Int {
        bodies.append(Data(body.utf8))
        return bodies.count
    }

    @discardableResult
    func addStream(_ entries: String, data: Data) -> Int {
        var body = Data("<< \(entries) /Length \(data.count) >>\nstream\n".utf8)
        body.append(data)
        body.append(Data("\nendstream".utf8))
        bodies.append(body)
        return bodies.count
    }

    /// Adds a page with the given resource dictionary entries and content stream.
    func addPage(resources: String, content: Data, mediaBox: String = "0 0 200 200") {
        let contentID = addStream("", data: content)
        pageIDs.append(addObject("""
            << /Type /Page /Parent \(Self.pageTreeID) 0 R /MediaBox [\(mediaBox)] \
            /Resources << \(resources) >> /Contents \(contentID) 0 R >>
            """))
    }

    func addPage(resources: String, content: String) {
        addPage(resources: resources, content: Data(content.utf8))
    }

    /// Adds a page that paints each of the given image objects once.
    func addPage(painting imageIDs: [Int]) {
        let xObjects = imageIDs.map { "/Im\($0) \($0) 0 R" }.joined(separator: " ")
        let content = imageIDs.map { "q 50 0 0 50 10 10 cm /Im\($0) Do Q" }.joined(separator: "\n")
        addPage(resources: "/XObject << \(xObjects) >>", content: content)
    }

    func build() -> Data {
        let kids = pageIDs.map { "\($0) 0 R" }.joined(separator: " ")
        bodies[Self.catalogID - 1] = Data("<< /Type /Catalog /Pages \(Self.pageTreeID) 0 R >>".utf8)
        bodies[Self.pageTreeID - 1] = Data("<< /Type /Pages /Kids [\(kids)] /Count \(pageIDs.count) >>".utf8)

        var pdf = Data("%PDF-1.7\n".utf8)
        var offsets: [Int] = []
        for (index, body) in bodies.enumerated() {
            offsets.append(pdf.count)
            pdf.append(Data("\(index + 1) 0 obj\n".utf8))
            pdf.append(body)
            pdf.append(Data("\nendobj\n".utf8))
        }
        let crossReferenceOffset = pdf.count
        var trailer = "xref\n0 \(bodies.count + 1)\n0000000000 65535 f \n"
        trailer += offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
        trailer += "trailer\n<< /Size \(bodies.count + 1) /Root \(Self.catalogID) 0 R >>\n"
        trailer += "startxref\n\(crossReferenceOffset)\n%%EOF\n"
        pdf.append(Data(trailer.utf8))
        return pdf
    }

    /// Writes the PDF into a fresh temporary directory and returns its URL.
    func write(named name: String = "fixture") throws -> URL {
        let url = try TemporaryDirectory.make().appendingPathComponent("\(name).pdf")
        try build().write(to: url)
        return url
    }
}

extension PDFBuilder {
    /// Adds an image XObject; `entries` supplies colour space, bit depth, masks and filters.
    @discardableResult
    func addImage(width: Int, height: Int, entries: String, data: Data) -> Int {
        addStream("/Type /XObject /Subtype /Image /Width \(width) /Height \(height) \(entries)", data: data)
    }

    @discardableResult
    func addRGBImage(width: Int, height: Int, samples: [UInt8], entries: String = "") -> Int {
        addImage(
            width: width, height: height,
            entries: "/ColorSpace /DeviceRGB /BitsPerComponent 8 \(entries)", data: Data(samples))
    }

    @discardableResult
    func addGrayImage(width: Int, height: Int, samples: [UInt8], entries: String = "") -> Int {
        addImage(
            width: width, height: height,
            entries: "/ColorSpace /DeviceGray /BitsPerComponent 8 \(entries)", data: Data(samples))
    }

    /// A one-colour RGB image, handy when a test only needs distinguishable pictures.
    @discardableResult
    func addSolidImage(_ color: [UInt8], width: Int = 4, height: Int = 4) -> Int {
        let samples = Array(repeating: color, count: width * height).flatMap { $0 }
        return addRGBImage(width: width, height: height, samples: samples)
    }
}

enum TemporaryDirectory {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PluckTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
