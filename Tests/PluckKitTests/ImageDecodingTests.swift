import Foundation
@testable import PluckKit
import Testing

@Suite("Decoding PDF images")
struct ImageDecodingTests {
    private static let fourColors = Color.red + Color.green + Color.blue + Color.white

    @Test("Raw RGB samples come out pixel-exact and opaque")
    func rawRGB() throws {
        let page = try ExtractedPage.single { $0.addRGBImage(width: 2, height: 2, samples: Self.fourColors) }

        let image = try #require(page.rasters.first)
        #expect(image.width == 2 && image.height == 2)
        #expect(image.pixel(0, 0) == Color.red + [255])
        #expect(image.pixel(1, 0) == Color.green + [255])
        #expect(image.pixel(0, 1) == Color.blue + [255])
        #expect(image.pixel(1, 1) == Color.white + [255])
    }

    @Test("Grey samples keep their exact values")
    func rawGray() throws {
        let page = try ExtractedPage.single { $0.addGrayImage(width: 3, height: 1, samples: [0, 128, 255]) }

        let image = try #require(page.rasters.first)
        #expect(image.pixel(0, 0) == [0, 0, 0, 255])
        #expect(image.pixel(1, 0) == [128, 128, 128, 255])
        #expect(image.pixel(2, 0) == [255, 255, 255, 255])
    }

    @Test("One-bit images honour row padding and the Decode array")
    func oneBitWithDecode() throws {
        let page = try ExtractedPage.single {
            $0.addImage(
                width: 2, height: 2, entries: "/ColorSpace /DeviceGray /BitsPerComponent 1 /Decode [1 0]",
                data: Data([0b1000_0000, 0b0100_0000]))
        }

        let image = try #require(page.rasters.first)
        #expect(image.pixel(0, 0) == Color.black + [255])
        #expect(image.pixel(1, 0) == Color.white + [255])
        #expect(image.pixel(0, 1) == Color.white + [255])
        #expect(image.pixel(1, 1) == Color.black + [255])
    }

    @Test("Sixteen-bit samples are read big-endian")
    func sixteenBit() throws {
        let page = try ExtractedPage.single {
            $0.addImage(
                width: 1, height: 1, entries: "/ColorSpace /DeviceRGB /BitsPerComponent 16",
                data: Data([0xFF, 0xFF, 0x00, 0x00, 0x80, 0x00]))
        }

        #expect(isClose(try #require(page.rasters.first).pixel(0, 0), [255, 0, 128, 255], tolerance: 1))
    }

    @Test("Indexed colour looks samples up in the palette")
    func indexed() throws {
        let page = try ExtractedPage.single {
            $0.addImage(
                width: 2, height: 1, entries: "/ColorSpace [/Indexed /DeviceRGB 1 <FF00000000FF>] /BitsPerComponent 8",
                data: Data([1, 0]))
        }

        let image = try #require(page.rasters.first)
        #expect(image.pixel(0, 0) == Color.blue + [255])
        #expect(image.pixel(1, 0) == Color.red + [255])
    }

    @Test("CMYK is converted to RGB")
    func cmyk() throws {
        let page = try ExtractedPage.single {
            $0.addImage(
                width: 2, height: 1, entries: "/ColorSpace /DeviceCMYK /BitsPerComponent 8",
                data: Data([0, 0, 0, 0, 0, 0, 0, 255]))
        }

        let image = try #require(page.rasters.first)
        #expect(isClose(image.pixel(0, 0), Color.white + [255]))
        #expect(isClose(image.pixel(1, 0), Color.black + [255], tolerance: 60))
    }

    @Test("A Separation ink is approximated as grey, with full ink dark")
    func separation() throws {
        let page = try ExtractedPage.single { builder in
            let tint = builder.addObject("<< /FunctionType 2 /Domain [0 1] /C0 [1] /C1 [0] /N 1 >>")
            return builder.addImage(
                width: 2, height: 1,
                entries: "/ColorSpace [/Separation /Black /DeviceGray \(tint) 0 R] /BitsPerComponent 8",
                data: Data([255, 0]))
        }

        let image = try #require(page.rasters.first)
        #expect(image.pixel(0, 0) == Color.black + [255])
        #expect(image.pixel(1, 0) == Color.white + [255])
    }

    @Test("JPEG streams are decoded")
    func jpeg() throws {
        let jpeg = try Fixture.jpeg(color: Color.red, width: 8, height: 6)
        let page = try ExtractedPage.single {
            $0.addImage(
                width: 8, height: 6, entries: "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode",
                data: jpeg)
        }

        let image = try #require(page.rasters.first)
        #expect(image.width == 8 && image.height == 6)
        #expect(isClose(image.pixel(4, 3), Color.red + [255]))
    }

    @Test("A CMYK JPEG's samples mean what they say unless its Decode array inverts them")
    func cmykJPEG() throws {
        let orange: [UInt8] = [0, 128, 255, 0]
        let jpeg = try Fixture.cmykJPEG(ink: orange, width: 8, height: 6)  // Stores the inverted samples.
        let entries = "/ColorSpace /DeviceCMYK /BitsPerComponent 8 /Filter /DCTDecode"
        let inverted = try ExtractedPage.single {
            $0.addImage(width: 8, height: 6, entries: entries + " /Decode [1 0 1 0 1 0 1 0]", data: jpeg)
        }
        let plain = try ExtractedPage.single { $0.addImage(width: 8, height: 6, entries: entries, data: jpeg) }

        let expectedOrange = try Fixture.rendered(ink: orange)
        let expectedStored = try Fixture.rendered(ink: orange.map { 255 - $0 })
        let invertedPixel = try #require(inverted.rasters.first).pixel(4, 3)
        let plainPixel = try #require(plain.rasters.first).pixel(4, 3)
        #expect(isClose(invertedPixel, expectedOrange), "\(invertedPixel) should be \(expectedOrange)")
        #expect(isClose(plainPixel, expectedStored), "\(plainPixel) should be \(expectedStored)")
    }

    @Test("An image with an unusable colour space is counted, not fatal")
    func undecodable() throws {
        let builder = PDFBuilder()
        let broken = builder.addImage(
            width: 1, height: 1, entries: "/ColorSpace /Pattern /BitsPerComponent 8", data: Data([0]))
        let truncated = builder.addRGBImage(width: 4, height: 4, samples: [1, 2, 3])
        let good = builder.addSolidImage(Color.green)
        builder.addPage(painting: [broken, truncated, good])

        let page = try ExtractedPage(builder)
        #expect(page.result.failureCount == 2)
        #expect(page.rasters.map { $0.pixel(0, 0) } == [Color.green + [255]])
    }
}
