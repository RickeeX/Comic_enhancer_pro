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


    var preservePhysical = false
    var sourceDPI: Double = 0
    var sourceDPIY: Double = 0
    var targetDPI: Double = 600
    var pageMode = 0
    var pageUnit = 0
    var pageWidth: Double = 12
    var pageHeight: Double = 15
    var marginLeft: Double = 0
    var marginRight: Double = 0
    var marginTop: Double = 0
    var marginBottom: Double = 0
    var fitMode = 0
    var alignX = 1
    var alignY = 1
    var alternateMargins = false
    var cropLeft: Double = 0
    var cropRight: Double = 0
    var cropTop: Double = 0
    var cropBottom: Double = 0
    var autoTrim = false
    var trimThreshold = 240
    var trimIgnore = 0
    var trimPadding = 2
    var removeBorders = false
    var despeckleDiameter = 0
    var despeckleThreshold = 127
    var edgeSmooth = false
    var smoothPasses = 1
    var fillNotches = false
    var resampleMethod = 2
    var flipHorizontal = false
    var flipVertical = false

    init() {}
    private enum CodingKeys: String, CodingKey {
        case sourceDPIY, brightness, contrast, gamma, whitePoint, sharpen, blur, scale, crop, grayscale, levels, autoLevels, rotation, page, format, quality, binarization, threshold, adaptiveRadius, sauvolaK, cleanup, cleanupPasses, dither, blurMethod, filterRadius, edgeSigma, sharpenMethod, sharpenThreshold, deskew, deskewLimit, angle, preservePhysical, sourceDPI, targetDPI, pageMode, pageUnit, pageWidth, pageHeight, marginLeft, marginRight, marginTop, marginBottom, fitMode, alignX, alignY, alternateMargins, cropLeft, cropRight, cropTop, cropBottom, autoTrim, trimThreshold, trimIgnore, trimPadding, removeBorders, despeckleDiameter, despeckleThreshold, edgeSmooth, smoothPasses, fillNotches, resampleMethod, flipHorizontal, flipVertical
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
        preservePhysical = try c.decodeIfPresent(Bool.self, forKey: .preservePhysical) ?? preservePhysical
        sourceDPIY = try c.decodeIfPresent(Double.self, forKey: .sourceDPIY) ?? sourceDPIY
        sourceDPI = try c.decodeIfPresent(Double.self, forKey: .sourceDPI) ?? sourceDPI
        targetDPI = try c.decodeIfPresent(Double.self, forKey: .targetDPI) ?? targetDPI
        pageMode = try c.decodeIfPresent(Int.self, forKey: .pageMode) ?? pageMode
        pageUnit = try c.decodeIfPresent(Int.self, forKey: .pageUnit) ?? pageUnit
        pageWidth = try c.decodeIfPresent(Double.self, forKey: .pageWidth) ?? pageWidth
        pageHeight = try c.decodeIfPresent(Double.self, forKey: .pageHeight) ?? pageHeight
        marginLeft = try c.decodeIfPresent(Double.self, forKey: .marginLeft) ?? marginLeft
        marginRight = try c.decodeIfPresent(Double.self, forKey: .marginRight) ?? marginRight
        marginTop = try c.decodeIfPresent(Double.self, forKey: .marginTop) ?? marginTop
        marginBottom = try c.decodeIfPresent(Double.self, forKey: .marginBottom) ?? marginBottom
        fitMode = try c.decodeIfPresent(Int.self, forKey: .fitMode) ?? fitMode
        alignX = try c.decodeIfPresent(Int.self, forKey: .alignX) ?? alignX
        alignY = try c.decodeIfPresent(Int.self, forKey: .alignY) ?? alignY
        alternateMargins = try c.decodeIfPresent(Bool.self, forKey: .alternateMargins) ?? alternateMargins
        cropLeft = try c.decodeIfPresent(Double.self, forKey: .cropLeft) ?? cropLeft
        cropRight = try c.decodeIfPresent(Double.self, forKey: .cropRight) ?? cropRight
        cropTop = try c.decodeIfPresent(Double.self, forKey: .cropTop) ?? cropTop
        cropBottom = try c.decodeIfPresent(Double.self, forKey: .cropBottom) ?? cropBottom
        autoTrim = try c.decodeIfPresent(Bool.self, forKey: .autoTrim) ?? autoTrim
        trimThreshold = try c.decodeIfPresent(Int.self, forKey: .trimThreshold) ?? trimThreshold
        trimIgnore = try c.decodeIfPresent(Int.self, forKey: .trimIgnore) ?? trimIgnore
        trimPadding = try c.decodeIfPresent(Int.self, forKey: .trimPadding) ?? trimPadding
        removeBorders = try c.decodeIfPresent(Bool.self, forKey: .removeBorders) ?? removeBorders
        despeckleDiameter = try c.decodeIfPresent(Int.self, forKey: .despeckleDiameter) ?? despeckleDiameter
        despeckleThreshold = try c.decodeIfPresent(Int.self, forKey: .despeckleThreshold) ?? despeckleThreshold
        edgeSmooth = try c.decodeIfPresent(Bool.self, forKey: .edgeSmooth) ?? edgeSmooth
        smoothPasses = try c.decodeIfPresent(Int.self, forKey: .smoothPasses) ?? smoothPasses
        fillNotches = try c.decodeIfPresent(Bool.self, forKey: .fillNotches) ?? fillNotches
        resampleMethod = try c.decodeIfPresent(Int.self, forKey: .resampleMethod) ?? resampleMethod
        flipHorizontal = try c.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? flipHorizontal
        flipVertical = try c.decodeIfPresent(Bool.self, forKey: .flipVertical) ?? flipVertical
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
        let geometry = [sourceDPI, sourceDPIY, targetDPI, pageWidth, pageHeight, marginLeft, marginRight, marginTop, marginBottom, cropLeft, cropRight, cropTop, cropBottom]
        guard geometry.allSatisfy({ $0.isFinite }), (sourceDPI == 0 || (36...2400).contains(sourceDPI)), (sourceDPIY == 0 || (36...2400).contains(sourceDPIY)),
              (36...2400).contains(targetDPI), (0.01...100000).contains(pageWidth), (0.01...100000).contains(pageHeight),
              [marginLeft, marginRight, marginTop, marginBottom].allSatisfy({ (0...10000).contains($0) }),
              [cropLeft, cropRight, cropTop, cropBottom].allSatisfy({ (0...0.49).contains($0) }),
              cropLeft + cropRight < 0.95, cropTop + cropBottom < 0.95,
              (0...4).contains(pageMode), (0...1).contains(pageUnit), (0...2).contains(fitMode),
              (0...2).contains(alignX), (0...2).contains(alignY), (0...254).contains(trimThreshold),
              (0...128).contains(trimIgnore), (0...200).contains(trimPadding),
              (0...128).contains(despeckleDiameter), (0...254).contains(despeckleThreshold),
              (1...3).contains(smoothPasses), (0...2).contains(resampleMethod) else {
            throw ProcessingError.message("页面或去斑参数超出范围。")
        }
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
