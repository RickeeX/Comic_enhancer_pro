import AppKit
import SwiftUI
import UniformTypeIdentifiers

private final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}
final class Model: ObservableObject {
    @Published var files: [PageItem] = []
    @Published var selection: PageItem?
    @Published var pdfMode = 0
    @Published var pdfDPI = 200
    @Published var importing = false
    @Published var settings = Settings()
    @Published var original: NSImage?
    @Published var enhanced: NSImage?
    @Published var showOriginal = false
    @Published var busy = false
    @Published var previewing = false
    @Published var completed = 0
    @Published var total = 0
    @Published var status = "导入扫描页，开始修复你的漫画。"
    @Published var error: String?
    private let queue = DispatchQueue(label: "comic.processing", qos: .userInitiated)
    private var previewCancellation = Cancellation()
    private var previewWork: DispatchWorkItem?
    private var generation = UUID()
    private var cancellation = Cancellation()

    func addFiles() {
        guard !busy && !importing else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.message = "选择图片、PDF 或文件夹；PDF 按左下方选定方式导入。"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        status = "正在建立页面索引…"; importing = true
        let embedded = pdfMode == 1, dpi = pdfDPI
        queue.async {
            var found: [PageItem] = [], errors: [String] = []
            func append(_ file: URL) {
                do {
                    if file.pathExtension.lowercased() == "pdf" { found += try PDFLoader.items(file, embedded: embedded, dpi: dpi) }
                    else if Processor.extensions.contains(file.pathExtension.lowercased()) { found.append(PageItem(url: file)) }
                } catch { errors.append(error.localizedDescription) }
            }
            for url in urls {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                        for case let file as URL in iterator {
                            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                            if values?.isRegularFile == true && values?.isSymbolicLink != true { append(file) }
                        }
                    }
                } else { append(url) }
            }
            let imported = found, issues = errors
            DispatchQueue.main.async {
                self.files = Array(Set(self.files + imported)).sorted { $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending }
                if self.selection == nil { self.selection = self.files.first }
                self.importing = false
                self.status = "已导入 \(self.files.count) 页"
                if !issues.isEmpty { self.error = issues.prefix(5).joined(separator: "\n") }
            }
        }
    }
    func preview() {
        previewWork?.cancel(); previewCancellation.cancel(); generation = UUID()
        let cancel = Cancellation(); previewCancellation = cancel
        let token = generation
        guard let url = selection else { original = nil; enhanced = nil; previewing = false; return }
        let options = settings
        previewing = true
        let work = DispatchWorkItem {
            guard !cancel.isCancelled else { return }
            let result = Result { try autoreleasepool { try Processor.render(url, settings: options, preview: true) } }
            guard !cancel.isCancelled else { return }
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                self.previewing = false
                switch result {
                case .success(let value):
                    self.original = NSImage(cgImage: value.original, size: .zero)
                    self.enhanced = NSImage(cgImage: value.enhanced, size: .zero)
                case .failure(let e): self.original = nil; self.enhanced = nil; self.error = e.localizedDescription
                }
            }
        }
        previewWork = work
        queue.asyncAfter(deadline: .now() + 0.18, execute: work)
    }
    func savePreset() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "漫画增强.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(settings).write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    func loadPreset() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: url)).validated() }
        catch { self.error = error.localizedDescription }
    }
    func export(single: Bool) {
        guard !busy, !files.isEmpty else { return }
        let inputs = single ? selection.map { [$0] } ?? [] : files
        guard !inputs.isEmpty else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.message = "将在所选目录下新建独立导出文件夹，原图保持不变。"
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let folder = parent.appendingPathComponent("ComicEnhancer-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
        catch { self.error = error.localizedDescription; return }
        let options = settings
        let cancel = Cancellation(); cancellation = cancel
        busy = true; completed = 0; total = inputs.count; status = "正在导出…"
        queue.async {
            var succeeded = 0, failed = 0, processed = 0
            var log = "Comic Enhancer export\n"
            for (index, url) in inputs.enumerated() {
                if cancel.isCancelled { break }
                autoreleasepool {
                    do {
                        let value = try Processor.render(url, settings: options, preview: false)
                        let name = String(format: "%05d_", index + 1) + url.exportStem + "." + options.format
                        try Processor.write(value.enhanced, to: folder.appendingPathComponent(name), settings: options)
                        succeeded += 1
                        log += "OK\t\(url.path)\t\(name)\n"
                    } catch { failed += 1; log += "ERROR\t\(url.path)\t\(error.localizedDescription)\n" }
                }
                processed += 1
                let count = processed
                DispatchQueue.main.async { self.completed = count }
            }
            log += "succeeded=\(succeeded) failed=\(failed) cancelled=\(cancel.isCancelled)\n"
            var logError = ""
            do {
                try log.write(to: folder.appendingPathComponent("export.log"), atomically: true, encoding: .utf8)
                try JSONEncoder().encode(options).write(to: folder.appendingPathComponent("settings.json"), options: .atomic)
            } catch { logError = "；记录保存失败：\(error.localizedDescription)" }
            let summary = "\(cancel.isCancelled ? "已停止" : "已完成")：成功 \(succeeded)，失败 \(failed)，未处理 \(inputs.count - processed)\(logError)"
            DispatchQueue.main.async {
                self.busy = false; self.status = summary
                if failed > 0 || !logError.isEmpty { self.error = summary + "\n详情见导出目录中的 export.log。" }
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            }
        }
    }
    func cancel() { cancellation.cancel(); status = "将在当前页处理完成后停止…" }
}
