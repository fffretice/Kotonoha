import SwiftUI
import AppKit
import TranslationCore

struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: LocalEngine
    @State private var tab = 0
    private let accent = Color(red: 0.43, green: 0.85, blue: 0.72)
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    BrandMark(size: 46)
                    VStack(alignment: .leading, spacing: 2) { Text("言叶 Kotonoha").font(.headline); Text("让故事，用中文继续").font(.caption).foregroundStyle(.secondary) }
                }
                VStack(spacing: 7) {
                    nav("翻译", icon: "rectangle.inset.filled.and.person.filled", index: 0)
                    nav("对话记录", icon: "text.bubble", index: 1)
                    nav("偏好设置", icon: "slider.horizontal.3", index: 2)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    Label("完全本地", systemImage: "lock.shield").font(.callout.weight(.medium)).foregroundStyle(accent)
                    Text("画面和日文不上传。\n翻译记录只保留在本次会话。").font(.caption).foregroundStyle(.secondary).lineSpacing(4)
                    Divider()
                    Text("⌃⌥T  开始 / 暂停\n⌃⌥R  重新框选\n⌃⌥H  显示 / 隐藏译文").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(6)
                    Text("言叶 · 0.8.1").font(.caption2).foregroundStyle(.tertiary)
                }
            }.padding(24).frame(width: 225).background(Color.white.opacity(0.025))
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tab == 0 ? "读懂，眼前的故事。" : tab == 1 ? "把喜欢的对话留下。" : "调整到刚刚好。").font(.system(size: 27, weight: .semibold))
                        Text(tab == 0 ? "框选日文对话，中文会出现在原来的位置。" : tab == 1 ? "最近 100 条译文 · 关闭 App 后清空" : "为你的游戏调整文字、背景和翻译习惯。").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 7) { Circle().fill(model.running ? accent : .gray).frame(width: 7, height: 7); Text(model.running ? "翻译中" : "待命").font(.caption) }.padding(.horizontal, 12).padding(.vertical, 7).background(.white.opacity(0.05), in: Capsule())
                }.padding(28)
                Divider().opacity(0.4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let error = model.error {
                            HStack(alignment: .top) { Image(systemName: "exclamationmark.circle"); Text(error).textSelection(.enabled); Spacer(); Button(model.needsScreenAuthorization ? "选择游戏窗口" : "重试") { model.retryFromUI() }; Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                                .font(.callout).padding(14).background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                        }
                        if tab == 0 { translatePage }
                        else if tab == 1 { historyPage }
                        else { settingsPage }
                    }.padding(28)
                }
                Divider().opacity(0.4)
                HStack(spacing: 8) {
                    Image(systemName: model.running ? "waveform" : "circle.dotted").foregroundStyle(accent)
                    Text(model.status).lineLimit(1)
                    Spacer()
                    Text("模型生成耗时  \(model.latency)").foregroundStyle(.secondary)
                }.font(.caption).padding(.horizontal, 28).padding(.vertical, 14)
            }
        }.frame(minWidth: 1000, minHeight: 720)
        .background(Color(red: 0.055, green: 0.064, blue: 0.079)).preferredColorScheme(.dark).tint(accent)
    }
    func nav(_ title: String, icon: String, index: Int) -> some View {
        Button { tab = index } label: {
            HStack(spacing: 11) { Image(systemName: icon).frame(width: 20); Text(title); Spacer() }
                .font(.system(size: 14, weight: tab == index ? .semibold : .regular)).padding(.horizontal, 13).padding(.vertical, 12)
                .foregroundStyle(tab == index ? accent : Color.secondary)
                .background(tab == index ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
    var translatePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            card {
                HStack(alignment: .top) {
                    step("01")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("本地翻译模型").font(.headline)
                        Label(engine.status, systemImage: engine.ready ? "checkmark.circle.fill" : "cpu").font(.callout).foregroundStyle(engine.ready ? accent : .secondary)
                        if !engine.modelPath.isEmpty { Text(URL(fileURLWithPath: engine.modelPath).lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer()
                    if engine.loading { ProgressView().controlSize(.small); Button("取消") { engine.unload() } }
                    else if engine.ready { Button("卸载") { model.stop(); engine.unload() } }
                    else { Button("选择模型") { engine.chooseModel() }; Button("加载模型") { engine.load() }.buttonStyle(.borderedProminent) }
                }
            }
            card {
                HStack(alignment: .top) {
                    step("02")
                    VStack(alignment: .leading, spacing: 8) { Text("选择要翻译的区域").font(.headline); Text("\(model.captureMode.rawValue) · \(model.regionLabel)").font(.callout).foregroundStyle(.secondary); Text("建议只框选对话文字，避开立绘和菜单。").font(.caption).foregroundStyle(.tertiary) }
                    Spacer()
                    HStack(spacing: 7) {
                        Button("全屏") { model.selectFullScreen() }
                        Button("框选区域") { model.chooseRegion() }
                        Button("窗口选择") { model.selectWindow() }
                    }.disabled(model.choosingScreen)
                }
                if model.region != nil {
                    Button("停止共享") { model.stop() }.font(.caption).buttonStyle(.link)
                }
                if let preview = model.preview {
                    Image(nsImage: preview).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 150).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 8)).padding(.top, 8)
                }
            }
            HStack(spacing: 12) {
                Button { model.toggle() } label: { Label(model.running ? "暂停翻译" : "开始翻译", systemImage: model.running ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 10) }.buttonStyle(.borderedProminent).disabled(!engine.ready && !model.running)
                Button { model.peek.toggle() } label: { Label(model.peek ? "恢复译文" : "查看原文", systemImage: model.peek ? "eye.slash" : "eye").padding(.vertical, 10) }.buttonStyle(.bordered).disabled(!model.running)
            }
            HStack(alignment: .top, spacing: 16) {
                textCard("日文原文", text: model.source, empty: "日文对话出现后，会显示在这里。")
                textCard("中文译文", text: model.translation, empty: "译文会同时覆盖到游戏对话的位置。")
            }
            HStack { Label("首次使用需要允许屏幕录制。", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary); Spacer(); Button("打开试读场景") { model.openDemo() } }
        }
    }
    var historyPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("\(model.history.count) 条对话").foregroundStyle(.secondary); Spacer(); Button("清空记录") { model.history = [] }; Button("导出记录") { exportHistory() }.disabled(model.history.isEmpty) }
            if model.history.isEmpty { ContentUnavailableView("故事还没开始", systemImage: "text.bubble", description: Text("开始翻译后，日文和中文会成对保存在这里。")) }
            ForEach(model.history) { entry in
                card {
                    HStack { Text(entry.time, style: .time).font(.caption).foregroundStyle(.secondary); Spacer(); Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.translation, forType: .string) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("复制译文") }
                    Text(entry.source).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(entry.translation).font(.system(size: 17)).textSelection(.enabled).lineSpacing(5)
                }
            }
        }
    }
    var settingsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            card {
                Text("覆盖与排版").font(.headline)
                Picker("背景", selection: $model.style) { ForEach(CoverStyle.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                slider("统一字号", value: $model.fontSize, range: 14...40, suffix: "pt")
                slider("背景不透明度", value: $model.opacity, range: 0.5...1, suffix: "%", multiplier: 100)
                slider("覆盖边距", value: $model.padding, range: 2...24, suffix: "pt")
                Text("融入背景会从文字四周取色。每句只取色一次；每句固定字号、位置与底色；长句自动换行，动态视频建议选择深色对话框。").font(.caption).foregroundStyle(.secondary)
            }
            card {
                Text("识别与翻译").font(.headline)
                Picker("文字显示",selection:$model.timingMode) {
                    ForEach(TextTimingMode.allCases,id:\.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text("同段追加文字时保留已有译文，后续译好后更新；整段换句时清空。逐字对白等待新内容停稳，实时字幕优先速度。").font(.caption).foregroundStyle(.secondary)
                Toggle("逐行翻译（菜单 / 全屏界面）", isOn: $model.separateLines)
                Text("默认自动分组：只合并位置相近的同段文字，人物名和不同气泡分别覆盖。开启后每行独立。").font(.caption).foregroundStyle(.secondary)
                HStack { Text("文字稳定等待"); Slider(value: $model.stabilityDelay, in: 0.1...0.6); Text(String(format: "%.2f 秒", model.stabilityDelay)).monospacedDigit().frame(width: 70) }
                Button("清空对话记忆") { model.resetContext() }
            }
            card {
                Text("人物与术语").font(.headline)
                Text("每行一条，例如：春日野穹 = 春日野穹。会同时用于日文识别和翻译。").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $model.glossary).font(.system(size: 13)).frame(height: 110).padding(6).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack { Button("选择游戏窗口") { model.authorizeScreen() }; Button("屏幕录制权限设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }; Button("查看引擎日志") { engine.showLog() }; Spacer(); Text("模型占用取决于所选 GGUF").font(.caption).foregroundStyle(.secondary) }
        }
    }
    func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content).padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
    func step(_ s: String) -> some View { Text(s).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(accent).frame(width: 32, height: 32).background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8)) }
    func textCard(_ title: String, text: String, empty: String) -> some View {
        card { HStack { Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary); Spacer(); if !text.isEmpty { Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain) } }; Text(text.isEmpty ? empty : text).font(.system(size: 16)).foregroundStyle(text.isEmpty ? .secondary : .primary).textSelection(.enabled).lineSpacing(5).frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading) }
    }
    func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String, multiplier: Double = 1) -> some View {
        HStack { Text(title).frame(width: 120, alignment: .leading); Slider(value: value, in: range); Text("\(Int(value.wrappedValue * multiplier)) \(suffix)").monospacedDigit().frame(width: 65, alignment: .trailing) }.font(.callout)
    }
    func exportHistory() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "言叶-对话记录.txt"
        if panel.runModal() == .OK, let url = panel.url {
            let text = model.history.reversed().map { "\($0.source)\n\($0.translation)" }.joined(separator: "\n\n────\n\n")
            do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { model.error = "导出失败：\(error.localizedDescription)" }
        }
    }
}
