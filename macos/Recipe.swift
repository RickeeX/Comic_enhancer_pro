import Foundation

enum StageKind: String, Codable, CaseIterable, Identifiable {
    case page, resize, rotate, deskew, crop, layout, tone, sharpen, blur, gray, binary, despeckle, mirror, invert
    var id: String { rawValue }
    var title: String {
        switch self {
        case .page: return "综合页面（旧预设兼容）"
        case .resize: return "重采样 / 物理 DPI"
        case .rotate: return "页面旋转"
        case .deskew: return "水平矫正"
        case .crop: return "分页 / 裁边 / 内容框"
        case .layout: return "统一页面 / 边距"
        case .tone: return "亮度 · 对比度 · Gamma"
        case .sharpen: return "锐化"
        case .blur: return "模糊 / 降噪"
        case .gray: return "灰度 / 减色"
        case .binary: return "二值化 / 温和去毛刺"
        case .despeckle: return "独立去黑点 / 黑边"
        case .mirror: return "镜像 / 翻转"
        case .invert: return "反色"
        }
    }
    var symbol: String {
        switch self {
        case .page, .resize, .rotate, .deskew, .crop, .layout: return "doc.viewfinder"
        case .tone: return "circle.lefthalf.filled"
        case .sharpen: return "triangle"
        case .blur: return "drop"
        case .gray: return "circle.dotted"
        case .binary: return "circle.righthalf.filled"
        case .despeckle: return "eraser"
        case .mirror: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .invert: return "circle.lefthalf.filled"
        }
    }
}
struct Stage: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: StageKind
    var enabled = true
    var settings = Settings()
    init(_ kind: StageKind) { self.kind = kind }
    func duplicated() -> Stage { var copy = self; copy.id = UUID(); return copy }
    var summary: String {
        let s = settings
        func n(_ value: Double) -> String { String(format: "%.1f", value) }
        func yes(_ value: Bool) -> String { value ? "开" : "关" }
        switch kind {
        case .tone: return "亮度=\(n((s.brightness + 1) * 100)), 对比度=\(n(s.contrast * 100)), Gamma=\(n(s.gamma * 100)), 白点=\(n(s.whitePoint * 100)), 自动色阶=\(yes(s.autoLevels))"
        case .sharpen: return "算法=\(s.sharpenMethod == 0 ? "USM" : "Laplacian"), 强度=\(n(s.sharpen * 100)), 半径(USM)=\(s.filterRadius)px, 阈值=\(n(s.sharpenThreshold))"
        case .blur: return "算法=\(["高斯", "Box 均值", "中值", "双边"][s.blurMethod]), 强度=\(n(s.blur * 100)), 半径=\(s.filterRadius)px, 色差σ(双边)=\(n(s.edgeSigma))"
        case .gray: return "灰度=\(yes(s.grayscale || s.levels > 0)), 减色=\(s.levels == 0 ? "连续" : "\(s.levels)级"), 抖动=\(["无", "Bayer", "Floyd–Steinberg"][s.dither])"
        case .binary: return "算法=\(["关闭", "固定阈值", "Otsu", "Sauvola"][s.binarization]), 阈值=\(n(s.threshold)), 窗口半径=\(s.adaptiveRadius)px, k=\(n(s.sauvolaK)), 温和去毛刺=\(yes(s.edgeSmooth)), 次数=\(s.smoothPasses), 补凹口=\(yes(s.fillNotches))"
        case .despeckle: return "最大黑点直径=\(s.despeckleDiameter)px, 黑色灰度阈值=\(s.despeckleThreshold), 清除连边黑区=\(yes(s.removeBorders))"
        case .mirror: return "水平镜像=\(yes(s.flipHorizontal)), 上下翻转=\(yes(s.flipVertical))"
        case .invert: return "RGB=255−原值"
        case .resize:
            return "源X DPI=\(s.sourceDPI == 0 ? "自动／缺失300" : n(s.sourceDPI)), 源Y DPI=\(s.sourceDPIY == 0 ? "跟随X／自动" : n(s.sourceDPIY)), 保持物理尺寸=\(yes(s.preservePhysical)), 目标DPI=\(n(s.targetDPI)), 缩放=\(n(s.scale*100))%, 重采样=\(["最近邻", "双线性", "双三次"][s.resampleMethod])"
        case .rotate: return "顺时针旋转=\(s.rotation*90)°"
        case .deskew: return "自动=\(["关闭", "横排", "竖排"][s.deskew]), 范围±\(n(s.deskewLimit))°, 微调=\(n(s.angle))°, 边角填白"
        case .crop: return "分页=\(["整页", "左页", "右页"][s.page]), L/R/T/B=\(n((s.crop+s.cropLeft)*100))/\(n((s.crop+s.cropRight)*100))/\(n((s.crop+s.cropTop)*100))/\(n((s.crop+s.cropBottom)*100))%, 内容框=\(yes(s.autoTrim)), 阈值=\(s.trimThreshold), 忽略直径=\(s.trimIgnore)px, 补偿=\(s.trimPadding)px, 清连边=\(yes(s.removeBorders)), 奇偶交换=\(yes(s.alternateMargins))"
        case .layout: return "页面=\(["保持", "指定宽", "指定高", "指定宽高", "内容加边距"][s.pageMode]), W/H=\(n(s.pageWidth))/\(n(s.pageHeight))\(s.pageUnit == 0 ? "cm" : "px"), 边距L/R/T/B=\(n(s.marginLeft))/\(n(s.marginRight))/\(n(s.marginTop))/\(n(s.marginBottom)), 排布=\(["完整放入", "铺满裁切", "拉伸"][s.fitMode]), 对齐=\(s.alignX)/\(s.alignY), 奇偶交换=\(yes(s.alternateMargins)), 重采样=\(["最近邻", "双线性", "双三次"][s.resampleMethod])"
        case .page:
            return "分页=\(["整页", "左页", "右页"][s.page]), 旋转=\(s.rotation * 90)°, 纠斜=\(["关闭", "横排", "竖排"][s.deskew]), 范围±\(n(s.deskewLimit))°, 微调=\(n(s.angle))°, 裁边 L/R/T/B=\(n((s.cropLeft+s.crop)*100))/\(n((s.cropRight+s.crop)*100))/\(n((s.cropTop+s.crop)*100))/\(n((s.cropBottom+s.crop)*100))%, 自动内容框=\(yes(s.autoTrim)), 内容阈值=\(s.trimThreshold), 清连边=\(yes(s.removeBorders)), 忽略斑点=\(s.trimIgnore)px, 补偿=\(s.trimPadding)px, 源DPI=\(s.sourceDPI == 0 ? "自动／缺失时300" : n(s.sourceDPI)), 源Y DPI=\(s.sourceDPIY == 0 ? "跟随X或自动" : n(s.sourceDPIY)), 保持物理尺寸=\(yes(s.preservePhysical)), 目标DPI=\(n(s.targetDPI)), 缩放=\(n(s.scale*100))%, 页面=\(["原尺寸", "指定宽", "指定高", "指定宽高", "内容加边距"][s.pageMode]), W/H=\(n(s.pageWidth))/\(n(s.pageHeight))\(s.pageUnit == 0 ? "cm" : "px"), 边距 L/R/T/B=\(n(s.marginLeft))/\(n(s.marginRight))/\(n(s.marginTop))/\(n(s.marginBottom)), 排布=\(["等比完整", "等比铺满裁切", "拉伸校正宽高"][s.fitMode]), 对齐=\(s.alignX)/\(s.alignY), 奇偶镜像边距=\(yes(s.alternateMargins)), 重采样=\(["最近邻", "双线性", "双三次"][s.resampleMethod])"
        }
    }
}
struct Recipe: Codable, Equatable {
    var stages: [Stage]
    var format = "png"
    var quality: Double = 0.9
    var nameStyle = 0
    var namePrefix = ""
    var nameDigits = 4
    init(stages: [Stage]) { self.stages = stages }
    private enum CodingKeys: String, CodingKey { case stages, format, quality, nameStyle, namePrefix, nameDigits }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stages = try c.decode([Stage].self,forKey:.stages)
        format = try c.decodeIfPresent(String.self,forKey:.format) ?? "png"
        quality = try c.decodeIfPresent(Double.self,forKey:.quality) ?? 0.9
        nameStyle = try c.decodeIfPresent(Int.self,forKey:.nameStyle) ?? 0
        namePrefix = try c.decodeIfPresent(String.self,forKey:.namePrefix) ?? ""
        nameDigits = try c.decodeIfPresent(Int.self,forKey:.nameDigits) ?? 4
    }
    func filename(index: Int, page: PageItem) -> String {
        namePrefix + String(format:"%0*d",nameDigits,index) + (nameStyle == 0 ? "_"+page.exportStem : "") + "."+format
    }
    static let neutral = Recipe.standard()
    static func standard() -> Recipe { Recipe(stages: [.resize, .tone, .blur, .sharpen, .gray, .binary].map(Stage.init)) }
    func validated() throws -> Recipe {
        guard stages.count <= 64, Set(stages.map(\.id)).count == stages.count,
              ["png", "jpg", "tiff"].contains(format), quality.isFinite, (0.1...1).contains(quality), (0...1).contains(nameStyle), (4...8).contains(nameDigits),
              namePrefix.utf8.count <= 100, !namePrefix.contains("/"), !namePrefix.contains("\\"), !namePrefix.contains("\0") else {
            throw ProcessingError.message("操作栈无效（最多 64 步，步骤编号必须唯一）。")
        }
        for stage in stages { _ = try stage.settings.validated() }
        return self
    }
    static func legacy(_ settings: Settings) throws -> Recipe {
        let s = try settings.validated()
        var recipe = Recipe(stages: [.page, .tone, .blur, .sharpen, .gray, .binary].map(Stage.init)); recipe.format = s.format; recipe.quality = s.quality
        for i in recipe.stages.indices { recipe.stages[i].settings = s; recipe.stages[i].settings.cleanup = 0 }
        if s.cleanup == 1 {
            var stage = Stage(.despeckle); stage.settings.despeckleDiameter = 1
            recipe.stages.append(stage)
        }
        return recipe
    }
}
struct Project: Codable {
    var version = 1
    var pages: [PageItem]
    var recipes: [PageRecipe]
    struct PageRecipe: Codable { var page: PageItem; var recipe: Recipe }
    func validated() throws -> Project {
        let set = Set(pages)
        guard version == 1, pages.count <= 100000, set.count == pages.count, recipes.count <= pages.count,
              Set(recipes.map(\.page)).count == recipes.count, recipes.allSatisfy({ set.contains($0.page) }),
              pages.allSatisfy({ $0.url.isFileURL && (72...1200).contains($0.dpi) && ($0.pdfPage == nil || $0.pdfPage! > 0) && ($0.embeddedIndex == nil || ($0.pdfPage != nil && $0.embeddedIndex! >= 0)) }) else {
            throw ProcessingError.message("工程页面列表或版本无效。")
        }
        for row in recipes { _ = try row.recipe.validated() }
        return self
    }
}
enum PageRanges {
    static func indices(_ text: String, count: Int) throws -> Set<Int> {
        var result = Set<Int>()
        for token in text.replacingOccurrences(of: "，", with: ",").split(separator: ",") {
            let parts = token.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
            guard (1...2).contains(parts.count), let first = Int(parts[0].trimmingCharacters(in: .whitespaces)), first >= 0, first < count else { throw ProcessingError.message("页码范围无效，使用从 0000 开始的索引，如 0000,0003-0008。") }
            let last: Int
            if parts.count == 2 { guard let end = Int(parts[1].trimmingCharacters(in: .whitespaces)), end >= first, end < count else { throw ProcessingError.message("页码区间超出资料库。") }; last = end }
            else { last = first }
            result.formUnion(first...last)
        }
        guard !result.isEmpty else { throw ProcessingError.message("请选择至少一页。") }
        return result
    }
}

struct RecipeBook {
    var values: [PageItem: Recipe] = [:]
    mutating func recipe(for page: PageItem) -> Recipe {
        if let existing = values[page] { return existing }
        let created = Recipe.neutral; values[page] = created; return created
    }
    mutating func apply(_ recipe: Recipe, indices: Set<Int>, pages: [PageItem]) throws {
        _ = try recipe.validated()
        guard indices.allSatisfy({ pages.indices.contains($0) }) else { throw ProcessingError.message("应用范围包含无效页面。") }
        for i in indices { values[pages[i]] = recipe }
    }
}
