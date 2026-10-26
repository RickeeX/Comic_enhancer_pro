import AppKit
import ImageIO

struct SourceInfo {
    var width: Int
    var height: Int
    var dpiX: Double?
    var dpiY: Double?
    var assumed: Bool { dpiX == nil || dpiY == nil }
    var description: String {
        let x = dpiX ?? 300, y = dpiY ?? 300
        return String(format: "%d×%d px · %.1f×%.1f DPI · %.2f×%.2f cm%@", width, height, x, y, Double(width)/x*2.54, Double(height)/y*2.54, assumed ? "（DPI 缺失，暂按300；可手动指定）" : "")
    }
}
struct PipelineResult {
    var original: CGImage
    var image: CGImage
    var logicalWidth: Int
    var logicalHeight: Int
    var dpiX: Double
    var dpiY: Double
    var grayLevels: Int // -1 RGB, 0 continuous gray, 2/4/16/...
    var source: SourceInfo
    var description: String { String(format: "%d×%d px · %.1f×%.1f DPI · %.2f×%.2f cm", logicalWidth, logicalHeight, dpiX, dpiY, Double(logicalWidth)/dpiX*2.54, Double(logicalHeight)/dpiY*2.54) }
}
enum Pipeline {
    private final class InfoBox { let info: SourceInfo; init(_ info: SourceInfo) { self.info = info } }
    private static let metadata: NSCache<NSString, InfoBox> = { let c = NSCache<NSString, InfoBox>(); c.countLimit = 256; return c }()
    static func sourceInfo(_ item: PageItem) throws -> SourceInfo {
        let date = (try? item.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(item.path)-\(date)" as NSString
        if let cached = metadata.object(forKey: key) { return cached.info }
        let info = try readSourceInfo(item); metadata.setObject(InfoBox(info), forKey: key); return info
    }
    private static func readSourceInfo(_ item: PageItem) throws -> SourceInfo {
        if item.pdfPage != nil { return try PDFLoader.sourceInfo(item) }
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? NSNumber, let h = p[kCGImagePropertyPixelHeight] as? NSNumber else { throw ProcessingError.message("无法读取源图尺寸。") }
        var result = SourceInfo(width: w.intValue, height: h.intValue,
            dpiX: (p[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue,
            dpiY: (p[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue)
        if let orientation = p[kCGImagePropertyOrientation] as? NSNumber, (5...8).contains(orientation.intValue) {
            swap(&result.width, &result.height); swap(&result.dpiX, &result.dpiY)
        }
        if let x = result.dpiX, !x.isFinite || x <= 0 { result.dpiX = nil }
        if let y = result.dpiY, !y.isFinite || y <= 0 { result.dpiY = nil }
        return result
    }
    static func rgba(_ image: CGImage) throws -> [UInt8] {
        try checkSize(image.width, image.height)
        var pixels = [UInt8](repeating: 255, count: image.width * image.height * 4)
        let ok = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let c = CGContext(data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return true
        }
        guard ok else { throw ProcessingError.message("无法分配图像缓冲区。") }; return pixels
    }
    static func image(_ pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw ProcessingError.message("创建图像失败。") }
        return image
    }
    static func checkSize(_ w: Int, _ h: Int) throws {
        guard w > 0, h > 0, w <= 50000, h <= 50000, w <= 100_000_000 / h else { throw ProcessingError.message("输出超过 1 亿像素或单边 5 万像素，请降低 DPI 或页面尺寸。") }
    }
    static func render(_ item: PageItem, recipe: Recipe, preview: Bool, pageIndex: Int = 0) throws -> PipelineResult {
        _ = try recipe.validated()
        let source = try sourceInfo(item)
        try checkSize(source.width, source.height)
        let original = try Processor.sourceImage(item, preview: preview)
        var f = PipelineResult(original: original, image: original, logicalWidth: source.width, logicalHeight: source.height,
            dpiX: source.dpiX ?? 300, dpiY: source.dpiY ?? 300,
            grayLevels: original.colorSpace?.model == .monochrome ? (original.bitsPerComponent == 1 ? 2 : 0) : -1, source: source)
        for stage in recipe.stages where stage.enabled {
            try autoreleasepool { try apply(stage, to: &f, preview: preview, pageIndex: pageIndex) }
        }
        return f
    }
    private static func apply(_ stage: Stage, to f: inout PipelineResult, preview: Bool, pageIndex: Int) throws {
        let s = stage.settings
        var core = Settings()
        let ratio = min(Double(f.image.width)/Double(f.logicalWidth), Double(f.image.height)/Double(f.logicalHeight))
        switch stage.kind {
        case .page, .resize, .rotate, .deskew, .crop, .layout:
            try geometry(pageSettings(stage), frame: &f, preview: preview, pageIndex: pageIndex); return
        case .tone:
            if s.brightness == 0 && s.contrast == 1 && s.gamma == 1 && s.whitePoint == 1 && !s.autoLevels { return }
            core.brightness = s.brightness; core.contrast = s.contrast; core.gamma = s.gamma; core.whitePoint = s.whitePoint; core.autoLevels = s.autoLevels
            if f.grayLevels >= 0 { f.grayLevels = 0 }
        case .sharpen:
            if s.sharpen == 0 { return }
            core.sharpen = s.sharpen; core.sharpenMethod = s.sharpenMethod; core.sharpenThreshold = s.sharpenThreshold
            core.filterRadius = max(1, Int((Double(s.filterRadius)*ratio).rounded()))
            if f.grayLevels >= 0 { f.grayLevels = 0 }
        case .blur:
            if s.blur == 0 { return }
            core.blur = s.blur; core.blurMethod = s.blurMethod; core.edgeSigma = s.edgeSigma
            core.filterRadius = max(1, Int((Double(s.filterRadius)*ratio).rounded()))
            if f.grayLevels >= 0 { f.grayLevels = 0 }
        case .gray:
            if !s.grayscale && s.levels == 0 { return }
            core.grayscale = s.grayscale; core.levels = s.levels; core.dither = s.dither
            f.grayLevels = s.levels
        case .binary:
            if s.binarization == 0 { return }
            core.binarization = s.binarization; core.threshold = s.threshold; core.sauvolaK = s.sauvolaK
            core.adaptiveRadius = max(1, min(100, Int((Double(s.adaptiveRadius)*ratio).rounded())))
            f.image = try Processor.processCore(f.image, settings: core).enhanced; f.grayLevels = 2
            if s.edgeSmooth {
                var data = try rgba(f.image)
                let status = data.withUnsafeMutableBufferPointer { ce_smooth_binary($0.baseAddress, UInt32(f.image.width), UInt32(f.image.height), Int32(s.smoothPasses), s.fillNotches ? 1 : 0) }
                guard status == 0 else { throw ProcessingError.message("二值边缘修整失败（\(status)）。") }
                f.image = try image(data, width: f.image.width, height: f.image.height)
            }
            return
        case .despeckle:
            if s.despeckleDiameter == 0 && !s.removeBorders { return }
            var data = try rgba(f.image)
            let diameter = s.despeckleDiameter == 0 ? 0 : max(1, Int((Double(s.despeckleDiameter)*ratio).rounded()))
            let status = data.withUnsafeMutableBufferPointer { ce_despeckle($0.baseAddress, UInt32(f.image.width), UInt32(f.image.height), Int32(diameter), Int32(s.despeckleThreshold), s.removeBorders ? 1 : 0) }
            guard status == 0 else { throw ProcessingError.message("去斑失败（\(status)）。") }
            f.image = try image(data, width: f.image.width, height: f.image.height); return
        case .invert:
            var data = try rgba(f.image)
            let status = data.withUnsafeMutableBufferPointer { ce_invert($0.baseAddress, UInt32(f.image.width), UInt32(f.image.height)) }
            guard status == 0 else { throw ProcessingError.message("反色失败。") }
            f.image = try image(data, width: f.image.width, height: f.image.height); return
        case .mirror:
            if !s.flipHorizontal && !s.flipVertical { return }
            let input = try rgba(f.image); var output = input; let w = f.image.width, h = f.image.height
            let status = input.withUnsafeBufferPointer { p in output.withUnsafeMutableBufferPointer { o in
                ce_mirror(p.baseAddress, UInt32(w), UInt32(h), s.flipHorizontal ? 1 : 0, s.flipVertical ? 1 : 0, o.baseAddress, o.count)
            } }
            guard status == 0 else { throw ProcessingError.message("镜像失败。") }
            f.image = try image(output, width: w, height: h); return
        }
        f.image = try Processor.processCore(f.image, settings: core).enhanced
    }
    private static func pageSettings(_ stage: Stage) -> Settings {
        let s = stage.settings
        if stage.kind == .page { return s }
        var p = Settings()
        switch stage.kind {
        case .resize:
            p.sourceDPI = s.sourceDPI; p.sourceDPIY = s.sourceDPIY; p.preservePhysical = s.preservePhysical
            p.targetDPI = s.targetDPI; p.scale = s.scale; p.resampleMethod = s.resampleMethod
        case .rotate: p.rotation = s.rotation
        case .deskew: p.deskew = s.deskew; p.deskewLimit = s.deskewLimit; p.angle = s.angle
        case .crop:
            p.page = s.page; p.crop = s.crop; p.cropLeft = s.cropLeft; p.cropRight = s.cropRight; p.cropTop = s.cropTop; p.cropBottom = s.cropBottom
            p.autoTrim = s.autoTrim; p.trimThreshold = s.trimThreshold; p.trimIgnore = s.trimIgnore; p.trimPadding = s.trimPadding
            p.removeBorders = s.removeBorders; p.alternateMargins = s.alternateMargins
        case .layout:
            p.pageMode = s.pageMode; p.pageUnit = s.pageUnit; p.pageWidth = s.pageWidth; p.pageHeight = s.pageHeight
            p.marginLeft = s.marginLeft; p.marginRight = s.marginRight; p.marginTop = s.marginTop; p.marginBottom = s.marginBottom
            p.fitMode = s.fitMode; p.alignX = s.alignX; p.alignY = s.alignY; p.alternateMargins = s.alternateMargins; p.resampleMethod = s.resampleMethod
        default: break
        }
        return p
    }
    private static func crop(_ rect: CGRect, frame f: inout PipelineResult) throws {
        let bounded = rect.integral.intersection(CGRect(x: 0, y: 0, width: f.image.width, height: f.image.height))
        guard bounded.width >= 1, bounded.height >= 1, let image = f.image.cropping(to: bounded) else { throw ProcessingError.message("裁切区域为空。") }
        f.logicalWidth = max(1, Int((Double(f.logicalWidth)*Double(image.width)/Double(f.image.width)).rounded()))
        f.logicalHeight = max(1, Int((Double(f.logicalHeight)*Double(image.height)/Double(f.image.height)).rounded()))
        f.image = try self.image(rgba(image),width:image.width,height:image.height)
    }
    private static func geometry(_ s: Settings, frame f: inout PipelineResult, preview: Bool, pageIndex: Int) throws {
        if s.sourceDPI > 0 { f.dpiX = s.sourceDPI; if s.sourceDPIY == 0 { f.dpiY = s.sourceDPI } }
        if s.sourceDPIY > 0 { f.dpiY = s.sourceDPIY }
        if s.page != 0 {
            let half = f.image.width / 2
            try crop(CGRect(x: s.page == 1 ? 0 : half, y: 0, width: s.page == 1 ? half : f.image.width-half, height: f.image.height), frame: &f)
        }
        var left = s.cropLeft + s.crop, right = s.cropRight + s.crop
        if s.alternateMargins && pageIndex % 2 == 1 { swap(&left, &right) }
        let top = s.cropTop + s.crop, bottom = s.cropBottom + s.crop
        if left+right+top+bottom > 0 {
            try crop(CGRect(x: (Double(f.image.width)*left).rounded(), y: (Double(f.image.height)*top).rounded(),
                width: (Double(f.image.width)*(1-left-right)).rounded(), height: (Double(f.image.height)*(1-top-bottom)).rounded()), frame: &f)
        }
        if s.rotation != 0 || s.deskew != 0 || s.angle != 0 {
            var core = Settings(); core.rotation = s.rotation; core.deskew = s.deskew; core.deskewLimit = s.deskewLimit; core.angle = s.angle
            f.image = try Processor.processCore(f.image, settings: core).enhanced
            if s.rotation % 2 == 1 { swap(&f.logicalWidth, &f.logicalHeight); swap(&f.dpiX, &f.dpiY) }
            if (s.deskew != 0 || s.angle != 0) && f.grayLevels >= 0 { f.grayLevels = 0 }
        }
        if s.autoTrim {
            var data = try rgba(f.image)
            if s.removeBorders {
                let cleared = data.withUnsafeMutableBufferPointer { ce_despeckle($0.baseAddress, UInt32(f.image.width), UInt32(f.image.height), 0, Int32(s.trimThreshold), 1) }
                guard cleared == 0 else { throw ProcessingError.message("连边黑区清除失败。") }
            }
            var bounds = [UInt32](repeating: 0, count: 4)
            let ratio = Double(f.image.width)/Double(f.logicalWidth)
            let ignore = s.trimIgnore == 0 ? 0 : max(1, Int((Double(s.trimIgnore)*ratio).rounded()))
            let status = data.withUnsafeBufferPointer { p in bounds.withUnsafeMutableBufferPointer { b in ce_content_bounds(p.baseAddress, UInt32(f.image.width), UInt32(f.image.height), Int32(s.trimThreshold), Int32(ignore), b.baseAddress) } }
            guard status == 0 else { throw ProcessingError.message("自动内容框失败。") }
            if s.removeBorders { f.image = try image(data, width: f.image.width, height: f.image.height) }
            let padding = ceil(Double(s.trimPadding)*ratio)
            try crop(CGRect(x: Double(bounds[0])-padding, y: Double(bounds[1])-padding,
                width: Double(bounds[2])+padding*2, height: Double(bounds[3])+padding*2), frame: &f)
        }
        let oldX = f.dpiX, oldY = f.dpiY
        if s.preservePhysical { f.dpiX = s.targetDPI; f.dpiY = s.targetDPI }
        let contentW = Double(f.logicalWidth) * (s.preservePhysical ? f.dpiX/oldX : s.scale)
        let contentH = Double(f.logicalHeight) * (s.preservePhysical ? f.dpiY/oldY : s.scale)
        func units(_ value: Double, dpi: Double) -> Double { s.pageUnit == 0 ? value / 2.54 * dpi : value }
        var ml = units(s.marginLeft, dpi: f.dpiX), mr = units(s.marginRight, dpi: f.dpiX)
        if s.alternateMargins && pageIndex % 2 == 1 { swap(&ml, &mr) }
        let mt = units(s.marginTop, dpi: f.dpiY), mb = units(s.marginBottom, dpi: f.dpiY)
        var width = contentW, height = contentH
        switch s.pageMode {
        case 1: width = units(s.pageWidth, dpi: f.dpiX); height = (width-ml-mr)*contentH/contentW+mt+mb
        case 2: height = units(s.pageHeight, dpi: f.dpiY); width = (height-mt-mb)*contentW/contentH+ml+mr
        case 3: width = units(s.pageWidth, dpi: f.dpiX); height = units(s.pageHeight, dpi: f.dpiY)
        case 4: width = contentW+ml+mr; height = contentH+mt+mb
        default: break
        }
        guard width.isFinite, height.isFinite, width >= 1, height >= 1, width <= 50000, height <= 50000 else { throw ProcessingError.message("页面尺寸无效。") }
        let logicalW = Int(width.rounded()), logicalH = Int(height.rounded()); try checkSize(logicalW, logicalH)
        var rw = contentW, rh = contentH, x = 0.0, y = 0.0
        if s.pageMode != 0 {
            let innerW = width-ml-mr, innerH = height-mt-mb
            guard innerW >= 1, innerH >= 1 else { throw ProcessingError.message("页边距超过页面大小。") }
            if s.fitMode == 2 { rw = innerW; rh = innerH }
            else { let scale = s.fitMode == 0 ? min(innerW/contentW, innerH/contentH) : max(innerW/contentW, innerH/contentH); rw *= scale; rh *= scale }
            x = ml + (innerW-rw)*Double(s.alignX)/2; y = mt + (innerH-rh)*Double(s.alignY)/2
        }
        let ratio = preview ? min(1, 1600/Double(max(logicalW, logicalH))) : 1
        let actualW = max(1, Int((Double(logicalW)*ratio).rounded())), actualH = max(1, Int((Double(logicalH)*ratio).rounded()))
        if actualW != f.image.width || actualH != f.image.height || x != 0 || y != 0 || abs(rw-width) > 0.01 || abs(rh-height) > 0.01 {
            let xr = Double(actualW)/width, yr = Double(actualH)/height
            var rect = [Float(x*xr), Float(y*yr), Float(rw*xr), Float(rh*yr)]
            let resized = try Processor.makeRGBAImage(width: actualW, height: actualH) { output in
                let status = try Processor.withRGBA(f.image) { input in rect.withUnsafeMutableBufferPointer { r in
                    ce_canvas(input, UInt32(f.image.width), UInt32(f.image.height), UInt32(actualW), UInt32(actualH), r.baseAddress, Int32(s.resampleMethod), output.baseAddress, output.count)
                } }
                guard status == 0 else { throw ProcessingError.message("页面排版失败（\(status)）。") }
                if s.pageMode != 0 {
                    var clip = [Float(ml*xr), Float(mt*yr), Float((width-ml-mr)*xr), Float((height-mt-mb)*yr)]
                    let masked = clip.withUnsafeMutableBufferPointer { ce_whiten_outside(output.baseAddress, UInt32(actualW), UInt32(actualH), $0.baseAddress) }
                    guard masked == 0 else { throw ProcessingError.message("版心裁切失败。") }
                }
            }
            f.image = resized
            if f.grayLevels >= 0 && s.resampleMethod != 0 { f.grayLevels = 0 }
        }
        f.logicalWidth = logicalW; f.logicalHeight = logicalH
    }
    static func stitch(_ first: PipelineResult, _ second: PipelineResult, vertical: Bool, gap: Int) throws -> PipelineResult {
        guard first.logicalWidth == first.image.width, first.logicalHeight == first.image.height,
              second.logicalWidth == second.image.width, second.logicalHeight == second.image.height else { throw ProcessingError.message("拼接需使用全尺寸处理结果。") }
        guard (0...1000).contains(gap) else { throw ProcessingError.message("拼接间距需为 0–1000 像素。") }
        let w1 = first.image.width, h1 = first.image.height
        let w2 = max(1,Int((Double(second.logicalWidth)/second.dpiX*first.dpiX).rounded()))
        let h2 = max(1,Int((Double(second.logicalHeight)/second.dpiY*first.dpiY).rounded()))
        try checkSize(w2,h2)
        let width = vertical ? max(w1,w2) : w1+w2+gap, height = vertical ? h1+h2+gap : max(h1,h2)
        try checkSize(width,height)
        let a = try rgba(first.image)
        var b = try rgba(second.image)
        let resized = w2 != second.image.width || h2 != second.image.height
        if resized {
            var scaled = [UInt8](repeating:255,count:w2*h2*4), rect = [Float(0),0,Float(w2),Float(h2)]
            let status = b.withUnsafeBufferPointer { p in scaled.withUnsafeMutableBufferPointer { out in rect.withUnsafeMutableBufferPointer { r in ce_canvas(p.baseAddress,UInt32(second.image.width),UInt32(second.image.height),UInt32(w2),UInt32(h2),r.baseAddress,2,out.baseAddress,out.count) } } }
            guard status == 0 else { throw ProcessingError.message("拼接分辨率匹配失败。") }; b = scaled
        }
        var output = [UInt8](repeating:255,count:width*height*4)
        let positions = vertical ? [(w1,h1,(width-w1)/2,0),(w2,h2,(width-w2)/2,h1+gap)] : [(w1,h1,0,(height-h1)/2),(w2,h2,w1+gap,(height-h2)/2)]
        for (i, item) in positions.enumerated() {
            let input = i == 0 ? a : b
            let status = input.withUnsafeBufferPointer { p in output.withUnsafeMutableBufferPointer { out in ce_blit(p.baseAddress,UInt32(item.0),UInt32(item.1),out.baseAddress,UInt32(width),UInt32(height),UInt32(item.2),UInt32(item.3),out.count) } }
            guard status == 0 else { throw ProcessingError.message("拼接失败。") }
        }
        let image = try self.image(output,width:width,height:height)
        return PipelineResult(original:first.original,image:image,logicalWidth:width,logicalHeight:height,dpiX:first.dpiX,dpiY:first.dpiY,
            grayLevels:first.grayLevels == 2 && second.grayLevels == 2 && !resized ? 2 : first.grayLevels >= 0 && second.grayLevels >= 0 ? 0 : -1,source:first.source)
    }
    static func write(_ result: PipelineResult, to url: URL, recipe: Recipe) throws {
        var settings = Settings(); settings.format = recipe.format; settings.quality = recipe.quality
        settings.grayscale = result.grayLevels >= 0; settings.levels = max(0, result.grayLevels)
        var image = result.image
        if result.grayLevels >= 0 && !(image.bitsPerPixel == 32 && image.bitsPerComponent == 8 && image.bitmapInfo.contains(.byteOrder32Big)) {
            image = try self.image(rgba(image), width: image.width, height: image.height)
        }
        try Processor.write(image, to: url, settings: settings, dpiX: result.dpiX, dpiY: result.dpiY)
    }
}
