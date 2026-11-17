import Foundation

/// The text of the pages shown, as the text view and its export see it.
extension PluckModel {
    /// The pages whose text is shown: the selected ones, or all of them, in page order.
    public var textPageIndexes: [Int] {
        selectedPages.isEmpty ? Array(0..<pageCount) : selectedPages.sorted()
    }

    /// The text of the shown pages as blocks. Paragraphs cut by a page break are rejoined
    /// where the pages are consecutive.
    public var visibleTextBlocks: [TextBlock] {
        var runs: [[[TextBlock]]] = []
        var previousIndex: Int?
        for index in textPageIndexes {
            guard let blocks = pageTexts[index] else { continue }
            if let previousIndex, index == previousIndex + 1 {
                runs[runs.count - 1].append(blocks)
            } else {
                runs.append([blocks])
            }
            previousIndex = index
        }
        return runs.flatMap(TextFlow.join)
    }

    /// The text of the shown pages in the chosen format, one line per paragraph.
    public var visibleText: String {
        TextRenderer(format: textFormat, options: TextRenderOptions(defaults: defaults)).render(visibleTextBlocks)
    }

    /// A file name for exported text, such as `Scenario.md`.
    public var textFileName: String {
        let stem = documentURL?.deletingPathExtension().lastPathComponent ?? "text"
        return "\(stem).\(textFormat.fileExtension)"
    }
}
