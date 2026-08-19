import SwiftUI

/// Stroked / filled SVG glyphs lifted from the provided design assets.
/// All use a 16×16 viewBox and scale to the view size.

/// plus_bottun.svg: `M8 4.5V11.5 M4.5 8H11.5` (stroke 1)
struct PlusIcon: View {
    var lineWidth: CGFloat = 1.5

    var body: some View {
        PlusPath()
            .stroke(style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    struct PlusPath: Shape {
        func path(in rect: CGRect) -> Path {
            let m = IconMetrics(rect: rect)
            var p = Path()
            p.move(to: m.point(8, 4.5))
            p.addLine(to: m.point(8, 11.5))
            p.move(to: m.point(4.5, 8))
            p.addLine(to: m.point(11.5, 8))
            return p
        }
    }
}

/// sidebar_left_icon.svg: same pane as `sidebar_icon.svg`, mirrored so the
/// rail sits on the left (`x=3.5 y=5 w=1.75 h=6 rx=0.875`, opacity 0.7).
struct SidebarIcon: View {
    var lineWidth: CGFloat = 1.5

    var body: some View {
        ZStack {
            OutlinePath()
                .stroke(style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            DividerPath()
                .fill()
                .opacity(0.7)
        }
    }

    struct OutlinePath: Shape {
        func path(in rect: CGRect) -> Path {
            let m = IconMetrics(rect: rect)
            return Path(roundedRect: m.rect(x: 2, y: 2.75, w: 12, h: 10.5), cornerRadius: m.v(2.25))
        }
    }

    struct DividerPath: Shape {
        func path(in rect: CGRect) -> Path {
            let m = IconMetrics(rect: rect)
            return Path(roundedRect: m.rect(x: 3.5, y: 5, w: 1.75, h: 6), cornerRadius: m.v(0.875))
        }
    }
}

/// search_icon.svg: magnifying glass (stroke 1).
struct SearchIcon: View {
    var lineWidth: CGFloat = 1.5

    var body: some View {
        SearchPath()
            .stroke(style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    struct SearchPath: Shape {
        func path(in rect: CGRect) -> Path {
            let m = IconMetrics(rect: rect)
            var p = Path()
            p.addEllipse(in: m.rect(x: 2, y: 2, w: 10.6667, h: 10.6667))
            p.move(to: m.point(11.1, 11.1))
            p.addLine(to: m.point(14, 14))
            return p
        }
    }
}

/// Light appearance: entypo light-up (ring + eight ticks).
struct LightThemeIcon: View {
    var lineWidth: CGFloat = 1.5

    var body: some View {
        LightUpPath()
            .fill(style: FillStyle(eoFill: true))
    }

    struct LightUpPath: Shape {
        func path(in rect: CGRect) -> Path {
            let m = IconMetrics(rect: rect)
            var p = Path()
            // Source is 20×20; map into the 16×16 viewBox.
            p.addEllipse(in: m.rect(x: 3.6, y: 3.6, w: 8.8, h: 8.8))
            p.addEllipse(in: m.rect(x: 4.8, y: 4.8, w: 6.4, h: 6.4))

            let center = m.point(8, 8)
            let thickness = m.v(1.28)
            let ticks: [(CGFloat, CGFloat, CGFloat)] = [
                (0, 7.2, 1.58),
                (45, 7.05, 1.35),
                (90, 7.2, 1.58),
                (135, 7.05, 1.35),
                (180, 7.2, 1.58),
                (225, 7.05, 1.35),
                (270, 7.2, 1.58),
                (315, 7.05, 1.35),
            ]
            for (deg, radial16, length16) in ticks {
                let rad = deg * .pi / 180
                let mid = CGPoint(
                    x: center.x + cos(rad) * m.v(radial16),
                    y: center.y + sin(rad) * m.v(radial16)
                )
                let length = m.v(length16)
                let tick = Path(
                    roundedRect: CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness),
                    cornerRadius: thickness / 2
                )
                p.addPath(tick, transform: CGAffineTransform(translationX: mid.x, y: mid.y).rotated(by: rad))
            }
            return p
        }
    }
}

/// Dark appearance: solar moon-linear crescent.
struct DarkThemeIcon: View {
    var lineWidth: CGFloat = 1.5

    var body: some View {
        MoonPath()
            .stroke(style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    struct MoonPath: Shape {
        func path(in rect: CGRect) -> Path {
            let m = IconMetrics(rect: rect)
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                m.point(x * 16 / 24, y * 16 / 24)
            }
            var p = Path()
            p.move(to: pt(12, 22))
            p.addCurve(to: pt(22, 12), control1: pt(17.5228, 22), control2: pt(22, 17.5228))
            p.addCurve(to: pt(21.0672, 11.8568), control1: pt(22, 11.5373), control2: pt(21.3065, 11.4608))
            p.addCurve(to: pt(15.5, 15), control1: pt(19.9289, 13.7406), control2: pt(17.8615, 15))
            p.addCurve(to: pt(9, 8.5), control1: pt(11.9101, 15), control2: pt(9, 12.0899))
            p.addCurve(to: pt(12.1432, 2.93276), control1: pt(9, 6.13845), control2: pt(10.2594, 4.07105))
            p.addCurve(to: pt(12, 2), control1: pt(12.5392, 2.69347), control2: pt(12.4627, 2))
            p.addCurve(to: pt(2, 12), control1: pt(6.47715, 2), control2: pt(2, 6.47715))
            p.addCurve(to: pt(12, 22), control1: pt(2, 17.5228), control2: pt(6.47715, 22))
            p.closeSubpath()
            return p
        }
    }
}

/// bottom_bar_icon.svg: rounded window with a bottom rail.
struct BottomBarIcon: View {
    var lineWidth: CGFloat = 1.5

    var body: some View {
        ZStack {
            OutlinePath()
                .stroke(style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            RailPath()
                .fill()
                .opacity(0.7)
        }
    }

    struct OutlinePath: Shape {
        func path(in rect: CGRect) -> Path {
            let m = IconMetrics(rect: rect)
            return Path(roundedRect: m.rect(x: 2, y: 2.75, w: 12, h: 10.5), cornerRadius: m.v(2.25))
        }
    }

    struct RailPath: Shape {
        func path(in rect: CGRect) -> Path {
            let m = IconMetrics(rect: rect)
            return Path(roundedRect: m.rect(x: 5, y: 10.35, w: 6, h: 1.75), cornerRadius: m.v(0.875))
        }
    }
}

/// download_icon.svg: arrow into a tray.
struct DownloadIcon: View {
    var lineWidth: CGFloat = 1.5

    var body: some View {
        ZStack {
            ArrowPath()
                .stroke(style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            TrayPath()
                .fill()
        }
    }

    struct ArrowPath: Shape {
        func path(in rect: CGRect) -> Path {
            let m = IconMetrics(rect: rect)
            var p = Path()
            p.move(to: m.point(8, 3.5))
            p.addLine(to: m.point(8, 10.2))
            p.move(to: m.point(5.2, 7.4))
            p.addLine(to: m.point(8, 10.2))
            p.addLine(to: m.point(10.8, 7.4))
            return p
        }
    }

    struct TrayPath: Shape {
        func path(in rect: CGRect) -> Path {
            let m = IconMetrics(rect: rect)
            return Path(roundedRect: m.rect(x: 4, y: 12, w: 8, h: 1.5), cornerRadius: m.v(0.75))
        }
    }
}

/// Maps 16×16 viewBox coordinates into `rect`, preserving aspect.
private struct IconMetrics {
    let origin: CGPoint
    let scale: CGFloat

    init(rect: CGRect) {
        let s = min(rect.width, rect.height)
        origin = CGPoint(x: rect.minX + (rect.width - s) / 2, y: rect.minY + (rect.height - s) / 2)
        scale = s / 16
    }

    func v(_ n: CGFloat) -> CGFloat { n * scale }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    func rect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
        CGRect(x: origin.x + x * scale, y: origin.y + y * scale, width: w * scale, height: h * scale)
    }
}
