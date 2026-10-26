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

    func validated() throws -> Settings {
        let floats = [brightness, contrast, gamma, whitePoint, sharpen, blur, scale, crop, quality]
        guard floats.allSatisfy({ $0.isFinite }), (-1...1).contains(brightness),
              (0...3).contains(contrast), (0.2...3).contains(gamma),
              (0.2...1).contains(whitePoint), (0...2).contains(sharpen),
              (0...1).contains(blur), (0.1...2).contains(scale), (0...0.2).contains(crop),
              [0,2,4,8,16,32,64,128,256].contains(levels), (0...3).contains(rotation),
              (0...2).contains(page), ["png", "jpg", "tiff"].contains(format),
              (0.1...1).contains(quality) else { throw ProcessingError.message("参数文件包含超出范围的值。") }
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
        return o
    }
}
