import Foundation
import CoreGraphics

/// Local glyph-edge evidence distinguishes OCR spelling noise from a changed subtitle.
public struct SubtitleFingerprint: Sendable {
    private let mask: [UInt8]
    private let width: Int
    private let height: Int
    public init?(image: CGImage, rect: CGRect) {
        let area = rect.insetBy(dx:-0.003,dy:-0.002).intersection(CGRect(x:0,y:0,width:1,height:1))
        let pixels = CGRect(x:area.minX*CGFloat(image.width),y:(1-area.maxY)*CGFloat(image.height),width:area.width*CGFloat(image.width),height:area.height*CGFloat(image.height)).integral
        guard let crop = image.cropping(to:pixels), crop.width > 20, crop.height > 5 else { return nil }
        width = min(768,crop.width); height = max(8,min(96,Int(Double(crop.height)*Double(width)/Double(crop.width))))
        guard let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue),let bytes=context.data?.assumingMemoryBound(to:UInt8.self) else { return nil }
        context.interpolationQuality = .high; context.draw(crop,in:CGRect(x:0,y:0,width:width,height:height))
        var output = [UInt8](repeating:0,count:width*height)
        for y in 2..<(height-2) { for x in 2..<(width-2) {
            let value = bytes[y*width+x]
            guard value > 185 else { continue }
            var dark = false
            for dy in -2...2 { for dx in -2...2 where bytes[(y+dy)*width+x+dx] < 80 { dark = true } }
            if dark { output[y*width+x] = 1 }
        } }
        guard output.reduce(0,{ $0+Int($1) }) >= 40 else { return nil }
        mask = output
    }
    public func matches(_ other: SubtitleFingerprint) -> Bool {
        guard width == other.width, height == other.height else { return false }
        func coverage(_ first:[UInt8],_ second:[UInt8]) -> Bool {
            var all=0, matched=0, totals=[Int](repeating:0,count:12), hits=totals
            for y in 1..<(height-1) { for x in 1..<(width-1) where first[y*width+x] != 0 {
                let bin=min(11,x*12/width); totals[bin]+=1;all+=1
                var found=false
                for dy in -1...1 { for dx in -1...1 where second[(y+dy)*width+x+dx] != 0 { found=true } }
                if found { matched+=1; hits[bin]+=1 }
            } }
            guard all >= 40, Double(matched)/Double(all) >= 0.86 else { return false }
            return totals.indices.allSatisfy { totals[$0] < 12 || Double(hits[$0])/Double(totals[$0]) >= 0.68 }
        }
        return coverage(mask,other.mask) && coverage(other.mask,mask)
    }
}
