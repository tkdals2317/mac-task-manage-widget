// 앱 아이콘 렌더러: swift scripts/make-icon.swift  →  Resources/AppIcon.icns
import AppKit

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: a)
}
let cs = CGColorSpaceCreateDeviceRGB()
func grad(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}
func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }

func star(_ c: CGPoint, _ R: CGFloat, _ r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let k = 2 * (r / 2.0.squareRoot() - R / 4)  // quad control offset so the waist sits at radius r
    let tips = [CGPoint(x: 0, y: -R), CGPoint(x: R, y: 0), CGPoint(x: 0, y: R), CGPoint(x: -R, y: 0)]
    let ctrl = [CGPoint(x: k, y: -k), CGPoint(x: k, y: k), CGPoint(x: -k, y: k), CGPoint(x: -k, y: -k)]
    p.move(to: CGPoint(x: c.x + tips[0].x, y: c.y + tips[0].y))
    for i in 0..<4 {
        let t = tips[(i + 1) % 4]
        p.addQuadCurve(to: CGPoint(x: c.x + t.x, y: c.y + t.y), control: CGPoint(x: c.x + ctrl[i].x, y: c.y + ctrl[i].y))
    }
    p.closeSubpath()
    return p
}

func drawStar(_ g: CGContext, _ c: CGPoint, _ R: CGFloat, _ r: CGFloat, _ s: CGFloat) {
    let path = star(c, R, r)
    g.saveGState()  // glow
    g.setShadow(offset: .zero, blur: 30 * s, color: rgb(0xFDBA74, 0.45))
    g.setFillColor(rgb(0xFDBA74, 0.45)); g.addPath(path); g.fillPath()
    g.restoreGState()
    g.saveGState()
    g.addPath(path); g.clip()
    g.drawRadialGradient(grad([(0, rgb(0xFDBA74)), (1, rgb(0xF97316))]), startCenter: c, startRadius: 0,
                         endCenter: c, endRadius: R, options: [.drawsAfterEndLocation])
    g.restoreGState()
}

func draw(_ g: CGContext, px: Int) {
    let s = CGFloat(px) / 1024
    let small = px <= 32
    g.translateBy(x: 0, y: CGFloat(px)); g.scaleBy(x: s, y: -s)  // top-left origin, 1024 canvas
    // shadow offsets are in device space (y up) and unscaled by CTM
    let body = rr(CGRect(x: 100, y: 100, width: 824, height: 824), 185)

    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: rgb(0x000000, 0.30))
    g.setFillColor(rgb(0x4F46E5)); g.addPath(body); g.fillPath()
    g.restoreGState()

    g.saveGState()
    g.addPath(body); g.clip()
    g.drawLinearGradient(grad([(0, rgb(0x4F46E5)), (0.55, rgb(0x7C3AED)), (1, rgb(0xA855F7))]),
                         start: CGPoint(x: 100, y: 100), end: CGPoint(x: 924, y: 924), options: [])
    g.drawLinearGradient(grad([(0, rgb(0xFFFFFF, 0.14)), (1, rgb(0xFFFFFF, 0))]),
                         start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 100 + 824 * 0.45), options: [])
    g.restoreGState()

    // card
    g.saveGState()
    g.translateBy(x: 500, y: 540); g.rotate(by: -6 * .pi / 180); g.translateBy(x: -260, y: -280)
    let card = rr(CGRect(x: 0, y: 0, width: 520, height: 560), 64)
    g.saveGState()
    if !small { g.setShadow(offset: CGSize(width: 0, height: -18 * s), blur: 40 * s, color: rgb(0x000000, 0.28)) }
    g.setFillColor(rgb(0xFFFFFF)); g.addPath(card); g.fillPath()
    g.restoreGState()
    g.saveGState()
    g.addPath(card); g.clip()
    g.drawLinearGradient(grad([(0, rgb(0xFFFFFF)), (1, rgb(0xF3F4F6))]), start: .zero, end: CGPoint(x: 0, y: 560), options: [])
    g.restoreGState()

    let widths: [CGFloat] = [260, 200, 240]
    for (i, cy) in [CGFloat(130), 270, 410].enumerated() {
        let box = CGRect(x: 70, y: cy - 42, width: 84, height: 84)
        let done = i < 2
        if done {
            g.setFillColor(rgb(0x22C55E)); g.addPath(rr(box, 22)); g.fillPath()
            g.setStrokeColor(rgb(0xFFFFFF)); g.setLineWidth(14); g.setLineCap(.round); g.setLineJoin(.round)
            g.move(to: CGPoint(x: 90, y: cy + 2)); g.addLine(to: CGPoint(x: 106, y: cy + 18)); g.addLine(to: CGPoint(x: 134, y: cy - 16))
            g.strokePath()
        } else {
            g.setStrokeColor(rgb(0xD1D5DB)); g.setLineWidth(8); g.addPath(rr(box.insetBy(dx: 4, dy: 4), 18)); g.strokePath()
        }
        g.setFillColor(rgb(done ? 0xE5E7EB : 0xCBD5E1))
        g.addPath(rr(CGRect(x: 190, y: cy - 15, width: widths[i], height: 30), 15)); g.fillPath()
    }
    g.restoreGState()

    drawStar(g, CGPoint(x: 760, y: 250), 92, 18, s)
    if !small { drawStar(g, CGPoint(x: 842, y: 360), 38, 8, s) }
}

func render(_ px: Int) -> CGImage {
    let g = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    g.setAllowsAntialiasing(true); g.interpolationQuality = .high
    draw(g, px: px)
    return g.makeImage()!
}
func save(_ img: CGImage, _ path: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); precondition(CGImageDestinationFinalize(d), "write \(path)")
}

let fm = FileManager.default
let set = "build/icon/AppIcon.iconset"
try? fm.removeItem(atPath: set)
try fm.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    save(render(base), "\(set)/icon_\(base)x\(base).png")
    save(render(base * 2), "\(set)/icon_\(base)x\(base)@2x.png")
}
save(render(1024), "build/icon/preview-1024.png")
try fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set, "-o", "Resources/AppIcon.icns"]
try p.run(); p.waitUntilExit()
precondition(p.terminationStatus == 0, "iconutil failed")
print("wrote Resources/AppIcon.icns")
