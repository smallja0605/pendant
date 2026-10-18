import CoreGraphics

extension CGRect {
    /// Edge-inclusive hit test for pointer positions. `CGRect.contains` excludes `maxY`, but the pointer
    /// parked at the very top of the screen sits exactly on it (y == screen height), which made the
    /// capsule ignore clicks made with the cursor pushed against the top edge.
    func containsPointer(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}
