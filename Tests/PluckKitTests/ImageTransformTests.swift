import Foundation
@testable import PluckKit
import Testing

@Suite("Rotating and flipping")
struct ImageTransformTests {
    /// A 3 × 2 image in which every pixel is distinct, so any misplacement shows.
    private static let sample = RasterImage(rows: [
        [[10, 0, 0, 255], [20, 0, 0, 255], [30, 0, 0, 255]],
        [[40, 0, 0, 255], [50, 0, 0, 255], [60, 0, 0, 255]]
    ])

    /// The red channel of each pixel, row by row: a compact picture of the layout.
    private func layout(_ image: RasterImage) -> [[UInt8]] {
        (0..<image.height).map { row in (0..<image.width).map { image.pixel($0, row)[0] } }
    }

    private func layout(after edits: ImageEdit...) throws -> [[UInt8]] {
        let transform = edits.reduce(ImageTransform.identity) { $0.applying($1) }
        return layout(try transform.apply(to: Self.sample))
    }

    /// Performs one edit by moving pixels directly: the oracle the transform is checked against.
    private func reference(_ edit: ImageEdit, _ rows: [[UInt8]]) -> [[UInt8]] {
        let columns = rows[0].indices
        switch edit {
        case .flipHorizontal: return rows.map { $0.reversed() }
        case .flipVertical: return rows.reversed()
        case .rotateRight: return columns.map { column in rows.reversed().map { $0[column] } }
        case .rotateLeft: return columns.reversed().map { column in rows.map { $0[column] } }
        }
    }

    @Test("Rotate right turns the image clockwise")
    func rotateRight() throws {
        #expect(try layout(after: .rotateRight) == [[40, 10], [50, 20], [60, 30]])
    }

    @Test("Rotate left turns the image anticlockwise")
    func rotateLeft() throws {
        #expect(try layout(after: .rotateLeft) == [[30, 60], [20, 50], [10, 40]])
    }

    @Test("Flip horizontal mirrors left to right")
    func flipHorizontal() throws {
        #expect(try layout(after: .flipHorizontal) == [[30, 20, 10], [60, 50, 40]])
    }

    @Test("Flip vertical mirrors top to bottom")
    func flipVertical() throws {
        #expect(try layout(after: .flipVertical) == [[40, 50, 60], [10, 20, 30]])
    }

    @Test("The identity transform returns the image untouched")
    func identity() throws {
        #expect(ImageTransform.identity.isIdentity)
        #expect(try ImageTransform.identity.apply(to: Self.sample) == Self.sample)
    }

    @Test("Four quarter turns, or two identical flips, return to the start", arguments: ImageEdit.allCases)
    func editsCancelOut(edit: ImageEdit) {
        let isRotation = edit == .rotateLeft || edit == .rotateRight
        let result = (0..<(isRotation ? 4 : 2)).reduce(ImageTransform.identity) { transform, _ in
            transform.applying(edit)
        }
        #expect(result.isIdentity)
    }

    @Test("Any sequence of edits composes to the same picture as doing them one by one")
    func composition() throws {
        var sequences: [[ImageEdit]] = [[]]
        for _ in 0..<4 {
            sequences = sequences.flatMap { sequence in ImageEdit.allCases.map { sequence + [$0] } }
            for sequence in sequences {
                let transform = sequence.reduce(ImageTransform.identity) { $0.applying($1) }
                let expected = sequence.reduce(layout(Self.sample)) { reference($1, $0) }
                #expect(layout(try transform.apply(to: Self.sample)) == expected, "\(sequence)")
            }
        }
    }

    @Test("Transparent pixels stay transparent when transformed")
    func keepsAlpha() throws {
        let image = RasterImage(rows: [[[255, 0, 0, 255], [0, 0, 0, 0]]])
        let flipped = try ImageTransform.identity.applying(.flipHorizontal).apply(to: image)
        #expect(flipped.alphas == [0, 255])
        #expect(flipped.pixel(1, 0) == [255, 0, 0, 255])
    }
}
