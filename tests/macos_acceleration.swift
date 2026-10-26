import Foundation
import Metal

@main
struct AccelerationBenchmark {
    static func main() throws {
        let w=3344,h=5316,count=w*h
        var source=[UInt8](repeating:255,count:count)
        for y in 0..<h { for x in 0..<w { source[y*w+x]=UInt8((x%19<3 && y%31<13 ? 35:180)+(x*17+y*31)%35) } }
        var reference:[UInt8]=[]
        for backend in [1,2] {
            guard let ws=ce_gray_workspace_create() else { fatalError("workspace allocation") };defer { ce_gray_workspace_destroy(ws) }
            ce_gray_workspace_backend(ws,Int32(backend))
            var samples=[Double]()
            for trial in -1..<3 {
                var a=[UInt8](repeating:0,count:count),b=a
                var blur=ce_defaults();blur.blur=0.3;blur.filter_radius=1
                var usm=ce_defaults();usm.sharpen=0.6;usm.filter_radius=2;usm.sharpen_threshold=2
                let start=Date()
                let first=source.withUnsafeBufferPointer { p in a.withUnsafeMutableBufferPointer { out in ce_process_gray(p.baseAddress,UInt32(w),UInt32(h),&blur,out.baseAddress,out.count,ws) } }
                let second=a.withUnsafeBufferPointer { p in b.withUnsafeMutableBufferPointer { out in ce_process_gray(p.baseAddress,UInt32(w),UInt32(h),&usm,out.baseAddress,out.count,ws) } }
                guard first==0,second==0 else { fatalError("gray backend failed") }
                let elapsed=Date().timeIntervalSince(start)*1000
                if trial>=0 { samples.append(elapsed) }
                if backend==1 { reference=b } else { guard b==reference else { fatalError("Accelerate changed filter pixels") } }
            }
            print(String(format:"17.78 MP Gray8 %@ Gaussian+USM mean: %.1f ms",backend==1 ? "portable":"vImage candidate",samples.reduce(0,+)/Double(samples.count)))
        }
        guard let metal=MetalFilters.shared else { print("Metal evaluation: unavailable on this runner; no GPU speed/quality claim");return }
        let plane=try GrayPlane(width:w,height:h) { out in out.baseAddress!.update(from:source,count:count) }
        var blur=Settings();blur.blur=0.3;blur.filterRadius=1
        var usm=Settings();usm.sharpen=0.6;usm.filterRadius=2;usm.sharpenThreshold=2
        var samples=[Double](),maximumDifference=0
        for trial in -1..<3 {
            let start=Date(),result=try metal.run(plane,blur:blur,usm:usm)
            let ms=Date().timeIntervalSince(start)*1000
            result.withBytes { bytes in for i in 0..<count { maximumDifference=max(maximumDifference,abs(Int(bytes[i])-Int(reference[i]))) } }
            if trial>=0 { samples.append(ms) }
        }
        guard maximumDifference==0 else { fatalError("Production Metal changed filter pixels") }
        let workspace=try GrayWorkspace()
        if let result=try metal.automatic(plane,blur:blur,usm:usm,workspace:workspace) {
            guard result.data as Data == Data(reference) else { fatalError("Automatic backend changed pixels") }
        }
        print(String(format:"17.78 MP Metal Gaussian+USM: %.1f ms including upload/allocation/download/LUT; max channel difference=%d; device=%@",samples.reduce(0,+)/Double(samples.count),maximumDifference,metal.device.name))
        print("Metal automatic decision: \(metal.decisionDescription)")
    }
}
