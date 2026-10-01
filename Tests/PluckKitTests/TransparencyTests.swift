import Foundation
@testable import PluckKit
import Testing

@Suite("Honouring transparency")
struct TransparencyTests {
    private static let fourReds = Array(repeating: Color.red, count: 4).flatMap { $0 }

    @Test("A soft mask becomes the alpha channel")
    func softMask() throws {
        let page = try ExtractedPage.single { builder in
            let mask = builder.addGrayImage(width: 2, height: 2, samples: [0, 85, 170, 255])
            return builder.addRGBImage(width: 2, height: 2, samples: Self.fourReds, entries: "/SMask \(mask) 0 R")
        }

        let image = try #require(page.rasters.first)
        #expect(image.alphas == [0, 85, 170, 255])
        #expect(image.pixel(1, 1) == Color.red + [255])
        #expect(Array(image.pixel(1, 0).prefix(3)) == Color.red, "colour under partial alpha is not premultiplied")
    }

    @Test("A soft mask of a different resolution is resampled to the image")
    func softMaskResampled() throws {
        let page = try ExtractedPage.single { builder in
            let mask = builder.addGrayImage(width: 1, height: 1, samples: [128])
            return builder.addRGBImage(width: 2, height: 2, samples: Self.fourReds, entries: "/SMask \(mask) 0 R")
        }

        #expect(try #require(page.rasters.first).alphas == [128, 128, 128, 128])
    }

    @Test("A soft mask applies to a JPEG image")
    func softMaskOnJPEG() throws {
        let jpeg = try Fixture.jpeg(color: Color.blue, width: 8, height: 8)
        let page = try ExtractedPage.single { builder in
            let mask = builder.addGrayImage(width: 8, height: 8, samples: [UInt8](repeating: 64, count: 64))
            return builder.addImage(
                width: 8, height: 8,
                entries: "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /SMask \(mask) 0 R",
                data: jpeg)
        }

        let image = try #require(page.rasters.first)
        #expect(Set(image.alphas) == [64])
        #expect(isClose(Array(image.pixel(3, 3).prefix(3)), Color.blue))
    }

    @Test("A stencil mask hides the pixels whose mask bit is set")
    func stencilMask() throws {
        let page = try ExtractedPage.single { builder in
            let mask = builder.addImage(
                width: 2, height: 2, entries: "/ImageMask true /BitsPerComponent 1",
                data: Data([0b0100_0000, 0b1000_0000]))
            return builder.addRGBImage(width: 2, height: 2, samples: Self.fourReds, entries: "/Mask \(mask) 0 R")
        }

        #expect(try #require(page.rasters.first).alphas == [255, 0, 0, 255])
    }

    @Test("A colour-key mask makes the keyed colour transparent")
    func colorKeyMask() throws {
        let page = try ExtractedPage.single {
            $0.addRGBImage(
                width: 2, height: 1, samples: Color.red + Color.blue, entries: "/Mask [255 255 0 0 0 0]")
        }

        let image = try #require(page.rasters.first)
        #expect(image.alphas == [0, 255])
        #expect(image.pixel(1, 0) == Color.blue + [255])
    }

    @Test("A stencil image is extracted as black on transparent")
    func stencilImage() throws {
        let page = try ExtractedPage.single {
            $0.addImage(width: 2, height: 1, entries: "/ImageMask true /BitsPerComponent 1", data: Data([0b0100_0000]))
        }

        let image = try #require(page.rasters.first)
        #expect(image.pixel(0, 0) == Color.black + [255])
        #expect(image.pixel(1, 0) == Color.black + [0])
    }
}
