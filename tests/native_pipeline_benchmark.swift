import AppKit
import Foundation
import ImageIO

// Uses only APIs present in v0.4.2, so the exact same harness can be compiled
// against both revisions. Synthetic gray source; no uploaded book pages in CI.
@main
struct NativePipelineBenchmark {
    static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:root) }
        let w=1672,h=2658
        var values=Data(count:w*h)
        values.withUnsafeMutableBytes { (p:UnsafeMutableRawBufferPointer) in
            for y in 0..<h { for x in 0..<w { p[y*w+x]=UInt8((x%19<3 && y%31<13 ? 35:180)+(x*17+y*31)%35) } }
        }
        let provider=CGDataProvider(data:values as CFData)!
        let image=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.none.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        var inputSettings=Settings();inputSettings.format="jpg"
        let source=root.appendingPathComponent("scan.jpg")
        // Avoid assuming the old writer accepts an already-gray provider when
        // grayscale packing is requested: default Settings is RGB-tag neutral.
        try Processor.write(image,to:source,settings:inputSettings,dpiX:300,dpiY:300)
        var resize=Stage(.resize);resize.settings.preservePhysical=true;resize.settings.sourceDPI=300;resize.settings.targetDPI=600
        var tone=Stage(.tone);tone.settings.brightness=0.04;tone.settings.contrast=1.1;tone.settings.gamma=1.1
        var blur=Stage(.blur);blur.settings.blur=0.3;blur.settings.filterRadius=1
        var usm=Stage(.sharpen);usm.settings.sharpen=0.6;usm.settings.filterRadius=2;usm.settings.sharpenThreshold=2
        var binary=Stage(.binary);binary.settings.binarization=3;binary.settings.edgeSmooth=true;binary.settings.fillNotches=true
        let recipe=Recipe(stages:[resize,tone,blur,usm,binary])
        var processing=[Double](),encoding=[Double]();var fingerprint:UInt64=0
        for trial in -1..<3 {
            try autoreleasepool {
                let start=Date();let result=try Pipeline.render(PageItem(url:source),recipe:recipe,preview:false)
                let rendered=Date()
                try Pipeline.write(result,to:root.appendingPathComponent("result.png"),recipe:recipe)
                let end=Date()
                if trial>=0 { processing.append(rendered.timeIntervalSince(start)*1000);encoding.append(end.timeIntervalSince(rendered)*1000) }
                precondition(result.image.width==w*2 && result.image.height==h*2)
                let pixels=result.image.dataProvider!.data! as Data
                var hash:UInt64=14695981039346656037
                for value in pixels { hash=(hash ^ UInt64(value)) &* 1099511628211 }
                if trial>0 { precondition(hash==fingerprint,"Nondeterministic native pixels") }
                fingerprint=hash
            }
        }
        print(String(format:"17.78 MP full native 2x+tone+Gaussian+USM+Sauvola+edge: %.1f ms; PNG encode: %.1f ms",processing.reduce(0,+)/Double(processing.count),encoding.reduce(0,+)/Double(encoding.count)))
        print("Native pixel fingerprint: \(String(fingerprint,radix:16))")
    }
}
