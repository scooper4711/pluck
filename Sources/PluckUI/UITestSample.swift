#if DEBUG && os(iOS)
import UIKit

/// A two-page PDF the UI tests open (launch argument `-UITestSample`), since real adventures are copyrighted and
/// the tests can't hand the app a file. Page 1 has a heading, a paragraph and two pictures, one of them with a
/// transparent background; page 2 has a paragraph and a third picture.
enum UITestSample {
    static let argument = "-UITestSample"
    static let fileVariable = "UITestSampleFile"
    private static let page = CGRect(x: 0, y: 0, width: 612, height: 792)

    static func urlIfRequested() -> URL? {
        if let file = ProcessInfo.processInfo.environment[fileVariable] { return copyOfFile(at: file) }
        guard ProcessInfo.processInfo.arguments.contains(argument) else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "UI Test Sample.pdf")
        do {
            try UIGraphicsPDFRenderer(bounds: page).writePDF(to: url, withActions: draw)
            return url
        } catch {
            return nil
        }
    }

    /// A PDF from outside the app, for the store's screenshots (`UITestSampleFile`).
    private static func copyOfFile(at path: String) -> URL? {
        let source = URL(fileURLWithPath: path)
        let copy = FileManager.default.temporaryDirectory.appending(path: source.lastPathComponent)
        try? FileManager.default.removeItem(at: copy)
        return (try? FileManager.default.copyItem(at: source, to: copy)) == nil ? nil : copy
    }

    private static func draw(_ context: UIGraphicsPDFRendererContext) {
        context.beginPage()
        write("The Clockwork Cellar", at: 72, font: .boldSystemFont(ofSize: 28))
        write("The stairs end at a brass door. Behind it, gears the size of cartwheels turn in the dark.", at: 120)
        picture(CGSize(width: 320, height: 200), isOpaque: true, color: .systemTeal)
            .draw(in: CGRect(x: 72, y: 190, width: 320, height: 200))
        picture(CGSize(width: 160, height: 160), isOpaque: false, color: .systemOrange)
            .draw(in: CGRect(x: 72, y: 420, width: 160, height: 160))
        context.beginPage()
        write("A lever on the far wall stops the gears. Pulling it takes both hands.", at: 72)
        picture(CGSize(width: 240, height: 300), isOpaque: true, color: .systemPurple)
            .draw(in: CGRect(x: 72, y: 130, width: 240, height: 300))
    }

    private static func write(_ text: String, at top: CGFloat, font: UIFont = .systemFont(ofSize: 12)) {
        (text as NSString).draw(in: CGRect(x: 72, y: top, width: page.width - 144, height: 80),
                                withAttributes: [.font: font])
    }

    /// A disc on a colored field, or on nothing when the picture isn't opaque.
    private static func picture(_ size: CGSize, isOpaque: Bool, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = isOpaque
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if isOpaque {
                color.withAlphaComponent(0.35).setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            color.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 24, dy: 24))
        }
    }
}
#endif
