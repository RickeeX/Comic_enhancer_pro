import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ProcessingError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
struct Rendered {
    let original: CGImage
    let enhanced: CGImage
}
enum Processor {
    static let extensions: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff", "bmp", "gif", "heic", "heif"]
    private final class ImageBox { let image: CGImage; init(_ image: CGImage) { self.image = image } }
    private static let previews: NSCache<NSString, ImageBox> = {
        let cache = NSCache<NSString, ImageBox>(); cache.totalCostLimit = 128 * 1024 * 1024; return cache
    }()
    static func render(_ url: URL, settings: Settings, preview: Bool) throws -> Rendered {
        try render(PageItem(url: url), settings: settings, preview: preview)
    }
    static func render(_ item: PageItem, settings: Settings, preview: Bool) throws -> Rendered {
        _ = try settings.validated()
        let image = try sourceImage(item, preview: preview)
        return try processCore(image, settings: settings)
    }
    static func sourceImage(_ item: PageItem, preview: Bool) throws -> CGImage {
        let date = (try? item.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let key = "\(item.path)-\(date?.timeIntervalSince1970 ?? 0)" as NSString
        let image: CGImage
        if preview, let cached = previews.object(forKey: key) { image = cached.image }
        else {
            image = try item.pdfPage != nil ? PDFLoader.image(item, preview: preview) : decodeImage(item.url, preview: preview)
            if preview { previews.setObject(ImageBox(image), forKey: key, cost: image.width * image.height * 4) }
        }
        return image
    }
    static func processCore(_ image: CGImage, settings: Settings) throws -> Rendered {
        _ = try settings.validated()
        let iw = image.width, ih = image.height
        var rgba = [UInt8](repeating: 255, count: iw * ih * 4)
        let color = CGColorSpace(name: CGColorSpace.sRGB)!
        let flags = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
        let decoded = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: iw, height: ih,
                bitsPerComponent: 8, bytesPerRow: iw * 4, space: color, bitmapInfo: flags) else { return false }
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: iw, height: ih))
            context.draw(image, in: CGRect(x: 0, y: 0, width: iw, height: ih)); return true
        }
        guard decoded else { throw ProcessingError.message("无法分配图像缓冲区。") }
        var o = settings.core
        var ow: UInt32 = 0, oh: UInt32 = 0
        guard ce_dimensions(UInt32(iw), UInt32(ih), &o, &ow, &oh) == 0 else {
            throw ProcessingError.message("输出超过 1 亿像素上限，请降低缩放比例。")
        }
        var output = [UInt8](repeating: 0, count: Int(ow) * Int(oh) * 4)
        let status = rgba.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                ce_process(src.baseAddress, UInt32(iw), UInt32(ih), &o, dst.baseAddress, dst.count)
            }
        }
        guard status == 0 else { throw ProcessingError.message("图像处理失败（\(status)）。") }
        let data = Data(output)
        guard let provider = CGDataProvider(data: data as CFData),
              let result = CGImage(width: Int(ow), height: Int(oh), bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: Int(ow) * 4, space: color, bitmapInfo: CGBitmapInfo(rawValue: flags),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw ProcessingError.message("无法创建输出图像。")
        }
        return Rendered(original: image, enhanced: result)
    }
    private static func decodeImage(_ url: URL, preview: Bool) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let h = props[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw ProcessingError.message("无法读取图像：\(url.lastPathComponent)")
        }
        let width = w.intValue, height = h.intValue
        guard width > 0, height > 0, width <= 100_000_000 / height else {
            throw ProcessingError.message("单页图像上限为 1 亿像素。")
        }
        let limit = preview ? min(1600, max(width, height)) : max(width, height)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit, kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ProcessingError.message("此图像无法解码。")
        }
        return image
    }
    static func write(_ image: CGImage, to url: URL, settings: Settings, dpiX: Double? = nil, dpiY: Double? = nil) throws {
        let type = settings.format == "jpg" ? UTType.jpeg : settings.format == "tiff" ? UTType.tiff : UTType.png
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw ProcessingError.message("无法创建输出文件。")
        }
        // Use an actual grayscale color space for gray exports, reducing storage.
        var export = image
        if settings.grayscale || settings.levels > 0 || settings.binarization != 0 {
            guard let raw = image.dataProvider?.data else { throw ProcessingError.message("无法读取灰度输出数据。") }
            let binary = settings.binarization != 0 || settings.levels == 2
            let bits = settings.format == "jpg" ? 8 : binary ? 1 : settings.levels == 4 ? 2 : settings.levels == 16 ? 4 : 8
            let stride = (image.width * bits + 7) / 8
            var packed = Data(repeating: 0, count: stride * image.height)
            let source = CFDataGetBytePtr(raw)!
            packed.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
                for y in 0..<image.height {
                    for x in 0..<image.width {
                        let value = Int(source[y * image.bytesPerRow + x * 4])
                        let quantized = (value * ((1 << bits) - 1) + 127) / 255
                        let bit = x * bits
                        bytes[y * stride + bit / 8] |= UInt8(quantized << (8 - bits - bit % 8))
                    }
                }
            }
            guard let provider = CGDataProvider(data: packed as CFData),
                  let gray = CGImage(width: image.width, height: image.height, bitsPerComponent: bits,
                    bitsPerPixel: bits, bytesPerRow: stride, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
                    decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
                throw ProcessingError.message("无法创建灰度输出。")
            }
            export = gray
        }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: settings.quality]
        if let x = dpiX, let y = dpiY, x.isFinite, y.isFinite, x > 0, y > 0 {
            properties[kCGImagePropertyDPIWidth] = x; properties[kCGImagePropertyDPIHeight] = y
            properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFXResolution: x, kCGImagePropertyTIFFYResolution: y, kCGImagePropertyTIFFResolutionUnit: 2]
        }
        CGImageDestinationAddImage(dest, export, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ProcessingError.message("编码图像失败。") }
        try (data as Data).write(to: url, options: .atomic)
    }
}
