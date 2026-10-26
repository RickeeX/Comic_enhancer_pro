import AppKit
import Foundation
import ImageIO

@main
struct IntegrationTests {
    static func pdfFixture(_ url: URL, jpeg: Data? = nil, decode: String? = nil) throws {
        let content = "q 80 0 0 40 24 60 cm /Im1 Do Q\n1 0 0 rg 10 180 30 20 re f\n"
        let pixels: [UInt8] = [0,0,0, 255,255,255, 255,0,0, 0,255,0, 0,0,255, 120,120,120, 200,200,200, 255,255,255]
        var objects: [Data] = [
            Data("<< /Type /Catalog /Pages 2 0 R >>".utf8),
            Data("<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /MediaBox [0 0 144 216] /Resources << /XObject << /Im1 6 0 R >> >> >>".utf8),
            Data("<< /Type /Page /Parent 2 0 R /Contents 5 0 R >>".utf8),
            Data("<< /Type /Page /Parent 2 0 R /Rotate 90 /Contents 5 0 R >>".utf8),
            Data("<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream".utf8)
        ]
        let payload = jpeg ?? Data(pixels)
        let dimensions = (jpeg == nil ? "/Width 4 /Height 2" : "/Width 120 /Height 80 /Filter /DCTDecode") + (decode.map { " /Decode [\($0)]" } ?? "")
        var image = Data("<< /Type /XObject /Subtype /Image \(dimensions) /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length \(payload.count) >>\nstream\n".utf8)
        image.append(payload); image.append(Data("\nendstream".utf8)); objects.append(image)
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
        let raster = pageOne.enhanced.dataProvider!.data! as Data
        var redCount = 0, blackCount = 0
        for i in stride(from: 0, to: raster.count, by: 4) {
            if raster[i] > 200 && raster[i+1] < 50 && raster[i+2] < 50 { redCount += 1 }
            if raster[i] < 30 && raster[i+1] < 30 && raster[i+2] < 30 { blackCount += 1 }
        }
        precondition(redCount > 100 && blackCount > 100, "PDF vector content or image content was not drawn")
        precondition(pageTwo.original.width == 432 && pageTwo.original.height == 288, "PDF page rotation ignored")
        let extracted = try PDFLoader.items(pdfURL, embedded: true, dpi: 200)
        precondition(extracted.count == 2, "Inherited PDF resources not found")
        let embedded = try Processor.render(extracted[0], settings: Settings(), preview: false)
        precondition(embedded.original.width == 4 && embedded.original.height == 2, "Embedded image was rasterized at PDF DPI")
        let embeddedBytes = embedded.enhanced.dataProvider!.data! as Data
        precondition(embeddedBytes[0] == 0 && embeddedBytes[4] == 255, "Raw RGB extraction changed image data")
        var jpegSettings = Settings(); jpegSettings.format = "jpg"
        let jpegURL = folder.appendingPathComponent("embedded-source.jpg")
        try Processor.write(image, to: jpegURL, settings: jpegSettings)
        let jpegPDF = folder.appendingPathComponent("jpeg-book.pdf")
        try pdfFixture(jpegPDF, jpeg: Data(contentsOf: jpegURL))
        let jpegItems = try PDFLoader.items(jpegPDF, embedded: true, dpi: 300)
        let extractedJPEG = try Processor.render(jpegItems[0], settings: Settings(), preview: false)
        let originalJPEG = try Processor.render(jpegURL, settings: Settings(), preview: false)
        precondition(extractedJPEG.enhanced.width == 120 && extractedJPEG.enhanced.height == 80)
        precondition((extractedJPEG.enhanced.dataProvider!.data! as Data) == (originalJPEG.enhanced.dataProvider!.data! as Data), "DCT image stream extraction differs from JPEG decode")
        let invertedPDF = folder.appendingPathComponent("inverted-scan.pdf")
        try pdfFixture(invertedPDF,decode:"1 0 1 0 1 0")
        let invertedItems = try PDFLoader.items(invertedPDF,embedded:true,dpi:200)
        let invertedScan = try Processor.render(invertedItems[0],settings:Settings(),preview:false).enhanced
        let invertedData = invertedScan.dataProvider!.data! as Data
        precondition(invertedData[0] == 255 && invertedData[4] == 0,"PDF Decode inversion was not applied")
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
        // Ordered and repeated operations must be observably different.
        var sharpen = Stage(.sharpen); sharpen.settings.sharpen = 1.2
        var blur = Stage(.blur); blur.settings.blur = 0.7
        var tone = Stage(.tone); tone.settings.brightness = 0.12; tone.settings.gamma = 1.6
        let ordered = Recipe(stages: [tone, sharpen, blur, sharpen.duplicated()])
        let reordered = Recipe(stages: [sharpen, blur, tone, sharpen.duplicated()])
        let first = try Pipeline.render(PageItem(url: source), recipe: ordered, preview: false)
        let changedOrder = try Pipeline.render(PageItem(url: source), recipe: reordered, preview: false)
        precondition((first.image.dataProvider!.data! as Data) != (changedOrder.image.dataProvider!.data! as Data), "Operation order was ignored")
        let singleSharpen = try Pipeline.render(PageItem(url: source), recipe: Recipe(stages: [tone, sharpen, blur]), preview: false)
        precondition((first.image.dataProvider!.data! as Data) != (singleSharpen.image.dataProvider!.data! as Data), "Repeated operation was dropped")
        var binaryStage = Stage(.binary); binaryStage.settings.binarization = 2; binaryStage.settings.edgeSmooth = true
        let finalBinary = try Pipeline.render(PageItem(url: source), recipe: Recipe(stages: [tone, sharpen, blur, binaryStage]), preview: false)
        let binaryPixels = finalBinary.image.dataProvider!.data! as Data
        precondition(finalBinary.grayLevels == 2)
        for i in stride(from: 0, to: binaryPixels.count, by: 4) { precondition(binaryPixels[i] == 0 || binaryPixels[i] == 255) }
        let binaryThenBlur = try Pipeline.render(PageItem(url: source), recipe: Recipe(stages: [binaryStage, blur]), preview: false)
        precondition(binaryThenBlur.grayLevels == 0, "Postbinary filtering was incorrectly labeled bilevel")
        var pageStage = Stage(.resize); pageStage.settings.sourceDPI = 300; pageStage.settings.preservePhysical = true; pageStage.settings.targetDPI = 800
        var highDPIRecipe = Recipe(stages: [pageStage, blur, sharpen, binaryStage])
        let highDPI = try Pipeline.render(PageItem(url: source), recipe: highDPIRecipe, preview: false)
        precondition(highDPI.image.width == 320 && highDPI.image.height == 213)
        precondition(highDPI.dpiX == 800 && highDPI.dpiY == 800)
        precondition(abs(Double(highDPI.logicalWidth)/highDPI.dpiX - 120.0/300) < 1.0/800)
        for format in ["png", "tiff", "jpg"] {
            highDPIRecipe.format = format
            let out = folder.appendingPathComponent("density.\(format)")
            try Pipeline.write(highDPI, to: out, recipe: highDPIRecipe)
            let info = try Pipeline.sourceInfo(PageItem(url: out))
            precondition(abs((info.dpiX ?? 0)-800) < 1 && abs((info.dpiY ?? 0)-800) < 1, "Output DPI metadata lost")
        }
        let pdfInfo = try Pipeline.sourceInfo(extracted[0])
        precondition(abs((pdfInfo.dpiX ?? 0)-3.6) < 0.01 && abs((pdfInfo.dpiY ?? 0)-3.6) < 0.01, "Embedded PDF physical placement ignored")
        var pdfDPI = Stage(.resize); pdfDPI.settings.preservePhysical = true; pdfDPI.settings.targetDPI = 72
        let physicalPDF = try Pipeline.render(extracted[0], recipe: Recipe(stages: [pdfDPI]), preview: false)
        precondition(physicalPDF.logicalWidth == 80 && physicalPDF.logicalHeight == 40)
        let anisotropicInfo = try Pipeline.sourceInfo(jpegItems[0])
        precondition(abs((anisotropicInfo.dpiX ?? 0)-108) < 0.01 && abs((anisotropicInfo.dpiY ?? 0)-144) < 0.01)
        let normalizedPixelAspect = try Pipeline.render(jpegItems[0],recipe:Recipe(stages:[pdfDPI]),preview:false)
        precondition(normalizedPixelAspect.logicalWidth == 80 && normalizedPixelAspect.logicalHeight == 40,"Unequal PDF X/Y PPI ignored")
        let horizontal = try Pipeline.stitch(highDPI,highDPI,vertical:false,gap:5)
        let vertical = try Pipeline.stitch(highDPI,highDPI,vertical:true,gap:7)
        precondition(horizontal.image.width == 645 && horizontal.image.height == 213 && horizontal.grayLevels == 2)
        precondition(vertical.image.width == 320 && vertical.image.height == 433)
        let horizontalData = horizontal.image.dataProvider!.data! as Data
        precondition(horizontalData[(100*645+322)*4] == 255,"Stitch gap is not white")
        var normalize = Stage(.page); normalize.settings.sourceDPI = 300; normalize.settings.pageUnit = 1
        normalize.settings.pageMode = 3; normalize.settings.pageWidth = 200; normalize.settings.pageHeight = 300
        normalize.settings.marginLeft = 10; normalize.settings.marginRight = 20; normalize.settings.marginTop = 30; normalize.settings.marginBottom = 40
        var layouts: [Data] = []
        for fit in [0,1,2] {
            normalize.settings.fitMode = fit
            let result = try Pipeline.render(PageItem(url: source), recipe: Recipe(stages: [normalize]), preview: false)
            precondition(result.image.width == 200 && result.image.height == 300)
            let bytes = result.image.dataProvider!.data! as Data
            layouts.append(bytes)
            precondition(bytes[(150*200+5)*4] == 255 && bytes[(15*200+100)*4] == 255, "Fill/crop destroyed page margins")
        }
        precondition(layouts[0] != layouts[1] && layouts[1] != layouts[2], "Layout fit/fill/stretch modes ignored")
        var layoutCM = Stage(.layout); layoutCM.settings.pageMode = 3;layoutCM.settings.pageWidth = 2.54;layoutCM.settings.pageHeight = 5.08
        var resizeCM = pageStage;resizeCM.settings.targetDPI = 600
        let cmPage = try Pipeline.render(PageItem(url:source),recipe:Recipe(stages:[resizeCM,layoutCM]),preview:false)
        precondition(cmPage.logicalWidth == 600 && cmPage.logicalHeight == 1200 && cmPage.dpiX == 600,"Centimeter layout conversion is wrong")
        var cropStep = Stage(.crop);cropStep.settings.cropLeft = 0.25
        let cropPage = try Pipeline.render(PageItem(url:source),recipe:Recipe(stages:[cropStep]),preview:false)
        let uncropped = try Pipeline.rgba(Processor.sourceImage(PageItem(url:source),preview:false))
        let cropped = cropPage.image.dataProvider!.data! as Data
        precondition(cropPage.image.width == 90 && abs(Int(cropped[30*90*4])-Int(uncropped[(30*120+30)*4])) <= 1,"Cropped image provider offset is wrong")
        var rotateStep = Stage(.rotate);rotateStep.settings.rotation = 1
        let rotatedPage = try Pipeline.render(PageItem(url:source),recipe:Recipe(stages:[rotateStep]),preview:false)
        precondition(rotatedPage.logicalWidth == 80 && rotatedPage.logicalHeight == 120)
        let pageA = PageItem(url: source), pageB = PageItem(url: jpegURL), pageC = PageItem(url: bad)
        var book = RecipeBook(); var a = book.recipe(for: pageA); a.stages[1].settings.brightness = 0.2; book.values[pageA] = a
        precondition(book.recipe(for: pageB).stages[1].settings.brightness == 0, "Default pages share settings")
        try book.apply(a, indices: PageRanges.indices("0001 - 0002", count: 3), pages: [pageA,pageB,pageC])
        var b = book.recipe(for: pageB); b.stages[1].settings.gamma = 2; book.values[pageB] = b
        precondition(book.recipe(for: pageA).stages[1].settings.gamma == 1 && book.recipe(for: pageC).stages[1].settings.gamma == 1, "Applied recipes remained linked")
        let project = Project(pages: [pageA,pageB,pageC], recipes: book.values.map { Project.PageRecipe(page: $0.key, recipe: $0.value) })
        let savedProject = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project)).validated()
        precondition(savedProject.recipes.count == 3)
        do { _ = try PageRanges.indices("0000-9999", count: 3); fatalError("Invalid range accepted") } catch is ProcessingError { }
        precondition(Recipe.standard().stages.last?.kind == .binary)
        var names = Recipe.standard();names.nameStyle = 1;names.namePrefix = "book_";names.nameDigits = 5
        precondition(names.filename(index:12,page:pageA) == "book_00012.png")
        names.namePrefix = "../"
        do { _ = try names.validated();fatalError("Unsafe filename prefix accepted") } catch is ProcessingError { }
        var unsafeLegacy = Settings(); unsafeLegacy.cleanup = 3; unsafeLegacy.binarization = 2
        let migratedRecipe = try Recipe.legacy(unsafeLegacy)
        precondition(migratedRecipe.stages.allSatisfy { $0.settings.cleanup == 0 && !$0.settings.edgeSmooth }, "Unsafe legacy morphology re-enabled")
        _ = NSApplication.shared
        let scroll = PaperScroll(frame: NSRect(x: 0,y: 0,width: 500,height: 400))
        scroll.setPictures([NSImage(size: NSSize(width: 3000,height: 4000))]); scroll.layoutSubtreeIfNeeded(); scroll.command(.fit)
        precondition(scroll.magnification > 0 && scroll.magnification < 1)
        scroll.command(.actual); precondition(abs(scroll.magnification-1) < 0.001)
        scroll.command(.zoomIn); precondition(scroll.magnification > 1)
        scroll.contentView.scroll(to: NSPoint(x: 50,y: 100)); scroll.reflectScrolledClipView(scroll.contentView)
        precondition(scroll.contentView.bounds.origin.x > 0 && scroll.contentView.bounds.origin.y > 0, "Native panning did not move the viewport")
        scroll.setPictures([NSImage(size:NSSize(width:3000,height:4000)),NSImage(size:NSSize(width:2000,height:3000))])
        precondition(scroll.paper.rectangles.count == 2 && scroll.paper.rectangles[1].minX > scroll.paper.rectangles[0].maxX)
        scroll.command(.fit)
        print("PASS: macOS ImageIO decode, transform, PNG/JPEG/TIFF round trips, presets, malformed input, 1-bit PNG/TIFF, advanced algorithms, legacy migration, PDF rendering/extraction/rotation and source cache, ordered repeated steps, per-page projects, physical DPI, canvas and native preview zoom/pan")
    }
}
