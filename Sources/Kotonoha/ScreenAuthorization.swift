import AppKit
import ScreenCaptureKit

/// macOS owns consent and supplies the authorized content filter; no TCC database changes.
@MainActor final class ScreenAuthorization: NSObject, SCContentSharingPickerObserver {
    private var completion: ((Result<SCContentFilter, Error>) -> Void)?
    func present(mode: CaptureMode, completion: @escaping (Result<SCContentFilter, Error>) -> Void) {
        self.completion = completion
        let picker = SCContentSharingPicker.shared
        picker.remove(self); picker.add(self)
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = mode.pickerMode
        config.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "app.kotonoha.localtranslator"]
        config.allowsChangingSelectedContent = false
        picker.defaultConfiguration = config
        picker.isActive = true
        NSApp.activate(ignoringOtherApps: true)
        picker.present(using: mode.pickerStyle)
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in finish(.failure(AppFailure("已取消屏幕选择，可以再次点击开始翻译"))) }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in finish(.success(filter)) }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in finish(.failure(error)) }
    }
    private func finish(_ result: Result<SCContentFilter, Error>) {
        let callback = completion; completion = nil; callback?(result)
    }
}
