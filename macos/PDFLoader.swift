import AppKit
import CoreGraphics
import ImageIO

private final class PDFEntries {
    var values: [(String, CGPDFObjectRef)] = []
}
enum PDFLoader {
    // Access is serialized, keeping only one parsed document alive, not every page bitmap.
    private static let lock = NSLock()
    private static var cachedURL: URL?
    private static var cachedDate: Date?
    private static var cachedImagePage: Int?
    private static var cachedStreams: [CGPDFStreamRef] = []
    private static var cachedDocument: CGPDFDocument?
    private static func document(_ url: URL) throws -> CGPDFDocument {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if url == cachedURL, date == cachedDate, let document = cachedDocument { return document }
        guard let doc = CGPDFDocument(url as CFURL), doc.numberOfPages > 0 else { throw ProcessingError.message("无法读取 PDF：\(url.lastPathComponent)") }
        guard !doc.isEncrypted || doc.isUnlocked else { throw ProcessingError.message("PDF 已加密，请先解锁再导入：\(url.lastPathComponent)") }
        cachedImagePage = nil; cachedStreams = []
        cachedURL = url; cachedDate = date; cachedDocument = doc
        return doc
    }
    private static func images(_ resources: CGPDFDictionaryRef?, depth: Int = 0) -> [CGPDFStreamRef] {
        guard depth < 8, let resources = resources else { return [] }
        var objects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects = objects else { return [] }
        let entries = PDFEntries()
        CGPDFDictionaryApplyFunction(objects, { key, object, info in
            let collector = Unmanaged<PDFEntries>.fromOpaque(info!).takeUnretainedValue()
            collector.values.append((String(cString: key), object))
        }, Unmanaged.passUnretained(entries).toOpaque())
        var found: [CGPDFStreamRef] = []
        for (_, object) in entries.values.sorted(by: { $0.0 < $1.0 }) {
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream = stream else { continue }
            guard let dict = CGPDFStreamGetDictionary(stream) else { continue }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype = subtype else { continue }
            if String(cString: subtype) == "Image" {
                var mask: CGPDFBoolean = 0
                if !CGPDFDictionaryGetBoolean(dict, "ImageMask", &mask) || mask == 0 { found.append(stream) }
            } else if String(cString: subtype) == "Form" {
                var nested: CGPDFDictionaryRef?
                _ = CGPDFDictionaryGetDictionary(dict, "Resources", &nested)
                found += images(nested, depth: depth + 1)
            }
        }
        return found
    }
    private static func resources(_ page: CGPDFPage) -> CGPDFDictionaryRef? {
        var dict: CGPDFDictionaryRef? = page.dictionary
        for _ in 0..<16 {
            guard let current = dict else { break }
            var resources: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(current, "Resources", &resources) { return resources }
            var parent: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(current, "Parent", &parent) else { break }
            dict = parent
        }
        return nil
    }
    static func items(_ url: URL, embedded: Bool, dpi: Int) throws -> [PageItem] {
        lock.lock(); defer { lock.unlock() }
        guard (72...600).contains(dpi) else { throw ProcessingError.message("PDF DPI 需在 72–600 之间。") }
        let doc = try document(url)
        var items: [PageItem] = []
        for number in 1...doc.numberOfPages {
            if embedded {
                guard let page = doc.page(at: number) else { continue }
                for index in images(resources(page)).indices { items.append(PageItem(url: url, pdfPage: number, embeddedIndex: index, dpi: dpi)) }
            } else { items.append(PageItem(url: url, pdfPage: number, dpi: dpi)) }
        }
        guard !items.isEmpty else { throw ProcessingError.message("PDF 中没有可提取的内嵌图片，请选择按页渲染。") }
        return items
    }
    static func image(_ item: PageItem, preview: Bool) throws -> CGImage {
        lock.lock(); defer { lock.unlock() }
        let doc = try document(item.url)
        guard let number = item.pdfPage, let page = doc.page(at: number) else { throw ProcessingError.message("PDF 页面已不存在，请重新导入。") }
        if let index = item.embeddedIndex {
            if cachedImagePage != number { cachedStreams = images(resources(page)); cachedImagePage = number }
            let streams = cachedStreams
            guard streams.indices.contains(index) else { throw ProcessingError.message("内嵌图片已变化，请重新导入 PDF。") }
            return try embedded(streams[index], preview: preview)
        }
        let bounds = page.getBoxRect(.cropBox)
        var width = abs(bounds.width), height = abs(bounds.height)
        if abs(page.rotationAngle) % 180 == 90 { swap(&width, &height) }
        width = ceil(width * CGFloat(item.dpi) / 72); height = ceil(height * CGFloat(item.dpi) / 72)
        guard width.isFinite, height.isFinite, width > 0, height > 0, width * height <= 100_000_000 else { throw ProcessingError.message("PDF 渲染超过 1 亿像素，请降低导入 DPI。") }
        if preview {
            let ratio = min(1, 1600 / max(width, height)); width = max(1, floor(width * ratio)); height = max(1, floor(height * ratio))
        }
        guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8,
            bytesPerRow: Int(width) * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw ProcessingError.message("无法分配 PDF 渲染缓冲区。") }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw ProcessingError.message("PDF 页面渲染失败。") }
        return image
    }
    private static func embedded(_ stream: CGPDFStreamRef, preview: Bool) throws -> CGImage {
        guard let dict = CGPDFStreamGetDictionary(stream) else { throw ProcessingError.message("PDF 图片字典损坏。") }
        var w: CGPDFInteger = 0, h: CGPDFInteger = 0, bits: CGPDFInteger = 8
        _ = CGPDFDictionaryGetInteger(dict, "Width", &w); _ = CGPDFDictionaryGetInteger(dict, "Height", &h)
        _ = CGPDFDictionaryGetInteger(dict, "BitsPerComponent", &bits)
        guard w > 0, h > 0, w <= 100_000_000 / h else { throw ProcessingError.message("PDF 内嵌图片超过像素上限。") }
        var mask: CGPDFStreamRef?
        var colorMask: CGPDFArrayRef?
        var decode: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dict, "Decode", &decode) { throw ProcessingError.message("此图片有自定义色彩映射，请选择按页渲染以保留外观。") }
        if CGPDFDictionaryGetArray(dict, "Mask", &colorMask) || CGPDFDictionaryGetStream(dict, "SMask", &mask) || CGPDFDictionaryGetStream(dict, "Mask", &mask) {
            throw ProcessingError.message("此内嵌图片有透明掩膜，请选择 PDF 按页渲染以保留外观。")
        }
        var colorArray: CGPDFArrayRef?
        var colorName: UnsafePointer<CChar>?
        if CGPDFDictionaryGetArray(dict, "ColorSpace", &colorArray) { throw ProcessingError.message("此图片使用特殊色彩空间，请选择按页渲染。") }
        if CGPDFDictionaryGetName(dict, "ColorSpace", &colorName), let name = colorName,
           !["DeviceGray", "G", "DeviceRGB", "RGB", "DeviceCMYK", "CMYK"].contains(String(cString: name)) {
            throw ProcessingError.message("此图片使用自定义色彩空间，请选择按页渲染。")
        }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) else { throw ProcessingError.message("无法解压 PDF 图片。") }
        var image: CGImage?
        if format != .raw, let source = CGImageSourceCreateWithData(data, nil) {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: preview ? min(1600, max(w, h)) : max(w, h)] as CFDictionary)
        } else {
            var name: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dict, "ColorSpace", &name), let name = name else { throw ProcessingError.message("此 PDF 图片使用特殊色彩空间，请选择按页渲染。") }
            let space: CGColorSpace
            switch String(cString: name) {
            case "DeviceGray", "G": space = CGColorSpaceCreateDeviceGray()
            case "DeviceRGB", "RGB": space = CGColorSpaceCreateDeviceRGB()
            case "DeviceCMYK", "CMYK": space = CGColorSpaceCreateDeviceCMYK()
            default: throw ProcessingError.message("暂不支持提取此色彩空间，请选择 PDF 按页渲染。")
            }
            guard [1,2,4,8].contains(bits), space.numberOfComponents == 1 || bits == 8 else { throw ProcessingError.message("暂不支持此图片位深，请选择按页渲染。") }
            let stride = (w * bits * space.numberOfComponents + 7) / 8
            guard CFDataGetLength(data) >= stride * h, let provider = CGDataProvider(data: data) else { throw ProcessingError.message("PDF 图片数据不完整。") }
            var decodeArray: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(dict, "Decode", &decodeArray) { throw ProcessingError.message("此图片有自定义色彩映射，请选择按页渲染以保留外观。") }
            image = CGImage(width: w, height: h, bitsPerComponent: bits, bitsPerPixel: bits * space.numberOfComponents,
                bytesPerRow: stride, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
        guard let result = image else { throw ProcessingError.message("无法解码 PDF 内嵌图片，请选择按页渲染。") }
        if preview && max(result.width, result.height) > 1600 {
            let ratio = 1600.0 / Double(max(result.width, result.height))
            let w = max(1, Int(Double(result.width) * ratio)), h = max(1, Int(Double(result.height) * ratio))
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw ProcessingError.message("无法缩小 PDF 预览。") }
            ctx.interpolationQuality = .high; ctx.draw(result, in: CGRect(x: 0, y: 0, width: w, height: h))
            if let small = ctx.makeImage() { return small }
        }
        return result
    }
}

