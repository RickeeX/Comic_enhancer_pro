import AppKit
import SwiftUI
import UniformTypeIdentifiers

private final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func exportSpread(vertical: Bool) {
        guard !busy, displayedIndices.count == 2 else { return }
        var indices = displayedIndices
        if rightToLeft && !vertical { indices.reverse() }
        let pages = indices.map { files[$0] }, plans = indices.map { book.values[files[$0]] ?? .neutral }
        let alert = NSAlert(); alert.messageText = vertical ? "垂直拼接两页" : "水平拼接两页"
        alert.informativeText = "分别执行两页各自的操作栈，再按第一页 DPI 匹配第二页并拼接。间距（0–1000 像素）："
        let field = NSTextField(string:"0"); field.frame = NSRect(x:0,y:0,width:260,height:26);alert.accessoryView = field
        alert.addButton(withTitle:"继续");alert.addButton(withTitle:"取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let gap = Int(field.stringValue), (0...1000).contains(gap) else { error = "间距需为 0–1000 像素。"; return }
        let panel = NSSavePanel(); let config = recipe
        panel.allowedContentTypes = [config.format == "jpg" ? .jpeg : config.format == "tiff" ? .tiff : .png]
        panel.nameFieldStringValue = String(format:"拼接_%04d_%04d.",indices[0],indices[1])+config.format
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !files.contains(where: { $0.url.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }) else { error = "不能覆盖源文件。"; return }
        busy = true; completed = 0; total = 2; status = "正在逐页处理并拼接…"
        let cancel = Cancellation(); cancellation = cancel
        queue.async {
            let result = Result { try autoreleasepool { () throws -> Void in
                let a = try Pipeline.render(pages[0],recipe:plans[0],preview:false,pageIndex:indices[0])
                guard !cancel.isCancelled else { throw ProcessingError.message("拼接已停止。") }
                DispatchQueue.main.async { self.completed = 1 }
                let b = try Pipeline.render(pages[1],recipe:plans[1],preview:false,pageIndex:indices[1])
                guard !cancel.isCancelled else { throw ProcessingError.message("拼接已停止。") }
                let merged = try Pipeline.stitch(a,b,vertical:vertical,gap:gap)
                try Pipeline.write(merged,to:url,recipe:config)
                let project = Project(pages:pages,recipes:zip(pages,plans).map { Project.PageRecipe(page:$0.0,recipe:$0.1) })
                let object = try JSONSerialization.jsonObject(with:JSONEncoder().encode(project))
                let record: [String:Any] = ["operation":"stitch","vertical":vertical,"gapPixels":gap,"project":object,"output":merged.description]
                try JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys]).write(to:url.appendingPathExtension("json"),options:.atomic)
            } }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success: self.completed = 2;self.status = "拼接已导出，参数记录保存在同名 JSON 中。";NSWorkspace.shared.activateFileViewerSelecting([url])
                case .failure(let e):self.error = e.localizedDescription;self.status = "拼接未完成。"
                }
            }
        }
    }
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}
final class Model: ObservableObject {
    @Published var files: [PageItem] = [] { didSet { pageIndices = Dictionary(uniqueKeysWithValues: files.enumerated().map { ($0.element, $0.offset) }) } }
    @Published var selection: PageItem? { didSet { if oldValue != selection { activatePage() } } }
    @Published var pdfMode = 0
    @Published var pdfDPI = 200
    @Published var importing = false
    @Published var recipe = Recipe.standard() {
        didSet {
            guard !loading, recipe != oldValue else { return }
            if let page = selection {
                remember(oldValue, page: page); book.values[page] = recipe
            }
            if recipe.stages != oldValue.stages { preview() }
        }
    }
    @Published var selectedStage: UUID?
    @Published var settings = Settings() {
        didSet {
            guard !loading, settings != oldValue, let i = recipe.stages.firstIndex(where: { $0.id == selectedStage }) else { return }
            var next = recipe; next.stages[i].settings = settings; recipe = next
        }
    }
    @Published var original: NSImage?
    @Published var enhanced: NSImage?
    @Published var secondOriginal: NSImage?
    @Published var secondEnhanced: NSImage?
    @Published var showOriginal = false
    @Published var doublePreview = false { didSet { preview() } }
    @Published var fullPreview = false { didSet { preview() } }
    @Published var rightToLeft = false
    @Published var showGrid = false
    @Published var displayedIndices: [Int] = []
    @Published var busy = false
    @Published var previewing = false
    @Published var completed = 0
    @Published var total = 0
    @Published var status = "导入图片或整本 PDF，逐页编辑。"
    @Published var sourceDescription = ""
    @Published var outputDescription = ""
    @Published var error: String?
    @Published var draggedStage: UUID?
    private var pageIndices: [PageItem: Int] = [:]
    private var spreadAnchor: PageItem?
    private struct PreviewEntry { var recipe: Recipe; var preview: Bool; var index: Int; var date: Date?; var value: PipelineResult }
    private var previewCache: [PageItem: PreviewEntry] = [:] // Accessed only on queue; at most the visible pair.
    private var loading = false
    private var book = RecipeBook()
    private var undo: [PageItem: [Recipe]] = [:], redo: [PageItem: [Recipe]] = [:]
    private let queue = DispatchQueue(label: "comic.processing", qos: .userInitiated)
    private var previewCancellation = Cancellation()
    private var previewWork: DispatchWorkItem?
    private var generation = UUID()
    private var cancellation = Cancellation()
    var activeIndex: Int? { selection.flatMap { pageIndices[$0] } }
    var stage: Stage? { recipe.stages.first { $0.id == selectedStage } }
    var canUndo: Bool { selection.map { !(undo[$0] ?? []).isEmpty } ?? false }
    var canRedo: Bool { selection.map { !(redo[$0] ?? []).isEmpty } ?? false }
    func indexLabel(_ page: PageItem) -> String { String(format: "%04d", pageIndices[page] ?? 0) }
    func navigate(_ delta: Int) { guard let index = activeIndex, files.indices.contains(index + delta) else { return }; selection = files[index + delta] }
    func navigatePreview(_ delta: Int) {
        guard let current = activeIndex else { return }
        let base = doublePreview ? displayedIndices.first ?? current : current
        let target = max(0, base + delta * (doublePreview ? 2 : 1))
        if files.indices.contains(target) { selection = files[target] }
    }
    private func renderedPreview(_ page: PageItem, recipe: Recipe, preview: Bool, index: Int) throws -> PipelineResult {
        let date = (try? page.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let entry = previewCache[page], entry.recipe.stages == recipe.stages, entry.preview == preview, entry.index == index, entry.date == date { return entry.value }
        let value = try Pipeline.render(page, recipe: recipe, preview: preview, pageIndex: index)
        previewCache[page] = PreviewEntry(recipe: recipe, preview: preview, index: index, date: date, value: value)
        return value
    }
    private func remember(_ recipe: Recipe, page: PageItem) {
        undo[page, default: []].append(recipe)
        if undo[page]!.count > 50 { undo[page]!.removeFirst() }; redo[page] = []
    }
    func undoEdit() {
        guard let page = selection, let previous = undo[page]?.popLast() else { return }
        redo[page, default: []].append(recipe); loadRecipe(previous, page: page)
    }
    func redoEdit() {
        guard let page = selection, let next = redo[page]?.popLast() else { return }
        undo[page, default: []].append(recipe); loadRecipe(next, page: page)
    }
    private func loadRecipe(_ next: Recipe, page: PageItem) {
        loading = true; recipe = next; book.values[page] = next
        let id = next.stages.contains(where: { $0.id == selectedStage }) ? selectedStage : next.stages.first?.id
        selectedStage = id; settings = next.stages.first(where: { $0.id == id })?.settings ?? Settings()
        loading = false; preview()
    }
    private func activatePage() {
        guard let page = selection else { preview(); return }
        let next = book.recipe(for: page)
        loadRecipe(next, page: page)
    }
    func chooseStage(_ id: UUID) {
        guard let step = recipe.stages.first(where: { $0.id == id }) else { return }
        loading = true; selectedStage = id; settings = step.settings; loading = false
    }
    func addStage(_ kind: StageKind) {
        guard recipe.stages.count < 64 else { error = "最多 64 个步骤。"; return }
        let step = Stage(kind); var next = recipe
        let index = kind == .despeckle ? next.stages.count : next.stages.firstIndex(where: { $0.kind == .binary }) ?? next.stages.count
        next.stages.insert(step, at: index); recipe = next; chooseStage(step.id)
    }
    func duplicateStage(_ id: UUID) {
        guard recipe.stages.count < 64, let i = recipe.stages.firstIndex(where: { $0.id == id }) else { return }
        let copy = recipe.stages[i].duplicated(); var next = recipe; next.stages.insert(copy, at: i+1); recipe = next; chooseStage(copy.id)
    }
    func removeStage(_ id: UUID) {
        var next = recipe; next.stages.removeAll { $0.id == id }; recipe = next
        if selectedStage == id { if let first = next.stages.first { chooseStage(first.id) } else { selectedStage = nil } }
    }
    func moveStage(_ id: UUID, to destination: Int) {
        guard let i = recipe.stages.firstIndex(where: { $0.id == id }), recipe.stages.indices.contains(destination), i != destination else { return }
        var next = recipe; let step = next.stages.remove(at: i); next.stages.insert(step, at: destination); recipe = next
    }
    func toggleStage(_ id: UUID) { guard let i = recipe.stages.firstIndex(where: { $0.id == id }) else { return }; recipe.stages[i].enabled.toggle() }
    func resetPage() { guard let page = selection else { return }; remember(recipe, page: page); loadRecipe(.standard(), page: page) }
    func copyRecipe() {
        do { _ = try recipe.validated(); let data = try JSONEncoder().encode(recipe); NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string); status = "已复制当前页的完整操作栈。" }
        catch { self.error = error.localizedDescription }
    }
    func pasteRecipe() {
        do {
            guard let text = NSPasteboard.general.string(forType: .string) else { return }
            recipe = try decodeRecipe(Data(text.utf8)); if let first = recipe.stages.first { chooseStage(first.id) }
        } catch { self.error = error.localizedDescription }
    }
    func applyRecipe(_ scope: String) {
        guard let current = activeIndex else { return }
        do {
            _ = try recipe.validated()
            let indices: Set<Int>
            if scope == "all" { indices = Set(files.indices) }
            else if scope == "after" { indices = Set(files.indices.filter { $0 > current }) }
            else {
                let alert = NSAlert(); alert.messageText = "应用到自选页面"
                alert.informativeText = "使用从 0000 开始的索引，例如 0000,0003-0008。会替换这些页面的完整操作栈。"
                let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 330, height: 26)); field.placeholderString = "0000,0003-0008"; alert.accessoryView = field
                alert.addButton(withTitle: "应用"); alert.addButton(withTitle: "取消")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                indices = try PageRanges.indices(field.stringValue, count: files.count)
            }
            for i in indices where files[i] != selection { remember(book.values[files[i]] ?? .neutral, page: files[i]) }
            try book.apply(recipe, indices: indices, pages: files); status = "已应用到 \(indices.count) 页；各页仍可独立编辑。"; preview()
        } catch { self.error = error.localizedDescription }
    }
    func addFiles() {
        guard !busy && !importing else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.message = "选择图片、PDF 或文件夹；PDF 使用左下方导入设置。"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls, embedded = pdfMode == 1, dpi = pdfDPI
        status = "正在建立页面索引…"; importing = true
        queue.async {
            var found: [PageItem] = [], errors: [String] = []
            func append(_ file: URL) {
                do { if file.pathExtension.lowercased() == "pdf" { found += try PDFLoader.items(file, embedded: embedded, dpi: dpi) }
                    else if Processor.extensions.contains(file.pathExtension.lowercased()) { found.append(PageItem(url: file)) }
                } catch { errors.append(error.localizedDescription) }
            }
            for url in urls {
                var directory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue {
                    if let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                        for case let file as URL in iterator {
                            let v = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                            if v?.isRegularFile == true && v?.isSymbolicLink != true { append(file) }
                        }
                    }
                } else { append(url) }
            }
            let imported = found, issues = errors
            DispatchQueue.main.async {
                self.files = Array(Set(self.files + imported)).sorted { $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending }
                if self.selection == nil { self.selection = self.files.first }
                self.preview()
                self.importing = false; self.status = "已导入 \(self.files.count) 页，各页参数独立。"
                if !issues.isEmpty { self.error = issues.prefix(5).joined(separator: "\n") }
            }
        }
    }
    func clearLibrary() {
        guard !busy && !importing else { return }
        previewCancellation.cancel(); queue.async { self.previewCache = [:] }; files = []; selection = nil; spreadAnchor = nil; book = RecipeBook(); undo = [:]; redo = [:]; status = "资料库已清空，原文件未删除。"
    }
    func preview() {
        guard !loading else { return }
        previewWork?.cancel(); previewCancellation.cancel(); generation = UUID()
        let cancel = Cancellation(); previewCancellation = cancel; let token = generation
        guard selection != nil, let index = activeIndex else {
            displayedIndices = []
            original = nil; enhanced = nil; secondOriginal = nil; secondEnhanced = nil; previewing = false; sourceDescription = ""; outputDescription = ""; return
        }
        var base = index
        if doublePreview, let anchor = spreadAnchor, let start = pageIndices[anchor], index == start || index == start+1 { base = start }
        spreadAnchor = files[base]
        let page = files[base]
        let firstRecipe = book.values[page] ?? .neutral, previewMode = !fullPreview
        let next = doublePreview && files.indices.contains(base+1) ? files[base+1] : nil
        displayedIndices = next == nil ? [base] : [base,base+1]
        let nextRecipe = next.map { book.values[$0] ?? .neutral }
        let firstIndex = base
        previewing = true
        let work = DispatchWorkItem {
            guard !cancel.isCancelled else { return }
            self.previewCache = self.previewCache.filter { $0.key == page || $0.key == next }
            let result = Result { try autoreleasepool { try self.renderedPreview(page, recipe: firstRecipe, preview: previewMode, index: firstIndex) } }
            guard !cancel.isCancelled else { return }
            let second: Result<PipelineResult, Error>? = next.flatMap { item in nextRecipe.map { config in Result { try autoreleasepool { try self.renderedPreview(item, recipe: config, preview: previewMode, index: firstIndex+1) } } } }
            guard !cancel.isCancelled else { return }
            self.previewCache = self.previewCache.filter { $0.key == page || $0.key == next }
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                self.previewing = false
                switch result {
                case .success(let value):
                    self.original = NSImage(cgImage: value.original, size: .zero); self.enhanced = NSImage(cgImage: value.image, size: .zero)
                    if index == firstIndex { self.sourceDescription = value.source.description; self.outputDescription = value.description }
                    self.status = "第 \(String(format: "%04d", index)) 页 · \(previewMode ? "缩略预览；可开启全尺寸检查细节" : "全尺寸预览")"
                case .failure(let e): self.original = nil; self.enhanced = nil; self.error = e.localizedDescription
                }
                self.secondOriginal = nil; self.secondEnhanced = nil
                if let second = second {
                    switch second {
                    case .success(let value):
                        self.secondOriginal = NSImage(cgImage: value.original, size: .zero); self.secondEnhanced = NSImage(cgImage: value.image, size: .zero)
                        if index != firstIndex { self.sourceDescription = value.source.description; self.outputDescription = value.description }
                    case .failure(let e): self.error = "后一页：" + e.localizedDescription
                    }
                }
            }
        }
        previewWork = work; queue.asyncAfter(deadline: .now()+0.2, execute: work)
    }
    private func decodeRecipe(_ data: Data) throws -> Recipe {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProcessingError.message("不是有效的参数文件。") }
        if object["stages"] != nil { return try JSONDecoder().decode(Recipe.self, from: data).validated() }
        guard ["brightness", "contrast", "gamma", "levels", "binarization", "format"].contains(where: { object[$0] != nil }) else { throw ProcessingError.message("文件不是操作栈或旧版参数。") }
        return try Recipe.legacy(JSONDecoder().decode(Settings.self, from: data))
    }
    func savePreset() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "操作栈.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { _ = try recipe.validated(); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(recipe).write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    func loadPreset() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { recipe = try decodeRecipe(Data(contentsOf: url)); if let first = recipe.stages.first { chooseStage(first.id) } }
        catch { self.error = error.localizedDescription }
    }
    func saveProject() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "书籍工程.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let project = Project(pages: files, recipes: files.compactMap { page in book.values[page].map { Project.PageRecipe(page: page, recipe: $0) } })
            try JSONEncoder().encode(project.validated()).write(to: url, options: .atomic); status = "工程已保存（含逐页操作栈，原文件需保留）。"
        } catch { self.error = error.localizedDescription }
    }
    func loadProject() {
        guard !busy && !importing else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let project = try JSONDecoder().decode(Project.self, from: Data(contentsOf: url)).validated()
            guard project.version == 1, project.pages.count <= 100000, Set(project.pages).count == project.pages.count else { throw ProcessingError.message("工程版本或页面列表无效。") }
            var next = RecipeBook()
            for row in project.recipes { next.values[row.page] = try row.recipe.validated() }
            book = next; undo = [:]; redo = [:]; files = project.pages; selection = nil; selection = files.first
            status = "已载入工程，共 \(files.count) 页。"
        } catch { self.error = error.localizedDescription }
    }
    func export(single: Bool) {
        guard !busy && !files.isEmpty else { return }
        let inputs = single ? selection.map { [$0] } ?? [] : files
        guard !inputs.isEmpty else { return }
        do { for page in inputs { _ = try (book.values[page] ?? .neutral).validated() } }
        catch { self.error = error.localizedDescription; return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.message = "新建独立导出目录；每页使用各自的操作栈，并写入 DPI。"
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let folder = parent.appendingPathComponent("ComicEnhancer-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) } catch { self.error = error.localizedDescription; return }
        let plans = inputs.map { book.values[$0] ?? .neutral }, indices = inputs.map { pageIndices[$0] ?? 0 }
        let project = Project(pages: files, recipes: files.compactMap { page in book.values[page].map { Project.PageRecipe(page: page, recipe: $0) } })
        let cancel = Cancellation(); cancellation = cancel; busy = true; completed = 0; total = inputs.count; status = "正在按逐页设置导出…"
        queue.async {
            var succeeded = 0, failed = 0, processed = 0, log = "Comic Enhancer operation-stack export\n"
            for (index, page) in inputs.enumerated() {
                if cancel.isCancelled { break }
                autoreleasepool {
                    do {
                        let config = plans[index]
                        let name = config.filename(index:indices[index],page:page)
                        let destination = folder.appendingPathComponent(name)
                        guard !FileManager.default.fileExists(atPath:destination.path) else { throw ProcessingError.message("输出名称冲突："+name) }
                        let value = try Pipeline.render(page, recipe: config, preview: false, pageIndex: indices[index])
                        try Pipeline.write(value, to: destination, recipe: config)
                        succeeded += 1; log += "OK\t\(page.path)\t\(name)\t\(value.description)\n"
                    } catch { failed += 1; log += "ERROR\t\(page.path)\t\(error.localizedDescription)\n" }
                }
                processed += 1; let count = processed; DispatchQueue.main.async { self.completed = count }
            }
            var recordError = ""
            do { try log.write(to: folder.appendingPathComponent("export.log"), atomically: true, encoding: .utf8); try JSONEncoder().encode(project).write(to: folder.appendingPathComponent("project.json"), options: .atomic) }
            catch { recordError = "；工程／日志写入失败：\(error.localizedDescription)" }
            let summary = "\(cancel.isCancelled ? "已停止" : "已完成")：成功 \(succeeded)，失败 \(failed)，未处理 \(inputs.count-processed)\(recordError)"
            DispatchQueue.main.async { self.busy = false; self.status = summary; if failed > 0 || !recordError.isEmpty { self.error = summary }; NSWorkspace.shared.activateFileViewerSelecting([folder]) }
        }
    }
    func cancel() { cancellation.cancel(); status = "将在当前页完成后停止…" }
}
