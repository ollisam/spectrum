import AppKit

/// A rounded glass surface: Liquid Glass on macOS 26, HUD vibrancy before that.
/// Put content in `content`.
class GlassView: NSView {
    let content = NSView()
    private let surface: NSView

    init(cornerRadius: CGFloat) {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            surface = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = cornerRadius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            effect.addSubview(content)
            surface = effect
        }
        super.init(frame: .zero)
        surface.autoresizingMask = [.width, .height]
        content.autoresizingMask = [.width, .height]
        addSubview(surface)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        surface.frame = bounds
        content.frame = surface.bounds
    }
}

/// A small rounded color chip with a hairline border.
final class SwatchView: NSView {
    var color: RGB? {
        didSet { updateColor() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        updateColor()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    private func updateColor() {
        layer?.backgroundColor = color?.cgColor ?? CGColor(gray: 0.5, alpha: 0.25)
        let light = (color?.luminance ?? 0) > 0.5
        layer?.borderColor = light ? CGColor(gray: 0, alpha: 0.18) : CGColor(gray: 1, alpha: 0.28)
    }
}

/// Shared panel setup for Spectrum's floating, click-through HUD windows.
func makeOverlayPanel(size: NSSize, level: NSWindow.Level) -> NSPanel {
    let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = level
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.sharingType = .none
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    return panel
}
