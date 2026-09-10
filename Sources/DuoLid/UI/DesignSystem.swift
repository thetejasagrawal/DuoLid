import DuoLidCore
import SwiftUI

enum DuoTheme {
    static let ink = Color.primary
    static let muted = Color.secondary
    static let accent = Color.accentColor
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let line = Color(nsColor: .separatorColor).opacity(0.45)
}

extension GlowPalette {
    var swiftUIColors: [Color] {
        colors.map { components in
            let white = components.max() ?? 1
            return Color(
                red: components[0] * 0.42 + white * 0.58,
                green: components[1] * 0.42 + white * 0.58,
                blue: components[2] * 0.42 + white * 0.58)
        }
    }
}

struct DuoMark: View {
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25).fill(
                LinearGradient(
                    colors: [Color(red: 0.71, green: 0.63, blue: 1), Color(red: 0.46, green: 0.36, blue: 0.83)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.075)
                .stroke(.white.opacity(0.95), lineWidth: size * 0.052)
                .frame(width: size * 0.44, height: size * 0.44)
                .rotationEffect(.degrees(-13)).offset(x: size * 0.045, y: -size * 0.04)
            Capsule().fill(.white).frame(width: size * 0.55, height: size * 0.049).offset(y: size * 0.235)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
