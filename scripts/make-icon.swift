// Draws the app icon with CoreGraphics and writes an .iconset directory.
//   swift scripts/make-icon.swift <out.iconset>
// scripts/make-icon.sh wraps this and runs iconutil to produce Support/AppIcon.icns.
// All geometry is in a 1024-pt canvas following the macOS icon grid
// (824-pt rounded square, 100-pt margin) and is scaled per output size.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let rgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: rgb, components: [r, g, b, a])!
}

func linearGradient(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: rgb, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [])
}

func drawIcon(_ ctx: CGContext) {
    // Background: blue rounded square.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: color(0, 0, 0, 0.3))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0.12, 0.30, 0.75))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    linearGradient(ctx, [color(0.26, 0.60, 1.00), color(0.10, 0.26, 0.68)],
                   from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))

    // Database cylinder: three stacked discs, drawn bottom-up so each one
    // hides the back half of the disc below and leaves a thin visible rim.
    let cx: CGFloat = 512, rx: CGFloat = 230, ry: CGFloat = 66
    let discHeight: CGFloat = 112, gap: CGFloat = 26
    let bottom: CGFloat = 290
    let body = [color(0.99, 1.00, 1.00), color(0.80, 0.87, 0.97)]

    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: color(0.02, 0.08, 0.25, 0.45))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    for i in 0..<3 {
        let yb = bottom + CGFloat(i) * (discHeight + gap)
        let yt = yb + discHeight
        let side = CGMutablePath()
        side.addEllipse(in: CGRect(x: cx - rx, y: yb - ry, width: 2 * rx, height: 2 * ry))
        side.addRect(CGRect(x: cx - rx, y: yb, width: 2 * rx, height: discHeight))
        ctx.saveGState()
        ctx.addPath(side)
        ctx.clip()
        // Horizontal gradient gives the side a rounded, lit-from-the-left look.
        linearGradient(ctx, body, from: CGPoint(x: cx - rx, y: 0), to: CGPoint(x: cx + rx, y: 0))
        ctx.restoreGState()

        let top = CGRect(x: cx - rx, y: yt - ry, width: 2 * rx, height: 2 * ry)
        ctx.addEllipse(in: top)
        ctx.setFillColor(color(0.90, 0.94, 1.00))
        ctx.fillPath()
    }
    ctx.endTransparencyLayer()

    // Top face: a small result grid, the "viewer" part.
    let topY = bottom + 2 * (discHeight + gap) + discHeight
    let face = CGRect(x: cx - rx, y: topY - ry, width: 2 * rx, height: 2 * ry)
    ctx.saveGState()
    ctx.addEllipse(in: face.insetBy(dx: 26, dy: 9))
    ctx.clip()
    ctx.setFillColor(color(0.78, 0.86, 0.98))
    ctx.fill(face)
    ctx.setStrokeColor(color(0.26, 0.55, 0.98, 0.55))
    ctx.setLineWidth(7)
    for dx in stride(from: -120 as CGFloat, through: 120, by: 80) {
        ctx.move(to: CGPoint(x: cx + dx, y: face.minY))
        ctx.addLine(to: CGPoint(x: cx + dx, y: face.maxY))
    }
    for dy in [-22 as CGFloat, 22] {
        ctx.move(to: CGPoint(x: face.minX, y: topY + dy))
        ctx.addLine(to: CGPoint(x: face.maxX, y: topY + dy))
    }
    ctx.strokePath()
    ctx.restoreGState()

    ctx.restoreGState()
}

func writePNG(pixels: Int, to url: URL) throws {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)
    drawIcon(ctx)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("uso: swift make-icon.swift <out.iconset>\n".utf8))
    exit(2)
}
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try writePNG(pixels: points, to: dir.appendingPathComponent("icon_\(points)x\(points).png"))
    try writePNG(pixels: points * 2, to: dir.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
