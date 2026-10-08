import CoreGraphics
import Foundation
import PDFKit

/// Extracts structured text from one PDF. Safe to call from any thread; calls are serialized.
public final class PDFTextSource: @unchecked Sendable {
    /// How many pages are sampled to learn the body font and the running headers and footers.
    private static let sampleSize = 24
    /// Margin, as a share of the page height, in which a lone number is a page number.
    private static let pageNumberMargin: CGFloat = 0.08

    public let pageCount: Int
    /// The PDF's own title, when it has a meaningful one. Many only repeat a file name.
    public let title: String?

    private let document: PDFDocument
    private let graphicsDocument: CGPDFDocument
    private let lock = NSLock()
    private var contents: [Int: PageContent] = [:]
    private var blocks: [Int: [TextBlock]] = [:]
    private var profile: DocumentProfile?

    public init(url: URL, password: String = "") throws {
        graphicsDocument = try PDFDocumentOpener.open(url, password: password)
        guard let document = PDFDocument(url: url), !document.isLocked || document.unlock(withPassword: password)
        else { throw PluckError.cannotOpenDocument(url) }
        self.document = document
        pageCount = document.pageCount
        let declaredTitle = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        title = declaredTitle.flatMap { title in
            let looksLikeFileName = title.range(of: #"\.[A-Za-z]{3,4}$"#, options: .regularExpression) != nil
            return title.isEmpty || looksLikeFileName ? nil : title
        }
    }

    /// The page's text as headings, paragraphs, list items and boxes, in reading order.
    public func blocks(forPageAt index: Int) -> [TextBlock] {
        lock.withLock {
            if let known = blocks[index] { return known }
            let result = autoreleasepool { makeBlocks(forPageAt: index) }
            blocks[index] = result
            contents[index] = nil
            return result
        }
    }

    private func makeBlocks(forPageAt index: Int) -> [TextBlock] {
        let profile = documentProfile()
        guard let content = content(ofPageAt: index) else { return [] }
        // Typed-in values take the body style so they read as part of the text around them
        // rather than as headings; they are set in whatever font the form's author chose.
        let fieldValues = content.fieldValues.map { $0.restyled(as: profile.body) }
        let fragments = content.fragments.filter { !profile.isRunningElement($0, on: content.size) } + fieldValues
        let flow = PageLayout(pageSize: content.size, body: profile.body)
            .flow(fragments: fragments, panels: content.panels, rules: content.rules)
        return ParagraphBuilder(
            body: profile.body, obstacles: content.images, compounds: profile.compounds, source: title
        ).blocks(from: flow)
    }

    private func documentProfile() -> DocumentProfile {
        if let profile { return profile }
        let step = max(1, pageCount / Self.sampleSize)
        let sample = stride(from: 0, to: pageCount, by: step).compactMap(content)
        let made = DocumentProfile(sample: sample, pageNumberMargin: Self.pageNumberMargin)
        profile = made
        return made
    }

    private func content(ofPageAt index: Int) -> PageContent? {
        if let known = contents[index] { return known }
        guard let page = document.page(at: index), let graphicsPage = graphicsDocument.page(at: index + 1)
        else { return nil }
        let graphics = PDFContentInterpreter.graphics(of: graphicsPage)
        let reader = PageTextReader(page: page, graphics: graphics)
        let fields = FormFieldReader(page: page, readingRect: reader.readingRect)
        let content = PageContent(
            size: page.bounds(for: .cropBox).size, fragments: reader.fragments(), fieldValues: fields.fragments(),
            panels: (graphics.panels + graphics.images).map(reader.readingRect),
            images: graphics.images.map(reader.readingRect), rules: graphics.rules.map(reader.readingRect))
        contents[index] = content
        return content
    }
}

/// A page's raw material for layout, in reading coordinates.
struct PageContent {
    let size: CGSize
    let fragments: [TextFragment]
    /// What has been typed into the page's form fields. They are kept apart from the page's
    /// printed text, which alone decides the document's body style and running headers.
    let fieldValues: [TextFragment]
    /// Filled shapes and images: anything that could be the background of a box.
    let panels: [CGRect]
    let images: [CGRect]
    let rules: [CGRect]
}

/// What is true of the document as a whole: its body font, and the text repeated on every page.
struct DocumentProfile {
    private static let gridSize: CGFloat = 6
    private static let minimumRepeats = 3

    let body: BodyStyle
    /// Hyphenated words that appear unbroken somewhere in the sample, lower-cased.
    let compounds: Set<String>
    private let runningKeys: Set<String>
    private let pageNumberMargin: CGFloat

    init(sample: [PageContent], pageNumberMargin: CGFloat) {
        self.pageNumberMargin = pageNumberMargin
        var weights: [BodyStyle: Int] = [:]
        var repeats: [String: Int] = [:]
        var compounds: Set<String> = []
        for page in sample {
            for fragment in page.fragments {
                let style = fragment.style
                weights[BodyStyle(family: style.family, size: (style.size * 2).rounded() / 2), default: 0]
                    += fragment.characters.count
            }
            for key in Set(page.fragments.map(Self.key)) { repeats[key, default: 0] += 1 }
            compounds.formUnion(page.fragments.flatMap { Self.compounds(in: $0.text) })
        }
        self.compounds = compounds
        body = weights.max { $0.value < $1.value }?.key ?? BodyStyle(family: "", size: 10)
        let threshold = max(Self.minimumRepeats, sample.count * 3 / 10)
        runningKeys = Set(repeats.filter { $0.value >= threshold }.keys)
    }

    /// True for headers, footers and page numbers, which are not part of the page's text.
    func isRunningElement(_ fragment: TextFragment, on pageSize: CGSize) -> Bool {
        if runningKeys.contains(Self.key(for: fragment)), Self.isInMargin(fragment.frame, of: pageSize) {
            return true
        }
        let isNumber = fragment.text.count <= 4 && fragment.text.allSatisfy(\.isNumber)
        let margin = pageSize.height * pageNumberMargin
        return isNumber && (fragment.frame.maxY < margin || fragment.frame.minY > pageSize.height - margin)
    }

    /// Headers, footers and side tabs sit at the edges of the page. Text repeated from page to
    /// page inside the text area, such as a sidebar that recurs with every encounter, is content.
    private static func isInMargin(_ frame: CGRect, of pageSize: CGSize) -> Bool {
        frame.maxY < pageSize.height * 0.13 || frame.minY > pageSize.height * 0.9
            || frame.maxX < pageSize.width * 0.16 || frame.minX > pageSize.width * 0.84
    }

    /// Words written with an internal hyphen, such as "mosquito-free".
    private static func compounds(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && $0 != "-" }
            .filter { $0.contains("-") && $0.first != "-" && $0.last != "-" }
            .map(String.init)
    }

    /// Identifies a fragment by rough position and text, with digits masked so that a page
    /// number in the same spot matches from page to page.
    private static func key(for fragment: TextFragment) -> String {
        let text = String(fragment.text.map { $0.isNumber ? "#" : $0 })
        let column = Int(fragment.frame.minX / gridSize)
        let row = Int(fragment.frame.minY / gridSize)
        return "\(column)|\(row)|\(text)"
    }
}
