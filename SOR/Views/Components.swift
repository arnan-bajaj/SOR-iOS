import SwiftUI
import SafariServices

/// A round photo, or initials on a tint when there's no photo.
struct Avatar: View {
    let name: String
    let photoURL: String
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let url = URL(string: photoURL), !photoURL.isEmpty {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() } else { initials }
                }
            } else { initials }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: some View {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        let hue = Double(abs(name.hashValue % 360)) / 360
        return ZStack {
            Circle().fill(Color(hue: hue, saturation: 0.45, brightness: 0.55))
            Text(letters.uppercased()).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white)
        }
    }
}

struct PersonAvatar: View {
    @Environment(AppModel.self) private var model
    let id: String
    var size: CGFloat = 24
    var body: some View {
        let p = model.person(id)
        Avatar(name: p?.name ?? "?", photoURL: p?.photoURL ?? "", size: size)
    }
}

/// Overlapping faces for a task's owners.
struct AvatarStack: View {
    let ids: [String]
    var size: CGFloat = 22
    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(ids.prefix(4), id: \.self) { id in
                PersonAvatar(id: id, size: size).overlay(Circle().stroke(Color.card, lineWidth: 2))
            }
        }
    }
}

struct Pill: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Due-date pill coloured by how close it is.
struct DuePill: View {
    let iso: String
    var done = false
    var body: some View {
        if !iso.isEmpty {
            let n = Day.until(iso) ?? 99
            let tint: Color = done ? .secondary : n < 0 ? .red : n <= 2 ? .orange : .secondary
            Pill(text: n < 0 && !done ? "Overdue · \(Day.pretty(iso))" : Day.pretty(iso), systemImage: "calendar", tint: tint)
        }
    }
}

struct SubteamDot: View {
    let color: Color
    var size: CGFloat = 9
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

/// A rounded card on the page background.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
    }
}

/// Placeholder rows shaped like the content while it loads (the website's skeletons).
struct SkeletonRows: View {
    var count = 4
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.card).frame(height: 64)
            }
        }
        .redacted(reason: .placeholder)
        .opacity(0.7)
    }
}

/// A page of the website in Safari's sheet. Google lets people sign in there (it won't in an embedded web view).
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

/// A short message that floats above the tab bar and goes away by itself.
struct ToastModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let t = model.toast {
                Text(t)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 70)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: t) {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation { model.toast = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: model.toast)
    }
}

/// Lays children out in rows, wrapping onto the next line (for subteam chips and pills).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].items.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width && !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            let add = rows[rows.count - 1].items.isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].items.append(i)
            rows[rows.count - 1].width += add
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
