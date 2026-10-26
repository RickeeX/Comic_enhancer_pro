import Foundation
import Metal

// Exact integer binomial passes; CPU-generated blend tables preserve the
// existing float rounding for every possible original/blurred byte pair.
final class MetalFilters {
    static let availability:Result<MetalFilters,Error> = Result { try MetalFilters() }
    static var shared:MetalFilters? { try? availability.get() }
    let device:MTLDevice
    private let queue:MTLCommandQueue,pipeline:MTLComputePipelineState
    private let lock=NSLock()
    private var choices:[String:Bool]=[:]
    private var validated=false
    private static let shader="""
    #include <metal_stdlib>
    using namespace metal;
    struct Params { uint width,height,radius,vertical; };
    kernel void filter(device const uchar *input [[buffer(0)]],device const uchar *base [[buffer(1)]],device uchar *output [[buffer(2)]],constant Params &p [[buffer(3)]],device const uchar *blend [[buffer(4)]],uint2 xy [[thread_position_in_grid]]) {
        if(xy.x>=p.width || xy.y>=p.height)return;
        const uint k1[3]={1,2,1};const uint k2[5]={1,4,6,4,1};const uint k3[7]={1,6,15,20,15,6,1};uint sum=0;
        for(int d=-int(p.radius);d<=int(p.radius);++d){int x=p.vertical?int(xy.x):clamp(int(xy.x)+d,0,int(p.width)-1);int y=p.vertical?clamp(int(xy.y)+d,0,int(p.height)-1):int(xy.y);
            sum+=uint(input[uint(y)*p.width+uint(x)])*(p.radius==1?k1[d+1]:p.radius==2?k2[d+2]:k3[d+3]);}
        uint divisor=1u<<(2u*p.radius),i=xy.y*p.width+xy.x,soft=(sum+divisor/2u)/divisor;
        output[i]=p.vertical?blend[uint(base[i])*256u+soft]:uchar(soft);
    }
    """
    private struct Params { var width:UInt32,height:UInt32,radius:UInt32,vertical:UInt32 }
    private init() throws {
        guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else { throw ProcessingError.message("此设备未提供 Metal 计算设备。") }
        let options=MTLCompileOptions();options.fastMathEnabled=false
        let library=try device.makeLibrary(source:Self.shader,options:options)
        guard let function=library.makeFunction(name:"filter") else { throw ProcessingError.message("无法创建 Metal 滤镜。") }
        self.device=device;self.queue=queue;self.pipeline=try device.makeComputePipelineState(function:function)
    }
    func run(_ source:GrayPlane,blur:Settings,usm:Settings) throws -> GrayPlane {
        guard (1...3).contains(blur.filterRadius),(1...3).contains(usm.filterRadius),blur.blurMethod==0,usm.sharpenMethod==0 else { throw ProcessingError.message("Metal 滤镜配置不适用。") }
        return try autoreleasepool {
            let count=source.width*source.height
            guard let input=device.makeBuffer(bytes:source.bytes,length:count,options:.storageModeShared),let tmp=device.makeBuffer(length:count,options:.storageModeShared),let blurred=device.makeBuffer(length:count,options:.storageModeShared),let output=device.makeBuffer(length:count,options:.storageModeShared),let bLUT=device.makeBuffer(length:65536,options:.storageModeShared),let sLUT=device.makeBuffer(length:65536,options:.storageModeShared),let commands=queue.makeCommandBuffer() else { throw ProcessingError.message("Metal 位图分配失败。") }
            guard ce_gray_blend_table(Float(blur.blur),0,0,bLUT.contents().assumingMemoryBound(to:UInt8.self),65536)==0,
                ce_gray_blend_table(Float(usm.sharpen),Float(usm.sharpenThreshold),1,sLUT.contents().assumingMemoryBound(to:UInt8.self),65536)==0 else { throw ProcessingError.message("Metal 参数无效。") }
            for pass in 0..<4 {
                guard let encoder=commands.makeComputeCommandEncoder() else { throw ProcessingError.message("Metal 命令创建失败。") }
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(pass==0 ? input:pass==1 ? tmp:pass==2 ? blurred:tmp,offset:0,index:0)
                encoder.setBuffer(pass<2 ? input:blurred,offset:0,index:1)
                encoder.setBuffer(pass==0 || pass==2 ? tmp:pass==1 ? blurred:output,offset:0,index:2)
                var p=Params(width:UInt32(source.width),height:UInt32(source.height),radius:UInt32(pass<2 ? blur.filterRadius:usm.filterRadius),vertical:pass%2==1 ? 1:0)
                encoder.setBytes(&p,length:MemoryLayout<Params>.stride,index:3)
                encoder.setBuffer(pass<2 ? bLUT:sLUT,offset:0,index:4)
                let groupWidth=min(16,pipeline.threadExecutionWidth),groupHeight=min(16,max(1,pipeline.maxTotalThreadsPerThreadgroup/groupWidth))
                encoder.dispatchThreads(MTLSize(width:source.width,height:source.height,depth:1),threadsPerThreadgroup:MTLSize(width:groupWidth,height:groupHeight,depth:1));encoder.endEncoding()
            }
            commands.commit();commands.waitUntilCompleted()
            guard commands.status == .completed else { throw commands.error ?? ProcessingError.message("Metal 计算失败。") }
            return try GrayPlane(width:source.width,height:source.height) { out in out.baseAddress!.update(from:output.contents().assumingMemoryBound(to:UInt8.self),count:count) }
        }
    }
    // One exact canary suite before GPU use. Actual settings use their own
    // exhaustive byte-pair LUT; small/odd dimensions exercise boundary handling.
    private func validate() throws {
        let ws=try GrayWorkspace();ce_gray_workspace_backend(ws.core,1)
        for (w,h) in [(1,1),(2,3),(17,19)] { for radius in 1...3 {
            let source=try GrayPlane(width:w,height:h) { out in for i in 0..<out.count { out[i]=UInt8((i*71+radius*31)%256) } }
            var blur=Settings();blur.blur=0.37;blur.filterRadius=radius
            var usm=Settings();usm.sharpen=1.13;usm.filterRadius=4-radius;usm.sharpenThreshold=2
            let cpu=try source.process(blur,workspace:ws)!.process(usm,workspace:ws)!
            let gpu=try run(source,blur:blur,usm:usm)
            guard cpu.data as Data == gpu.data as Data else { throw ProcessingError.message("Metal 像素校验未通过。") }
        } }
    }
    var decisionDescription:String {
        lock.lock();defer { lock.unlock() }
        return choices.sorted{$0.key<$1.key}.map{"\($0.key)=\($0.value ? "Metal":"CPU")"}.joined(separator:", ")
    }
    func automatic(_ source:GrayPlane,blur:Settings,usm:Settings,workspace:GrayWorkspace) throws -> GrayPlane? {
        guard source.width*source.height>=4_000_000 else { return nil }
        let key="\(ce_get_thread_budget())-\(source.width*source.height>=16_000_000)-\(blur.filterRadius)-\(usm.filterRadius)"
        lock.lock()
        if let enabled=choices[key] {
            lock.unlock();if !enabled { return nil }
            do { return try run(source,blur:blur,usm:usm) }
            catch { lock.lock();choices[key]=false;lock.unlock();return nil }
        }
        defer { lock.unlock() }
        // Calibrate on this device and page size. The CPU output also supplies
        // an exact fallback without recomputing the first candidate pair.
        let start=Date()
        guard let first=try source.process(blur,workspace:workspace),let cpu=try first.process(usm,workspace:workspace) else { choices[key]=false;return nil }
        let cpuTime=Date().timeIntervalSince(start)
        do {
            if !validated { try validate();validated=true }
            let begin=Date(),gpu=try run(source,blur:blur,usm:usm)
            let gpuTime=Date().timeIntervalSince(begin)
            guard cpu.data as Data == gpu.data as Data else { choices[key]=false;return cpu }
            let enabled=gpuTime<cpuTime*0.85
            choices[key]=enabled;return enabled ? gpu:cpu
        } catch { choices[key]=false;return cpu }
    }
}
