# 言叶 Kotonoha

面向视觉小说的 macOS 本地日文 → 中文屏幕翻译 App。选择游戏窗口、框选区域或整个屏幕，在原文附近显示中文覆盖，不必反复截图和切换应用。

使用 Apple Vision 识别文字，使用 llama.cpp 在本机运行 GGUF 模型。**发行包不包含模型，需要自行选择。**

当前预览版：**0.7.3** · Apple Silicon · macOS 14+

## 下载与开始使用

1. 从 [Releases](https://github.com/fffretice/Kotonoha/releases) 下载 `Kotonoha-0.7.3-AppleSilicon.dmg`，将 App 拖进「应用程序」。
2. 打开 App，点击「选择模型」，选择自己的兼容 GGUF 文件，然后加载模型。
3. 选择「全屏」「框选区域」或「窗口选择」，通过 macOS 的系统选择器确认共享内容。
4. 预览正确后点击「开始翻译」。

当前发行包使用本地开发签名，**尚未取得 Apple Developer ID 发行签名和公证**。其他 Mac 首次启动可能受到 Gatekeeper 拦截，请确认来源可信，并按系统提示操作；项目不提供关闭系统安全检查的脚本。

## 功能

- 全屏、框选区域、窗口选择三种范围。
- 同一对白继续补字或追加行时，保留已经显示的译文；续文译好后更新，换到下一段再清除旧译文。
- 同段覆盖固定左上角与底色，尽量避免文字、字号和背景闪动。
- 自动识别、实时字幕、逐字对白三种显示节奏。
- 自动背景取色、深色或浅色对话框，统一字号。
- 人名与术语表、当前会话对话记录、查看原文快捷键。

覆盖使用周围取色的色块，**并非生成式背景修复**。复杂背景、艺术字体和低清画面仍可能影响识别与观感。

## 模型和内存

已在 Qwen3 非思考模式下调试，包括 8B Q4_K_M 与 30B-A3B Q4_K_M。具体翻译质量和速度取决于模型、量化版本、上下文及 GPU 负载，不能只按参数量判断。

- 目前使用本地 GGUF 文件，不直接连接 Ollama、云端 API 或 ChatGPT 账户。
- 模型文件大小上限为 20GiB；运行时还需要上下文和计算缓冲内存。此限制不是进程内存上限。
- 「卸载」结束模型进程，进程退出后释放模型资源，保留磁盘文件。系统仍可能保留可回收的文件缓存。
- 请自行遵守所选模型的许可证。

## 快捷键与使用建议

| 快捷键 | 操作 |
| --- | --- |
| Control + Option + T | 开始 / 暂停翻译 |
| Control + Option + R | 重新框选 |
| Control + Option + H | 查看原文 / 恢复译文 |

逐字出现的游戏对白可在偏好设置选择「逐字对白」；同段换行建议保持默认合并翻译。窗口移动、尺寸或分辨率改变后，请重新选择并确认预览。关闭主窗口后仍可从菜单栏「言」控制，退出 App 才会结束共享并卸载模型。

## 隐私

正常使用时，画面识别与翻译都在本机进行，不上传画面或日文。模型子进程仅监听本机随机端口，使用每次启动生成的随机密钥。会话记录保存在内存中，只有主动导出才会写出；引擎会在系统临时目录保留运行日志，可从偏好设置查看。可选诊断命令会写出测试报告和测试画面。

下载推理引擎或模型需要联网；仓库、源码包和 DMG 均不包含个人配置、录屏或模型权重。

## 从源码构建

需要 Apple Silicon Mac、macOS 14+、Swift 命令行工具、Python 3。无需完整 Xcode。

```sh
xcode-select --install  # 已安装命令行工具时可跳过
./scripts/setup-runtime.sh
./scripts/build.sh
./scripts/test.sh
./scripts/package-dmg.sh
```

输出位于 `outputs/`。推理引擎固定到 llama.cpp `b12428` 并检查 SHA256；如需使用已有代理，可为下载脚本设置 `KOTONOHA_PROXY`，脚本不会修改系统网络设置。

`./scripts/setup-runtime.sh --model` 是可选步骤：另行下载 Qwen3-8B GGUF 到本机 `outputs/Models/`，不嵌入 App。也可自行获取模型并通过 App 选择。

源码构建默认使用本地开发签名。发布正式签名和公证版本需要开发者自行配置 Apple 发行身份。

## 测试

`./scripts/test.sh` 运行 45 项核心检查，不需要模型或录屏权限。GitHub Actions 执行 Apple Silicon 构建和这些检查，不下载模型。

以下原生诊断参数由 App 可执行文件接收，需要交互式 macOS 桌面；涉及翻译的检查还需要先在 App 配置本地模型：

- `--diagnose`：本地 OCR 和模型翻译。
- `--typewriter-test`：逐字补全、完整句翻译及前缀缓存检查。
- `--pipeline-test --fast-test`：试读窗口的快速换句回归。
- `--pipeline-test --jitter-test`：识别抖动时持续显示。
- `--screen-test --display-filter`、`--resize-test`：共享范围、覆盖排除和重新选择。

`--dialogue-append-test`、`--presentation-test`、`--visual-text-test`、`--recording-replay-test` 是开发阶段的可选录屏回归入口，需要自行提供对应的本地素材；相关录屏帧不随仓库分发。

可设置 `KOTONOHA_DIAGNOSTICS_DIR` 指定诊断报告目录。模型质量、屏幕权限和真实游戏效果无法由无交互的 CI 覆盖，仍需人工测试。

## 限制与贡献

目前仅支持 Apple Silicon，未提供 Intel 版。OCR 错字、模型误译、复杂布局和其他应用的 GPU 占用仍可能影响效果；字幕很快换句时也不能保证每句都来得及显示。请在 [Issues](https://github.com/fffretice/Kotonoha/issues) 提供不含隐私的复现步骤，贡献流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

本项目源码采用 [Apache License 2.0](LICENSE)，版权声明见 [NOTICE](NOTICE)。llama.cpp 使用 MIT 许可证；第三方说明见 [THIRD_PARTY.md](THIRD_PARTY.md)。模型和外部游戏素材不适用本项目的许可证。
