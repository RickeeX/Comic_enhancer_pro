import AppKit
import Foundation
import ImageIO

@main
struct IntegrationTests {
    static func pdfFixture(_ url: URL, jpeg: Data? = nil, decode: String? = nil, pageScale: Int = 1, jpegWidth: Int = 120, jpegHeight: Int = 80, placement: CGSize = CGSize(width:80,height:40)) throws {
        let content = "q \(pageScale) 0 0 \(pageScale) 0 0 cm\nq \(placement.width) 0 0 \(placement.height) 24 60 cm /Im1 Do Q\n1 0 0 rg 10 180 30 20 re f\nQ\n"
        let pixels: [UInt8] = [0,0,0, 255,255,255, 255,0,0, 0,255,0, 0,0,255, 120,120,120, 200,200,200, 255,255,255]
        var objects: [Data] = [
            Data("<< /Type /Catalog /Pages 2 0 R >>".utf8),
            Data("<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /MediaBox [0 0 \(144*pageScale) \(216*pageScale)] /Resources << /XObject << /Im1 6 0 R >> >> >>".utf8),
            Data("<< /Type /Page /Parent 2 0 R /Contents 5 0 R >>".utf8),
            Data("<< /Type /Page /Parent 2 0 R /Rotate 90 /Contents 5 0 R >>".utf8),
            Data("<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream".utf8)
        ]
        let payload = jpeg ?? Data(pixels)
        let dimensions = (jpeg == nil ? "/Width 4 /Height 2" : "/Width \(jpegWidth) /Height \(jpegHeight) /Filter /DCTDecode") + (decode.map { " /Decode [\($0)]" } ?? "")
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
    static func inkBounds(_ image: CGImage) throws -> CGRect {
        let pixels = try Pipeline.rgba(image)
        var x0 = image.width, y0 = image.height, x1 = -1, y1 = -1
        for y in 0..<image.height { for x in 0..<image.width {
            let i = (y*image.width+x)*4
            if min(pixels[i],min(pixels[i+1],pixels[i+2])) < 128 {
                x0 = min(x0,x);x1 = max(x1,x);y0 = min(y0,y);y1 = max(y1,y)
            }
        } }
        precondition(x1 >= x0 && y1 >= y0,"Test document lost all content")
        return CGRect(x:Double(x0)/Double(image.width),y:Double(y0)/Double(image.height),
            width:Double(x1-x0+1)/Double(image.width),height:Double(y1-y0+1)/Double(image.height))
    }
    static func sameInkGeometry(_ a: CGImage, _ b: CGImage, message: String) throws {
        let x = try inkBounds(a), y = try inkBounds(b)
        let tolerance = 2.0 / Double(min(min(a.width,a.height),min(b.width,b.height)))
        guard abs(x.minX-y.minX) < tolerance && abs(x.minY-y.minY) < tolerance && abs(x.width-y.width) < tolerance && abs(x.height-y.height) < tolerance else {
            throw ProcessingError.message(message + ": normalized content bounds \(x) versus \(y)")
        }
    }
    static func benchmark() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:folder) }
        let w=5000,h=6000
        let image = try Processor.makeRGBAImage(width:w,height:h) { pixels in
            for y in 0..<h { for x in 0..<w {
                let i=(y*w+x)*4,v=UInt8((x%19<3 && y%31<13 ? 35:180)+(x*17+y*31)%35)
                pixels[i]=v;pixels[i+1]=v;pixels[i+2]=v;pixels[i+3]=255
            } }
        }
        let source = folder.appendingPathComponent("30MP.png")
        try Processor.write(image,to:source,settings:Settings())
        var tone=Stage(.tone);tone.settings.autoLevels=true;tone.settings.contrast=1.1
        var sharp=Stage(.sharpen);sharp.settings.sharpen=0.4;sharp.settings.filterRadius=3
        var binary=Stage(.binary);binary.settings.binarization=3
        let recipe=Recipe(stages:[tone,sharp,binary])
        let start=Date()
        let result=try Pipeline.render(PageItem(url:source),recipe:recipe,preview:false)
        let processed=Date()
        try Pipeline.write(result,to:folder.appendingPathComponent("output.png"),recipe:recipe)
        print(String(format:"30 MP native full-size decode + tone + USM + Sauvola: %.0f ms; 1-bit PNG export: %.0f ms",processed.timeIntervalSince(start)*1000,Date().timeIntervalSince(processed)*1000))
    }
    static func batchBenchmark() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:root) }
        let plane=try GrayPlane(width:1672,height:2658) { out in
            for y in 0..<2658 { for x in 0..<1672 { out[y*1672+x]=UInt8((x%19<3 && y%31<13 ? 35:180)+(x*17+y*31)%35) } }
        }
        var jpeg=Settings();jpeg.format="jpg"
        var pages=[PageItem]()
        for i in 0..<4 { let url=root.appendingPathComponent("scan-\(i).jpg");try Processor.writeEncoded(plane.exportImage(bits:8),to:url,settings:jpeg,dpiX:300,dpiY:300);pages.append(PageItem(url:url)) }
        var resize=Stage(.resize);resize.settings.preservePhysical=true;resize.settings.sourceDPI=300;resize.settings.targetDPI=600
        var tone=Stage(.tone);tone.settings.brightness=0.04;tone.settings.contrast=1.1;tone.settings.gamma=1.1
        var blur=Stage(.blur);blur.settings.blur=0.3;blur.settings.filterRadius=1
        var usm=Stage(.sharpen);usm.settings.sharpen=0.6;usm.settings.filterRadius=2;usm.settings.sharpenThreshold=2
        var binary=Stage(.binary);binary.settings.binarization=3;binary.settings.edgeSmooth=true;binary.settings.fillNotches=true
        let plans=Array(repeating:Recipe(stages:[resize,tone,blur,usm,binary]),count:4)
        print("Batch hardware: \(ProcessInfo.processInfo.activeProcessorCount) active CPUs; \(ProcessInfo.processInfo.physicalMemory/1_000_000) MB RAM; automatic workers=\(BatchExporter.workerCount(pages:pages,recipes:plans))")
        for workers in [1,2] {
            var samples=[Double]()
            for trial in -1..<3 {
                let folder=root.appendingPathComponent("out-\(workers)-\(trial)")
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
                let start=Date(),report=BatchExporter.run(pages:pages,recipes:plans,indices:[0,1,2,3],folder:folder,cancelled:{false},progress:{_ in},workers:workers)
                let ms=Date().timeIntervalSince(start)*1000
                guard report.succeeded==4 && report.failed==0 else { throw ProcessingError.message(report.log) }
                if trial>=0 { samples.append(ms) }
            }
            print(String(format:"Four 17.78 MP pages native export, workers=%d: %.1f ms total",workers,samples.reduce(0,+)/Double(samples.count)))
        }
    }
    static func main() throws {
        if CommandLine.arguments.contains("--benchmark") { try benchmark();return }
        if CommandLine.arguments.contains("--benchmark-batch") { try batchBenchmark();return }

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
        var cancellationChecks=0
        do {
            _ = try Pipeline.render(PageItem(url:source),recipe:Recipe(stages:[Stage(.tone),Stage(.invert)]),preview:false,cancelled:{
                cancellationChecks += 1;return cancellationChecks >= 3
            })
            fatalError("Cancelled preview completed the remaining stack")
        } catch is CancellationError { precondition(cancellationChecks == 3) }
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
        let page72 = try PDFLoader.image(PageItem(url:pdfURL,pdfPage:1,dpi:72),preview:false)
        try sameInkGeometry(page72,pageOne.original,message:"Increasing PDF render DPI enlarged only the canvas")
        let bigPDF = folder.appendingPathComponent("large-point-scan.pdf")
        try pdfFixture(bigPDF,pageScale:8)
        let bigItem = PageItem(url:bigPDF,pdfPage:1,dpi:100)
        let bigThumbnail = try PDFLoader.image(bigItem,preview:true)
        let bigFull = try PDFLoader.image(bigItem,preview:false)
        try sameInkGeometry(bigThumbnail,bigFull,message:"Full-size PDF content shrank relative to the thumbnail")
        var dpi400 = Stage(.resize);dpi400.settings.preservePhysical = true;dpi400.settings.targetDPI = 400
        let resizedPDF = try Pipeline.render(pages[0],recipe:Recipe(stages:[dpi400]),preview:false)
        precondition(resizedPDF.image.width == 800 && resizedPDF.image.height == 1200)
        try sameInkGeometry(page72,resizedPDF.image,message:"400 DPI resampling centered an unscaled source in a larger page")
        let dpi400URL = folder.appendingPathComponent("pdf-resampled-400.png")
        try Pipeline.write(resizedPDF,to:dpi400URL,recipe:Recipe(stages:[dpi400]))
        let reloaded400 = try Processor.sourceImage(PageItem(url:dpi400URL),preview:false)
        try sameInkGeometry(page72,reloaded400,message:"Exported 400 DPI content has extra whitespace")

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
        // Exercise the user's exact import path at scanner-sized resolutions,
        // with real PDF placement DPI and explicit fallback DPI overrides.
        let scanContext = CGContext(data:nil,width:2400,height:3600,bitsPerComponent:8,bytesPerRow:2400*4,space:space,
            bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
        scanContext.setFillColor(CGColor(gray:1,alpha:1));scanContext.fill(CGRect(x:0,y:0,width:2400,height:3600))
        scanContext.setFillColor(CGColor(gray:0,alpha:1));scanContext.fill(CGRect(x:400,y:600,width:1600,height:2400))
        let scanJPEG = folder.appendingPathComponent("scan.jpg")
        var scanJPEGSettings = Settings();scanJPEGSettings.format = "jpg"
        try Processor.write(scanContext.makeImage()!,to:scanJPEG,settings:scanJPEGSettings)
        let scanPDF = folder.appendingPathComponent("embedded-scan.pdf")
        try pdfFixture(scanPDF,jpeg:Data(contentsOf:scanJPEG),jpegWidth:2400,jpegHeight:3600,placement:CGSize(width:576,height:864))
        let scanItem = try PDFLoader.items(scanPDF,embedded:true,dpi:200)[0]
        let scanOriginal = try PDFLoader.image(scanItem,preview:false)
        var scanStep = Stage(.resize);scanStep.settings.preservePhysical = true;scanStep.settings.targetDPI = 400;scanStep.settings.resampleMethod = 2
        for explicit in [false,true] {
            scanStep.settings.sourceDPI = explicit ? 300 : 0
            let recipe = Recipe(stages:[scanStep])
            let small = try Pipeline.render(scanItem,recipe:recipe,preview:true)
            let full = try Pipeline.render(scanItem,recipe:recipe,preview:false)
            precondition(full.image.width == 3200 && full.image.height == 4800,"Embedded scan DPI dimensions changed")
            try sameInkGeometry(scanOriginal,full.image,message:"Embedded JPEG content shrank when resampled to 400 DPI")
            try sameInkGeometry(small.image,full.image,message:"Embedded JPEG thumbnail/full-size content mismatch")
            let url = folder.appendingPathComponent("embedded-400-\(explicit).png")
            try Pipeline.write(full,to:url,recipe:recipe)
            try sameInkGeometry(scanOriginal,Processor.sourceImage(PageItem(url:url),preview:false),message:"Embedded JPEG export shrank content")
        }
        // Borrowed normalized providers and CoreGraphics fallback must agree;
        // test a cropped provider whose data still includes the parent image.
        let normalized = try Processor.processCore(image,settings:Settings()).enhanced
        let direct = try Processor.withRGBA(normalized) { Data(bytes:$0,count:normalized.width*normalized.height*4) }
        let normalizedPixels = try Pipeline.rgba(normalized)
        precondition(direct == Data(normalizedPixels),"Borrowed RGBA changes color or row origin")
        let subimage = normalized.cropping(to:CGRect(x:12,y:9,width:63,height:41))!
        let subpixels = try Processor.withRGBA(subimage) { Data(bytes:$0,count:subimage.width*subimage.height*4) }
        let subimagePixels = try Pipeline.rgba(subimage)
        precondition(subpixels == Data(subimagePixels),"Borrowing ignored a cropped provider offset")
        let monoSource=folder.appendingPathComponent("gray-source.png")
        let monoPlane=try GrayPlane.normalized(Pipeline.image([255,0,0,255],width:1,height:1)) // colored input must fail safely
        precondition(monoPlane == nil,"Color data entered the one-channel path")
        let mono=try GrayPlane(width:137,height:193) { out in
            for i in 0..<out.count { out[i]=UInt8((i*71)%256) }
        }
        try Processor.writeEncoded(mono.exportImage(bits:8),to:monoSource,settings:Settings(),dpiX:300,dpiY:300)
        var monoResize=Stage(.resize);monoResize.settings.scale=2
        var monoTone=Stage(.tone);monoTone.settings.brightness=0.04;monoTone.settings.contrast=1.1;monoTone.settings.gamma=1.1
        var monoBlur=Stage(.blur);monoBlur.settings.blur=0.3;monoBlur.settings.filterRadius=1
        var monoUSM=Stage(.sharpen);monoUSM.settings.sharpen=0.6;monoUSM.settings.filterRadius=2;monoUSM.settings.sharpenThreshold=2
        var monoBinary=Stage(.binary);monoBinary.settings.binarization=3;monoBinary.settings.edgeSmooth=true;monoBinary.settings.fillNotches=true
        let monoRecipe=Recipe(stages:[monoResize,monoTone,monoBlur,monoUSM,monoBinary])
        let monoResult=try Pipeline.render(PageItem(url:monoSource),recipe:monoRecipe,preview:false)
        precondition(monoResult.gray != nil && monoResult.gray!.width==274 && monoResult.gray!.height==386,"Gray8 path was lost across operations")
        let monoLazy=try Pipeline.render(PageItem(url:monoSource),recipe:monoRecipe,preview:false,materialize:false)
        let monoURL=folder.appendingPathComponent("gray-export.png")
        try Pipeline.write(monoLazy,to:monoURL,recipe:monoRecipe)
        let monoDecoded=try Processor.render(monoURL,settings:Settings(),preview:false).enhanced
        let monoDisplayPixels=try Pipeline.rgba(monoResult.image),monoDecodedPixels=try Pipeline.rgba(monoDecoded)
        precondition(Data(monoDisplayPixels) == Data(monoDecodedPixels),"Gray8 display/export pixels differ")
        let batchFolder=folder.appendingPathComponent("batch")
        try FileManager.default.createDirectory(at:batchFolder,withIntermediateDirectories:false)
        let batchPages=[PageItem(url:monoSource),PageItem(url:source),PageItem(url:monoSource)]
        let batchPlans=[monoRecipe,Recipe.neutral,monoRecipe]
        let batch=BatchExporter.run(pages:batchPages,recipes:batchPlans,indices:[0,1,2],folder:batchFolder,cancelled:{false},progress:{_ in},workers:2)
        precondition(batch.succeeded==3 && batch.failed==0 && batch.completed==3,"Bounded parallel export lost a page")
        for i in batchPages.indices {
            let url=batchFolder.appendingPathComponent(batchPlans[i].filename(index:i,page:batchPages[i]))
            precondition(FileManager.default.fileExists(atPath:url.path),"Parallel export filename mismatch")
        }
        let duplicates=BatchExporter.run(pages:[batchPages[0],batchPages[0]],recipes:[monoRecipe,monoRecipe],indices:[4,4],folder:batchFolder,cancelled:{false},progress:{_ in},workers:2)
        precondition(duplicates.succeeded==1 && duplicates.failed==1,"Concurrent duplicate names overwrote output")
        var upperName=monoRecipe,lowerName=monoRecipe
        upperName.nameStyle=1;lowerName.nameStyle=1;upperName.namePrefix="Case-";lowerName.namePrefix="case-"
        let caseCollision=BatchExporter.run(pages:[batchPages[0],batchPages[0]],recipes:[upperName,lowerName],indices:[5,5],folder:batchFolder,cancelled:{false},progress:{_ in},workers:2)
        precondition(caseCollision.succeeded==1 && caseCollision.failed==1,"Case-insensitive output collision was not reserved")
        let stopped=BatchExporter.run(pages:batchPages,recipes:batchPlans,indices:[10,11,12],folder:batchFolder,cancelled:{true},progress:{_ in},workers:2)
        precondition(stopped.completed==0,"Cancelled batch started processing pages")
        precondition(BatchExporter.workerCount(pages:batchPages,recipes:batchPlans,memory:256_000_000,cpus:8)==1,"Memory budget allowed unsafe parallelism")
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
