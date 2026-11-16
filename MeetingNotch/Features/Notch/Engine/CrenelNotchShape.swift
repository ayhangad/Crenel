import SwiftUI

/// The notch silhouette: flush with the top edge, flaring outward at the top corners the
/// way the hardware notch meets the menu bar, rounded at the bottom. Both radii animate,
/// so one shape can morph from the hardware notch into any size the content needs.
struct CrenelNotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = max(0, min(topRadius, rect.width / 4))
        let bottom = max(0, min(bottomRadius, (rect.width - 2 * top) / 2, rect.height - top))
        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: minX, y: minY))
        // Outward flare into the left wall.
        path.addQuadCurve(
            to: CGPoint(x: minX + top, y: minY + top),
            control: CGPoint(x: minX + top, y: minY)
        )
        path.addLine(to: CGPoint(x: minX + top, y: maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: minX + top + bottom, y: maxY),
            control: CGPoint(x: minX + top, y: maxY)
        )
        path.addLine(to: CGPoint(x: maxX - top - bottom, y: maxY))
        path.addQuadCurve(
            to: CGPoint(x: maxX - top, y: maxY - bottom),
            control: CGPoint(x: maxX - top, y: maxY)
        )
        path.addLine(to: CGPoint(x: maxX - top, y: minY + top))
        path.addQuadCurve(
            to: CGPoint(x: maxX, y: minY),
            control: CGPoint(x: maxX - top, y: minY)
        )
        path.closeSubpath()
        return path
    }
}

/// Lays out the closed notch: content flanks the hardware notch on both sides. Both
/// flanks get the wider flank's width so the gap stays centred on the camera housing.
struct NotchFlankLayout: Layout {
    var gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[1].sizeThatFits(.unspecified)
        let side = max(leading.width, trailing.width)
        return CGSize(width: side * 2 + gap, height: max(leading.height, trailing.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: .unspecified
        )
        subviews[1].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: .unspecified
        )
    }
}
