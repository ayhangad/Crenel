import SwiftUI

/// The notch silhouette: flush with the top edge, flaring outward at the top corners the
/// way the hardware notch meets the menu bar, rounded at the bottom. Both radii animate,
/// so one shape can morph from the hardware notch into any size the content needs.
///
/// The flares lie inside the frame: the walls are inset by `topRadius` on each side, so
/// a body of width `w` needs a frame of `w + 2 * topRadius`.
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

        // Circular arcs, as the prototype's CSS draws them: a concave quarter circle of
        // `top` outside each wall, a convex quarter circle of `bottom` at each bottom corner.
        var path = Path()
        path.move(to: CGPoint(x: minX, y: minY))
        path.addArc(
            tangent1End: CGPoint(x: minX + top, y: minY),
            tangent2End: CGPoint(x: minX + top, y: minY + top),
            radius: top
        )
        path.addLine(to: CGPoint(x: minX + top, y: maxY - bottom))
        path.addArc(
            tangent1End: CGPoint(x: minX + top, y: maxY),
            tangent2End: CGPoint(x: minX + top + bottom, y: maxY),
            radius: bottom
        )
        path.addLine(to: CGPoint(x: maxX - top - bottom, y: maxY))
        path.addArc(
            tangent1End: CGPoint(x: maxX - top, y: maxY),
            tangent2End: CGPoint(x: maxX - top, y: maxY - bottom),
            radius: bottom
        )
        path.addLine(to: CGPoint(x: maxX - top, y: minY + top))
        path.addArc(
            tangent1End: CGPoint(x: maxX - top, y: minY),
            tangent2End: CGPoint(x: maxX, y: minY),
            radius: top
        )
        path.closeSubpath()
        return path
    }
}

/// Lays out the closed notch: content flanks the hardware notch on both sides. Both
/// flanks get the wider flank's width so the gap stays centred on the camera housing.
///
/// With `totalWidth` (the strip) the two ears share what is left beside the gap and
/// their content is truncated to fit; without it the notch is only as wide as the wider
/// ear needs.
struct NotchFlankLayout: Layout {
    var gap: CGFloat
    var totalWidth: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let ear = earProposal
        let leading = subviews[0].sizeThatFits(ear)
        let trailing = subviews[1].sizeThatFits(ear)
        let side = max(leading.width, trailing.width)
        return CGSize(width: totalWidth ?? (side * 2 + gap), height: max(leading.height, trailing.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: earProposal
        )
        subviews[1].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: earProposal
        )
    }

    private var earProposal: ProposedViewSize {
        guard let totalWidth else { return .unspecified }
        return ProposedViewSize(width: max(0, (totalWidth - gap) / 2), height: nil)
    }
}
