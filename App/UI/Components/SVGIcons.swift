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

/// start.svg: outlined favorite star supplied for the library UI (24×24 viewBox).
struct FavoriteIcon: View {
    var lineWidth: CGFloat = 1.5

    var body: some View {
        StarPath()
            .stroke(style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    struct StarPath: Shape {
        func path(in rect: CGRect) -> Path {
            let m = IconMetrics(rect: rect)
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                m.point(x * 16 / 24, y * 16 / 24)
            }
            var p = Path()
            p.move(to: pt(11.525, 2.295))
            p.addCurve(to: pt(12, 2.0001), control1: pt(11.6144, 2.1144), control2: pt(11.7985, 2.0001))
            p.addCurve(to: pt(12.475, 2.295), control1: pt(12.2015, 2.0001), control2: pt(12.3856, 2.1144))
            p.addLine(to: pt(14.785, 6.974))
            p.addCurve(to: pt(16.38, 8.134), control1: pt(15.0939, 7.5991), control2: pt(15.6901, 8.0327))
            p.addLine(to: pt(21.546, 8.89))
            p.addCurve(to: pt(21.974, 9.2506), control1: pt(21.7457, 8.9189), control2: pt(21.9116, 9.0587))
            p.addCurve(to: pt(21.84, 9.794), control1: pt(22.0364, 9.4425), control2: pt(21.9845, 9.6531))
            p.addLine(to: pt(18.104, 13.432))
            p.addCurve(to: pt(17.493, 15.31), control1: pt(17.6038, 13.9194), control2: pt(17.3754, 14.6216))
            p.addLine(to: pt(18.375, 20.45))
            p.addCurve(to: pt(18.1645, 20.971), control1: pt(18.4103, 20.6496), control2: pt(18.3286, 20.8519))
            p.addCurve(to: pt(17.604, 21.01), control1: pt(18.0005, 21.0901), control2: pt(17.7829, 21.1053))
            p.addLine(to: pt(12.986, 18.582))
            p.addCurve(to: pt(11.013, 18.582), control1: pt(12.3683, 18.2577), control2: pt(11.6307, 18.2577))
            p.addLine(to: pt(6.396, 21.01))
            p.addCurve(to: pt(5.8363, 20.9702), control1: pt(6.2171, 21.1047), control2: pt(6, 21.0893))
            p.addCurve(to: pt(5.626, 20.45), control1: pt(5.6726, 20.8512), control2: pt(5.591, 20.6493))
            p.addLine(to: pt(6.507, 15.311))
            p.addCurve(to: pt(5.896, 13.432), control1: pt(6.6251, 14.6223), control2: pt(6.3966, 13.9195))
            p.addLine(to: pt(2.16, 9.795))
            p.addCurve(to: pt(2.0241, 9.2502), control1: pt(2.0143, 9.6543), control2: pt(1.9616, 9.4428))
            p.addCurve(to: pt(2.454, 8.889), control1: pt(2.0866, 9.0575), control2: pt(2.2534, 8.9174))
            p.addLine(to: pt(7.619, 8.134))
            p.addCurve(to: pt(9.216, 6.974), control1: pt(8.3097, 8.0335), control2: pt(8.9068, 7.5998))
            p.addCurve(to: pt(11.525, 2.295), control1: pt(9.9857, 5.4143), control2: pt(10.7553, 3.8547))
            p.closeSubpath()
            return p
        }
    }
}

/// morphicons trash SVG supplied for delete and library Trash affordances (24×24 viewBox).
struct TrashIcon: View {
    var lineWidth: CGFloat = 1.5

    var body: some View {
        TrashPath()
            .stroke(style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    struct TrashPath: Shape {
        func path(in rect: CGRect) -> Path {
            let m = IconMetrics(rect: rect)
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                m.point(x * 16 / 24, y * 16 / 24)
            }
            var p = Path()
            p.move(to: pt(14.74, 9))
            p.addCurve(to: pt(14.394, 18), control1: pt(14.6247, 12), control2: pt(14.5093, 15))
            p.move(to: pt(9.606, 18))
            p.addCurve(to: pt(9.26, 9), control1: pt(9.4907, 15), control2: pt(9.3753, 12))
            p.move(to: pt(19.228, 5.79))
            p.addCurve(to: pt(20.25, 5.956), control1: pt(19.57, 5.842), control2: pt(19.91, 5.897))
            p.move(to: pt(19.228, 5.791))
            p.addCurve(to: pt(18.16, 19.673), control1: pt(18.872, 10.4183), control2: pt(18.516, 15.0457))
            p.addCurve(to: pt(15.916, 21.75), control1: pt(18.0696, 20.8453), control2: pt(17.0918, 21.7503))
            p.addLine(to: pt(8.084, 21.75))
            p.addCurve(to: pt(5.84, 19.673), control1: pt(6.9082, 21.7503), control2: pt(5.9304, 20.8453))
            p.addLine(to: pt(4.772, 5.79))
            p.move(to: pt(19.228, 5.79))
            p.addCurve(to: pt(15.75, 5.393), control1: pt(18.0739, 5.6155), control2: pt(16.9138, 5.4831))
            p.move(to: pt(3.75, 5.955))
            p.addCurve(to: pt(4.772, 5.79), control1: pt(4.09, 5.896), control2: pt(4.43, 5.841))
            p.move(to: pt(4.772, 5.79))
            p.addCurve(to: pt(8.25, 5.393), control1: pt(5.9261, 5.6155), control2: pt(7.0862, 5.4831))
            p.move(to: pt(15.75, 5.393))
            p.addLine(to: pt(15.75, 4.477))
            p.addCurve(to: pt(13.66, 2.276), control1: pt(15.75, 3.297), control2: pt(14.84, 2.313))
            p.addCurve(to: pt(10.34, 2.276), control1: pt(12.5536, 2.2406), control2: pt(11.4464, 2.2406))
            p.addCurve(to: pt(8.25, 4.477), control1: pt(9.16, 2.313), control2: pt(8.25, 3.298))
            p.addLine(to: pt(8.25, 5.393))
            p.move(to: pt(15.75, 5.393))
            p.addCurve(to: pt(8.25, 5.393), control1: pt(13.2537, 5.2001), control2: pt(10.7463, 5.2001))
            return p
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
