import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate_app_icon.swift <output.iconset>\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: outputURL)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let icons: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for icon in icons {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: icon.pixels,
        pixelsHigh: icon.pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: icon.pixels, height: icon.pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(icon.pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to render \(icon.name)\n", stderr)
        exit(1)
    }
    try data.write(to: outputURL.appendingPathComponent(icon.name), options: .atomic)
}

private func drawIcon(size: CGFloat) {
    let fullRect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    fullRect.fill()

    let inset = size * 0.055
    let backgroundRect = fullRect.insetBy(dx: inset, dy: inset)
    let background = NSBezierPath(
        roundedRect: backgroundRect,
        xRadius: size * 0.22,
        yRadius: size * 0.22
    )
    NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.22, alpha: 1).setFill()
    background.fill()

    let topGlow = NSBezierPath(ovalIn: NSRect(
        x: size * 0.1,
        y: size * 0.52,
        width: size * 0.8,
        height: size * 0.46
    ))
    NSColor(calibratedRed: 0.16, green: 0.27, blue: 0.48, alpha: 0.75).setFill()
    topGlow.fill()

    let tigerRect = NSRect(x: size * 0.13, y: size * 0.1, width: size * 0.74, height: size * 0.78)
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: tigerRect.minX, yBy: tigerRect.minY)
    transform.scaleX(by: tigerRect.width / 22, yBy: tigerRect.height / 22)
    transform.concat()
    drawTigerHead()
    NSGraphicsContext.restoreGraphicsState()
}

private func drawTigerHead() {
    let orange = NSColor(calibratedRed: 1.0, green: 0.57, blue: 0.12, alpha: 1)
    let darkOrange = NSColor(calibratedRed: 0.75, green: 0.28, blue: 0.03, alpha: 1)
    let black = NSColor(calibratedWhite: 0.06, alpha: 1)
    let cream = NSColor(calibratedRed: 1.0, green: 0.9, blue: 0.66, alpha: 1)
    let pink = NSColor(calibratedRed: 1.0, green: 0.67, blue: 0.5, alpha: 1)

    drawEar(points: [NSPoint(x: 5.2, y: 13.6), NSPoint(x: 6.8, y: 20), NSPoint(x: 10.2, y: 15.4)], fill: orange, stroke: darkOrange)
    drawEar(points: [NSPoint(x: 11.8, y: 15.4), NSPoint(x: 15.2, y: 20), NSPoint(x: 16.8, y: 13.6)], fill: orange, stroke: darkOrange)
    drawEar(points: [NSPoint(x: 6.5, y: 14.7), NSPoint(x: 7.2, y: 17.7), NSPoint(x: 8.8, y: 15.5)], fill: pink, stroke: nil)
    drawEar(points: [NSPoint(x: 13.2, y: 15.5), NSPoint(x: 14.8, y: 17.7), NSPoint(x: 15.5, y: 14.7)], fill: pink, stroke: nil)

    let face = NSBezierPath(ovalIn: NSRect(x: 3.6, y: 3, width: 14.8, height: 15.8))
    orange.setFill()
    face.fill()
    darkOrange.setStroke()
    face.lineWidth = 0.7
    face.stroke()

    drawStripe(from: NSPoint(x: 11, y: 17.7), to: NSPoint(x: 11, y: 13.4), color: black, width: 1.3)
    drawStripe(from: NSPoint(x: 8.2, y: 16.1), to: NSPoint(x: 9.7, y: 13.3), color: black, width: 1.1)
    drawStripe(from: NSPoint(x: 13.8, y: 16.1), to: NSPoint(x: 12.3, y: 13.3), color: black, width: 1.1)
    drawStripe(from: NSPoint(x: 4.4, y: 11.8), to: NSPoint(x: 7.6, y: 10.8), color: black, width: 1.1)
    drawStripe(from: NSPoint(x: 17.6, y: 11.8), to: NSPoint(x: 14.4, y: 10.8), color: black, width: 1.1)

    let muzzle = NSBezierPath(ovalIn: NSRect(x: 7.3, y: 5.1, width: 7.4, height: 5.5))
    cream.setFill()
    muzzle.fill()

    black.setFill()
    NSBezierPath(ovalIn: NSRect(x: 7.4, y: 10.9, width: 1.8, height: 2.2)).fill()
    NSBezierPath(ovalIn: NSRect(x: 12.8, y: 10.9, width: 1.8, height: 2.2)).fill()
    NSBezierPath(ovalIn: NSRect(x: 10.1, y: 7.5, width: 1.8, height: 1.2)).fill()
    drawStripe(from: NSPoint(x: 11, y: 7.4), to: NSPoint(x: 11, y: 6.2), color: black, width: 0.7)
}

private func drawEar(points: [NSPoint], fill: NSColor, stroke: NSColor?) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: first)
    for point in points.dropFirst() {
        path.line(to: point)
    }
    path.close()
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = 0.55
        path.stroke()
    }
}

private func drawStripe(from start: NSPoint, to end: NSPoint, color: NSColor, width: CGFloat) {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    path.lineWidth = width
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
}
