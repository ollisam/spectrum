import AppKit

/// Full-screen, nearly invisible window that swallows clicks while picking.
/// A non-activating panel so it can sit on another app's full-screen Space.
private final class CatcherWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class BlankCursorView: NSView {
    static let blank = NSCursor(image: NSImage(size: NSSize(width: 1, height: 1)), hotSpot: .zero)
    override func resetCursorRects() { addCursorRect(bounds, cursor: Self.blank) }
}

/// Runs a pick session. The real pointer is frozen and hidden; Spectrum moves its
/// own virtual pointer from mouse deltas so Shift can slow it down for
/// pixel-precise picking. On exit the real pointer is warped to the final spot.
final class PickerController {
    var onPick: ((RGB, NSPoint) -> Void)?
    var onError: ((Error) -> Void)?

    private(set) var isActive = false
    private var point = NSPoint.zero
    private var precise = false
    private var catchers: [CatcherWindow] = []
    private let loupe = LoupeWindow()
    private var sampler: ScreenSampler?
    private var monitors: [Any] = []
    private var previousApp: NSRunningApplication?
    private var cursorHidden = false

    private let preciseSpeed: CGFloat = 0.2

    func toggle() {
        isActive ? finish() : begin()
    }

    func begin() {
        guard !isActive else { return }
        isActive = true

        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == getpid() ? nil : front
        point = clamp(NSEvent.mouseLocation)
        precise = NSEvent.modifierFlags.contains(.shift)

        for screen in NSScreen.screens {
            let w = CatcherWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.level = .screenSaver
            w.backgroundColor = NSColor(white: 0, alpha: 0.001)
            w.isOpaque = false
            w.hasShadow = false
            w.ignoresMouseEvents = false
            w.acceptsMouseMovedEvents = true
            w.isReleasedWhenClosed = false
            w.hidesOnDeactivate = false
            w.sharingType = .none
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.contentView = BlankCursorView(frame: NSRect(origin: .zero, size: screen.frame.size))
            w.orderFrontRegardless()
            catchers.append(w)
        }

        NSApp.activate()
        let home = catchers.first { NSPointInRect(point, $0.frame) } ?? catchers.first
        home?.makeKeyAndOrderFront(nil)

        loupe.setZoomed(precise, animated: false)
        loupe.update(grid: .empty(radius: LoupeView.gridRadius), at: point)
        loupe.show()

        CGAssociateMouseAndMouseCursorPosition(0)
        NSCursor.hide()
        cursorHidden = true

        installMonitors()

        let sampler = ScreenSampler()
        self.sampler = sampler
        Task { @MainActor in
            do {
                try await sampler.start(near: point) { [weak self] in self?.refresh() }
            } catch {
                sampler.stop()
                if self.sampler === sampler {
                    self.finish()
                    self.onError?(error)
                }
            }
        }
    }

    // MARK: - Events

    private func installMonitors() {
        let local: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                           .leftMouseDown, .rightMouseDown, .keyDown, .flagsChanged, .scrollWheel]
        if let m = NSEvent.addLocalMonitorForEvents(matching: local, handler: { [weak self] event in
            self?.handle(event)
            return nil
        }) { monitors.append(m) }

        // Fallback in case activation was refused and events go elsewhere.
        let global: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown, .flagsChanged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: global, handler: { [weak self] event in
            self?.handle(event)
        }) { monitors.append(m) }
    }

    private func handle(_ event: NSEvent) {
        guard isActive else { return }
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let speed = precise ? preciseSpeed : 1
            move(to: NSPoint(x: point.x + event.deltaX * speed, y: point.y - event.deltaY * speed))
        case .leftMouseDown:
            pick()
        case .rightMouseDown:
            finish()
        case .flagsChanged:
            let shift = event.modifierFlags.contains(.shift)
            if shift != precise {
                precise = shift
                loupe.setZoomed(shift, animated: true)
            }
        case .keyDown:
            switch Int(event.keyCode) {
            case 53: finish()                        // esc
            case 36, 76, 49: pick()                  // return, enter, space
            case 123: nudge(dx: -1, dy: 0)           // ←
            case 124: nudge(dx: 1, dy: 0)            // →
            case 125: nudge(dx: 0, dy: -1)           // ↓
            case 126: nudge(dx: 0, dy: 1)            // ↑
            default: break
            }
        default:
            break
        }
    }

    /// Moves by exactly one device pixel.
    private func nudge(dx: CGFloat, dy: CGFloat) {
        let scale = NSScreen.screens.first { NSPointInRect(point, $0.frame) }?.backingScaleFactor ?? 2
        move(to: NSPoint(x: point.x + dx / scale, y: point.y + dy / scale))
    }

    private func move(to p: NSPoint) {
        point = clamp(p)
        refresh()
    }

    private func refresh() {
        guard isActive else { return }
        let grid = sampler?.grid(at: point, radius: LoupeView.gridRadius) ?? .empty(radius: LoupeView.gridRadius)
        loupe.update(grid: grid, at: point)
    }

    /// Keeps the point on a display (the union of screens isn't rectangular).
    private func clamp(_ p: NSPoint) -> NSPoint {
        let screens = NSScreen.screens
        if screens.contains(where: { NSPointInRect(p, $0.frame) }) { return p }
        var best = p
        var bestDistance = CGFloat.infinity
        for s in screens {
            let f = s.frame
            let c = NSPoint(x: min(max(p.x, f.minX), f.maxX - 0.01), y: min(max(p.y, f.minY), f.maxY - 0.01))
            let d = hypot(c.x - p.x, c.y - p.y)
            if d < bestDistance { bestDistance = d; best = c }
        }
        return best
    }

    // MARK: - Finish

    private func pick() {
        let color = sampler?.grid(at: point, radius: 0).center
        let at = point
        finish()
        if let color { onPick?(color, at) }
    }

    private func finish() {
        guard isActive else { return }
        isActive = false

        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        sampler?.stop()
        sampler = nil

        loupe.hide()
        catchers.forEach { $0.orderOut(nil) }
        catchers.removeAll()

        // Put the real pointer where the virtual one ended up.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: point.x, y: primaryHeight - point.y))
        CGAssociateMouseAndMouseCursorPosition(1)
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }

        previousApp?.activate()
        previousApp = nil
    }
}
