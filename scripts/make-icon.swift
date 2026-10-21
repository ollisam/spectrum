// Renders Spectrum's app icon: the circular gradient artwork in Resources/icon-source.png,
// cropped inside its grey rim and placed on the macOS icon grid with a drop shadow.
// Usage: swift scripts/make-icon.swift <source.png> <output.png>
import AppKit

let src = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))!.cgImage!
// The artwork's circle (in source pixels, top-left origin), inset past the anti-aliased grey rim.
let srcCenter = CGPoint(x: 194, y: 194), srcRadius: CGFloat = 183
let crop = src.cropping(to: CGRect(x: srcCenter.x - srcRadius, y: srcCenter.y - srcRadius,
                                   width: srcRadius * 2, height: srcRadius * 2))!

let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.interpolationQuality = .high

// Circle on the standard macOS icon grid (824pt body, 100pt margin).
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.28))
ctx.addEllipse(in: body); ctx.setFillColor(.white); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addEllipse(in: body); ctx.clip()
ctx.draw(crop, in: body)
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
