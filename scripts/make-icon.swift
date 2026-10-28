// Draws the GitSpect app icon: a single bold branch glyph on a plain tile.
// Usage: swift scripts/make-icon.swift <output.png> [light|blue|dark|sheet]
// "sheet" renders every style side by side for comparison.
import AppKit

struct Style {
    let tile: [UInt32]
    let glyph: [UInt32]
    let accent: [UInt32]
    let bevel: CGFloat
}

let styles: [String: Style] = [
    "light": Style(tile: [0xFFFFFF, 0xE4E4EA], glyph: [0x3A3A3C, 0x1C1C1E], accent: [0x2E8BFF, 0x0A6CF0], bevel: 0.9),
    "blue": Style(tile: [0x3D9BFF, 0x0A5BE0], glyph: [0xFFFFFF, 0xEAF2FF], accent: [0xFFFFFF, 0xEAF2FF], bevel: 0.35),
    "dark": Style(tile: [0x3A3A3E, 0x161618], glyph: [0xFFFFFF, 0xD1D1D6], accent: [0xFFB340, 0xFF8A00], bevel: 0.22),
]
let order = ["light", "blue", "dark"]

let args = CommandLine.arguments.dropFirst()
let output = args.first ?? "icon.png"
let choice = args.dropFirst().first ?? "dark"
let names = choice == "sheet" ? order : [choice]

let size: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size) * names.count, height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Fills `path` with a top-to-bottom gradient spanning `rect`.
func fill(_ path: CGPath, _ colors: [CGColor], over rect: CGRect) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func circle(_ center: CGPoint, _ radius: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
           transform: nil)
}

func draw(_ style: Style) {
    // macOS icon grid: an 824pt rounded square centred on the 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.3))
    ctx.addPath(tilePath)
    ctx.setFillColor(rgb(style.tile[1]))
    ctx.fillPath()
    ctx.restoreGState()
    fill(tilePath, style.tile.map { rgb($0) }, over: tile)

    // Hairline bevel: bright along the top edge, gone by the middle.
    let bevel = tilePath.copy(strokingWithWidth: 4, lineCap: .butt, lineJoin: .round, miterLimit: 10)
    fill(bevel, [rgb(0xFFFFFF, style.bevel), rgb(0xFFFFFF, 0), rgb(0xFFFFFF, 0)], over: tile)

    // Glyph: a trunk with one branch forking off, uniform weight like an SF Symbol.
    let weight: CGFloat = 50, node: CGFloat = 62
    let base = CGPoint(x: 410, y: 320), head = CGPoint(x: 410, y: 704), tip = CGPoint(x: 630, y: 640)
    let lines = CGMutablePath()
    lines.move(to: base)
    lines.addLine(to: head)
    lines.move(to: CGPoint(x: base.x, y: base.y + 90))
    lines.addCurve(to: tip, control1: CGPoint(x: base.x, y: 560), control2: CGPoint(x: tip.x, y: 470))
    // Filled one by one: overlapping subpaths in a single path cancel out where they cross.
    let parts = [
        lines.copy(strokingWithWidth: weight, lineCap: .round, lineJoin: .round, miterLimit: 10),
        circle(base, node),
        circle(head, node),
    ]

    let glyphRect = CGRect(x: 340, y: 250, width: 360, height: 520)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: rgb(0x000000, 0.18))
    // A transparency layer so the overlapping strokes and nodes cast one shadow.
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    for part in parts { fill(part, style.glyph.map { rgb($0) }, over: glyphRect) }
    fill(circle(tip, node), style.accent.map { rgb($0) }, over: glyphRect)
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

for (index, name) in names.enumerated() {
    ctx.saveGState()
    ctx.translateBy(x: CGFloat(index) * size, y: 0)
    draw(styles[name]!)
    ctx.restoreGState()
}

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
