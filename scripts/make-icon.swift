// Draws the GitSpect app icon: a fine loupe over a git branch, on a graphite tile.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon.png"

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}

/// Fills `path` with a vertical gradient spanning `rect`.
func fill(_ path: CGPath, _ colors: [CGColor], over rect: CGRect) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient(colors), start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
}

// macOS icon grid: an 824pt rounded square centred on the 1024 canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.4))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0x1C1C1E))
ctx.fillPath()
ctx.restoreGState()

// Graphite tile with a faint glow behind the glyph.
fill(tilePath, [rgb(0x3A3A3E), rgb(0x161618)], over: tile)
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let glowCenter = CGPoint(x: 490, y: 560)
ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.07), rgb(0xFFFFFF, 0)]),
                       startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: 360, options: [])
ctx.restoreGState()

// Hairline bevel: bright at the top edge, fading out by the middle.
let bevel = tilePath.copy(strokingWithWidth: 4, lineCap: .butt, lineJoin: .round, miterLimit: 10)
fill(bevel, [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0.0), rgb(0xFFFFFF, 0.0)], over: tile)

// Glyph: one silver shape built from strokes.
let lensCenter = CGPoint(x: 480, y: 560)
let lensRadius: CGFloat = 215
let glyph = CGMutablePath()
func stroke(_ path: CGPath, width: CGFloat) {
    glyph.addPath(path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10))
}

let ring = CGPath(ellipseIn: circle(lensCenter, lensRadius), transform: nil)
stroke(ring, width: 24)

let diagonal = CGFloat(0.5).squareRoot()
let handle = CGMutablePath()
handle.move(to: CGPoint(x: lensCenter.x + (lensRadius + 34) * diagonal, y: lensCenter.y - (lensRadius + 34) * diagonal))
handle.addLine(to: CGPoint(x: 768, y: 272))
stroke(handle, width: 46)

// Branch: a trunk with one commit forking off to the right.
let nodeRadius: CGFloat = 26
let top = CGPoint(x: 420, y: 670), bottom = CGPoint(x: 420, y: 450), tip = CGPoint(x: 560, y: 620)
let lines = CGMutablePath()
lines.move(to: CGPoint(x: top.x, y: top.y - nodeRadius))
lines.addLine(to: CGPoint(x: bottom.x, y: bottom.y + nodeRadius))
lines.move(to: CGPoint(x: bottom.x, y: bottom.y + nodeRadius + 30))
lines.addCurve(to: CGPoint(x: tip.x, y: tip.y - nodeRadius),
               control1: CGPoint(x: bottom.x, y: 560), control2: CGPoint(x: tip.x, y: 520))
stroke(lines, width: 16)
for point in [top, bottom] {
    stroke(CGPath(ellipseIn: circle(point, nodeRadius), transform: nil), width: 16)
}

let glyphBounds = circle(lensCenter, lensRadius + 40)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: rgb(0x000000, 0.45))
fill(glyph, [rgb(0xFFFFFF), rgb(0xC9CAD1)], over: glyphBounds)
ctx.restoreGState()

// The single accent: the new commit on the branch.
let accent = CGPath(ellipseIn: circle(tip, nodeRadius + 4), transform: nil)
fill(accent, [rgb(0xFFB340), rgb(0xFF8A00)], over: circle(tip, nodeRadius + 4))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
