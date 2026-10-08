import Foundation
@testable import PluckKit
import Testing

@Suite("Encoding images")
struct ImageEncodingTests {
    private static let sample = RasterImage(rows: [
        [[255, 0, 0, 255], [0, 255, 0, 128]],
        [[0, 0, 255, 255], [0, 0, 0, 0]]
    ])

    @Test("Lossless WebP reproduces color and alpha exactly")
    func losslessWebP() throws {
        let data = try WebPEncoder.encode(Self.sample, options: WebPOptions(isLossless: true))
        let decoded = try RasterImage(webP: data)

        #expect(data.prefix(4) == Data("RIFF".utf8))
        #expect(decoded.alphas == Self.sample.alphas)
        #expect(decoded.pixel(0, 0) == [255, 0, 0, 255])
        #expect(decoded.pixel(1, 0) == [0, 255, 0, 128])
    }

    @Test("Lossy WebP keeps the size and the alpha channel")
    func lossyWebP() throws {
        var pixels: [UInt8] = []
        for index in 0..<(32 * 32) { pixels += [200, 40, 40, index < 512 ? 255 : 0] }
        let image = RasterImage(width: 32, height: 32, pixels: Data(pixels))

        let decoded = try RasterImage(webP: WebPEncoder.encode(image, options: WebPOptions(quality: 80)))

        #expect(decoded.width == 32 && decoded.height == 32)
        #expect(decoded.alphas == image.alphas)
        #expect(isClose(decoded.pixel(5, 5), [200, 40, 40, 255]))
    }

    @Test("An image too large for WebP is rejected with a reason")
    func oversizedWebP() {
        let width = WebPEncoder.maximumDimension + 1
        let image = RasterImage(width: width, height: 1, pixels: Data(count: width * 4))

        #expect(throws: PluckError.self) { try WebPEncoder.encode(image) }
    }

    @Test("PNG and TIFF keep straight alpha")
    func pngAndTIFF() throws {
        for data in [try PNGEncoder.encode(Self.sample), try TIFFEncoder.encode(Self.sample)] {
            let decoded = try RasterImage(encodedData: data)
            #expect(decoded.alphas == Self.sample.alphas)
            #expect(decoded.pixel(0, 1) == [0, 0, 255, 255])
            #expect(isClose(decoded.pixel(1, 0), [0, 255, 0, 128], tolerance: 2))
        }
    }

    @Test("WebP options come from user defaults, falling back to lossy at quality 90")
    func optionsFromDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "PluckTests-\(UUID().uuidString)"))
        #expect(WebPOptions(defaults: defaults) == WebPOptions(isLossless: false, quality: 90))

        defaults.set(true, forKey: WebPOptions.losslessDefaultsKey)
        defaults.set(55.0, forKey: WebPOptions.qualityDefaultsKey)
        #expect(WebPOptions(defaults: defaults) == WebPOptions(isLossless: true, quality: 55))
    }

    @Test("Thumbnails are capped at the requested size and keep the aspect ratio")
    func thumbnail() throws {
        let image = RasterImage(width: 200, height: 100, pixels: Data(count: 200 * 100 * 4))
        let thumbnail = try image.makeThumbnail(maximumDimension: 50)
        #expect(thumbnail.width == 50 && thumbnail.height == 25)

        let small = try Self.sample.makeThumbnail(maximumDimension: 50)
        #expect(small.width == 2 && small.height == 2, "small images are not enlarged")
    }

    @Test("Identical pixels hash identically; different pixels or shapes do not")
    func contentHash() {
        let same = RasterImage(width: 2, height: 2, pixels: Self.sample.pixels)
        let reshaped = RasterImage(width: 4, height: 1, pixels: Self.sample.pixels)
        var changed = Self.sample.pixels
        changed[0] = 254

        #expect(same.contentHash == Self.sample.contentHash)
        #expect(reshaped.contentHash != Self.sample.contentHash)
        #expect(RasterImage(width: 2, height: 2, pixels: changed).contentHash != Self.sample.contentHash)
    }
}
