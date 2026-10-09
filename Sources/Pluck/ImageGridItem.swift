import AppKit
import PluckKit

/// The grid's collection view: adds ⌘C and makes a right-click act on the item under the pointer.
final class ImageCollectionView: NSCollectionView, NSMenuItemValidation {
    var onCopy: () -> Void = {
        // Nothing to copy until the grid connects it to the model.
    }

    @objc func copy(_: Any?) {
        onCopy()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(copy(_:)) ? !selectionIndexPaths.isEmpty : true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let indexPath = indexPathForItem(at: point) else { return nil }
        if !selectionIndexPaths.contains(indexPath) {
            selectionIndexPaths = [indexPath]
            delegate?.collectionView?(self, didSelectItemsAt: [indexPath])
        }
        return super.menu(for: event)
    }
}

/// One cell: the image over a checkerboard, with its pixel size beneath.
final class ImageGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ImageGridItem")

    private static let padding: CGFloat = 8
    private static let captionHeight: CGFloat = 18

    private let thumbnailView = ThumbnailView()
    private let caption = NSTextField(labelWithString: "")
    private var shown: (id: String, transform: ImageTransform)?

    static func size(forThumbnailSize thumbnailSize: CGFloat) -> NSSize {
        NSSize(width: thumbnailSize + padding * 2, height: thumbnailSize + captionHeight + padding * 2)
    }

    override var isSelected: Bool {
        didSet { (view as? SelectionBackgroundView)?.isSelected = isSelected }
    }

    override func loadView() {
        view = SelectionBackgroundView()
        caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingMiddle
        for subview in [thumbnailView, caption] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.padding),
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.padding),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.padding),
            thumbnailView.bottomAnchor.constraint(equalTo: caption.topAnchor),
            caption.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            caption.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            caption.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.padding),
            caption.heightAnchor.constraint(equalToConstant: Self.captionHeight)
        ])
    }

    func show(_ image: ExtractedImage, transform: ImageTransform) {
        guard shown?.id != image.id || shown?.transform != transform else {
            caption.stringValue = Self.caption(for: image)
            return
        }
        shown = (image.id, transform)
        thumbnailView.image = (try? transform.apply(to: image.thumbnail)) ?? image.thumbnail
        caption.stringValue = Self.caption(for: image)
    }

    private static func caption(for image: ExtractedImage) -> String {
        let pages = image.pageIndexes.count == 1
            ? "p. \((image.pageIndexes.first ?? 0) + 1)"
            : "\(image.pageIndexes.count) pages"
        return "\(image.pixelWidth) × \(image.pixelHeight) · \(pages)"
    }
}

private final class SelectionBackgroundView: NSView {
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    override func draw(_: NSRect) {
        guard isSelected else { return }
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        outline.fill()
        NSColor.controlAccentColor.setStroke()
        outline.lineWidth = 2
        outline.stroke()
    }
}

/// Draws an image aspect-fitted over a checkerboard, so transparency is visible.
private final class ThumbnailView: NSView {
    private static let checkSize: CGFloat = 8

    var image: CGImage? {
        didSet { needsDisplay = true }
    }

    override func draw(_: NSRect) {
        guard let image, let context = NSGraphicsContext.current?.cgContext else { return }
        let frame = fittedFrame(for: image)
        drawCheckerboard(in: frame, context: context)
        context.interpolationQuality = .high
        context.draw(image, in: frame)
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: frame.insetBy(dx: -0.5, dy: -0.5)).stroke()
    }

    /// Centers the image, shrinking it to fit but never enlarging it past its own pixels.
    private func fittedFrame(for image: CGImage) -> NSRect {
        let size = NSSize(width: image.width, height: image.height)
        let scale = min(bounds.width / size.width, bounds.height / size.height, 1)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(
            x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2,
            width: fitted.width, height: fitted.height).integral
    }

    private func drawCheckerboard(in frame: NSRect, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: frame)
        context.setFillColor(NSColor(white: 0.97, alpha: 1).cgColor)
        context.fill(frame)
        context.setFillColor(NSColor(white: 0.82, alpha: 1).cgColor)
        let columns = Int(ceil(frame.width / Self.checkSize))
        let rows = Int(ceil(frame.height / Self.checkSize))
        for row in 0..<rows {
            for column in stride(from: row % 2, to: columns, by: 2) {
                context.fill(NSRect(
                    x: frame.minX + CGFloat(column) * Self.checkSize,
                    y: frame.minY + CGFloat(row) * Self.checkSize,
                    width: Self.checkSize, height: Self.checkSize))
            }
        }
    }
}
