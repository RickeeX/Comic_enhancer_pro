# Comic Enhancer for macOS

面向 **macOS 13+ / Intel 与 Apple Silicon** 的原生扫描漫画增强工具。SwiftUI 界面，C++17 像素处理核心，ImageIO 编解码；不依赖 Python、Electron、网络服务或第三方图像库。

这是根据 ComicEnhancer Pro 功能说明独立实现的 **0.3 版**，不是 Windows 二进制的直接移植，也没有完全复现原版算法。原附件没有源码，帮助文档称原作为具有使用限制的 Friendware；本仓库不包含其程序、文档、图标或源代码。MIT 许可证仅适用于这里的新实现。

## 构建与运行

在 Mac 上安装 Xcode Command Line Tools（`xcode-select --install`），然后：

```bash
./scripts/test-core.sh
./scripts/test-macos.sh
./scripts/build-macos.sh
open '.build/Comic Enhancer.app'
```

构建脚本同时生成 arm64 与 x86_64，再使用 lipo 合成通用 `.app`，验证两种架构及本地签名。默认架构指令集不要求 AVX2，不使用 `-march=native`。需要 macOS SDK 和支持 SwiftUI 的 Swift 工具链，不能在 Linux 上生成可运行的 macOS GUI。

GitHub Actions 在 Linux 运行 C++ 测试和内存检查，在 Apple Silicon、Intel macOS runner 上运行原生编解码测试并构建通用应用。成功运行后的 Actions Artifacts 中有 `ComicEnhancer-macOS-universal.zip`。这不是已签发的正式发行版；本地 ad-hoc 签名不等于 Developer ID 签名或 Apple 公证。正式分发需要开发者自己的签名身份与公证流程。

## 使用

1. 导入图片或文件夹，文件夹递归扫描；支持多次添加并去重、自然排序；PDF 可以整本导入，在侧栏先选择内嵌图片或按页渲染及 DPI。
2. 选择页面，调节参数；用“查看原图”对照。内置“清理纸色”和“清晰线稿”起点。
3. 可将完整参数保存为 JSON，之后重新载入。
4. 导出当前页或整批页面。选择输出父目录后，应用创建唯一子目录，以编号加原名保存，避免同名源文件冲突。原图不覆盖。
5. 导出文件夹包含参数 `settings.json` 及逐文件结果 `export.log`。单页失败不会中断整批，停止按钮在当前页完成后生效。

## 已实现

| 类别 | 功能 |
| --- | --- |
| 色调 | 亮度、对比度、Gamma、白点去纸色、直方图自动色阶 |
| 线条 | 高斯／Box／中值／双边模糊，USM／Laplacian 锐化，半径与阈值可调 |
| 灰度 | 加权灰度与量化、Bayer／误差扩散抖动，固定／Otsu／Sauvola 二值化及去毛边 |
| 页面 | 对称裁边、90/180/270°旋转、双线性缩放、双页选择左半／右半，横竖排自动纠斜及手动微调 |
| 输入 | JPG、PNG、TIFF、BMP、GIF、HEIC/HEIF，具体解码支持由系统 ImageIO 提供 |
| 输出 | PNG、JPEG（品质可调）、TIFF；灰度输出使用灰度色彩空间 |
| 工作流 | 异步预览、批处理进度、停止、参数导入导出、失败日志 |

## 算法与性能

处理顺序为：分页 → 裁边 → 旋转与双线性缩放 → LUT 色调／灰度 → 自动／手动纠斜 → 模糊及锐化 → 二值化／去毛边或灰度量化。Gamma 使用 `x^gamma`，大于 1 压暗，与参考软件描述方向一致；其他参数采用本项目定义，不兼容原版 INI。

色调函数预先合成为 256 项查表，避免逐像素求幂。C++ 按行分块并行，自动线程数上限 8；大图批处理一次只解码、处理一页，外层不再并发多页。预览最长边 1600 像素并延迟 180 ms 合并快速调节，旧结果不会覆盖新结果。全尺寸导出不使用缩略图。透明输入合成为白底，按 EXIF 方向解码，转换为 8-bit sRGB。

