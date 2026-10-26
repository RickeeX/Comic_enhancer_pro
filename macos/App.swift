import SwiftUI

@main
struct ComicEnhancerApp: App {
    @StateObject private var model = Model()
    var body: some Scene {
        WindowGroup {
            WorkspaceView().environmentObject(model).frame(minWidth: 1060, minHeight: 700)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入图片或文件夹…") { model.addFiles() }.keyboardShortcut("o")
                Button("导出当前页…") { model.export(single: true) }.keyboardShortcut("s").disabled(model.selection == nil || model.busy)
            }
        }
    }
}
struct WorkspaceView: View {
    @EnvironmentObject var model: Model
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "book.closed.fill").font(.title2).foregroundStyle(.teal)
                    VStack(alignment: .leading) {
                        Text("页面资料库").font(.headline)
                        Text("\(model.files.count) 页 · 图片与 PDF").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(18)
                List(model.files, id: \.self, selection: $model.selection) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.callout).lineLimit(2)
                            if item.pdfPage != nil {
                                Text(item.embeddedIndex == nil ? "PDF · \(item.dpi) DPI" : "PDF · 内嵌原图").font(.caption2).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    } icon: { Image(systemName: item.pdfPage == nil ? "photo" : "doc.richtext").foregroundStyle(.teal) }
                    .tag(item).help(item.path)
                }.listStyle(.sidebar)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Label("PDF 导入选项", systemImage: "doc.text").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("读取方式", selection: $model.pdfMode) {
                        Text("按页渲染").tag(0); Text("提取内嵌图片").tag(1)
                    }.pickerStyle(.segmented).labelsHidden()
                    if model.pdfMode == 0 {
                        HStack {
                            Text("渲染 DPI").font(.caption)
                            TextField("72–600", value: $model.pdfDPI, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 65)
                            Stepper("DPI", value: $model.pdfDPI, in: 72...600, step: 25).labelsHidden()
                        }
                    }
                    Text(model.pdfMode == 0 ? "保留文字、矢量和页面排版；按需逐页渲染。" : "每张 XObject 图片独立列出；不包含矢量文字与页面排版。")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button(action: model.addFiles) { Label(model.importing ? "建立索引中…" : "导入图片 / PDF", systemImage: "plus").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                }.padding(16).disabled(model.busy || model.importing)
            }.navigationSplitViewColumnWidth(min: 225, ideal: 260)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.selection?.title ?? "Comic Enhancer").font(.title3.weight(.semibold)).lineLimit(1)
                            Text("PAGE STUDIO  /  让每一页，更好读").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("原图对照", isOn: $model.showOriginal).toggleStyle(.button).controlSize(.small)
                    }.padding(.horizontal, 24).padding(.vertical, 18)
                    ZStack {
                        RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .underPageBackgroundColor))
                        if let image = model.showOriginal ? model.original : model.enhanced {
                            Image(nsImage: image).resizable().scaledToFit().shadow(color: .black.opacity(0.16), radius: 12, y: 6).padding(24)
                        } else {
                            VStack(spacing: 18) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 24).fill(.teal.opacity(0.1)).frame(width: 104, height: 104).rotationEffect(.degrees(-8))
                                    Image(systemName: "book.pages.fill").font(.system(size: 48, weight: .light)).foregroundStyle(.teal)
                                }
                                Text("把好故事，留在清晰的一页里").font(.title2.weight(.medium))
                                Text("扫描漫画 · 整本 PDF · 批量修复\n原图保留，所有处理在本机完成")
                                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                                Button("导入第一本书", action: model.addFiles).buttonStyle(.borderedProminent).controlSize(.large)
                            }
                        }
                        if model.previewing { ProgressView().padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                    }.padding(.horizontal, 18)
                    HStack(spacing: 8) {
                        Circle().fill(model.busy || model.previewing ? Color.orange : Color.teal).frame(width: 6, height: 6)
                        Text(model.status).font(.caption).lineLimit(2)
                        Spacer()
                        Text("松手后更新预览").font(.caption2).foregroundStyle(.secondary)
                    }.padding(18)
                    if model.busy {
                        HStack {
                            ProgressView(value: Double(model.completed), total: Double(max(1, model.total))).tint(.teal)
                            Text("\(model.completed)/\(model.total)").font(.caption).monospacedDigit()
                            Button("停止", action: model.cancel)
                        }.padding([.horizontal, .bottom])
                    }
                }
                Divider()
                InspectorView().frame(width: 305)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(.teal)
        .onChange(of: model.selection) { _ in model.preview() }
        .onChange(of: model.settings) { _ in model.preview() }
        .alert("处理提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
struct InspectorView: View {
    @EnvironmentObject var model: Model
    @State private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack { Label("调节工作台", systemImage: "slider.horizontal.3").font(.headline); Spacer(); Button("重置") { model.settings = Settings() }.controlSize(.small) }.padding(18)
            Picker("调节类别", selection: $tab) {
                Text("增强").tag(0); Text("书页").tag(1); Text("输出").tag(2)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 16).padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if tab == 0 {
                        HStack {
                            Button("清理纸色") { model.settings = Settings(); model.settings.grayscale = true; model.settings.autoLevels = true; model.settings.whitePoint = 0.92; model.settings.contrast = 1.12 }
                            Button("清晰线稿") { model.settings = Settings(); model.settings.grayscale = true; model.settings.contrast = 1.2; model.settings.sharpen = 0.6 }
                        }.controlSize(.small)
                        Group {
                            Toggle("自动色阶", isOn: $model.settings.autoLevels)
                            Adjustment(title: "亮度", value: $model.settings.brightness, range: -1...1)
                            Adjustment(title: "对比度", value: $model.settings.contrast, range: 0...3)
                            Adjustment(title: "Gamma · 越大越暗", value: $model.settings.gamma, range: 0.2...3)
                            Adjustment(title: "纸张白点", value: $model.settings.whitePoint, range: 0.2...1)
                        }
                        DisclosureGroup("锐化与降噪") { FilterControls().padding(.top, 8) }
                        BinarizationControls()
                    } else if tab == 1 {
                        DeskewControls()
                        Divider()
                        Adjustment(title: "缩放比例", value: $model.settings.scale, range: 0.1...2)
                        Adjustment(title: "四边裁切比例", value: $model.settings.crop, range: 0...0.2)
                        Picker("顺时针旋转", selection: $model.settings.rotation) { ForEach(0..<4) { Text("\($0 * 90)°").tag($0) } }
                        Picker("双页拆分", selection: $model.settings.page) { Text("完整页面").tag(0); Text("仅左页").tag(1); Text("仅右页").tag(2) }
                    } else {
                        Toggle("灰度图像", isOn: $model.settings.grayscale)
                        Picker("灰度级数", selection: $model.settings.levels) {
                            Text("连续色调").tag(0)
                            ForEach([2,4,8,16,32,64,128,256], id: \.self) { Text("\($0) 级").tag($0) }
                        }
                        Picker("减色抖动", selection: $model.settings.dither) { Text("无").tag(0); Text("Bayer 有序抖动").tag(1); Text("Floyd–Steinberg").tag(2) }
                            .disabled(model.settings.binarization != 0 || model.settings.levels == 0)
                        Divider()
                        Picker("输出格式", selection: $model.settings.format) { Text("PNG · 无损").tag("png"); Text("JPEG · 小文件").tag("jpg"); Text("TIFF").tag("tiff") }
                        if model.settings.format == "jpg" { Adjustment(title: "JPEG 品质", value: $model.settings.quality, range: 0.1...1) }
                        HStack { Button("保存参数", action: model.savePreset); Button("载入参数", action: model.loadPreset) }
                        Text("源文件始终保留。参数保存仅包含图像处理设置；PDF 读取方式与 DPI 在导入前选择。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("预览最长边 1600 px；最终质量以单页导出为准。拖动滑块时暂缓运算，松手后更新。")
                        .font(.caption2).foregroundStyle(.secondary).lineSpacing(3)
                }.padding(16)
            }.background(Color(nsColor: .controlBackgroundColor).opacity(0.45)).disabled(model.busy)
            VStack(spacing: 10) {
                Button(action: { model.export(single: false) }) { Label("批量导出 \(model.files.count) 页", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large)
                Button("导出当前页", action: { model.export(single: true) }).buttonStyle(.bordered)
            }.padding(16).disabled(model.files.isEmpty || model.busy || model.importing)
        }
    }
}
struct Adjustment: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    @State private var draft: Double = 0
    @State private var editing = false
    var body: some View {
        VStack(spacing: 7) {
            HStack { Text(title); Spacer(); Text(draft, format: .number.precision(.fractionLength(2))).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: $draft, in: range, onEditingChanged: { active in
                editing = active
                if !active { value = draft }
            })
            .onChange(of: draft) { next in if !editing { value = next } }
        }.font(.callout)
        .onAppear { draft = value }
        .onChange(of: value) { next in if !editing { draft = next } }
    }
}
struct FilterControls: View {
    @EnvironmentObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("锐化与降噪").font(.headline)
            Picker("模糊算法", selection: $model.settings.blurMethod) {
                Text("高斯").tag(0); Text("均值 / Box").tag(1)
                Text("中值 · 椒盐噪声").tag(2); Text("双边 · 保留边缘").tag(3)
            }
            Adjustment(title: "模糊强度", value: $model.settings.blur, range: 0...1)
            Stepper("滤波半径：\(model.settings.filterRadius) px", value: $model.settings.filterRadius, in: 1...3)
            if model.settings.blurMethod == 3 {
                Adjustment(title: "双边色差 σ", value: $model.settings.edgeSigma, range: 1...100)
            }
            Picker("锐化算法", selection: $model.settings.sharpenMethod) {
                Text("USM 反遮罩").tag(0); Text("Laplacian 拉普拉斯").tag(1)
            }
            Adjustment(title: "锐化强度", value: $model.settings.sharpen, range: 0...2)
            Adjustment(title: "锐化阈值 · 保护噪声", value: $model.settings.sharpenThreshold, range: 0...64)
        }
    }
}
struct BinarizationControls: View {
    @EnvironmentObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("二值化与去毛边").font(.headline)
            Picker("算法", selection: $model.settings.binarization) {
                Text("关闭 · 使用上方灰度减色").tag(0)
                Text("固定阈值").tag(1); Text("Otsu 自动阈值").tag(2)
                Text("Sauvola 局部自适应").tag(3)
            }
            if model.settings.binarization == 1 {
                Adjustment(title: "黑白阈值", value: $model.settings.threshold, range: 0...255)
            }
            if model.settings.binarization == 3 {
                Stepper("局部窗口半径：\(model.settings.adaptiveRadius) px", value: $model.settings.adaptiveRadius, in: 1...100)
                Adjustment(title: "Sauvola k · 越大去背景越强", value: $model.settings.sauvolaK, range: 0...1)
            }
            if model.settings.binarization != 0 {
                Picker("去毛边", selection: $model.settings.cleanup) {
                    Text("关闭 · 保留细笔画").tag(0); Text("仅去孤立黑点").tag(1)
                    Text("多数投票平滑").tag(2); Text("开运算 · 去黑色毛刺").tag(3)
                    Text("闭运算 · 填白色缺口").tag(4)
                }
                if model.settings.cleanup != 0 {
                    Stepper("清理次数：\(model.settings.cleanupPasses)", value: $model.settings.cleanupPasses, in: 1...3)
                }
                Text("输出为纯黑白；强去毛边可能损失细笔画。推荐使用 PNG 或 TIFF 保持二值结果。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
struct DeskewControls: View {
    @EnvironmentObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("书页水平矫正").font(.headline)
            Picker("自动纠斜", selection: $model.settings.deskew) {
                Text("关闭").tag(0); Text("横排文字 / 水平基线").tag(1)
                Text("竖排文字 / 垂直列线").tag(2)
            }
            if model.settings.deskew != 0 {
                Adjustment(title: "自动搜索范围 ±°", value: $model.settings.deskewLimit, range: 1...10)
            }
            Adjustment(title: "手动微调 · 顺时针 °", value: $model.settings.angle, range: -15...15)
            Text("支持横版和竖版画布。空白或低置信页面不自动旋转；保持画布大小，边角填白，边缘内容可能被裁切。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
