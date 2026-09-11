import AppKit

@main struct PanelResizeTests {
    static func main() {
        let start = PanelDimensions.initial, maximum = NSSize(width: 900, height: 850)
        let tall = PanelDimensions.dragged(start, delta: NSPoint(x: 70, y: -120), horizontal: 0, vertical: true, maximum: maximum)
        assert(tall == NSSize(width: 424, height: 748))
        let wide = PanelDimensions.dragged(start, delta: NSPoint(x: -60, y: 100), horizontal: -1, vertical: false, maximum: maximum)
        assert(wide == NSSize(width: 544, height: 628))
        let corner = PanelDimensions.dragged(start, delta: NSPoint(x: 90, y: -80), horizontal: 1, vertical: true, maximum: maximum)
        assert(corner == NSSize(width: 604, height: 708))
        assert(PanelDimensions.clamped(NSSize(width: 10000, height: 10000), maximum: maximum) == maximum)
        assert(PanelDimensions.clamped(.zero, maximum: maximum) == NSSize(width: 424, height: 520))
        assert(PanelDimensions.clamped(start, maximum: NSSize(width: 380, height: 490)) == NSSize(width: 380, height: 490))
        assert(PanelDimensions.clamped(NSSize(width: CGFloat.nan, height: CGFloat.infinity), maximum: maximum) == start)
        print("PASS: side/bottom/corner resizing, independent axes, minimum and screen bounds, invalid saved sizes")
    }
}
