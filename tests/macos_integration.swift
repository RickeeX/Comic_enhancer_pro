import AppKit
import Foundation

@main
struct IntegrationTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 480,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.75, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1)); ctx.fill(CGRect(x: 20, y: 20, width: 40, height: 30))
        let image = ctx.makeImage()!
        let source = folder.appendingPathComponent("source.png")
        try Processor.write(image, to: source, settings: Settings())
        let neutral = try Processor.render(source, settings: Settings(), preview: false)
        precondition(neutral.enhanced.width == 120 && neutral.enhanced.height == 80)
        let preview = try Processor.render(source, settings: Settings(), preview: true)
        precondition(preview.enhanced.width == 120)
        var settings = Settings()
        settings.rotation = 1; settings.page = 2; settings.scale = 0.5
        settings.autoLevels = true; settings.sharpen = 0.4; settings.grayscale = true; settings.levels = 8
        let rendered = try Processor.render(source, settings: settings, preview: false)
        precondition(rendered.enhanced.width == 40 && rendered.enhanced.height == 30)
        for format in ["png", "jpg", "tiff"] {
            settings.format = format
            let url = folder.appendingPathComponent("result.\(format)")
            try Processor.write(rendered.enhanced, to: url, settings: settings)
            let roundTrip = try Processor.render(url, settings: Settings(), preview: false)
            precondition(roundTrip.original.width == 40 && roundTrip.original.height == 30)
        }
        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(Settings.self, from: data).validated()
        precondition(restored == settings)
        var invalid = settings; invalid.scale = 99
        do { _ = try invalid.validated(); fatalError("Invalid preset accepted") }
        catch is ProcessingError { }
        let bad = folder.appendingPathComponent("broken.png")
        try Data([1,2,3]).write(to: bad)
        do { _ = try Processor.render(bad, settings: Settings(), preview: false); fatalError("Broken input accepted") }
        catch is ProcessingError { }
        print("PASS: macOS ImageIO decode, transform, PNG/JPEG/TIFF round trips, presets, malformed input")
    }
}
