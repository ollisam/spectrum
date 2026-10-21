import AppKit

/// An 8-bit sRGB color sampled from the screen.
struct RGB: Equatable, Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: UInt8((v >> 16) & 0xFF), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF))
    }

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    /// Relative luminance (0…1), used to pick contrasting outlines.
    var luminance: Double {
        func lin(_ c: UInt8) -> Double {
            let v = Double(c) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    var lab: Lab {
        func lin(_ c: UInt8) -> Double {
            let v = Double(c) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let R = lin(r), G = lin(g), B = lin(b)
        let x = (0.4124564 * R + 0.3575761 * G + 0.1804375 * B) / 0.95047
        let y = (0.2126729 * R + 0.7151522 * G + 0.0721750 * B) / 1.0
        let z = (0.0193339 * R + 0.1191920 * G + 0.9503041 * B) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : (7.787 * t + 16.0 / 116.0) }
        let fx = f(x), fy = f(y), fz = f(z)
        return Lab(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }
}

struct Lab {
    var l: Double
    var a: Double
    var b: Double

    /// CIEDE2000 perceptual color difference.
    func distance(to o: Lab) -> Double {
        let rad = Double.pi / 180
        let c1 = (a * a + b * b).squareRoot(), c2 = (o.a * o.a + o.b * o.b).squareRoot()
        let cBar7 = pow((c1 + c2) / 2, 7)
        let g = 0.5 * (1 - (cBar7 / (cBar7 + 6103515625)).squareRoot())
        let a1p = (1 + g) * a, a2p = (1 + g) * o.a
        let c1p = (a1p * a1p + b * b).squareRoot(), c2p = (a2p * a2p + o.b * o.b).squareRoot()

        func hue(_ y: Double, _ x: Double) -> Double {
            if x == 0 && y == 0 { return 0 }
            let h = atan2(y, x) / rad
            return h < 0 ? h + 360 : h
        }
        let h1p = hue(b, a1p), h2p = hue(o.b, a2p)

        let dLp = o.l - l
        let dCp = c2p - c1p
        var dhp = 0.0
        if c1p * c2p != 0 {
            dhp = h2p - h1p
            if dhp > 180 { dhp -= 360 } else if dhp < -180 { dhp += 360 }
        }
        let dHp = 2 * (c1p * c2p).squareRoot() * sin(dhp / 2 * rad)

        let lBarP = (l + o.l) / 2
        let cBarP = (c1p + c2p) / 2
        var hBarP = h1p + h2p
        if c1p * c2p != 0 {
            if abs(h1p - h2p) > 180 {
                hBarP = (h1p + h2p + (h1p + h2p < 360 ? 360 : -360)) / 2
            } else {
                hBarP = (h1p + h2p) / 2
            }
        }

        let t = 1 - 0.17 * cos((hBarP - 30) * rad) + 0.24 * cos(2 * hBarP * rad)
            + 0.32 * cos((3 * hBarP + 6) * rad) - 0.20 * cos((4 * hBarP - 63) * rad)
        let dTheta = 30 * exp(-pow((hBarP - 275) / 25, 2))
        let cBarP7 = pow(cBarP, 7)
        let rc = 2 * (cBarP7 / (cBarP7 + 6103515625)).squareRoot()
        let sl = 1 + 0.015 * pow(lBarP - 50, 2) / (20 + pow(lBarP - 50, 2)).squareRoot()
        let sc = 1 + 0.045 * cBarP
        let sh = 1 + 0.015 * cBarP * t
        let rt = -sin(2 * dTheta * rad) * rc

        let tl = dLp / sl, tc = dCp / sc, th = dHp / sh
        return (tl * tl + tc * tc + th * th + rt * tc * th).squareRoot()
    }
}

/// A square block of screen pixels centred on the sampled point.
struct PixelGrid {
    let radius: Int
    var pixels: [RGB?]

    static func empty(radius: Int) -> PixelGrid {
        let side = radius * 2 + 1
        return PixelGrid(radius: radius, pixels: Array(repeating: nil, count: side * side))
    }

    subscript(i: Int, j: Int) -> RGB? {
        get { pixels[(j + radius) * (radius * 2 + 1) + (i + radius)] }
        set { pixels[(j + radius) * (radius * 2 + 1) + (i + radius)] = newValue }
    }

    var center: RGB? { self[0, 0] }
}
