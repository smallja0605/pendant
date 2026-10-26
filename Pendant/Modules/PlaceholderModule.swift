import SwiftUI

/// Stand-in for modules that arrive in later milestones: shows the module's icon and "coming soon".
@MainActor
final class PlaceholderModule: PendantModule {
    let id: String
    let displayName: String
    let symbolName: String
    let cells: CellRange
    var isEnabled = false

    init(descriptor: ModuleDescriptor) {
        id = descriptor.id
        displayName = descriptor.title
        symbolName = descriptor.symbolName
        cells = descriptor.cells
    }

    func makeView(size: CGSize) -> AnyView {
        AnyView(
            VStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(loc(displayName))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text("即將推出…")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(width: size.width, height: size.height)
        )
    }

    func activate() {}
    func deactivate() {}
}
