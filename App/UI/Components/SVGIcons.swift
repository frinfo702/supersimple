import SwiftUI

/// Stroked SVG glyphs lifted from the provided design assets (`plus_bottun.svg`
/// and `sidebar_icon.svg`). Both use a 16x16 viewBox with `currentColor`; we draw
/// them as SwiftUI `Shape`s in a [0–16] logical space and scale to the view size.

/// plus_bottun.svg: `M8 4.5V11.5 M4.5 8H11.5` (stroke 1)
struct PlusIcon: View {
    var lineWidth: CGFloat = 1.5

    var body: some View {
        PlusPath()
            .stroke(style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    struct PlusPath: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height)
            func x(_ v: CGFloat) -> CGFloat { rect.minX + (v / 16) * s }
            func y(_ v: CGFloat) -> CGFloat { rect.minY + (v / 16) * s }
            var p = Path()
            p.move(to: CGPoint(x: x(8), y: y(4.5)))
            p.addLine(to: CGPoint(x: x(8), y: y(11.5)))
            p.move(to: CGPoint(x: x(4.5), y: y(8)))
            p.addLine(to: CGPoint(x: x(11.5), y: y(8)))
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
        }
    }

    struct OutlinePath: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height)
            func cx(_ v: CGFloat) -> CGFloat { rect.minX + (v / 16) * s }
            func cy(_ v: CGFloat) -> CGFloat { rect.minY + (v / 16) * s }
            let r = CGRect(x: cx(2), y: cy(2.75), width: (12 / 16) * s, height: (10.5 / 16) * s)
            return Path(roundedRect: r, cornerRadius: (2.25 / 16) * s)
        }
    }

    struct DividerPath: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height)
            func cx(_ v: CGFloat) -> CGFloat { rect.minX + (v / 16) * s }
            func cy(_ v: CGFloat) -> CGFloat { rect.minY + (v / 16) * s }
            let r = CGRect(x: cx(10.75), y: cy(5), width: (1.75 / 16) * s, height: (6 / 16) * s)
            return Path(roundedRect: r, cornerRadius: (0.875 / 16) * s)
        }
    }
}
