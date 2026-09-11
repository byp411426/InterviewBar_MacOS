import AppKit
import SwiftUI

// A widget is a single design canvas: geometry, typography and corners share one scale.
enum WidgetDimensions {
    static let base = NSSize(width: 330, height: 210)
    static let ratio = NSSize(width: 11, height: 7)
    static let corner: CGFloat = 22
    static func size(scale: CGFloat) -> NSSize { NSSize(width: base.width * scale, height: base.height * scale) }
    static func maximumScale(in available: NSSize) -> CGFloat {
        max(0.1, min(1.6, available.width / base.width, available.height / base.height))
    }
    static func restored(_ saved: NSRect, in screen: NSRect) -> NSRect {
        let maximum = maximumScale(in: screen.size)
        let proposed = saved.width.isFinite && saved.width > 0 ? saved.width / base.width : 1
        let size = size(scale: min(maximum, max(min(0.9, maximum), proposed)))
        let x = saved.minX.isFinite ? saved.minX : screen.minX + 30
        let top = saved.maxY.isFinite ? saved.maxY : screen.maxY - 30
        return NSRect(x: min(max(x, screen.minX), screen.maxX - size.width),
                      y: min(max(top - size.height, screen.minY), screen.maxY - size.height),
                      width: size.width, height: size.height)
    }
}

@MainActor final class WidgetSurfaceView: NSView {
    private let glass = NSVisualEffectView()
    private let hosting: NSHostingView<DesktopWidgetView>
    override var isFlipped: Bool { true }
    init(rootView: DesktopWidgetView) {
        hosting = NSHostingView(rootView: rootView)
        super.init(frame: NSRect(origin: .zero, size: WidgetDimensions.base))
        wantsLayer = true
        glass.material = .popover; glass.blendingMode = .behindWindow; glass.state = .active
        glass.wantsLayer = true
        hosting.sizingOptions = []
        addSubview(glass); addSubview(hosting)
        toolTip = "拖动空白处移动；拖边缘或角等比例缩放"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let scale = min(bounds.width / WidgetDimensions.base.width, bounds.height / WidgetDimensions.base.height)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glass.frame = bounds; hosting.frame = bounds
        // Clip the AppKit backdrop as well as SwiftUI; SwiftUI clipping alone cannot
        // reliably mask a behind-window visual effect during native live resizing.
        for surface in [layer, glass.layer] {
            surface?.cornerRadius = WidgetDimensions.corner * scale
            surface?.cornerCurve = .continuous; surface?.masksToBounds = true
        }
        layer?.borderWidth = max(0.5, scale * 0.8)
        layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        CATransaction.commit()
        window?.invalidateShadow()
    }
}
