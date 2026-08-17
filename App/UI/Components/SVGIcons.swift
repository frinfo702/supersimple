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

/// sidebar_icon.svg: rounded rect `x=2 y=2.75 w=12 h=10.5 rx=2.25` (stroke 1)
/// plus an inner filled divider `x=10.75 y=5 w=1.75 h=6 rx=0.875` (opacity 0.7).
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
            return Path(roundedRect: m.rect(x: 10.75, y: 5, w: 1.75, h: 6), cornerRadius: m.v(0.875))
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

/// Light appearance: a sun (circle + rays).
struct LightThemeIcon: View {
    var lineWidth: CGFloat = 1.5

    var body: some View {
        LightSunPath()
            .stroke(style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    struct LightSunPath: Shape {
        func path(in rect: CGRect) -> Path {
            let m = IconMetrics(rect: rect)
            var p = Path()
            p.addEllipse(in: m.rect(x: 5, y: 5, w: 6, h: 6))
            let rays: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (8, 1.6, 8, 3.4),
                (8, 12.6, 8, 14.4),
                (1.6, 8, 3.4, 8),
                (12.6, 8, 14.4, 8),
                (3.3, 3.3, 4.6, 4.6),
                (11.4, 11.4, 12.7, 12.7),
                (12.7, 3.3, 11.4, 4.6),
                (4.6, 11.4, 3.3, 12.7),
            ]
            for ray in rays {
                p.move(to: m.point(ray.0, ray.1))
                p.addLine(to: m.point(ray.2, ray.3))
            }
            return p
        }
    }
}

/// dark_theme_icon.svg: sun over two horizon bars.
struct DarkThemeIcon: View {
    var lineWidth: CGFloat = 1.5

    var body: some View {
        ZStack {
            SunArc()
                .stroke(style: .init(lineWidth: lineWidth, lineCap: .round))
            HorizonBars()
                .fill()
        }
    }

    struct SunArc: Shape {
        func path(in rect: CGRect) -> Path {
            let m = IconMetrics(rect: rect)
            let sun = m.rect(x: 3, y: 2.2, w: 10, h: 10)
            var p = Path()
            p.addArc(
                center: CGPoint(x: sun.midX, y: sun.midY),
                radius: sun.width / 2,
                startAngle: .degrees(200),
                endAngle: .degrees(-20),
                clockwise: false
            )
            return p
        }
    }

    struct HorizonBars: Shape {
        func path(in rect: CGRect) -> Path {
            let m = IconMetrics(rect: rect)
            var p = Path()
            p.addPath(Path(roundedRect: m.rect(x: 1.5, y: 10.5, w: 13, h: 1.5), cornerRadius: m.v(0.75)))
            p.addPath(Path(roundedRect: m.rect(x: 4.5, y: 13.4, w: 7, h: 1.5), cornerRadius: m.v(0.75)))
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
