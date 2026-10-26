# 项目开发与交付约定

## 用户的长期要求

- 以后每次功能改进或修复，都要直接在云端完成 macOS Release 应用的编译和交付，不能只提交源码或让用户自行编译。
- 使用云端 macOS runner（现有 GitHub Actions），运行相关测试，并构建兼容 Mac Intel（x86_64）和 Apple Silicon／M 系列（arm64）的优化版 `.app`。优先交付同时包含两种架构的 Universal 应用。
- 复用 `scripts/build-macos.sh` 及 `.github/workflows/build.yml`；检查对应提交的 CI 结果、架构验证和产物上传成功后，再报告构建完成。
- 交付时提供该次构建的 `.app` 压缩包下载入口，并说明尚未完成的签名、公证或真实设备验证。不能把仅保存构建配置、排队中的 CI 或失败的构建称为已交付。
- 如遇到 macOS runner、权限或配额等外部阻塞，应明确记录实际阻塞和未完成的交付。

## 云环境

使用 `/workspace/Comic_enhancer_pro` 现有检出；任务已隔离，除非用户明确要求，不创建额外 Git worktree。Linux 云主机用于 C++ 开发和测试，macOS 专属编译与测试在云端 macOS runner 执行。
