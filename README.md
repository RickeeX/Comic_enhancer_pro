# Comic Enhancer for macOS

面向 **macOS 13+ / Intel 与 Apple Silicon** 的原生扫描漫画、书籍增强工具。SwiftUI + AppKit 界面，C++17 图像核心，CoreGraphics / ImageIO 编解码与 PDF 读取；不依赖 Python、Electron、网络服务或第三方图像库。

**下载：[GitHub Releases](https://github.com/RickeeX/Comic_enhancer_pro/releases)**。下载通用版 ZIP，解压后得到 `.app`。应用为 ad-hoc 签名，尚未 Apple 公证。

这是根据 ComicEnhancer Pro 帮助独立重写的 **v0.4**，不包含原软件源码、程序、文档或图标，不宣称逐像素兼容。原附件将原软件称为有使用限制的 Friendware；本仓库 MIT 许可证仅适用于新的实现。

## v0.4：操作栈与逐页工程

完整指南：[操作栈、书页排版与预览](docs/operation-stack.md)。

- 每页独立操作栈，真实按列表顺序执行。拖放排序、启停、删除、复制及多次重复同一操作。
- 默认栈：重采样 / DPI → 色调 → 模糊 → 锐化 → 灰度 / 减色 → 二值化。亮度、对比度、Gamma 以 100 为基准。
- 重采样、旋转、纠斜、裁边／内容框、页面排版是可单独添加的步骤，能自由安排彼此的位置；旧预设的综合页面步骤仍可迁移。
- 顶部参数摘要及完整记录；应用到全部、自选索引区间、此页之后；整页栈复制／粘贴、撤销／重做、预设与书籍工程 JSON。
- 原生预览缩放、拖动、捏合、鼠标定点缩放、100%／适应、双击、双页和右开书；点选双页任一页编辑、辅助网格、全尺寸检查。
- 保持物理尺寸而提高 DPI，实际重采样并写入 X/Y DPI；识别 PDF 内嵌图片的放置尺寸和不同轴 PPI，支持手动修正。
- 独立四边裁切、自动内容框、固定宽高、厘米／像素、边距、对齐、奇偶页镜像边距、完整放入／铺满裁切／拉伸。
- 按连通分量宽高筛选的独立去黑点；温和模板去毛刺，前台移除多数投票和开／闭运算。
- 镜像、翻转、反色、水平／垂直双页拼接、非破坏式编号导出。

## 基本使用

1. 导入图片、PDF 或文件夹。PDF 可选择原始内嵌图片，或按 72–1200 DPI 逐页渲染；只建立索引，按需解码，不一次展开整本书。
2. 左侧选择页面索引，顶部操作栈选择和编辑步骤。滑块松手后计算；尺寸／DPI 数值框输入后按回车应用。
3. 想提高密度：在“重采样 / 物理 DPI”开启保持物理尺寸，选择 600 或 800 DPI，再在后面安排模糊、锐化及二值化。未知源 DPI 需按扫描实际值指定。
4. 想统一尺寸：添加“统一页面 / 边距”，选择厘米或像素，设置宽高及排布，再应用到所需页面。
5. 预览默认最长边 1600 px。细节检查可开“全尺寸”或先导出一页。批量导出使用各页自己的操作栈，不覆盖源图。
6. 保存工程以保留逐页参数。导出目录含 `project.json` 和 `export.log`；单页失败不会中断整批。停止在当前页完成后生效。

## 图像与 PDF

| 类别 | 当前支持 |
| --- | --- |
| 色调 | 亮度、对比度、Gamma、白点、自动色阶 |
| 线条 | 高斯 / Box / 中值 / 双边模糊；USM / Laplacian 锐化 |
| 二值与减色 | 固定阈值、Otsu、Sauvola；灰度量化、Bayer、蛇形 Floyd–Steinberg；独立去斑、温和边缘模板 |
| 图像输入 | JPG、PNG、TIFF、BMP、GIF、HEIC / HEIF，由系统 ImageIO 解码 |
| PDF | 按页渲染，或每页 XObject 图片独立提取，包括嵌套 Form；常见反向 Decode 映射 |
| 输出 | PNG、JPEG、TIFF，记录 X/Y DPI；严格二值 PNG / TIFF 为真实 1-bit；4 / 16 级分别 2 / 4-bit |

内嵌图片模式不包含矢量文字、页面排版或内联 BI 图片。复杂 ICC／索引色空间、透明掩膜等应使用按页渲染。相同图片有多个放置尺寸时按最大放置面积估算 PPI，必要时手动修正。PDF 需先解密。源文件路径需保留，工程不内嵌整本原图。

动画和多页 TIFF 只处理首帧。输出不保留原始 EXIF / ICC；会归一为 8-bit sRGB 或灰度，并写出当前 DPI。JPEG 有损压缩可能产生灰边，纯黑白页面建议 PNG / TIFF。

## 性能与资源

灰度书页采用连续 Gray8 流水线和限量复用工作区；高斯／USM 混合查表，Mac 使用 Accelerate／vImage 与 GCD 动态分块。Metal 候选仅保留独立基准，未在正式应用启用。彩色与复杂操作保留 RGBA 回退。批量导出按 CPU／内存预算最多同时处理两页，页内线程共享预算；预览拖动缩放和平移不触发处理。

[v0.5.0 性能对照与完成后审核](docs/performance-v050.md) 包含实际书页逐像素比较、Mac 完整操作栈、后端选择、内存与批处理边界，以及剩余优化方向。[v0.4.2 核心基准](docs/performance.md) 保留历史对照。

原生 `-O3` + Swift 全模块优化，通用架构不使用 `-march=native` 或强制 AVX2；使用系统向量化库，保留便携 CPU 实现；Metal 候选仍在独立评估。最大输入／输出 1 亿像素，单边 5 万像素；极限分辨率、多步滤波和全尺寸双页可能需要数 GB 内存。高 DPI 不是 AI 超分，不会恢复原扫描缺失的信息。缩略预览和全尺寸的滤波、自动内容框、纠斜可能存在差异，请单页导出确认。

## 构建、测试与发布

Mac 上安装 Xcode Command Line Tools，然后：

```bash
./scripts/test-core.sh
./scripts/test-macos.sh
./scripts/build-macos.sh
open '.build/Comic Enhancer.app'
```

构建脚本分别编译 arm64 与 x86_64，通过 lipo 合并，并验证双架构和本地签名。原创图标由 AppKit 脚本生成 ICNS。Linux 不能编译 macOS GUI，但可运行便携核心测试：

```bash
./scripts/test-core.sh
.build/core-tests --benchmark
# 可选 CMake 3.20+
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j2
ctest --test-dir build --output-on-failure
```

CI 在 Linux 运行核心与 ASan / UBSan，在 Intel 和 Apple Silicon macOS 上验证编解码、PDF、可排序重复操作、逐页工程、DPI、页面排布、拼接、原生预览缩放和平移，并生成通用应用。实际测试结果以对应提交的 Actions 为准，真实设备手感仍需试用反馈。

发布 `v*` 标签会重新验证，仅在全部通过后创建 Release，上传 `ComicEnhancer-macOS-universal.zip` 和 `SHA256SUMS.txt`。维护者发布前应更新版本与 `docs/release-notes.md`。ad-hoc 签名不等于 Developer ID 签名／公证，正式分发需要开发者自己的身份。

## 尚未完整复刻

当前不是原软件全部功能：透视矫正、曲面展平、自动中缝、曲线编辑、高级照度归一、原版全部特殊图像格式和编解码参数仍待实现。多张任意网格拼接及原地批量重命名未提供，目前使用双页拼接和不改源文件的编号导出。