private final class PDFPlacementContext {
    var transform = CGAffineTransform.identity
    var saved: [CGAffineTransform] = []
    var sizes: [CGPDFStreamRef: CGSize] = [:]
    var depth = 0
    var operations = 0
}
extension PDFLoader {
    private static func scanPlacements(_ content: CGPDFContentStreamRef, context: PDFPlacementContext) {
        guard context.depth < 8, let table = CGPDFOperatorTableCreate() else { return }
        CGPDFOperatorTableSetCallback(table, "q", { _, info in
            guard let info = info else { return }
            let c = Unmanaged<PDFPlacementContext>.fromOpaque(info).takeUnretainedValue(); c.saved.append(c.transform)
        })
        CGPDFOperatorTableSetCallback(table, "Q", { _, info in
            guard let info = info else { return }
            let c = Unmanaged<PDFPlacementContext>.fromOpaque(info).takeUnretainedValue()
            if let last = c.saved.popLast() { c.transform = last }
        })
        CGPDFOperatorTableSetCallback(table, "cm", { scanner, info in
            guard let scanner = scanner, let info = info else { return }
            let c = Unmanaged<PDFPlacementContext>.fromOpaque(info).takeUnretainedValue()
            var values = [CGPDFReal](repeating: 0, count: 6)
            for i in (0..<6).reversed() { guard CGPDFScannerPopNumber(scanner, &values[i]) else { return } }
            let m = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
            c.transform = m.concatenating(c.transform)
        })
        CGPDFOperatorTableSetCallback(table, "Do", { scanner, info in
            guard let scanner = scanner, let info = info else { return }
            let c = Unmanaged<PDFPlacementContext>.fromOpaque(info).takeUnretainedValue()
            c.operations += 1; guard c.operations <= 100000 else { return }
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name = name,
                  let content = CGPDFScannerGetContentStream(scanner),
                  let object = CGPDFContentStreamGetResource(content, "XObject", name) else { return }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream = stream,
                  let dict = CGPDFStreamGetDictionary(stream) else { return }
            var type: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dict, "Subtype", &type), let type = type else { return }
            if String(cString: type) == "Image" {
                let w = hypot(c.transform.a, c.transform.b), h = hypot(c.transform.c, c.transform.d)
                if w.isFinite, h.isFinite, w > 0, h > 0 {
                    let size = CGSize(width: w, height: h)
                    if w * h > (c.sizes[stream].map { $0.width * $0.height } ?? 0) { c.sizes[stream] = size }
                }
            } else if String(cString: type) == "Form", c.depth < 7 {
                let saved = c.transform, stack = c.saved
                var matrix: CGPDFArrayRef?
                if CGPDFDictionaryGetArray(dict, "Matrix", &matrix), let matrix = matrix, CGPDFArrayGetCount(matrix) == 6 {
                    var v = [CGPDFReal](repeating: 0, count: 6)
                    for i in 0..<6 { _ = CGPDFArrayGetNumber(matrix, i, &v[i]) }
                    c.transform = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]).concatenating(c.transform)
                }
                var resources: CGPDFDictionaryRef?
                _ = CGPDFDictionaryGetDictionary(dict, "Resources", &resources)
                if let nested = CGPDFContentStreamCreateWithStream(stream, resources, content) {
                    c.depth += 1; PDFLoader.scanPlacements(nested, context: c); c.depth -= 1
                }
                c.transform = saved; c.saved = stack
            }
        })
        if let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(context).toOpaque()) { _ = CGPDFScannerScan(scanner) }
    }
    static func sourceInfo(_ item: PageItem) throws -> SourceInfo {
        lock.lock(); defer { lock.unlock() }
        let doc = try document(item.url)
        guard let number = item.pdfPage, let page = doc.page(at: number) else { throw ProcessingError.message("PDF 页面不存在。") }
        if let index = item.embeddedIndex {
            let streams = images(resources(page))
            guard streams.indices.contains(index), let dict = CGPDFStreamGetDictionary(streams[index]) else { throw ProcessingError.message("PDF 图片不存在。") }
            var w: CGPDFInteger = 0, h: CGPDFInteger = 0
            _ = CGPDFDictionaryGetInteger(dict, "Width", &w); _ = CGPDFDictionaryGetInteger(dict, "Height", &h)
            let context = PDFPlacementContext()
            if let content = CGPDFContentStreamCreateWithPage(page) { scanPlacements(content, context: context) }
            let size = context.sizes[streams[index]]
            return SourceInfo(width: w, height: h, dpiX: size.map { Double(w) * 72 / $0.width }, dpiY: size.map { Double(h) * 72 / $0.height })
        }
        let rect = page.getBoxRect(.cropBox)
        var w = Double(abs(rect.width)), h = Double(abs(rect.height))
        if abs(page.rotationAngle) % 180 == 90 { swap(&w, &h) }
        let pixelsW = Int(ceil(w * Double(item.dpi) / 72)), pixelsH = Int(ceil(h * Double(item.dpi) / 72))
        return SourceInfo(width: pixelsW, height: pixelsH, dpiX: Double(pixelsW) * 72 / w, dpiY: Double(pixelsH) * 72 / h)
    }
}
