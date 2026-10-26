import Foundation
import Metal

@main
struct AccelerationBenchmark {
    static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Params { uint width,height,radius,vertical,sharpen; float amount,threshold; };
    kernel void filter(device const uchar *input [[buffer(0)]],device const uchar *base [[buffer(1)]],device uchar *output [[buffer(2)]],constant Params &p [[buffer(3)]],uint2 xy [[thread_position_in_grid]]) {
        if(xy.x>=p.width || xy.y>=p.height)return;
        const uint k1[3]={1,2,1};const uint k2[5]={1,4,6,4,1};uint sum=0;
        for(int d=-int(p.radius);d<=int(p.radius);++d){int x=p.vertical?int(xy.x):clamp(int(xy.x)+d,0,int(p.width)-1);int y=p.vertical?clamp(int(xy.y)+d,0,int(p.height)-1):int(xy.y);
            sum+=uint(input[uint(y)*p.width+uint(x)])*(p.radius==1?k1[d+1]:k2[d+2]);}
        uint divisor=p.radius==1?4:16;uint i=xy.y*p.width+xy.x;
        float soft=float((sum+divisor/2)/divisor);
        if(!p.vertical){output[i]=uchar(soft);return;}
        float original=base[i],delta=original-soft,value=original;
        if(p.sharpen){if(abs(delta)>=p.threshold)value=original+p.amount*delta;}
        else value=original+(soft-original)*p.amount;
        output[i]=uchar(clamp(floor(value+0.5f),0.0f,255.0f));
    }
    """
    struct Params { var width:UInt32,height:UInt32,radius:UInt32,vertical:UInt32,sharpen:UInt32;var amount:Float,threshold:Float }
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
        guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else { print("Metal evaluation: unavailable on this runner; no GPU speed/quality claim");return }
        let options=MTLCompileOptions();options.fastMathEnabled=false
        let library=try device.makeLibrary(source:shader,options:options)
        let pipeline=try device.makeComputePipelineState(function:library.makeFunction(name:"filter")!)
        var samples=[Double](),maximumDifference=0
        for trial in -1..<3 {
            let start=Date()
            guard let input=device.makeBuffer(bytes:source,length:count,options:.storageModeShared),let tmp=device.makeBuffer(length:count,options:.storageModeShared),let blur=device.makeBuffer(length:count,options:.storageModeShared),let output=device.makeBuffer(length:count,options:.storageModeShared),let commands=queue.makeCommandBuffer() else { fatalError("Metal allocation") }
            for pass in 0..<4 {
                guard let encoder=commands.makeComputeCommandEncoder() else { fatalError("Metal encoder") }
                encoder.setComputePipelineState(pipeline)
                let src=pass==0 ? input:pass==1 ? tmp:pass==2 ? blur:tmp
                let base=pass<2 ? input:blur
                let dst=pass==0 || pass==2 ? tmp:pass==1 ? blur:output
                encoder.setBuffer(src,offset:0,index:0);encoder.setBuffer(base,offset:0,index:1);encoder.setBuffer(dst,offset:0,index:2)
                var p=Params(width:UInt32(w),height:UInt32(h),radius:pass<2 ? 1:2,vertical:pass%2==1 ? 1:0,sharpen:pass<2 ? 0:1,amount:pass<2 ? 0.3:0.6,threshold:2)
                encoder.setBytes(&p,length:MemoryLayout<Params>.stride,index:3)
                encoder.dispatchThreads(MTLSize(width:w,height:h,depth:1),threadsPerThreadgroup:MTLSize(width:16,height:16,depth:1));encoder.endEncoding()
            }
            commands.commit();commands.waitUntilCompleted()
            guard commands.status == .completed else { throw commands.error ?? ProcessingError.message("Metal commands failed") }
            let copied=Array(UnsafeBufferPointer(start:output.contents().assumingMemoryBound(to:UInt8.self),count:count))
            let ms=Date().timeIntervalSince(start)*1000
            for i in 0..<count { maximumDifference=max(maximumDifference,abs(Int(copied[i])-Int(reference[i]))) }
            if trial>=0 { samples.append(ms) }
        }
        print(String(format:"17.78 MP Metal Gaussian+USM: %.1f ms including upload/allocation/download; max channel difference=%d; device=%@",samples.reduce(0,+)/Double(samples.count),maximumDifference,device.name))
    }
}
