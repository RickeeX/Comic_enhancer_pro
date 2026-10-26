import AppKit
import ImageIO

final class GrayWorkspace {
    let core: OpaquePointer
    init() throws {
        guard let core=ce_gray_workspace_create() else { throw ProcessingError.message("无法分配灰度工作区。") }
        self.core=core
    }
    func trim() { withExtendedLifetime(self) { ce_gray_workspace_trim(core,64*1024*1024) } }
    deinit { ce_gray_workspace_destroy(core) }
}
// Immutable normalized sRGB values. Every unsafe C/GPU read explicitly borrows
// its owner until the operation completes; a raw pointer alone does not retain it.
final class GrayPlane {
    let width:Int,height:Int,data:CFData
    private let displayLock=NSLock()
    private var display:CGImage?
    init(width:Int,height:Int,fill:(UnsafeMutableBufferPointer<UInt8>) throws -> Void) throws {
        try Pipeline.checkSize(width,height)
        let count=width*height
        guard let memory=malloc(count) else { throw ProcessingError.message("无法分配灰度位图。") }
        var owned=true
        defer { if owned { free(memory) } }
        try fill(UnsafeMutableBufferPointer(start:memory.assumingMemoryBound(to:UInt8.self),count:count))
        guard let data=CFDataCreateWithBytesNoCopy(kCFAllocatorDefault,memory.assumingMemoryBound(to:UInt8.self),count,kCFAllocatorMalloc)
        else { throw ProcessingError.message("无法创建灰度数据。") }
        owned=false;self.width=width;self.height=height;self.data=data
    }
    func withBytes<T>(_ body:(UnsafePointer<UInt8>) throws -> T) rethrows -> T {
        try withExtendedLifetime(data) { try body(CFDataGetBytePtr(data)!) }
    }
    func hasSamePixels(as other:GrayPlane) -> Bool {
        guard width==other.width,height==other.height else { return false }
        return withBytes { lhs in other.withBytes { rhs in memcmp(lhs,rhs,width*height)==0 } }
    }
    static func normalized(_ image:CGImage) throws -> GrayPlane? {
        var status:Int32=0
        let plane=try GrayPlane(width:image.width,height:image.height) { out in
            status=try Processor.withRGBA(image) { ce_gray_from_rgba($0,UInt32(image.width),UInt32(image.height),out.baseAddress,out.count) }
        }
        if status == -5 { return nil }
        guard status==0 else { throw ProcessingError.message("灰度转换失败（\(status)）。") }
        return plane
    }
    func rgbaImage() throws -> CGImage {
        displayLock.lock();defer { displayLock.unlock() }
        if let image=display { return image }
        let image=try withBytes { bytes in try Processor.makeRGBAImage(width:width,height:height) { out in
            guard ce_gray_to_rgba(bytes,UInt32(width),UInt32(height),out.baseAddress,out.count)==0 else { throw ProcessingError.message("灰度显示转换失败。") }
        } }
        display=image;return image
    }
    func process(_ settings:Settings,workspace:GrayWorkspace) throws -> GrayPlane? {
        var o=settings.core
        guard ce_gray_supported(&o) != 0 else { return nil }
        var w:UInt32=0,h:UInt32=0
        guard ce_dimensions(UInt32(width),UInt32(height),&o,&w,&h)==0 else { throw ProcessingError.message("灰度输出尺寸无效。") }
        return try withExtendedLifetime(workspace) { try withBytes { bytes in
            try GrayPlane(width:Int(w),height:Int(h)) { out in
                let status=ce_process_gray(bytes,UInt32(width),UInt32(height),&o,out.baseAddress,out.count,workspace.core)
                guard status==0 else { throw ProcessingError.message("灰度处理失败（\(status)）。") }
            }
        } }
    }
    func editing(_ operation:(UnsafeMutableBufferPointer<UInt8>) throws -> Void) throws -> GrayPlane {
        try withBytes { bytes in try GrayPlane(width:width,height:height) { out in
            out.baseAddress!.update(from:bytes,count:out.count);try operation(out)
        } }
    }
    func cropped(_ rect:CGRect) throws -> GrayPlane {
        let x=Int(rect.minX),y=Int(rect.minY),w=Int(rect.width),h=Int(rect.height)
        return try withBytes { bytes in try GrayPlane(width:w,height:h) { out in
            for row in 0..<h { out.baseAddress!.advanced(by:row*w).update(from:bytes.advanced(by:(row+y)*width+x),count:w) }
        } }
    }
    func resized(width w:Int,height h:Int,rect:[Float],method:Int,clip:[Float]?) throws -> GrayPlane {
        try withBytes { bytes in try GrayPlane(width:w,height:h) { out in
            let status=rect.withUnsafeBufferPointer { ce_canvas_gray(bytes,UInt32(width),UInt32(height),UInt32(w),UInt32(h),$0.baseAddress,Int32(method),out.baseAddress,out.count) }
            guard status==0 else { throw ProcessingError.message("灰度排版失败（\(status)）。") }
            if let clip=clip {
                let status=clip.withUnsafeBufferPointer { ce_whiten_outside_gray(out.baseAddress,UInt32(w),UInt32(h),$0.baseAddress) }
                guard status==0 else { throw ProcessingError.message("灰度版心裁切失败。") }
            }
        } }
    }
    func exportImage(bits:Int) throws -> CGImage {
        let stride=(width*bits+7)/8
        let raw:CFData
        if bits==8 { raw=data }
        else {
            var packed=Data(count:stride*height)
            let status=withBytes { bytes in packed.withUnsafeMutableBytes { (out:UnsafeMutableRawBufferPointer) in
                ce_gray_pack(bytes,UInt32(width),UInt32(height),Int32(bits),out.baseAddress?.assumingMemoryBound(to:UInt8.self),out.count)
            } }
            guard status==0 else { throw ProcessingError.message("灰度位深打包失败。") };raw=packed as CFData
        }
        guard let provider=CGDataProvider(data:raw),let image=CGImage(width:width,height:height,bitsPerComponent:bits,bitsPerPixel:bits,bytesPerRow:stride,
            space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.none.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)
        else { throw ProcessingError.message("创建灰度输出失败。") }
        return image
    }
}
