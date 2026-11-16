import AppKit
import SwiftUI
import ImageIO

@main struct IconExporter {
    @MainActor static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for size in [16,32,128,256,512] {
            for scale in [1,2] {
                let n = size * scale
                let renderer = ImageRenderer(content: BrandMark(size: 944).frame(width: 1024, height: 1024))
                renderer.scale = CGFloat(n) / 1024
                guard let image = renderer.cgImage else { throw NSError(domain: "IconExport", code: 1) }
                let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
                let dest = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil)!
                CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
            }
        }
    }
}
