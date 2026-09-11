import Foundation

@main struct MenuBarPlacementTests {
    static func main() {
        let builtIn = MenuScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            left: CGRect(x: 0, y: 924, width: 645, height: 32),
            right: CGRect(x: 825, y: 924, width: 645, height: 32))
        func repair(_ x: Double, _ y: Double = 919, _ width: Double = 44) -> Bool {
            MenuBarPlacement.needsRepair(CGRect(x: x, y: y, width: width, height: 37), screens: [builtIn])
        }
        assert(!repair(1143), "Real menu window extends below safe strip but is clear of notch")
        assert(!repair(300), "Preserve a valid user-chosen position")
        assert(repair(720), "Item in camera gap must recover")
        assert(repair(810), "Even partial notch overlap must recover")
        assert(repair(1450), "Partially offscreen must recover")
        assert(repair(0, -37), "Unlaid-out window must recover")
        let external = MenuScreenGeometry(frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), left: nil, right: nil)
        assert(!MenuBarPlacement.needsRepair(CGRect(x: -90, y: 1056, width: 44, height: 24), screens: [external, builtIn]))
        print("PASS: real notch geometry, partial overlap, offscreen placement, preserved user position, external display")
    }
}