单张输入、输出分别限制为 4000 万像素；极限图像的解码、临时滤波和输出缓冲仍可能占用数百 MB 内存。自动色阶去除亮度直方图两端各 0.5%，整张相同色调时保持原值。滤波在 sRGB 编码值上执行，不是线性光处理。

`-O3` 构建允许各架构编译器优化；当前未实现手写 NEON/AVX 或 Metal。实际 Intel/M 系列速度需要在对应 Mac 上测量，不能由 Linux 结果推断。

## 当前边界

- 不是原版的全部功能：尚无透视矫正、曲面展平、自动找中缝、曲线编辑、图像拼接、文件重命名和逐页工程参数。
- 双页拆分需分别选择左页、右页各导出一次，不会自动生成两页。
- 动画与多页 TIFF 只处理首帧。无 WMF/UFO/JP2/WebP 支持承诺。
- 二值 PNG／TIFF 使用 1-bit 灰度，4／16 级分别为 2／4-bit；其余为 8-bit。JPEG 为有损输出。不保留 EXIF/DPI/ICC 等原始元数据。
- 预览图的锐化、柔化和直方图可能与全分辨率输出存在差异，请用“导出当前页”检查最终质量。
- macOS GUI 交互还需真实 Mac 验收；云端 Linux 只能验证核心。CI 结果以实际 Actions 运行状态为准。

## 核心测试（Linux / macOS）

```bash
./scripts/test-core.sh
.build/core-tests --benchmark
# 或使用 CMake 3.20+
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j2
ctest --test-dir build --output-on-failure
```

测试覆盖像素恒等、各方向旋转、奇数宽度分页、边界插值、Gamma、灰度、色阶、滤波、量化、串并行一致性及非法缓冲／参数／尺寸。macOS 集成测试额外覆盖 ImageIO 读写、变换、PNG/JPEG/TIFF 往返、JSON 参数和损坏输入。

## 下载试用版与发布

[GitHub Releases](https://github.com/RickeeX/Comic_enhancer_pro/releases) 提供通用版 `.app` 的 ZIP 包，解压即可得到应用；不需要安装开发工具。下载条件和签名说明见每个版本的发行说明。

维护者发布新的 `v*` Git 标签后，CI 会重新测试并构建。仅在 Linux、Intel Mac 和 Apple Silicon Mac 全部成功后，才创建对应 GitHub Release，上传 `ComicEnhancer-macOS-universal.zip` 和 `SHA256SUMS.txt`。发布说明使用 `docs/release-notes.md`；发布前同步更新应用版本与说明。

详细算法、参数含义和适用边界见 [算法与调参](docs/algorithms.md)。


## PDF、交互与外观（v0.3）

- **整本 PDF**：按页渲染支持 72–600 DPI，保留文字、矢量、裁切框与页旋转。导入时只索引，不预先渲染所有页面；预览最长边 1600 px，导出才按选定 DPI 渲染。
- **内嵌图片**：将每页 XObject 图片（包括嵌套 Form 与继承资源）独立列出，按图片原始像素处理，与 DPI 无关。扫描书可减少重新栅格化成本；不包含矢量文字、页面排版及内联 BI 图片。特殊色彩空间、自定义 Decode 或透明掩膜会提示改用按页渲染，不会悄悄丢弃其外观。
- **内存与缓存**：逐页导出、仅保留一个解析后的 PDF 文档；限量 128 MB 预览源图缓存，调参数时复用源图。4000 万像素限制仍适用，超出时降低 DPI。PDF 必须先解密才能导入。
- **滑块**：拖动时使用控件内部草稿数值，不逐位置发布全局参数或触发像素运算；松手再提交一次。键盘调节仍会更新并合并预览任务，过期任务不覆盖新结果。实际流畅度还需真实 Mac 交互验收。
- **界面**：新的书页工作台、增强／书页／输出三分区、折叠式滤波参数、原图对照，以及原创矢量书本图标。图标由 AppKit 脚本生成全尺寸 ICNS，并在通用应用签名前打包。

PDF 读取方式和 DPI 对每次导入生效，已导入页面不会因改变侧栏选项而自动重建。导出仍为独立图片，不会重新合并 PDF。参数预设只保存图像增强设置。PDF 内嵌模式可能把背景、插画、徽标等独立列出；想让一页保持完整外观，请选择按页渲染。
