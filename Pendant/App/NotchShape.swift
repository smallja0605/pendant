import SwiftUI

/// Notch silhouette: rounded bottom corners, reverse (concave) corners at the top
/// where it joins the menu bar / wallpaper. The shape is `ear` wider than the notch on each side.
struct NotchShape: Shape {
    var bottomRadius: CGFloat = 10
    var ear: CGFloat = NotchGeometry.earRadius

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let body = rect.insetBy(dx: ear, dy: 0)
        let ear = min(self.ear, body.height)
        let bottom = min(bottomRadius, body.width / 2, body.height - ear)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // top-left ear: concave quarter circle down into the body
        path.addArc(
            center: CGPoint(x: rect.minX, y: rect.minY + ear),
            radius: ear, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
        )
        path.addLine(to: CGPoint(x: body.minX, y: body.maxY - bottom))
        path.addArc(
            center: CGPoint(x: body.minX + bottom, y: body.maxY - bottom),
            radius: bottom, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true
        )
        path.addLine(to: CGPoint(x: body.maxX - bottom, y: body.maxY))
        path.addArc(
            center: CGPoint(x: body.maxX - bottom, y: body.maxY - bottom),
            radius: bottom, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true
        )
        path.addLine(to: CGPoint(x: body.maxX, y: rect.minY + ear))
        path.addArc(
            center: CGPoint(x: rect.maxX, y: rect.minY + ear),
            radius: ear, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
