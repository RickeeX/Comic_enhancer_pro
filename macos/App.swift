import SwiftUI
import UniformTypeIdentifiers

@main
struct ComicEnhancerApp: App {
    @StateObject private var model = Model()
    var body: some Scene {
        WindowGroup { WorkspaceView().environmentObject(model).frame(minWidth: 1180, minHeight: 720) }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入图片 / PDF…", action: model.addFiles).keyboardShortcut("o")
                Button("打开书籍工程…", action: model.loadProject).keyboardShortcut("o", modifiers: [.command, .shift])
                Button("保存书籍工程…", action: model.saveProject).keyboardShortcut("s")
                Button("导出当前页…") { model.export(single: true) }.keyboardShortcut("e").disabled(model.selection == nil || model.busy)
            }
        }
    }
}
struct WorkspaceView: View {
    @EnvironmentObject var model: Model
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("页面资料库", systemImage: "book.closed.fill").font(.headline)
                    Spacer()
                    Button(action: model.clearLibrary) { Image(systemName: "trash") }.buttonStyle(.plain).help("清空页面列表，不删除原文件").disabled(model.busy || model.importing)
                }.padding(16)
                Text("\(model.files.count) 页 · 从 0000 开始编号").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                List(model.files, id: \.self, selection: $model.selection) { page in
                    Text(model.indexLabel(page)).font(.system(.body, design: .monospaced)).padding(.vertical, 5).tag(page).help(page.path)
                }.listStyle(.sidebar)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Label("PDF 导入设置", systemImage: "doc.text").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("读取方式", selection: $model.pdfMode) { Text("按页渲染").tag(0); Text("内嵌图片").tag(1) }.pickerStyle(.segmented).labelsHidden()
                    if model.pdfMode == 0 {
                        HStack { Text("DPI").font(.caption); TextField("72–600", value: $model.pdfDPI, format: .number.grouping(.never)).textFieldStyle(.roundedBorder) }
                    }
                    Button(action: model.addFiles) { Label(model.importing ? "建立索引中…" : "导入图片 / PDF", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                    HStack { Button("打开工程", action: model.loadProject); Button("保存工程", action: model.saveProject) }.controlSize(.small)
                }.padding(14).disabled(model.busy || model.importing)
            }.navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.activeIndex.map { "页面 " + String(format: "%04d",$0) } ?? "Comic Enhancer").font(.title3.weight(.semibold))
                            Text("逐页独立 · 有序处理 · 非破坏编辑").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("原图", isOn: $model.showOriginal).toggleStyle(.button).controlSize(.small)
                        Toggle("双页", isOn: $model.doublePreview).toggleStyle(.button).controlSize(.small)
                        Toggle("全尺寸", isOn: $model.fullPreview).toggleStyle(.button).controlSize(.small).help("以完整输出像素计算。放大检查更准确，但高 DPI 会增加耗时和内存。")
                    }.padding(18)
                    PreviewPanel()
                    VStack(alignment: .leading, spacing: 4) {
                        if !model.sourceDescription.isEmpty { Text("源：" + model.sourceDescription).font(.caption2).foregroundStyle(.secondary) }
                        if !model.outputDescription.isEmpty { Text("出：" + model.outputDescription).font(.caption2).foregroundStyle(.secondary) }
                        Text(model.status).font(.caption).lineLimit(2)
                        if model.busy {
                            HStack { ProgressView(value: Double(model.completed), total: Double(max(1,model.total))); Text("\(model.completed)/\(model.total)").font(.caption.monospacedDigit()); Button("停止", action: model.cancel) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                Divider()
                RecipeInspector().frame(width: 390)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(.teal)
        .alert("处理提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("好", role: .cancel) { model.error = nil } } message: { Text(model.error ?? "") }
    }
}
struct StageRow: View {
    @EnvironmentObject var model: Model
    let step: Stage
    let index: Int
    @State private var dropTarget = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).help("拖动到另一操作上以调整顺序")
                Button { model.toggleStage(step.id) } label: { Image(systemName: step.enabled ? "checkmark.circle.fill" : "circle").foregroundStyle(step.enabled ? Color.teal : .secondary) }.buttonStyle(.plain)
                Text("\(index+1). " + step.kind.title).font(.caption.weight(.semibold))
                Spacer()
                Menu {
                    Button("复制此步骤") { model.duplicateStage(step.id) }
                    Button("上移") { model.moveStage(step.id, to: index-1) }.disabled(index == 0)
                    Button("下移") { model.moveStage(step.id, to: index+1) }.disabled(index+1 == model.recipe.stages.count)
                    Button("删除步骤", role: .destructive) { model.removeStage(step.id) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 20)
            }
            Text(step.summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).help(step.summary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(model.selectedStage == step.id ? Color.teal.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(dropTarget ? .orange : model.selectedStage == step.id ? .teal.opacity(0.4) : .clear))
        .opacity(step.enabled ? 1 : 0.55)
        .contentShape(Rectangle()).onTapGesture { model.chooseStage(step.id) }
        .onDrag { NSItemProvider(object: step.id.uuidString as NSString) }
        .onDrop(of: [UTType.text.identifier], isTargeted: $dropTarget) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? String, let id = UUID(uuidString: text) else { return }
                DispatchQueue.main.async { model.moveStage(id, to: index) }
            }
            return true
        }
    }
}
struct RecipeInspector: View {
    @EnvironmentObject var model: Model
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("当前页操作栈", systemImage: "square.stack.3d.up").font(.headline)
                Spacer()
                Button(action: model.undoEdit) { Image(systemName: "arrow.uturn.backward") }.disabled(!model.canUndo)
                Button(action: model.redoEdit) { Image(systemName: "arrow.uturn.forward") }.disabled(!model.canRedo)
            }.controlSize(.small).padding(14)
            HStack {
                Menu("添加操作") { ForEach(StageKind.allCases) { kind in Button(kind.title) { model.addStage(kind) } } }
                Menu("应用 / 复制") {
                    Button("应用到所有页面") { model.applyRecipe("all") }
                    Button("应用到自选页面…") { model.applyRecipe("selected") }
                    Button("应用到此页之后的所有页面") { model.applyRecipe("after") }
                    Divider()
                    Button("复制整页操作栈", action: model.copyRecipe)
                    Button("粘贴到当前页", action: model.pasteRecipe)
                    Divider()
                    Button("保存操作栈预设…", action: model.savePreset)
                    Button("载入操作栈预设…", action: model.loadPreset)
                    Button("重置当前页", action: model.resetPage)
                }
            }.controlSize(.small).padding(.horizontal, 14).padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(model.recipe.stages.enumerated()), id: \.element.id) { index, step in StageRow(step: step, index: index) }
                }.padding(.horizontal, 12).padding(.bottom, 8)
            }.frame(height: 225)
            Text("按列表从上到下执行。默认二值化最后；拖动可自行改变顺序，同一操作可重复。")
                .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if let stage = model.stage {
                        Label(stage.kind.title, systemImage: stage.kind.symbol).font(.headline)
                        StageEditor(kind: stage.kind)
                        DisclosureGroup("完整参数记录") { Text(stage.summary).font(.caption).textSelection(.enabled).lineSpacing(3) }
                    } else { Text("添加或选择一个操作以编辑参数。").foregroundStyle(.secondary) }
                    Divider()
                    DisclosureGroup("当前页输出设置") {
                        VStack(spacing: 12) {
                            Picker("格式", selection: $model.recipe.format) { Text("PNG · 无损").tag("png"); Text("JPEG").tag("jpg"); Text("TIFF").tag("tiff") }
                            if model.recipe.format == "jpg" { Adjustment(title: "JPEG 品质", value: $model.recipe.quality, range: 0.1...1, displayScale: 100) }
                            Text("DPI 随文件写出；JPEG 会引入灰边，二值页面请使用 PNG / TIFF。").font(.caption2).foregroundStyle(.secondary)
                        }.padding(.top, 10)
                    }
                }.padding(16)
            }.background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            VStack(spacing: 8) {
                Button { model.export(single: false) } label: { Label("按各页设置批量导出", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large)
                Button("导出当前页") { model.export(single: true) }.buttonStyle(.bordered)
            }.padding(14)
        }.disabled(model.busy || model.selection == nil)
    }
}
struct StageEditor: View {
    @EnvironmentObject var model: Model
    let kind: StageKind
    var body: some View {
        Group {
            switch kind {
            case .tone: ToneEditor()
            case .sharpen: SharpEditor()
            case .blur: BlurEditor()
            case .gray: GrayEditor()
            case .binary: BinaryEditor()
            case .despeckle: SpeckleEditor()
            case .page: PageEditor()
            case .mirror:
                Toggle("水平镜像", isOn: $model.settings.flipHorizontal)
                Toggle("上下翻转", isOn: $model.settings.flipVertical)
            case .invert: Text("按 RGB=255−原值反色；透明背景仍使用白底。")
            }
        }
    }
}
struct Adjustment: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var displayScale: Double = 1
    var displayOffset: Double = 0
    @State private var draft = 0.0
    @State private var editing = false
    var body: some View {
        VStack(spacing: 5) {
            HStack { Text(title); Spacer(); Text(draft*displayScale+displayOffset, format: .number.precision(.fractionLength(1))).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: $draft, in: range, onEditingChanged: { active in editing = active; if !active { value = draft } })
                .onChange(of: draft) { next in if !editing { value = next } }
        }.font(.callout)
        .onAppear { draft = value }
        .onChange(of: value) { next in if !editing { draft = next } }
    }
}
struct NumericField: View {
    let title: String
    @Binding var value: Double
    @State private var draft = ""
    var body: some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            TextField(title, text: $draft).textFieldStyle(.roundedBorder).frame(width: 100).multilineTextAlignment(.trailing)
                .onSubmit { if let next = Double(draft), next.isFinite { value = next } else { draft = String(format:"%.2f", value) } }
        }.onAppear { draft = String(format:"%.2f",value) }.onChange(of: value) { draft = String(format:"%.2f",$0) }
    }
}
struct ToneEditor: View {
    @EnvironmentObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("自动色阶", isOn: $model.settings.autoLevels)
            Adjustment(title: "亮度（100 不变）", value: $model.settings.brightness, range: -1...1, displayScale: 100, displayOffset: 100)
            Adjustment(title: "对比度（100 不变）", value: $model.settings.contrast, range: 0...3, displayScale: 100)
            Adjustment(title: "Gamma（100 不变）", value: $model.settings.gamma, range: 0.2...3, displayScale: 100)
            Adjustment(title: "白点", value: $model.settings.whitePoint, range: 0.2...1, displayScale: 100)
            Text("组内固定为：自动色阶 → 对比度 → 亮度 → 白点 → Gamma；合成查表执行，组间可排序和重复。").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
struct SharpEditor: View {
    @EnvironmentObject var model: Model
    var body: some View {
        VStack(spacing: 14) {
            Picker("算法", selection: $model.settings.sharpenMethod) { Text("USM 反遮罩").tag(0); Text("Laplacian 拉普拉斯").tag(1) }
            Adjustment(title: "锐化强度", value: $model.settings.sharpen, range: 0...2, displayScale: 100)
            Stepper("半径：\(model.settings.filterRadius) px", value: $model.settings.filterRadius, in: 1...3)
            Adjustment(title: "锐化阈值", value: $model.settings.sharpenThreshold, range: 0...255)
        }
    }
}
struct BlurEditor: View {
    @EnvironmentObject var model: Model
    var body: some View {
        VStack(spacing: 14) {
            Picker("算法", selection: $model.settings.blurMethod) { Text("高斯").tag(0); Text("Box 均值").tag(1); Text("中值").tag(2); Text("双边保边").tag(3) }
            Adjustment(title: "模糊强度", value: $model.settings.blur, range: 0...1, displayScale: 100)
            Stepper("半径：\(model.settings.filterRadius) px", value: $model.settings.filterRadius, in: 1...3)
            if model.settings.blurMethod == 3 { Adjustment(title: "色差 σ", value: $model.settings.edgeSigma, range: 1...100) }
        }
    }
}
struct GrayEditor: View {
    @EnvironmentObject var model: Model
    var body: some View {
        VStack(spacing: 14) {
            Toggle("转灰度", isOn: $model.settings.grayscale)
            Picker("灰度级数", selection: $model.settings.levels) { Text("连续色调").tag(0); ForEach([2,4,8,16,32,64,128,256], id: \.self) { Text("\($0) 级").tag($0) } }
            Picker("抖动", selection: $model.settings.dither) { Text("关闭").tag(0); Text("Bayer").tag(1); Text("Floyd–Steinberg").tag(2) }
        }
    }
}
struct BinaryEditor: View {
    @EnvironmentObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("算法", selection: $model.settings.binarization) { Text("关闭").tag(0); Text("固定阈值").tag(1); Text("Otsu").tag(2); Text("Sauvola").tag(3) }
            if model.settings.binarization == 1 { Adjustment(title: "黑白阈值", value: $model.settings.threshold, range: 0...255) }
            if model.settings.binarization == 3 {
                Stepper("窗口半径：\(model.settings.adaptiveRadius) px", value: $model.settings.adaptiveRadius, in: 1...100)
                Adjustment(title: "Sauvola k", value: $model.settings.sauvolaK, range: 0...1)
            }
            Toggle("边缘温和去毛刺", isOn: $model.settings.edgeSmooth).disabled(model.settings.binarization == 0)
            if model.settings.edgeSmooth {
                Stepper("模板处理次数：\(model.settings.smoothPasses)", value: $model.settings.smoothPasses, in: 1...3)
                Toggle("同时修补开放小凹口", isOn: $model.settings.fillNotches)
            }
            Text("仅修整匹配模板的单像素突出点，保留细线端点；不是整页多数投票、开运算或闭运算。默认关闭。去黑点请添加独立步骤。").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
struct SpeckleEditor: View {
    @EnvironmentObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Stepper("最大黑点直径：\(model.settings.despeckleDiameter) px（0 关闭）", value: $model.settings.despeckleDiameter, in: 0...128)
            Stepper("黑色灰度阈值：\(model.settings.despeckleThreshold)", value: $model.settings.despeckleThreshold, in: 0...254)
            Toggle("清除与页面边缘连通的黑色区域", isOn: $model.settings.removeBorders)
            Text("按 8 邻域连通区域判断，只有宽和高都不超过直径阈值才删除。过大会误删标点或字内独立点。清除连边黑区可能移除页眉、边框，请谨慎启用。").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
struct PageEditor: View {
    @EnvironmentObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            DisclosureGroup("方向与纠斜") {
                VStack(spacing: 12) {
                    Picker("分页", selection: $model.settings.page) { Text("整页").tag(0); Text("左半页").tag(1); Text("右半页").tag(2) }
                    Picker("旋转", selection: $model.settings.rotation) { ForEach(0..<4) { Text("\($0*90)°").tag($0) } }
                    Picker("自动纠斜", selection: $model.settings.deskew) { Text("关闭").tag(0); Text("横排").tag(1); Text("竖排").tag(2) }
                    Adjustment(title: "自动搜索范围 ±°", value: $model.settings.deskewLimit, range: 1...10)
                    Adjustment(title: "顺时针微调 °", value: $model.settings.angle, range: -15...15)
                }.padding(.top, 10)
            }
            DisclosureGroup("裁边与自动内容框") {
                VStack(spacing: 12) {
                    Adjustment(title: "对称裁边", value: $model.settings.crop, range: 0...0.2, displayScale: 100)
                    Adjustment(title: "左裁边 %", value: $model.settings.cropLeft, range: 0...0.45, displayScale: 100)
                    Adjustment(title: "右裁边 %", value: $model.settings.cropRight, range: 0...0.45, displayScale: 100)
                    Adjustment(title: "上裁边 %", value: $model.settings.cropTop, range: 0...0.45, displayScale: 100)
                    Adjustment(title: "下裁边 %", value: $model.settings.cropBottom, range: 0...0.45, displayScale: 100)
                    Toggle("自动选取有效内容框", isOn: $model.settings.autoTrim)
                    if model.settings.autoTrim {
                        Stepper("内容灰度阈值：\(model.settings.trimThreshold)", value: $model.settings.trimThreshold, in: 0...254)
                        Stepper("忽略小斑点直径：\(model.settings.trimIgnore) px", value: $model.settings.trimIgnore, in: 0...128)
                        Stepper("向外补偿：\(model.settings.trimPadding) px", value: $model.settings.trimPadding, in: 0...200)
                        Toggle("忽略并清除连边黑区", isOn: $model.settings.removeBorders)
                    }
                }.padding(.top, 10)
            }
            Divider()
            Toggle("保持当前物理尺寸，改变 DPI", isOn: $model.settings.preservePhysical)
            NumericField(title: "源 DPI（0=自动）", value: $model.settings.sourceDPI)
            if model.settings.preservePhysical {
                NumericField(title: "目标 DPI（回车生效）", value: $model.settings.targetDPI)
                Text("先重采样增加像素，再执行后续锐化 / 模糊 / 二值化。不会凭空恢复扫描中没有的细节。").font(.caption2).foregroundStyle(.secondary)
            } else { Adjustment(title: "像素缩放 %（会改变物理尺寸）", value: $model.settings.scale, range: 0.1...2, displayScale: 100) }
            Picker("重采样", selection: $model.settings.resampleMethod) { Text("最近邻").tag(0); Text("双线性").tag(1); Text("双三次").tag(2) }
            Divider()
            Picker("页面尺寸", selection: $model.settings.pageMode) {
                Text("保持当前页面").tag(0); Text("指定宽度，等比计算高度").tag(1); Text("指定高度，等比计算宽度").tag(2)
                Text("指定宽与高，统一页面").tag(3); Text("内容框加页边距").tag(4)
            }
            if model.settings.pageMode != 0 {
                Picker("单位", selection: $model.settings.pageUnit) { Text("厘米").tag(0); Text("像素").tag(1) }
                if [1,3].contains(model.settings.pageMode) { NumericField(title: "页面宽", value: $model.settings.pageWidth) }
                if [2,3].contains(model.settings.pageMode) { NumericField(title: "页面高", value: $model.settings.pageHeight) }
                HStack {
                    Button("A4") { model.settings.pageUnit = 0; model.settings.pageWidth = 21; model.settings.pageHeight = 29.7; model.settings.pageMode = 3 }
                    Button("A5") { model.settings.pageUnit = 0; model.settings.pageWidth = 14.8; model.settings.pageHeight = 21; model.settings.pageMode = 3 }
                    Button("12×15 cm") { model.settings.pageUnit = 0; model.settings.pageWidth = 12; model.settings.pageHeight = 15; model.settings.pageMode = 3 }
                }.controlSize(.small)
                NumericField(title: "左边距", value: $model.settings.marginLeft)
                NumericField(title: "右边距", value: $model.settings.marginRight)
                NumericField(title: "上边距", value: $model.settings.marginTop)
                NumericField(title: "下边距", value: $model.settings.marginBottom)
                Picker("内容排布", selection: $model.settings.fitMode) { Text("等比完整放入，留白").tag(0); Text("等比铺满，裁切溢出").tag(1); Text("拉伸到版心（校正宽高）").tag(2) }
                Picker("水平对齐", selection: $model.settings.alignX) { Text("左").tag(0); Text("居中").tag(1); Text("右").tag(2) }
                Picker("垂直对齐", selection: $model.settings.alignY) { Text("上").tag(0); Text("居中").tag(1); Text("下").tag(2) }
            }
            Toggle("奇偶页交换左右边距 / 裁边", isOn: $model.settings.alternateMargins)
            Text("固定页面宽高可统一扫描页大小；“完整放入”保持比例，“拉伸”才会改变内容宽高比例。所有新增空白填白。未知 DPI 暂按 300，请按实际扫描参数指定。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
