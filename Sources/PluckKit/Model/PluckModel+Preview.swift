import Foundation

extension PluckModel {
    /// The selected images as PNG files in a new temporary folder, rotated and flipped as shown, for Quick Look.
    public func previewSelection() async throws -> [URL] {
        let requests = try selectedImages.map { try renderRequest(for: $0) }
        let folder = FileManager.default.temporaryDirectory.appending(path: "Preview/\(UUID().uuidString)")
        return try await Task.detached {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return try requests.enumerated().map { index, request in
                let url = folder.appending(path: "Image \(index + 1).png")
                try PNGEncoder.encode(request.render()).write(to: url)
                return url
            }
        }.value
    }
}
