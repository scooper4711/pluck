// Draws Pluck's app icon: a picture being lifted off a page.
// Usage: swift scripts/make-icon.swift <output.png>   (see scripts/make-icon.sh)
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let canvasSize: CGFloat = 1024

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Runs `body` with the context rotated by `degrees` about `center`, which becomes the origin.
func rotated(_ context: CGContext, about center: CGPoint, degrees: CGFloat, body: () -> Void) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: degrees * .pi / 180)
    body()
    context.restoreGState()
}

func fillGradient(_ context: CGContext, in path: CGPath, top: UInt32, bottom: UInt32) {
    let bounds = path.boundingBox
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(top), color(bottom)] as CFArray,
        locations: [0, 1])!
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(
        gradient, start: CGPoint(x: bounds.midX, y: bounds.maxY), end: CGPoint(x: bounds.midX, y: bounds.minY),
        options: [])
    context.restoreGState()
}

func drawBackground(_ context: CGContext) {
    let tile = roundedRect(CGRect(x: 100, y: 100, width: 824, height: 824), radius: 185)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, alpha: 0.35))
    context.addPath(tile)
    context.setFillColor(color(0x3B2FB8))
    context.fillPath()
    context.restoreGState()
    fillGradient(context, in: tile, top: 0x8B7BFF, bottom: 0x3A2CB0)
}

/// The page: text lines and a dashed outline where the picture used to be.
func drawPage(_ context: CGContext) {
    rotated(context, about: CGPoint(x: 430, y: 490), degrees: 7) {
        let page = CGRect(x: -200, y: -265, width: 400, height: 530)
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x000000, alpha: 0.3))
        context.addPath(roundedRect(page, radius: 26))
        context.setFillColor(color(0xFBFAFF))
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)

        context.addPath(roundedRect(CGRect(x: -150, y: 20, width: 300, height: 195), radius: 14))
        context.setStrokeColor(color(0xB9B4DA))
        context.setLineWidth(8)
        context.setLineDash(phase: 0, lengths: [26, 18])
        context.strokePath()

        context.setFillColor(color(0xCFCBE6))
        for (index, width) in [300, 300, 250, 300, 170].enumerated() {
            let line = CGRect(x: -150, y: -45 - CGFloat(index) * 46, width: CGFloat(width), height: 20)
            context.addPath(roundedRect(line, radius: 10))
            context.fillPath()
        }
    }
}

/// The picture's scene: a sunset sky, a sun and two hills.
func drawScene(_ context: CGContext, in frame: CGRect) {
    let window = roundedRect(frame, radius: 10)
    fillGradient(context, in: window, top: 0xFFD166, bottom: 0xFF7A59)
    context.saveGState()
    context.addPath(window)
    context.clip()
    context.setFillColor(color(0xFFF6D6))
    context.fillEllipse(in: CGRect(x: frame.minX + 60, y: frame.maxY - 130, width: 84, height: 84))
    context.setFillColor(color(0x2F8F83))
    context.move(to: CGPoint(x: frame.minX - 40, y: frame.minY))
    context.addLine(to: CGPoint(x: frame.minX + 130, y: frame.minY + 150))
    context.addLine(to: CGPoint(x: frame.minX + 300, y: frame.minY))
    context.fillPath()
    context.setFillColor(color(0x1F5F6B))
    context.move(to: CGPoint(x: frame.minX + 110, y: frame.minY))
    context.addLine(to: CGPoint(x: frame.minX + 260, y: frame.minY + 195))
    context.addLine(to: CGPoint(x: frame.maxX + 60, y: frame.minY))
    context.fillPath()
    context.restoreGState()
}

/// The plucked picture, tilted and floating above the page.
func drawPicture(_ context: CGContext) {
    rotated(context, about: CGPoint(x: 615, y: 615), degrees: -9) {
        let print = CGRect(x: -215, y: -170, width: 430, height: 340)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -22), blur: 44, color: color(0x150A50, alpha: 0.55))
        context.addPath(roundedRect(print, radius: 24))
        context.setFillColor(color(0xFFFFFF))
        context.fillPath()
        context.restoreGState()
        drawScene(context, in: print.insetBy(dx: 24, dy: 24))
    }
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Writing the icon failed: cannot create \(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Writing the icon failed: \(path)") }
}

guard CommandLine.arguments.count == 2 else { fatalError("Usage: make-icon.swift <output.png>") }
let context = CGContext(
    data: nil, width: Int(canvasSize), height: Int(canvasSize), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
drawBackground(context)
drawPage(context)
drawPicture(context)
writePNG(context.makeImage()!, to: CommandLine.arguments[1])
