import Foundation
import TablesideShared
import UniformTypeIdentifiers

/// Scrollkeeper's library list (`ScrollkeeperLibrary` in tabletop-kit's `TablesideShared`) as Pluck lists it.
extension ScrollkeeperLibrary {
    /// The titles Pluck can open, as the window lists them: those with a PDF, or with an archive Scrollkeeper
    /// unpacks, which may hold some (as in the index Scrollkeeper hands Pluck). Each has its cover in Scrollkeeper's
    /// `folder` and, when it is on disk in the shared download folder, the PDFs to open.
    func pluckIndex(in folder: URL) -> ScrollkeeperIndex {
        let files = downloadFolderURL(in: folder)
        let listed = titles.filter { $0.editions.contains(where: Self.mayHoldPDFs) }.map { title in
            var entry = ScrollkeeperIndex.Entry(sku: title.sku, title: title.title, kind: title.kind,
                                                series: title.series, number: title.number,
                                                downloaded: title.downloaded)
            entry.coverURL = title.coverURL(in: folder)
            entry.localFiles = files.map { title.filesToOpen(in: $0) { $0.conforms(to: .pdf) } } ?? []
            return entry
        }
        return ScrollkeeperIndex(formatVersion: formatVersion, generatedAt: generatedAt, titles: listed)
    }

    private static func mayHoldPDFs(_ edition: Edition) -> Bool {
        let type = UTType(filenameExtension: URL(filePath: edition.path).pathExtension)
        return edition.isFolder || type?.conforms(to: .pdf) == true
    }
}
