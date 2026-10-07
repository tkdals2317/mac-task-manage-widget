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

func rounded(_ size: CGFloat, _ w: NSFont.Weight) -> CTFont {
    let f = NSFont.systemFont(ofSize: size, weight: w)
    return (NSFont(descriptor: f.fontDescriptor.withDesign(.rounded) ?? f.fontDescriptor, size: size) ?? f) as CTFont
}
func makeLine(_ str: String, _ font: CTFont, _ color: CGColor, _ kern: CGFloat) -> CTLine {
    let a: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color, kCTKernAttributeName: kern]
    return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, str as CFString, a as CFDictionary))
}
/// 글리프 경계 상자의 (hx, vy) 비율 지점(vy 0=위)이 p에 오도록 그린다. y-아래 좌표계 전제.
func drawText(_ g: CGContext, _ str: String, _ font: CTFont, _ color: CGColor, kern: CGFloat = 0,
              at p: CGPoint, hx: CGFloat = 0.5, vy: CGFloat = 0.5) {
    let line = makeLine(str, font, color, kern)
    let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    g.saveGState()
    g.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    g.textPosition = CGPoint(x: p.x - (b.minX + hx * b.width), y: p.y + b.maxY - vy * b.height)
    CTLineDraw(line, g)
    g.restoreGState()
}
func textWidth(_ str: String, _ font: CTFont) -> CGFloat {
    CTLineGetBoundsWithOptions(makeLine(str, font, rgb(0), 0), .useGlyphPathBounds).width
}

/// 위/아래 가장자리가 지그재그(찢김)인 영수증 경로
func receipt(_ x0: CGFloat, _ x1: CGFloat, _ top: CGFloat, _ bot: CGFloat, tornTop: Bool, tornBot: Bool, tw: CGFloat, th: CGFloat) -> CGPath {
    let n = 2 * max(1, Int((x1 - x0) / tw / 2 + 0.5)), step = (x1 - x0) / CGFloat(n)
    let p = CGMutablePath()
    if tornTop {
        p.move(to: CGPoint(x: x0, y: top + th))
        for i in 1...n { p.addLine(to: CGPoint(x: x0 + CGFloat(i) * step, y: top + (i % 2 == 0 ? th : 0))) }
    } else { p.move(to: CGPoint(x: x0, y: top)); p.addLine(to: CGPoint(x: x1, y: top)) }
    if tornBot {
        for i in stride(from: n, through: 0, by: -1) { p.addLine(to: CGPoint(x: x0 + CGFloat(i) * step, y: bot - (i % 2 == 0 ? th : 0))) }
    } else { p.addLine(to: CGPoint(x: x1, y: bot)); p.addLine(to: CGPoint(x: x0, y: bot)) }
    p.closeSubpath()
    return p
}
func check(_ g: CGContext, _ c: CGPoint, _ w: CGFloat, _ lw: CGFloat, _ col: CGColor) {
    g.setStrokeColor(col); g.setLineWidth(lw); g.setLineCap(.round); g.setLineJoin(.round)
    g.move(to: CGPoint(x: c.x - 0.45 * w, y: c.y + 0.02 * w))
    g.addLine(to: CGPoint(x: c.x - 0.12 * w, y: c.y + 0.34 * w))
    g.addLine(to: CGPoint(x: c.x + 0.5 * w, y: c.y - 0.36 * w))
    g.strokePath()
}
func dashed(_ g: CGContext, _ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, _ col: CGColor) {
    g.saveGState()
    g.setStrokeColor(col); g.setLineWidth(4); g.setLineDash(phase: 0, lengths: [14, 10])
    g.move(to: CGPoint(x: x0, y: y)); g.addLine(to: CGPoint(x: x1, y: y)); g.strokePath()
    g.restoreGState()
}
func fillGrad(_ g: CGContext, _ path: CGPath, _ stops: [(CGFloat, CGColor)], _ a: CGPoint, _ b: CGPoint) {
    g.saveGState(); g.addPath(path); g.clip()
    g.drawLinearGradient(grad(stops), start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    g.restoreGState()
}
func orangeSparkle(_ g: CGContext, _ c: CGPoint, _ R: CGFloat, _ s: CGFloat, _ small: Bool) {
    sparkle(g, c, R, s, small: small, inner: rgb(0xFDBA74), outer: rgb(0xF97316), glow: rgb(0xF97316, 0.55))
}

/// 컨셉 D: ATM 모노그램 (흰 워드마크 + 초록 체크 밑줄 + 주황 반짝이)
func content(_ g: CGContext, _ s: CGFloat, _ small: Bool) {
    let wm = rounded(260, .black)
    drawText(g, "ATM", wm, rgb(0xFFFFFF), kern: -4, at: CGPoint(x: 512, y: 470))
    g.setStrokeColor(rgb(0x22C55E)); g.setLineWidth(small ? 34 : 26); g.setLineCap(.round); g.setLineJoin(.round)
    g.move(to: CGPoint(x: 300, y: 700)); g.addLine(to: CGPoint(x: 640, y: 700))
    g.addLine(to: CGPoint(x: 690, y: 745)); g.addLine(to: CGPoint(x: 780, y: 640))
    g.strokePath()
    sparkle(g, CGPoint(x: 800, y: 330), small ? 90 : 70, s, small: small,
            inner: rgb(0xFDBA74), outer: rgb(0xF97316), glow: rgb(0xFDBA74, 0.45))
}

func draw(_ g: CGContext, px: Int) {
    let s = CGFloat(px) / 1024
    let small = px <= 32
    g.translateBy(x: 0, y: CGFloat(px)); g.scaleBy(x: s, y: -s)
    let body = rr(CGRect(x: 100, y: 100, width: 824, height: 824), 185)
    let stops = [(CGFloat(0), rgb(0x374151)), (1, rgb(0x111827))]
    shadowed(g, s, small: small, dy: 12, blur: 28, rgb(0, 0.30)) { g.setFillColor(stops[0].1); g.addPath(body); g.fillPath() }
    g.saveGState()
    g.addPath(body); g.clip()
    g.drawLinearGradient(grad(stops), start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    g.drawLinearGradient(grad([(0, rgb(0xFFFFFF, 0.08)), (1, rgb(0xFFFFFF, 0))]),
                         start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 100 + 824 * 0.4), options: [])
    content(g, s, small)
    g.restoreGState()
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
