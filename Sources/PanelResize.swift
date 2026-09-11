import AppKit
import SwiftUI

enum PanelDimensions {
    static let initial = NSSize(width: 424, height: 628)
    static func clamped(_ size: NSSize, maximum: NSSize) -> NSSize {
        let maxWidth = max(1, maximum.width), maxHeight = max(1, maximum.height)
        return NSSize(width: min(max(size.width.isFinite ? size.width : initial.width, min(424, maxWidth)), maxWidth),
                      height: min(max(size.height.isFinite ? size.height : initial.height, min(520, maxHeight)), maxHeight))
    }
    static func dragged(_ size: NSSize, delta: NSPoint, horizontal: CGFloat, vertical: Bool, maximum: NSSize) -> NSSize {
        clamped(NSSize(width: size.width + delta.x * horizontal * 2,
                       height: size.height - (vertical ? delta.y : 0)), maximum: maximum)
    }
}

@MainActor final class PanelSize: ObservableObject {
    @Published private(set) var size: NSSize
    var maximum = NSSize(width: 900, height: 1000)
    var resized: ((NSSize) -> Void)?
    init() {
        let defaults = UserDefaults.standard
        let width = defaults.object(forKey: "panelWidth") as? Double ?? 424
        let height = defaults.object(forKey: "panelHeight") as? Double ?? 628
        size = PanelDimensions.clamped(NSSize(width: width, height: height), maximum: maximum)
    }
    func set(_ proposed: NSSize, persist: Bool = false) {
        let result = PanelDimensions.clamped(proposed, maximum: maximum)
        if result != size { size = result; resized?(result) }
        if persist { UserDefaults.standard.set(result.width, forKey: "panelWidth"); UserDefaults.standard.set(result.height, forKey: "panelHeight") }
    }
}

// Only the thin edges intercept input; the rest of the dashboard remains interactive.
struct PanelResizeEdges: NSViewRepresentable {
    @ObservedObject var sizing: PanelSize
    func makeNSView(context: Context) -> ResizeEdgesView { ResizeEdgesView(sizing: sizing) }
    func updateNSView(_ view: ResizeEdgesView, context: Context) { view.sizing = sizing; view.window?.invalidateCursorRects(for: view) }
}

@MainActor final class ResizeEdgesView: NSView {
    var sizing: PanelSize
    private var origin = NSPoint.zero
    private var originalSize = NSSize.zero
    private var horizontal: CGFloat = 0
    private var vertical = false
    override var isFlipped: Bool { true }
    init(sizing: PanelSize) { self.sizing = sizing; super.init(frame: .zero); toolTip = "拖动左右边缘调宽度、底边调高度，底角同时调整；双击底角恢复默认大小" }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func edges(at point: NSPoint) -> (CGFloat, Bool) {
        let bottom = point.y >= bounds.height - 10
        let corner = point.y >= bounds.height - 22
        let side: CGFloat = point.x < (corner ? 22 : 7) ? -1 : point.x > bounds.width - (corner ? 22 : 7) ? 1 : 0
        return (side, bottom || (corner && side != 0))
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local), local.y > 14 else { return nil }
        let (side, bottom) = edges(at: local)
        return side != 0 || bottom ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() {
        addCursorRect(NSRect(x: 0, y: 14, width: 7, height: max(0, bounds.height - 36)), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.width - 7, y: 14, width: 7, height: max(0, bounds.height - 36)), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: 22, y: bounds.height - 10, width: max(0, bounds.width - 44), height: 10), cursor: .resizeUpDown)
        for x in [CGFloat(0), bounds.width - 22] { addCursorRect(NSRect(x: x, y: bounds.height - 22, width: 22, height: 22), cursor: .crosshair) }
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        (horizontal, vertical) = edges(at: point)
        if event.clickCount == 2 { sizing.set(PanelDimensions.initial, persist: true); return }
        origin = NSEvent.mouseLocation; originalSize = sizing.size
    }
    override func mouseDragged(with event: NSEvent) {
        guard event.clickCount < 2 else { return }
        let current = NSEvent.mouseLocation
        sizing.set(PanelDimensions.dragged(originalSize, delta: NSPoint(x: current.x - origin.x, y: current.y - origin.y), horizontal: horizontal, vertical: vertical, maximum: sizing.maximum))
    }
    override func mouseUp(with event: NSEvent) { sizing.set(sizing.size, persist: true) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.tertiaryLabelColor.setStroke()
        for inset in [CGFloat(6), 10, 14] {
            let path = NSBezierPath(); path.lineWidth = 1
            path.move(to: NSPoint(x: bounds.width - inset, y: bounds.height - 5))
            path.line(to: NSPoint(x: bounds.width - 5, y: bounds.height - inset)); path.stroke()
        }
    }
}
