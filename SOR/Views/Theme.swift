import SwiftUI

// The look: the board's dark slate with soft colour pools drifting behind frosted glass, like the website.
// Calm motion with a reduced-motion answer, tints and rings instead of coloured stripes, rounded numbers.

enum Brand {
    static let red = Color(red: 0.86, green: 0.13, blue: 0.16)
    static let blue = Color(red: 0.18, green: 0.56, blue: 1.0)
    static let violet = Color(red: 0.55, green: 0.36, blue: 0.96)
    static let teal = Color(red: 0.16, green: 0.78, blue: 0.75)
    static let amber = Color(red: 1.0, green: 0.62, blue: 0.16)

    /// A two-stop gradient from one colour, for hero cards and tiles.
    static func wash(_ c: Color) -> LinearGradient {
        LinearGradient(colors: [c.opacity(0.95), c.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Soft colour pools behind every page. They drift slowly; with Reduce Motion they hold still.
struct AppBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    var tint: Color = Brand.blue

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { ctx in
            let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    Color.page
                    pool(tint, size: w * 1.1, x: w * (0.15 + 0.08 * sin(t / 9)), y: h * (0.08 + 0.04 * cos(t / 11)))
                    pool(Brand.red, size: w * 0.9, x: w * (0.95 + 0.06 * cos(t / 10)), y: h * (0.35 + 0.05 * sin(t / 13)))
                    pool(Brand.violet, size: w * 1.0, x: w * (0.25 + 0.07 * cos(t / 12)), y: h * (0.85 + 0.04 * sin(t / 8)))
                }
            }
        }
        .ignoresSafeArea()
    }

    private func pool(_ c: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(c.opacity(scheme == .dark ? 0.22 : 0.16))
            .frame(width: size, height: size)
            .blur(radius: size * 0.28)
            .position(x: x, y: y)
    }
}

extension Color {
    /// List rows: frosted, so the colour pools show through a little.
    static let row = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0x1C / 255, green: 0x21 / 255, blue: 0x25 / 255, alpha: 0.72) : UIColor.white.withAlphaComponent(0.78) })
}

/// Frosted glass with a hairline, for cards. Liquid Glass on iOS 26.
struct GlassBackground: ViewModifier {
    var radius: CGFloat = 20
    var tint: Color?
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .background(shape.fill(Color.row.opacity(0.55)))
                .glassEffect(tint.map { .regular.tint($0.opacity(0.25)) } ?? .regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill((tint ?? .clear).opacity(0.12)))
                .overlay(shape.stroke(.white.opacity(0.08), lineWidth: 1))
        }
    }
}

extension View {
    func glass(_ radius: CGFloat = 20, tint: Color? = nil) -> some View { modifier(GlassBackground(radius: radius, tint: tint)) }
    func appBackground(_ tint: Color = Brand.blue) -> some View { background(AppBackground(tint: tint)) }
}

/// A round progress ring (goals, countdowns).
struct Ring: View {
    let progress: Double
    var color: Color = Brand.blue
    var width: CGFloat = 6
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: width)
            Circle().trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// A small coloured square with a symbol (list rows, stat tiles).
struct IconTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 32
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Brand.wash(color))
            .frame(width: size, height: size)
            .overlay(Image(systemName: systemImage).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(.white))
    }
}

/// A number with a label, for the stat row on Home and Analytics.
struct StatTile: View {
    let value: String
    let label: String
    let systemImage: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glass(18, tint: color)
    }
}

/// Bouncy press feedback for tappable cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A list row label with a coloured tile, used on You and in menus.
struct RowLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage, color: color, size: 30)
            Text(title)
        }
    }
}
