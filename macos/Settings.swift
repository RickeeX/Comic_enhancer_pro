import Foundation

struct Settings: Codable, Equatable {
    var brightness: Double = 0
    var contrast: Double = 1
    var gamma: Double = 1
    var whitePoint: Double = 1
    var sharpen: Double = 0
    var blur: Double = 0
    var scale: Double = 1
    var crop: Double = 0
    var grayscale = false
    var levels = 0
    var autoLevels = false
    var rotation = 0
    var page = 0
    var format = "png"
    var quality: Double = 0.9

    var binarization = 0
    var threshold: Double = 127
    var adaptiveRadius = 20
    var sauvolaK: Double = 0.2
    var cleanup = 0
    var cleanupPasses = 1
    var dither = 0
    var blurMethod = 0
    var filterRadius = 1
    var edgeSigma: Double = 25
    var sharpenMethod = 0
    var sharpenThreshold: Double = 0
    var deskew = 0
    var deskewLimit: Double = 5
    var angle: Double = 0


    init() {}
    private enum CodingKeys: String, CodingKey {
        case brightness, contrast, gamma, whitePoint, sharpen, blur, scale, crop, grayscale, levels, autoLevels, rotation, page, format, quality, binarization, threshold, adaptiveRadius, sauvolaK, cleanup, cleanupPasses, dither, blurMethod, filterRadius, edgeSigma, sharpenMethod, sharpenThreshold, deskew, deskewLimit, angle
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? brightness
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? contrast
        gamma = try c.decodeIfPresent(Double.self, forKey: .gamma) ?? gamma
        whitePoint = try c.decodeIfPresent(Double.self, forKey: .whitePoint) ?? whitePoint
        sharpen = try c.decodeIfPresent(Double.self, forKey: .sharpen) ?? sharpen
        blur = try c.decodeIfPresent(Double.self, forKey: .blur) ?? blur
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? scale
        crop = try c.decodeIfPresent(Double.self, forKey: .crop) ?? crop
        grayscale = try c.decodeIfPresent(Bool.self, forKey: .grayscale) ?? grayscale
        levels = try c.decodeIfPresent(Int.self, forKey: .levels) ?? levels
        autoLevels = try c.decodeIfPresent(Bool.self, forKey: .autoLevels) ?? autoLevels
        rotation = try c.decodeIfPresent(Int.self, forKey: .rotation) ?? rotation
        page = try c.decodeIfPresent(Int.self, forKey: .page) ?? page
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? format
        quality = try c.decodeIfPresent(Double.self, forKey: .quality) ?? quality
        binarization = try c.decodeIfPresent(Int.self, forKey: .binarization) ?? binarization
        threshold = try c.decodeIfPresent(Double.self, forKey: .threshold) ?? threshold
        adaptiveRadius = try c.decodeIfPresent(Int.self, forKey: .adaptiveRadius) ?? adaptiveRadius
        sauvolaK = try c.decodeIfPresent(Double.self, forKey: .sauvolaK) ?? sauvolaK
        cleanup = try c.decodeIfPresent(Int.self, forKey: .cleanup) ?? cleanup
        cleanupPasses = try c.decodeIfPresent(Int.self, forKey: .cleanupPasses) ?? cleanupPasses
        dither = try c.decodeIfPresent(Int.self, forKey: .dither) ?? dither
        blurMethod = try c.decodeIfPresent(Int.self, forKey: .blurMethod) ?? blurMethod
        filterRadius = try c.decodeIfPresent(Int.self, forKey: .filterRadius) ?? filterRadius
        edgeSigma = try c.decodeIfPresent(Double.self, forKey: .edgeSigma) ?? edgeSigma
        sharpenMethod = try c.decodeIfPresent(Int.self, forKey: .sharpenMethod) ?? sharpenMethod
        sharpenThreshold = try c.decodeIfPresent(Double.self, forKey: .sharpenThreshold) ?? sharpenThreshold
        deskew = try c.decodeIfPresent(Int.self, forKey: .deskew) ?? deskew
        deskewLimit = try c.decodeIfPresent(Double.self, forKey: .deskewLimit) ?? deskewLimit
        angle = try c.decodeIfPresent(Double.self, forKey: .angle) ?? angle
    }

    func validated() throws -> Settings {
        let floats = [brightness, contrast, gamma, whitePoint, sharpen, blur, scale, crop, quality, threshold, sauvolaK, edgeSigma, sharpenThreshold, deskewLimit, angle]
        guard floats.allSatisfy({ $0.isFinite }), (-1...1).contains(brightness),
              (0...3).contains(contrast), (0.2...3).contains(gamma),
              (0.2...1).contains(whitePoint), (0...2).contains(sharpen),
              (0...1).contains(blur), (0.1...2).contains(scale), (0...0.2).contains(crop),
              [0,2,4,8,16,32,64,128,256].contains(levels), (0...3).contains(rotation),
              (0...2).contains(page), ["png", "jpg", "tiff"].contains(format),
              (0.1...1).contains(quality), (0...3).contains(binarization),
              (0...255).contains(threshold), (1...100).contains(adaptiveRadius),
              (0...1).contains(sauvolaK), (0...4).contains(cleanup), (1...3).contains(cleanupPasses),
              (0...2).contains(dither), (0...3).contains(blurMethod), (1...3).contains(filterRadius),
              (1...100).contains(edgeSigma), (0...1).contains(sharpenMethod),
              (0...255).contains(sharpenThreshold), (0...2).contains(deskew),
              (1...10).contains(deskewLimit), (-15...15).contains(angle) else { throw ProcessingError.message("参数文件包含超出范围的值。") }
        return self
    }
    var core: CEOptions {
        var o = ce_defaults()
        o.brightness = Float(brightness); o.contrast = Float(contrast)
        o.gamma = Float(gamma); o.white_point = Float(whitePoint)
        o.sharpen = Float(sharpen); o.blur = Float(blur)
        o.scale = Float(scale); o.crop = Float(crop)
        o.grayscale = grayscale ? 1 : 0; o.levels = Int32(levels)
        o.auto_levels = autoLevels ? 1 : 0; o.rotation = Int32(rotation); o.page = Int32(page)
        o.binarization = Int32(binarization); o.threshold = Float(threshold)
        o.adaptive_radius = Int32(adaptiveRadius); o.sauvola_k = Float(sauvolaK)
        o.cleanup = Int32(cleanup); o.cleanup_passes = Int32(cleanupPasses)
        o.dither = Int32(dither); o.blur_method = Int32(blurMethod)
        o.filter_radius = Int32(filterRadius); o.edge_sigma = Float(edgeSigma)
        o.sharpen_method = Int32(sharpenMethod); o.sharpen_threshold = Float(sharpenThreshold)
        o.deskew = Int32(deskew); o.deskew_limit = Float(deskewLimit); o.angle = Float(angle)
        return o
    }
}
