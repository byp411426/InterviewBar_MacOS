import Foundation
import CoreGraphics

struct MenuScreenGeometry {
    var frame: CGRect
    var left: CGRect?
    var right: CGRect?
}

enum MenuBarPlacement {
    static func needsRepair(_ item: CGRect, screens: [MenuScreenGeometry]) -> Bool {
        guard item.width > 0, item.height > 0,
              let screen = screens.first(where: { $0.frame.intersects(item) }) else { return true }
        func fitsHorizontally(_ area: CGRect) -> Bool {
            item.minX >= area.minX && item.maxX <= area.maxX
        }
        guard let left = screen.left, let right = screen.right else {
            return !fitsHorizontally(screen.frame)
        }
        // Status-item windows can be taller than the menu's safe strip.
        return !fitsHorizontally(left) && !fitsHorizontally(right)
    }
}
