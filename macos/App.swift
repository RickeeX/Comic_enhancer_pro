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
            VStack(alignment: .leading, spacing: 12) {
                Text("页面库").font(.title2.bold()).padding(.horizontal)
                Text("\(model.files.count) 页 · 按文件名自然排序").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                List(model.files, id: \.self, selection: $model.selection) { url in
                    Label(url.lastPathComponent, systemImage: "doc.richtext").tag(url).help(url.path)
                }
                Button(action: model.addFiles) { Label("导入图片或文件夹", systemImage: "plus") }
                    .buttonStyle(.bordered).padding().disabled(model.busy)
            }.padding(.top).navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.selection?.lastPathComponent ?? "Comic Enhancer").font(.headline).lineLimit(1)
                            Text("为扫描漫画，找回清晰与纯净。").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("查看原图", isOn: $model.showOriginal).toggleStyle(.switch).controlSize(.small)
                    }.padding(20)
                    ZStack {
                        Color(nsColor: .underPageBackgroundColor)
                        if let image = model.showOriginal ? model.original : model.enhanced {
                            Image(nsImage: image).resizable().scaledToFit().padding(24)
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "book.closed").font(.system(size: 56, weight: .ultraLight)).foregroundStyle(.tint)
                                Text("让每一页，更好读").font(.title2.weight(.medium))
                                Text("导入 JPG、PNG、TIFF、BMP、GIF 或 HEIC\n调整效果后，批量导出到新的文件夹")
                                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                Button("选择图片", action: model.addFiles).buttonStyle(.borderedProminent)
                            }
                        }
                        if model.previewing { ProgressView().padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) }
                    }
                    HStack {
                        Text(model.status).font(.caption).lineLimit(2)
                        Spacer()
                        Text("预览最长边 1600 px · 导出原尺寸处理").font(.caption2).foregroundStyle(.secondary)
                    }.padding(12)
                    if model.busy {
                        HStack {
                            ProgressView(value: Double(model.completed), total: Double(max(1, model.total)))
                            Text("\(model.completed)/\(model.total)").monospacedDigit()
                            Button("停止", action: model.cancel)
                        }.padding([.horizontal, .bottom])
                    }
                }
                Divider()
                InspectorView().frame(width: 285)
            }
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
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("图像调节").font(.headline); Spacer(); Button("重置") { model.settings = Settings() } }.padding()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button("清理纸色") {
                            model.settings = Settings(); model.settings.grayscale = true
                            model.settings.autoLevels = true; model.settings.whitePoint = 0.92; model.settings.contrast = 1.12
                        }
                        Button("清晰线稿") {
                            model.settings = Settings(); model.settings.grayscale = true
                            model.settings.contrast = 1.2; model.settings.sharpen = 0.6
                        }
                    }.controlSize(.small)
                    Group {
                        Toggle("自动色阶（去除两端 0.5%）", isOn: $model.settings.autoLevels)
                        Adjustment(title: "亮度", value: $model.settings.brightness, range: -1...1)
                        Adjustment(title: "对比度", value: $model.settings.contrast, range: 0...3)
                        Adjustment(title: "Gamma · 越大越暗", value: $model.settings.gamma, range: 0.2...3)
                        Adjustment(title: "纸张白点", value: $model.settings.whitePoint, range: 0.2...1)
                        FilterControls()
                    }
                    Divider()
                    Toggle("灰度图像", isOn: $model.settings.grayscale)
                    Picker("灰度级数", selection: $model.settings.levels) {
                        Text("连续色调").tag(0)
                        ForEach([2,4,8,16,32,64,128,256], id: \.self) { Text("\($0) 级").tag($0) }
                    }
                    Picker("减色抖动", selection: $model.settings.dither) {
                        Text("无").tag(0); Text("Bayer 有序抖动").tag(1); Text("Floyd–Steinberg").tag(2)
                    }.disabled(model.settings.binarization != 0 || model.settings.levels == 0)
                    BinarizationControls()
                    DeskewControls()
                    Divider()
                    Adjustment(title: "缩放比例", value: $model.settings.scale, range: 0.1...2)
                    Adjustment(title: "四边裁切比例", value: $model.settings.crop, range: 0...0.2)
                    Picker("顺时针旋转", selection: $model.settings.rotation) {
                        ForEach(0..<4) { Text("\($0 * 90)°").tag($0) }
                    }
                    Picker("双页拆分", selection: $model.settings.page) {
                        Text("完整页面").tag(0); Text("仅左页").tag(1); Text("仅右页").tag(2)
                    }
                    Text("先分页、裁边，再旋转与缩放。分别选择左／右页导出可拆分双页。")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Picker("输出格式", selection: $model.settings.format) {
                        Text("PNG · 无损").tag("png"); Text("JPEG · 小文件").tag("jpg"); Text("TIFF").tag("tiff")
                    }
                    if model.settings.format == "jpg" { Adjustment(title: "JPEG 品质", value: $model.settings.quality, range: 0.1...1) }
                    HStack { Button("保存参数", action: model.savePreset); Button("载入参数", action: model.loadPreset) }
                    Text("源文件保持不变。动画／多页文件仅处理首帧。预览为缩略图，锐化效果请以全尺寸导出为准。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding([.horizontal, .bottom])
            }.disabled(model.busy)
            Divider()
            VStack(spacing: 10) {
                Button(action: { model.export(single: false) }) { Text("批量导出 \(model.files.count) 页").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                Button("导出当前页", action: { model.export(single: true) }).buttonStyle(.bordered)
            }.padding().disabled(model.files.isEmpty || model.busy)
        }
    }
}
struct Adjustment: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        VStack(spacing: 6) {
            HStack { Text(title); Spacer(); Text(value, format: .number.precision(.fractionLength(2))).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: $value, in: range)
        }.font(.callout)
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
