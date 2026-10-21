import AppKit

/// The circular magnifier: draws screen pixels as crisp enlarged squares.
final class LoupeView: NSView {
    static let diameter: CGFloat = 136
    static let normalCell: CGFloat = 8
    static let zoomedCell: CGFloat = 19
    static let gridRadius = Int(ceil(diameter / normalCell / 2)) + 1

    var grid = PixelGrid.empty(radius: LoupeView.gridRadius) {
        didSet { needsDisplay = true }
    }

    private var cell = LoupeView.normalCell
    private var targetCell = LoupeView.normalCell
    private var animation: Timer?

    override var isFlipped: Bool { true }

    func setZoomed(_ zoomed: Bool, animated: Bool) {
        targetCell = zoomed ? Self.zoomedCell : Self.normalCell
        animation?.invalidate()
        guard animated else {
            cell = targetCell
            needsDisplay = true
            return
        }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.cell += (self.targetCell - self.cell) * 0.28
            if abs(self.targetCell - self.cell) < 0.05 {
                self.cell = self.targetCell
                t.invalidate()
            }
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        animation = timer
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds
        let mid = CGPoint(x: b.midX, y: b.midY)
        let hairline = 1 / (window?.backingScaleFactor ?? 2)

        ctx.saveGState()
        ctx.addEllipse(in: b)
        ctx.clip()
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        ctx.fill(b)

        // Pixels, nearest-neighbour.
        let n = min(grid.radius, Int(ceil(b.width / cell / 2)))
        for j in -n...n {
            for i in -n...n {
                guard let p = grid[i, j] else { continue }
                ctx.setFillColor(p.cgColor)
                ctx.fill(CGRect(x: mid.x + (CGFloat(i) - 0.5) * cell,
                                y: mid.y + (CGFloat(j) - 0.5) * cell,
                                width: cell, height: cell))
            }
        }

        // Pixel grid fades in as you zoom.
        let gridAlpha = max(0, min(1, (cell - 10) / 6)) * 0.16
        if gridAlpha > 0 {
            ctx.setStrokeColor(CGColor(gray: 0, alpha: gridAlpha))
            ctx.setLineWidth(hairline)
            for k in -n...(n + 1) {
                let o = (CGFloat(k) - 0.5) * cell
                ctx.move(to: CGPoint(x: mid.x + o, y: b.minY)); ctx.addLine(to: CGPoint(x: mid.x + o, y: b.maxY))
                ctx.move(to: CGPoint(x: b.minX, y: mid.y + o)); ctx.addLine(to: CGPoint(x: b.maxX, y: mid.y + o))
            }
            ctx.strokePath()
        }

        // Target pixel.
        let target = CGRect(x: mid.x - cell / 2, y: mid.y - cell / 2, width: cell, height: cell)
        let light = (grid.center?.luminance ?? 0) > 0.45
        ctx.setStrokeColor(light ? CGColor(gray: 1, alpha: 0.7) : CGColor(gray: 0, alpha: 0.5))
        ctx.setLineWidth(1)
        ctx.stroke(target.insetBy(dx: -2, dy: -2))
        ctx.setStrokeColor(light ? CGColor(gray: 0, alpha: 0.9) : CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(1.5)
        ctx.stroke(target.insetBy(dx: -0.75, dy: -0.75))
        ctx.restoreGState()

        // Rim.
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.92))
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: b.insetBy(dx: 1.5, dy: 1.5))
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.22))
        ctx.setLineWidth(hairline)
        ctx.strokeEllipse(in: b.insetBy(dx: hairline / 2, dy: hairline / 2))
    }
}

/// Glass pill under the loupe showing swatch, hex and name.
final class InfoPill: GlassView {
    static let height: CGFloat = 30

    private let swatch = SwatchView(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
    private let hexLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")

    init() {
        super.init(cornerRadius: Self.height / 2)
        hexLabel.font = .monospacedSystemFont(ofSize: 12.5, weight: .semibold)
        hexLabel.textColor = .labelColor
        nameLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        [swatch, hexLabel, nameLabel].forEach(content.addSubview)
        set(color: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private(set) var preferredWidth: CGFloat = 120

    func set(color: RGB?) {
        swatch.color = color
        hexLabel.stringValue = color?.hex ?? "—"
        nameLabel.stringValue = color.map(ColorNames.name(for:)) ?? ""
        hexLabel.sizeToFit()
        nameLabel.sizeToFit()
        let nameWidth = min(nameLabel.frame.width, 150)
        preferredWidth = 9 + 14 + 8 + hexLabel.frame.width + (nameWidth > 0 ? 7 + nameWidth : 0) + 13
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        swatch.frame = NSRect(x: 9, y: (h - 14) / 2, width: 14, height: 14)
        hexLabel.frame.origin = NSPoint(x: swatch.frame.maxX + 8, y: (h - hexLabel.frame.height) / 2)
        let nameX = hexLabel.frame.maxX + 7
        nameLabel.frame = NSRect(x: nameX, y: (h - nameLabel.frame.height) / 2,
                                 width: max(0, bounds.width - nameX - 13), height: nameLabel.frame.height)
    }
}

/// Floating, click-through window containing the loupe and info pill.
/// The loupe is centred on the window, so the window's centre is the sample point.
final class LoupeWindow {
    let panel: NSPanel
    private let loupe = LoupeView(frame: NSRect(x: 0, y: 0, width: LoupeView.diameter, height: LoupeView.diameter))
    private let pill = InfoPill()
    private let gap: CGFloat = 10
    private var lastColor: RGB??

    init() {
        let size = NSSize(width: 320, height: LoupeView.diameter + 2 * (10 + InfoPill.height) + 40)
        panel = makeOverlayPanel(size: size, level: NSWindow.Level(NSWindow.Level.screenSaver.rawValue + 1))

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        let shadowHost = NSView(frame: NSRect(x: (size.width - LoupeView.diameter) / 2,
                                              y: (size.height - LoupeView.diameter) / 2,
                                              width: LoupeView.diameter, height: LoupeView.diameter))
        shadowHost.wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.32)
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = NSSize(width: 0, height: -5)
        shadowHost.shadow = shadow
        shadowHost.layer?.shadowPath = CGPath(ellipseIn: shadowHost.bounds, transform: nil)
        loupe.wantsLayer = true
        shadowHost.addSubview(loupe)
        root.addSubview(shadowHost)
        root.addSubview(pill)
        panel.contentView = root
    }

    func setZoomed(_ zoomed: Bool, animated: Bool) {
        loupe.setZoomed(zoomed, animated: animated)
    }

    func show() {
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        lastColor = nil
    }

    func update(grid: PixelGrid, at point: NSPoint) {
        loupe.grid = grid
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: (point.x - size.width / 2).rounded(), y: (point.y - size.height / 2).rounded()))

        if lastColor != .some(grid.center) {
            lastColor = .some(grid.center)
            pill.set(color: grid.center)
        }

        // Pill sits below the loupe, flipping above near the bottom of the screen.
        let screen = NSScreen.screens.first { NSPointInRect(point, $0.frame) }
        let needed = LoupeView.diameter / 2 + gap + InfoPill.height + 6
        let below = screen.map { point.y - needed >= $0.frame.minY } ?? true
        let w = pill.preferredWidth
        let mid = size.height / 2
        let y = below ? mid - LoupeView.diameter / 2 - gap - InfoPill.height : mid + LoupeView.diameter / 2 + gap
        pill.frame = NSRect(x: ((size.width - w) / 2).rounded(), y: y.rounded(), width: w, height: InfoPill.height)
    }
}
