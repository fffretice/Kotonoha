import AppKit
import ScreenCaptureKit

enum CaptureMode: String, CaseIterable, Identifiable {
    case fullScreen = "全屏", region = "框选区域", window = "窗口选择"
    var id: String { rawValue }
    var pickerMode: SCContentSharingPickerMode { self == .window ? .singleWindow : .singleDisplay }
    var pickerStyle: SCShareableContentStyle { self == .window ? .window : .display }
    var instruction: String { self == .window ? "请在系统选择器中选择要翻译的窗口" : "请在系统选择器中选择要翻译的屏幕" }
    func region(for filter: SCContentFilter, selected: CaptureRegion?) throws -> CaptureRegion {
        if self == .region, let selected { return selected }
        let top = NSScreen.screens[0].frame.maxY
        let content = filter.contentRect
        let rect = CGRect(x:content.minX,y:top-content.maxY,width:content.width,height:content.height)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x:rect.midX,y:rect.midY)) }),
              let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { throw AppFailure("无法定位选中的内容，请重新选择") }
        return CaptureRegion(displayID:id,screenFrame:screen.frame,rect:rect,scale:CGFloat(filter.pointPixelScale),displayName:self == .window ? "共享窗口 · \(screen.localizedName)" : screen.localizedName)
    }
}
