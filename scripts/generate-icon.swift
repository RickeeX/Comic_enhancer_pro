import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
func paint(_ size: Int, to url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.imageInterpolation = .high
    let base = NSBezierPath(roundedRect: NSRect(x: 28, y: 28, width: 968, height: 968), xRadius: 220, yRadius: 220)
    NSGradient(starting: NSColor(srgbRed: 0.04, green: 0.25, blue: 0.27, alpha: 1),
               ending: NSColor(srgbRed: 0.12, green: 0.61, blue: 0.56, alpha: 1))!.draw(in: base, angle: 55)
    NSColor.white.withAlphaComponent(0.05).setFill()
    NSBezierPath(ovalIn: NSRect(x: 300, y: 420, width: 650, height: 650)).fill()
    let left = NSBezierPath()
    left.move(to: NSPoint(x: 205, y: 292)); left.line(to: NSPoint(x: 205, y: 724))
    left.curve(to: NSPoint(x: 507, y: 690), controlPoint1: NSPoint(x: 310, y: 780), controlPoint2: NSPoint(x: 422, y: 760))
    left.line(to: NSPoint(x: 507, y: 254))
    left.curve(to: NSPoint(x: 205, y: 292), controlPoint1: NSPoint(x: 412, y: 319), controlPoint2: NSPoint(x: 308, y: 334))
    left.close()
    let right = NSBezierPath()
    right.move(to: NSPoint(x: 517, y: 254)); right.line(to: NSPoint(x: 517, y: 690))
    right.curve(to: NSPoint(x: 819, y: 724), controlPoint1: NSPoint(x: 615, y: 760), controlPoint2: NSPoint(x: 724, y: 780))
    right.line(to: NSPoint(x: 819, y: 292))
    right.curve(to: NSPoint(x: 517, y: 254), controlPoint1: NSPoint(x: 718, y: 334), controlPoint2: NSPoint(x: 610, y: 319)); right.close()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.2); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -14); shadow.set()
    NSColor(srgbRed: 1, green: 0.98, blue: 0.91, alpha: 1).setFill(); left.fill()
    NSColor(srgbRed: 0.89, green: 0.97, blue: 0.93, alpha: 1).setFill(); right.fill()
    NSGraphicsContext.restoreGraphicsState()
    for y in [590, 510, 430] {
        let line = NSBezierPath(); line.move(to: NSPoint(x: 270, y: y + 30)); line.curve(to: NSPoint(x: 445, y: y), controlPoint1: NSPoint(x: 330, y: y + 45), controlPoint2: NSPoint(x: 395, y: y + 35))
        line.lineWidth = 16; line.lineCapStyle = .round; NSColor(srgbRed: 0.4, green: 0.66, blue: 0.59, alpha: 0.5).setStroke(); line.stroke()
    }
    let mark = NSBezierPath(); mark.move(to: NSPoint(x: 633, y: 733)); mark.line(to: NSPoint(x: 633, y: 545)); mark.line(to: NSPoint(x: 674, y: 579)); mark.line(to: NSPoint(x: 715, y: 559)); mark.line(to: NSPoint(x: 715, y: 755)); mark.close()
    NSColor(srgbRed: 0.94, green: 0.66, blue: 0.27, alpha: 1).setFill(); mark.fill()
    let sparkle = NSBezierPath()
    sparkle.move(to: NSPoint(x: 794, y: 884)); sparkle.line(to: NSPoint(x: 815, y: 829)); sparkle.line(to: NSPoint(x: 870, y: 808)); sparkle.line(to: NSPoint(x: 815, y: 787)); sparkle.line(to: NSPoint(x: 794, y: 732)); sparkle.line(to: NSPoint(x: 773, y: 787)); sparkle.line(to: NSPoint(x: 718, y: 808)); sparkle.line(to: NSPoint(x: 773, y: 829)); sparkle.close()
    NSColor(srgbRed: 1, green: 0.88, blue: 0.57, alpha: 1).setFill(); sparkle.fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
for size in [16, 32, 128, 256, 512] {
    try paint(size, to: destination.appendingPathComponent("icon_\(size)x\(size).png"))
    try paint(size * 2, to: destination.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
