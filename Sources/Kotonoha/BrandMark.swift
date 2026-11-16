import SwiftUI

/// Shared by the in-app brand mark and the exported macOS application icon.
struct BrandMark: View {
    var size: CGFloat
    private let mint = Color(red: 0.43, green: 0.85, blue: 0.72)
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 13 / 46).fill(Color(red: 0.055, green: 0.064, blue: 0.079))
            RoundedRectangle(cornerRadius: size * 13 / 46).fill(mint.opacity(0.15))
            Text("言").font(.system(size: size * 27 / 46, weight: .medium, design: .serif)).foregroundStyle(mint)
        }.frame(width: size, height: size).environment(\.colorScheme, .dark)
    }
}
