import AppKit
import TranslationCore

struct TranslationBlock {
    var source: String
    var translated: String
    var rect: CGRect
}
enum CoverStyle: String, CaseIterable, Identifiable {
    case automatic = "融入背景", dark = "深色对话框", light = "浅色对话框"
    var id: String { rawValue }
}
struct OverlayAppearance: Equatable {
    var style: CoverStyle = .automatic
    var opacity: Double = 1
    var fontSize: Double = 20
    var padding: Double = 6
}

@MainActor final class OverlayController {
    private var window: NSWindow?
    private var view: OverlayView?
    var hidden = false { didSet { if hidden { window?.orderOut(nil) } else if !(view?.blocks.isEmpty ?? true) { window?.orderFrontRegardless() } } }
    func configure(region: CaptureRegion) {
        close()
        let w = NSPanel(contentRect: region.rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false; w.isOpaque = false; w.backgroundColor = .clear
        w.sharingType = .none
        w.hasShadow = false; w.ignoresMouseEvents = true; w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let v = OverlayView(frame: CGRect(origin: .zero, size: region.rect.size)); w.contentView = v
        window = w; view = v
    }
    func show(blocks: [TranslationBlock], image: CGImage, appearance: OverlayAppearance) {
        view?.setContent(blocks, image: image, appearance: appearance)
        if !hidden && window?.isVisible == false { window?.orderFrontRegardless() }
    }
    func update(_ appearance: OverlayAppearance) { view?.changeAppearance(appearance) }
    func clear() { view?.clearPresentation(); window?.orderOut(nil) }
    var isVisible: Bool { window?.isVisible ?? false }
    var presentationFonts: [CGFloat] { view?.presentationFonts ?? [] }
    var presentationSources: [String] { view?.presentationSources ?? [] }
    var presentationRects: [CGRect] { view?.presentationRects ?? [] }
    var ignoresMouse: Bool { window?.ignoresMouseEvents ?? false }
    func renderedImage() -> CGImage? {
        guard let view, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.cgImage
    }
    func close() { clear(); window?.close(); window = nil; view = nil }
}

private final class OverlayView: NSView {
    var blocks: [TranslationBlock] = []
    var image: CGImage?
    var coverAppearance = OverlayAppearance()
    private struct Paint: Equatable {
        var key: String
        var source: String
        var base: CGRect
        var rect: CGRect
        var background: NSColor
        var foreground: NSColor
        var text: String
        var font: CGFloat
    }
    var presentationFonts: [CGFloat] { paints.map(\.font) }
    var presentationSources: [String] { paints.map(\.source) }
    var presentationRects: [CGRect] { paints.map(\.rect) }
    private var paints: [Paint] = []
    private var recent: [Paint] = []
    func setContent(_ blocks: [TranslationBlock], image: CGImage, appearance: OverlayAppearance) {
        let previous = paints
        if coverAppearance != appearance { recent = [] }
        self.blocks = blocks; self.image = image; coverAppearance = appearance
        paints = blocks.map { block in
            let key = OCRText.key(block.translated)
            let base = TextTools.appKitRect(block.rect, in: bounds)
            // Freeze an already presented sentence. OCR box height/width and moving pixels are not layout input again.
            if let old = recent.first(where: { $0.key == key && abs($0.base.midX-base.midX) < 30 && abs($0.base.midY-base.midY) < 20 }) { return old }
            let continuation = previous.first { old in
                old.base.intersects(base) && abs(old.base.maxY-base.maxY) < 15 &&
                DialogueContinuity.isAppending(previous:old.source,current:block.source)
            }
            let font = CGFloat(appearance.fontSize)
            let pad = CGFloat(appearance.padding)
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping; paragraph.lineSpacing = 3
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize:font), .paragraphStyle:paragraph]
            let ideal = (block.translated as NSString).size(withAttributes:attributes).width
            let width = min(bounds.width, max(base.width+pad*2, min(ideal+20, bounds.width*0.85)))
            let textWidth = max(20, width-16)
            let measured = (block.translated as NSString).boundingRect(with:CGSize(width:textWidth,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes)
            let height = min(bounds.height, max(base.height+pad*2, ceil(measured.height)+12))
            var rect = CGRect(x:max(0,min(bounds.width-width,base.midX-width/2)), y:max(0,min(bounds.height-height,base.minY-pad)), width:width,height:height).integral
            if let old=continuation {
                // A longer paragraph grows down/right from its existing cover instead of recentering it.
                rect.size.width=min(bounds.width-old.rect.minX,max(old.rect.width,rect.width))
                rect.size.height=min(old.rect.maxY,max(old.rect.height,rect.height))
                rect.origin=CGPoint(x:old.rect.minX,y:old.rect.maxY-rect.height)
            }
            let background: NSColor
            if let old=continuation {background=old.background}
            else {switch appearance.style {
            case .automatic: background = sampleBackground(around:base)
            case .dark: background = NSColor(deviceRed:0.065,green:0.075,blue:0.11,alpha:1)
            case .light: background = NSColor(deviceRed:0.96,green:0.94,blue:0.90,alpha:1)
            }}
            let rgb = background.usingColorSpace(.deviceRGB) ?? .black
            let luma = rgb.redComponent*0.2126+rgb.greenComponent*0.7152+rgb.blueComponent*0.0722
            return Paint(key:key,source:block.source,base:base,rect:rect,background:background,foreground:luma > 0.58 ? .black : .white,text:block.translated,font:font)
        }
        // Keep independently detected labels from being covered by a taller wrapped subtitle.
        let order = paints.indices.sorted { paints[$0].base.midY > paints[$1].base.midY }
        for (position,i) in order.enumerated() {
            for j in order.prefix(position) where paints[i].rect.intersects(paints[j].rect) && !paints[i].base.intersects(paints[j].base) {
                let y = paints[j].rect.minY-paints[i].rect.height-3
                if y >= 0 { paints[i].rect.origin.y = y }
            }
        }
        recent = paints + recent.filter { old in !paints.contains { $0.key == old.key && $0.base.intersects(old.base) } }
        recent = Array(recent.prefix(100))
        if previous != paints { needsDisplay = true }
    }
    func clearPresentation() { blocks = []; paints = []; needsDisplay = true }
    func changeAppearance(_ appearance: OverlayAppearance) {
        recent = []
        if let image { setContent(blocks,image:image,appearance:appearance) }
        else { coverAppearance = appearance; needsDisplay = true }
    }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill(using:.copy)
        guard !blocks.isEmpty else { return }
        for paint in paints {
            paint.background.withAlphaComponent(coverAppearance.opacity).setFill()
            NSBezierPath(roundedRect:paint.rect,xRadius:5,yRadius:5).fill()
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping; paragraph.lineSpacing = 3
            let attributes: [NSAttributedString.Key: Any] = [.font:NSFont.systemFont(ofSize:paint.font), .foregroundColor:paint.foreground, .paragraphStyle:paragraph]
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:paint.rect).addClip()
            (paint.text as NSString).draw(with:paint.rect.insetBy(dx:8,dy:6),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    /// Median of pixels outside the recognized text, so glyph colors do not tint the cover.
    private func sampleBackground(around rect: CGRect) -> NSColor {
        guard let image else { return .black }
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let bytes = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return .black }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var rs: [UInt8] = [], gs: [UInt8] = [], bs: [UInt8] = []
        func sample(_ x: CGFloat, _ y: CGFloat) {
            let px = max(0, min(w - 1, Int(x / bounds.width * CGFloat(w))))
            let py = max(0, min(h - 1, Int((bounds.height-y) / bounds.height * CGFloat(h))))
            let i = (py * w + px) * 4
            rs.append(bytes[i]); gs.append(bytes[i+1]); bs.append(bytes[i+2])
        }
        for i in 0..<30 {
            let f = CGFloat(i)/29
            sample(rect.minX + rect.width*f, rect.maxY + 4)
            sample(rect.minX + rect.width*f, rect.minY - 4)
            sample(rect.minX - 5, rect.minY + rect.height*f)
            sample(rect.maxX + 5, rect.minY + rect.height*f)
        }
        rs.sort(); gs.sort(); bs.sort()
        let m = rs.count/2
        return NSColor(deviceRed: CGFloat(rs[m])/255, green: CGFloat(gs[m])/255, blue: CGFloat(bs[m])/255, alpha: 1)
    }
}
