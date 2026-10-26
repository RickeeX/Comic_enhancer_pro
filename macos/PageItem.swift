import Foundation

struct PageItem: Hashable, Identifiable {
    let url: URL
    var pdfPage: Int? = nil // One-based PDF page; nil for an ordinary image.
    var embeddedIndex: Int? = nil
    var dpi: Int = 200
    var id: Self { self }
    var title: String {
        guard let page = pdfPage else { return url.lastPathComponent }
        return "\(url.deletingPathExtension().lastPathComponent) · \(page) 页" + (embeddedIndex.map { " · 图 \($0 + 1)" } ?? "")
    }
    var path: String { url.path + (pdfPage.map { "#page=\($0),image=\(embeddedIndex.map(String.init) ?? "render"),dpi=\(dpi)" } ?? "") }
    var sortKey: String { url.path + String(format: "#%08d-%08d", pdfPage ?? 0, embeddedIndex ?? -1) }
    var exportStem: String {
        url.deletingPathExtension().lastPathComponent + (pdfPage.map { String(format: "_page%05d", $0) } ?? "") + (embeddedIndex.map { "_image\($0 + 1)" } ?? "")
    }
}
