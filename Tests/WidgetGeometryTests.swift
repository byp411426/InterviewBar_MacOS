import AppKit

@main struct WidgetGeometryTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let screen = NSRect(x: 0, y: 25, width: 1470, height: 868)
        for legacy in [NSRect(x: 40, y: 250, width: 500, height: 210), NSRect(x: 40, y: 250, width: 300, height: 320), NSRect(x: -4000, y: -2000, width: 1000, height: 1000)] {
            let fixed = WidgetDimensions.restored(legacy, in: screen)
            assert(abs(fixed.width / fixed.height - 11.0 / 7.0) < 0.000001)
            assert(screen.contains(fixed))
            if screen.contains(legacy) {
                assert(fixed.minX == legacy.minX && abs(fixed.maxY - legacy.maxY) < 0.000001)
            }
            assert(WidgetDimensions.restored(fixed, in: screen) == fixed)
        }
        let small = NSRect(x: -200, y: 0, width: 200, height: 100)
        let fitting = WidgetDimensions.restored(NSRect(origin: .zero, size: WidgetDimensions.base), in: small)
        assert(small.contains(fitting) && abs(fitting.width / fitting.height - 11.0 / 7.0) < 0.000001)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-geometry-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EventStore(directory: directory, notificationsAllowed: false)
        for kind in DesktopWidgetKind.allCases {
            let surface = WidgetSurfaceView(rootView: DesktopWidgetView(store: store, kind: kind, close: {}, open: {}))
            for scale in [CGFloat(0.9), 1.0, 1.25, 1.6] {
                surface.frame = NSRect(origin: .zero, size: WidgetDimensions.size(scale: scale))
                surface.layout()
                assert(abs((surface.layer?.cornerRadius ?? 0) - 22 * scale) < 0.001)
                assert(surface.layer?.masksToBounds == true)
                assert(surface.subviews.count == 2 && surface.subviews.allSatisfy { $0.frame == surface.bounds })
                assert(surface.subviews.first?.layer?.masksToBounds == true)
            }
        }
        print("PASS: legacy stretched-frame repair, fixed ratio, preserved top-left, display bounds, idempotent restore, both native rounded surfaces at 4 scales")
    }
}
