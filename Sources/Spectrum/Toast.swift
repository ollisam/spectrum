import AppKit

/// A brief glass HUD, e.g. "#3A7BD5  Copied".
enum Toast {
    private static var panel: NSPanel?
    private static var dismissWork: DispatchWorkItem?

    static func show(color: RGB? = nil, title: String, detail: String? = nil,
                     at point: NSPoint? = nil, duration: TimeInterval = 1.3) {
        dismissWork?.cancel()
        panel?.orderOut(nil)

        let height: CGFloat = 34
        let glass = GlassView(cornerRadius: height / 2)

        var x: CGFloat = 14
        if let color {
            let swatch = SwatchView(frame: NSRect(x: 10, y: (height - 16) / 2, width: 16, height: 16))
            swatch.color = color
            glass.content.addSubview(swatch)
            x = swatch.frame.maxX + 9
        }

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = color != nil
            ? .monospacedSystemFont(ofSize: 13, weight: .semibold)
            : .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.sizeToFit()
        titleLabel.frame.origin = NSPoint(x: x, y: (height - titleLabel.frame.height) / 2)
        glass.content.addSubview(titleLabel)
        x = titleLabel.frame.maxX

        if let detail {
            let detailLabel = NSTextField(labelWithString: detail)
            detailLabel.font = .systemFont(ofSize: 13)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.sizeToFit()
            detailLabel.frame.origin = NSPoint(x: x + 8, y: (height - detailLabel.frame.height) / 2)
            glass.content.addSubview(detailLabel)
            x = detailLabel.frame.maxX
        }

        let width = x + 15
        let margin: CGFloat = 24
        let size = NSSize(width: width + margin * 2, height: height + margin * 2)
        let panel = makeOverlayPanel(size: size, level: .statusBar)
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        glass.frame = NSRect(x: margin, y: margin, width: width, height: height)
        root.addSubview(glass)
        panel.contentView = root

        // Position: centred on the point (clamped on-screen), or low-centre of the main screen.
        let anchor = point ?? {
            let f = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            return NSPoint(x: f.midX, y: f.minY + f.height * 0.18)
        }()
        let screen = NSScreen.screens.first { NSPointInRect(anchor, $0.frame) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        var origin = NSPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2)
        origin.x = min(max(origin.x, vf.minX - margin + 8), vf.maxX - size.width + margin - 8)
        origin.y = min(max(origin.y, vf.minY - margin + 8), vf.maxY - size.height + margin - 8)
        panel.setFrameOrigin(NSPoint(x: origin.x.rounded(), y: (origin.y - 6).rounded()))

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(NSPoint(x: origin.x.rounded(), y: origin.y.rounded()))
        }
        self.panel = panel

        let work = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
