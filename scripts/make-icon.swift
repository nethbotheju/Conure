#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write("usage: make-icon <master.png> <output.icns>\n".data(using: .utf8)!)
    exit(1)
}

let masterURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let master = NSImage(contentsOf: masterURL) else {
    FileHandle.standardError.write("error: cannot read \(masterURL.path)\n".data(using: .utf8)!)
    exit(1)
}

func squirclePath(in rect: CGRect, n: Double = 5) -> CGPath {
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 240
    let path = CGMutablePath()
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = a * (ct < 0 ? -1.0 : 1.0) * pow(abs(ct), 2 / n)
        let y = b * (st < 0 ? -1.0 : 1.0) * pow(abs(st), 2 / n)
        let p = CGPoint(x: cx + x, y: cy + y)
        i == 0 ? path.move(to: p) : path.addLine(to: p)
    }
    path.closeSubpath()
    return path
}

// sample edge colors from the master so any gap between its (rounder) corners
// and our squircle mask shows the artwork's own gradient, never white
func masterEdgeColors() -> (NSColor, NSColor) {
    guard let tiff = master.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return (.white, .black) }
    let w = rep.pixelsWide, h = rep.pixelsHigh
    func color(at x: Int, y: Int) -> NSColor? {
        guard x >= 0, x < w, y >= 0, y < h, let c = rep.colorAt(x: x, y: y) else { return nil }
        return c
    }
    let top = color(at: w / 2, y: min(h - 1, Int(Double(h) * 0.02))) ?? .white
    let bottom = color(at: w / 2, y: max(0, Int(Double(h) * 0.98))) ?? .black
    return (top.usingColorSpace(.deviceRGB) ?? .white, bottom.usingColorSpace(.deviceRGB) ?? .black)
}

func render(size: CGFloat, scale: CGFloat = 1) -> NSBitmapImageRep {
    let px = Int(size * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    // macOS template: the squircle occupies 824/1024 of the canvas, centered,
    // so the icon matches Apple's own Dock icons in apparent size
    let shapeSide = size * (824.0 / 1024.0)
    let shapeRect = CGRect(x: (size - shapeSide) / 2, y: (size - shapeSide) / 2,
                           width: shapeSide, height: shapeSide)
    let (topColor, bottomColor) = masterEdgeColors()
    let gradient = NSGradient(starting: topColor, ending: bottomColor)!
    ctx.cgContext.addPath(squirclePath(in: shapeRect))
    ctx.cgContext.clip()
    gradient.draw(in: shapeRect, angle: -90)
    master.draw(in: shapeRect.insetBy(dx: -0.02 * shapeSide, dy: -0.02 * shapeSide))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconsetDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Conure.iconset")
try? fm.removeItem(at: iconsetDir)
try! fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let entries: [(String, CGFloat, CGFloat)] = [
    ("icon_16x16.png", 16, 1), ("icon_16x16@2x.png", 16, 2),
    ("icon_32_32.png", 32, 1), ("icon_32_32@2x.png", 32, 2),
    ("icon_128_128.png", 128, 1), ("icon_128_128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1), ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1), ("icon_512x512@2x.png", 512, 2),
]
for (name, size, scale) in entries {
    let rep = render(size: size, scale: scale)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: iconsetDir.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", outputURL.path]
try! process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    FileHandle.standardError.write("error: iconutil failed\n".data(using: .utf8)!)
    exit(1)
}

let pngName = outputURL.deletingPathExtension().lastPathComponent == "AppIcon-Dev"
    ? "icon-dev.png" : "icon.png"
let pngURL = outputURL.deletingLastPathComponent().appendingPathComponent(pngName)
try! render(size: 1024).representation(using: .png, properties: [:])!.write(to: pngURL)
print("Done: \(outputURL.path)")
print("Done: \(pngURL.path)")
