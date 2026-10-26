# Comic Enhancer for macOS

面向 **macOS 13+ / Intel 与 Apple Silicon** 的原生扫描漫画增强工具。SwiftUI 界面，C++17 像素处理核心，ImageIO 编解码；不依赖 Python、Electron、网络服务或第三方图像库。

这是根据 ComicEnhancer Pro 功能说明独立实现的 **0.1 初版**，不是 Windows 二进制的直接移植，也没有完全复现原版算法。原附件没有源码，帮助文档称原作为具有使用限制的 Friendware；本仓库不包含其程序、文档、图标或源代码。MIT 许可证仅适用于这里的新实现。

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

1. 导入图片或文件夹，文件夹递归扫描；支持多次添加并去重、自然排序。
2. 选择页面，调节参数；用“查看原图”对照。内置“清理纸色”和“清晰线稿”起点。
3. 可将完整参数保存为 JSON，之后重新载入。
4. 导出当前页或整批页面。选择输出父目录后，应用创建唯一子目录，以编号加原名保存，避免同名源文件冲突。原图不覆盖。
5. 导出文件夹包含参数 `settings.json` 及逐文件结果 `export.log`。单页失败不会中断整批，停止按钮在当前页完成后生效。

## 已实现

| 类别 | 功能 |
| --- | --- |
| 色调 | 亮度、对比度、Gamma、白点去纸色、直方图自动色阶 |
| 线条 | 3×3 高斯柔化、反遮罩锐化 |
| 灰度 | 加权灰度，2/4/8/16/32/64/128/256 级量化 |
| 页面 | 对称裁边、90/180/270°旋转、双线性缩放、双页选择左半／右半 |
| 输入 | JPG、PNG、TIFF、BMP、GIF、HEIC/HEIF，具体解码支持由系统 ImageIO 提供 |
| 输出 | PNG、JPEG（品质可调）、TIFF；灰度输出使用灰度色彩空间 |
| 工作流 | 异步预览、批处理进度、停止、参数导入导出、失败日志 |

## 算法与性能

处理顺序为：分页 → 裁边 → 旋转与双线性缩放 → LUT 色调／灰度 → 高斯柔化和反遮罩锐化 → 灰度量化。Gamma 使用 `x^gamma`，大于 1 压暗，与参考软件描述方向一致；其他参数采用本项目定义，不兼容原版 INI。

色调函数预先合成为 256 项查表，避免逐像素求幂。C++ 按行分块并行，自动线程数上限 8；大图批处理一次只解码、处理一页，外层不再并发多页。预览最长边 1600 像素并延迟 180 ms 合并快速调节，旧结果不会覆盖新结果。全尺寸导出不使用缩略图。透明输入合成为白底，按 EXIF 方向解码，转换为 8-bit sRGB。

单张输入、输出分别限制为 4000 万像素；极限图像的解码、临时滤波和输出缓冲仍可能占用数百 MB 内存。自动色阶去除亮度直方图两端各 0.5%，整张相同色调时保持原值。滤波在 sRGB 编码值上执行，不是线性光处理。

`-O3` 构建允许各架构编译器优化；当前未实现手写 NEON/AVX 或 Metal。实际 Intel/M 系列速度需要在对应 Mac 上测量，不能由 Linux 结果推断。

## 当前边界

- 不是原版的全部功能：尚无透视矫正、曲面展平、自动纠斜、自动找中缝、曲线编辑、图像拼接、文件重命名和逐页工程参数。
- 双页拆分需分别选择左页、右页各导出一次，不会自动生成两页。
- 动画与多页 TIFF 只处理首帧。无 WMF/UFO/JP2/WebP 支持承诺。
- 灰度量化输出为 8-bit 灰度编码，不是原版的低位深索引 PNG；不保留 EXIF/DPI/ICC 等原始元数据。
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
