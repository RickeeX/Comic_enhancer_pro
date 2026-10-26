import AppKit
import Foundation
import ImageIO

@main
struct IntegrationTests {
    static func pdfFixture(_ url: URL) throws {
        let content = "q 80 0 0 40 24 60 cm /Im1 Do Q\n1 0 0 rg 10 180 30 20 re f\n"
        let pixels: [UInt8] = [0,0,0, 255,255,255, 255,0,0, 0,255,0, 0,0,255, 120,120,120, 200,200,200, 255,255,255]
        var objects: [Data] = [
            Data("<< /Type /Catalog /Pages 2 0 R >>".utf8),
            Data("<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /MediaBox [0 0 144 216] /Resources << /XObject << /Im1 6 0 R >> >> >>".utf8),
            Data("<< /Type /Page /Parent 2 0 R /Contents 5 0 R >>".utf8),
            Data("<< /Type /Page /Parent 2 0 R /Rotate 90 /Contents 5 0 R >>".utf8),
            Data("<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream".utf8)
        ]
        var image = Data("<< /Type /XObject /Subtype /Image /Width 4 /Height 2 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length 24 >>\nstream\n".utf8)
        image.append(contentsOf: pixels); image.append(Data("\nendstream".utf8)); objects.append(image)
        var pdf = Data("%PDF-1.4\n".utf8), offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.count); pdf.append(Data("\(index + 1) 0 obj\n".utf8)); pdf.append(object); pdf.append(Data("\nendobj\n".utf8))
        }
        let xref = pdf.count
        pdf.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
        for offset in offsets.dropFirst() { pdf.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
        pdf.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        try pdf.write(to: url)
    }
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
        for mode in [1, 2, 3] {
            var advanced = Settings()
            advanced.binarization = mode; advanced.threshold = 100; advanced.cleanup = 1
            advanced.adaptiveRadius = 12; advanced.sauvolaK = 0.22
            advanced.deskew = 1; advanced.angle = 0.5
            advanced.blurMethod = 2; advanced.blur = 0.2; advanced.sharpenMethod = 1; advanced.sharpen = 0.3
            let output = try Processor.render(source, settings: advanced, preview: false).enhanced
            let pixels = output.dataProvider!.data! as Data
            for i in stride(from: 0, to: pixels.count, by: 4) {
                precondition(pixels[i] == 0 || pixels[i] == 255)
                precondition(pixels[i] == pixels[i+1] && pixels[i] == pixels[i+2])
            }
            for format in ["png", "tiff"] {
                advanced.format = format
                let url = folder.appendingPathComponent("binary-\(mode).\(format)")
                try Processor.write(output, to: url, settings: advanced)
                let decoded = try Processor.render(url, settings: Settings(), preview: false).enhanced
                precondition(decoded.width == 120 && decoded.height == 80)
                let values = decoded.dataProvider!.data! as Data
                precondition(values == pixels, "Lossless binary export changed pixels")
                let encoded = CGImageSourceCreateWithURL(url as CFURL, nil)!
                let props = CGImageSourceCopyPropertiesAtIndex(encoded, 0, nil)! as NSDictionary
                precondition((props[kCGImagePropertyDepth] as? NSNumber)?.intValue == 1, "Expected real 1-bit encoding")
            }
            let encoded = try JSONEncoder().encode(advanced)
            let loaded = try JSONDecoder().decode(Settings.self, from: encoded).validated()
            precondition(loaded == advanced)
        }
        let legacy = Data("{\"brightness\":0.1,\"levels\":16}".utf8)
        let migrated = try JSONDecoder().decode(Settings.self, from: legacy).validated()
        precondition(migrated.brightness == 0.1 && migrated.levels == 16 && migrated.binarization == 0 && migrated.filterRadius == 1)
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
        let pdfURL = folder.appendingPathComponent("book.pdf")
        try pdfFixture(pdfURL)
        let pages = try PDFLoader.items(pdfURL, embedded: false, dpi: 144)
        precondition(pages.count == 2 && pages[0].pdfPage == 1 && pages[1].pdfPage == 2)
        let pageOne = try Processor.render(pages[0], settings: Settings(), preview: false)
        let pageTwo = try Processor.render(pages[1], settings: Settings(), preview: false)
        precondition(pageOne.original.width == 288 && pageOne.original.height == 432)
        precondition(pageTwo.original.width == 432 && pageTwo.original.height == 288, "PDF page rotation ignored")
        let extracted = try PDFLoader.items(pdfURL, embedded: true, dpi: 200)
        precondition(extracted.count == 2, "Inherited PDF resources not found")
        let embedded = try Processor.render(extracted[0], settings: Settings(), preview: false)
        precondition(embedded.original.width == 4 && embedded.original.height == 2, "Embedded image was rasterized at PDF DPI")
        let embeddedBytes = embedded.enhanced.dataProvider!.data! as Data
        precondition(embeddedBytes[0] == 0 && embeddedBytes[4] == 255, "Raw RGB extraction changed image data")
        let cached = try Processor.render(pages[0], settings: Settings(), preview: true)
        precondition(cached.original.width == 288)
        var changed = Settings(); changed.brightness = 0.25
        let reused = try Processor.render(pages[0], settings: changed, preview: true)
        precondition(cached.original === reused.original, "Preview source was decoded again for a settings change")
        precondition(reused.enhanced.dataProvider!.data! as Data != cached.enhanced.dataProvider!.data! as Data)
        do { _ = try PDFLoader.items(pdfURL, embedded: false, dpi: 0); fatalError("Invalid PDF DPI accepted") }
        catch is ProcessingError { }
        do { _ = try PDFLoader.image(PageItem(url: pdfURL, pdfPage: 999), preview: false); fatalError("Invalid PDF page accepted") }
        catch is ProcessingError { }
        print("PASS: macOS ImageIO decode, transform, PNG/JPEG/TIFF round trips, presets, malformed input, 1-bit PNG/TIFF, advanced algorithms, legacy migration, PDF rendering/extraction/rotation and source cache")
    }
}
