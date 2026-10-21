import AppKit
import ScreenCaptureKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Holds the most recent frame of one display's capture stream.
private final class DisplayStream: NSObject, SCStreamOutput {
    let frame: NSRect
    let stream: SCStream
    private let onFrame: () -> Void
    private let lock = NSLock()
    private var latest: CVPixelBuffer?

    init(frame: NSRect, stream: SCStream, onFrame: @escaping () -> Void) {
        self.frame = frame
        self.stream = stream
        self.onFrame = onFrame
    }

    var buffer: CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }

        lock.lock()
        latest = pixelBuffer
        lock.unlock()
        DispatchQueue.main.async(execute: onFrame)
    }
}

/// Streams every display at native resolution (excluding Spectrum's own
/// windows) so pixels under the pointer can be read instantly.
final class ScreenSampler {
    private var displays: [DisplayStream] = []
    private var stopped = false
    private let queue = DispatchQueue(label: "spectrum.capture", qos: .userInteractive)

    func start(near point: NSPoint, onFrame: @escaping () -> Void) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let pid = getpid()
        let mine = content.applications.filter { $0.processID == pid }
        let myWindows = content.windows.filter { $0.owningApplication?.processID == pid }

        // Start the display under the pointer first so the loupe fills in fastest.
        var screens = NSScreen.screens
        if let i = screens.firstIndex(where: { NSPointInRect(point, $0.frame) }) {
            screens.insert(screens.remove(at: i), at: 0)
        }

        for screen in screens {
            guard !stopped else { return }
            guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { continue }

            let filter = mine.isEmpty
                ? SCContentFilter(display: display, excludingWindows: myWindows)
                : SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])

            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB
            config.showsCursor = false
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.queueDepth = 4

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            let output = DisplayStream(frame: screen.frame, stream: stream, onFrame: onFrame)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
            displays.append(output)
            try await stream.startCapture()

            if stopped { try? await stream.stopCapture() }
        }
    }

    func stop() {
        stopped = true
        for display in displays {
            display.stream.stopCapture { _ in }
        }
        displays.removeAll()
    }

    /// Reads a (2r+1)² block of device pixels centred on a global point.
    func grid(at point: NSPoint, radius r: Int) -> PixelGrid {
        var grid = PixelGrid.empty(radius: r)
        guard let display = displays.first(where: { NSPointInRect(point, $0.frame) }),
              let pb = display.buffer else { return grid }

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb)?.assumingMemoryBound(to: UInt8.self) else { return grid }

        let width = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let frame = display.frame
        let scale = CGFloat(width) / frame.width
        let cx = Int(floor((point.x - frame.minX) * scale))
        let cy = Int(floor((frame.maxY - point.y) * scale))

        for j in -r...r {
            let y = cy + j
            guard y >= 0, y < height else { continue }
            for i in -r...r {
                let x = cx + i
                guard x >= 0, x < width else { continue }
                let o = y * bytesPerRow + x * 4
                grid[i, j] = RGB(r: base[o + 2], g: base[o + 1], b: base[o])
            }
        }
        return grid
    }
}
