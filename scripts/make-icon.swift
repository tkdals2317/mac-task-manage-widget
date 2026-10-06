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

/// 4각 반짝이. inner/outer = 중심/끝 색(nil outer면 단색), glow = 글로우 색
func sparkle(_ g: CGContext, _ c: CGPoint, _ R: CGFloat, _ s: CGFloat, small: Bool, inner: CGColor, outer: CGColor, glow: CGColor) {
    let path = star(c, R, R * 0.2)
    if !small {
        g.saveGState()
        g.setShadow(offset: .zero, blur: 30 * s, color: glow)
        g.setFillColor(glow); g.addPath(path); g.fillPath()
        g.restoreGState()
    }
    g.saveGState()
    g.addPath(path); g.clip()
    g.drawRadialGradient(grad([(0, inner), (1, outer)]), startCenter: c, startRadius: 0,
                         endCenter: c, endRadius: R, options: [.drawsAfterEndLocation])
    g.restoreGState()
}

func checkbox(_ g: CGContext, _ box: CGRect, done: Bool, fill: UInt32, mark: UInt32, empty: UInt32) {
    let w = box.width, cy = box.midY
    if done {
        g.setFillColor(rgb(fill)); g.addPath(rr(box, w * 0.26)); g.fillPath()
        g.setStrokeColor(rgb(mark)); g.setLineWidth(w * 0.167); g.setLineCap(.round); g.setLineJoin(.round)
        g.move(to: CGPoint(x: box.minX + w * 0.238, y: cy + w * 0.024))
        g.addLine(to: CGPoint(x: box.minX + w * 0.43, y: cy + w * 0.214))
        g.addLine(to: CGPoint(x: box.minX + w * 0.76, y: cy - w * 0.19))
        g.strokePath()
    } else {
        g.setStrokeColor(rgb(empty)); g.setLineWidth(w * 0.095)
        g.addPath(rr(box.insetBy(dx: w * 0.048, dy: w * 0.048), w * 0.21)); g.strokePath()
    }
}
func bar(_ g: CGContext, _ x: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ col: CGColor) {
    g.setFillColor(col); g.addPath(rr(CGRect(x: x, y: cy - h / 2, width: w, height: h), h / 2)); g.fillPath()
}
/// 중심 (cx,cy) 기준 회전된 좌표계 안에서 그리기 (deg: 화면상 시계방향 +)
func rotated(_ g: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ deg: CGFloat, _ body: () -> Void) {
    g.saveGState()
    g.translateBy(x: cx, y: cy); g.rotate(by: deg * .pi / 180)
    body()
    g.restoreGState()
}
func shadowed(_ g: CGContext, _ s: CGFloat, small: Bool, dy: CGFloat, blur: CGFloat, _ col: CGColor, _ body: () -> Void) {
    g.saveGState()
    if !small { g.setShadow(offset: CGSize(width: 0, height: -dy * s), blur: blur * s, color: col) }
    body()
    g.restoreGState()
}

func draw(_ g: CGContext, px: Int) {
    let s = CGFloat(px) / 1024
    let small = px <= 32
    g.translateBy(x: 0, y: CGFloat(px)); g.scaleBy(x: s, y: -s)
    let body = rr(CGRect(x: 100, y: 100, width: 824, height: 824), 185)
    let top = CGPoint(x: 0, y: 100), bot = CGPoint(x: 0, y: 924)

    shadowed(g, s, small: small, dy: 12, blur: 28, rgb(0, 0.30)) {
        g.setFillColor(rgb(0x1F2937)); g.addPath(body); g.fillPath()
    }
    g.saveGState()
    g.addPath(body); g.clip()
    g.drawLinearGradient(grad([(0, rgb(0x1F2937)), (1, rgb(0x111827))]), start: top, end: bot, options: [])
    g.drawLinearGradient(grad([(0, rgb(0xFFFFFF, 0.10)), (1, rgb(0xFFFFFF, 0))]), start: top,
                         end: CGPoint(x: 0, y: 100 + 824 * 0.4), options: [])
    g.restoreGState()

    let win = CGRect(x: 212, y: 300, width: 600, height: 520)
    shadowed(g, s, small: small, dy: 18, blur: 40, rgb(0, 0.45)) {
        g.setFillColor(rgb(0xFFFFFF, 0.92)); g.addPath(rr(win, 48)); g.fillPath()
    }
    g.setStrokeColor(rgb(0xFFFFFF, 0.40)); g.setLineWidth(3); g.addPath(rr(win, 48)); g.strokePath()
    for (i, col) in ([0xFF5F57, 0xFEBC2E, 0x28C840] as [UInt32]).enumerated() {
        g.setFillColor(rgb(col))
        g.fillEllipse(in: CGRect(x: win.minX + 40 + CGFloat(i) * 46, y: win.minY + 34, width: 30, height: 30))
    }
    let widths: [CGFloat] = [380, 300, 340]
    for (i, cy) in [CGFloat(480), 600, 720].enumerated() {
        let done = i < 2
        checkbox(g, CGRect(x: 262, y: cy - 36, width: 72, height: 72), done: done, fill: 0x22C55E, mark: 0xFFFFFF, empty: 0xD1D5DB)
        bar(g, 372, cy, widths[i], 28, rgb(done ? 0xD7DEE8 : 0xCBD5E1))
    }
    sparkle(g, CGPoint(x: 812, y: 300), 80, s, small: small, inner: rgb(0xFDBA74), outer: rgb(0xF97316), glow: rgb(0xF97316, 0.55))
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
