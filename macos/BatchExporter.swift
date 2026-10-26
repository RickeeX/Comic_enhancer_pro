import Foundation

struct BatchReport {
    struct Entry { let success:Bool;let message:String }
    let entries:[Entry?]
    let workers:Int
    var succeeded:Int { entries.compactMap{$0}.filter{$0.success}.count }
    var failed:Int { entries.compactMap{$0}.filter{!$0.success}.count }
    var completed:Int { entries.compactMap{$0}.count }
    var log:String { "Comic Enhancer operation-stack export; workers=\(workers)\n" + entries.compactMap{$0?.message}.joined() }
}
enum BatchExporter {
    // A deliberately conservative bound on RGBA fallbacks and filter scratch.
    // Complex legacy/layout stacks get the full 100 MP bound and stay serial.
    static func estimatedBytes(_ page:PageItem,recipe:Recipe) -> UInt64 {
        guard let info=try? Pipeline.sourceInfo(page),info.width>0,info.height>0,info.width<=100_000_000/info.height else { return 3_000_000_000 }
        var w=Double(info.width),h=Double(info.height),peak=w*h,x=info.dpiX ?? 300,y=info.dpiY ?? 300
        for stage in recipe.stages where stage.enabled {
            let s=stage.settings
            if stage.kind == .page || stage.kind == .layout { return 3_000_000_000 }
            if stage.kind == .resize {
                if s.sourceDPI>0 { x=s.sourceDPI;if s.sourceDPIY==0 { y=x } }
                if s.sourceDPIY>0 { y=s.sourceDPIY }
                if s.preservePhysical { w *= s.targetDPI/x;h *= s.targetDPI/y;x=s.targetDPI;y=s.targetDPI }
                else { w *= s.scale;h *= s.scale }
            }
            if stage.kind == .rotate && s.rotation%2==1 { swap(&w,&h);swap(&x,&y) }
            guard w.isFinite,h.isFinite,w>0,h>0,w*h<=100_000_000 else { return 3_000_000_000 }
            peak=max(peak,w*h)
        }
        return UInt64(Double(info.width)*Double(info.height)*4+peak*24+32_000_000)
    }
    static func workerCount(pages:[PageItem],recipes:[Recipe],memory:UInt64=ProcessInfo.processInfo.physicalMemory,cpus:Int=ProcessInfo.processInfo.activeProcessorCount) -> Int {
        guard pages.count>1,recipes.count==pages.count,cpus>=4 else { return 1 }
        let bound=zip(pages,recipes).map{estimatedBytes($0.0,recipe:$0.1)}.max() ?? UInt64.max
        let budget=min(UInt64(1_500_000_000),memory/5)
        return bound<=budget/2 ? 2:1
    }
    static func run(pages:[PageItem],recipes:[Recipe],indices:[Int],folder:URL,cancelled:@escaping ()->Bool,progress:@escaping (Int)->Void,workers requestedWorkers:Int?=nil) -> BatchReport {
        guard recipes.count==pages.count,indices.count==pages.count else { return BatchReport(entries:[],workers:1) }
        let workers=min(max(1,requestedWorkers ?? workerCount(pages:pages,recipes:recipes)),min(2,max(1,pages.count)))
        let cap=max(1,min(8,ProcessInfo.processInfo.activeProcessorCount/workers))
        let names=pages.indices.map{recipes[$0].filename(index:indices[$0],page:pages[$0])}
        var first:[String:Int]=[:],duplicates=Set<Int>()
        for (i,name) in names.enumerated() { if first[name] != nil { duplicates.insert(i) } else { first[name]=i } }
        let lock=NSLock();var next=0,done=0,entries=[BatchReport.Entry?](repeating:nil,count:pages.count)
        DispatchQueue.concurrentPerform(iterations:workers) { _ in
            let old=ce_set_thread_budget(Int32(cap));defer { _ = ce_set_thread_budget(old) }
            let workspace=try? GrayWorkspace()
            while true {
                lock.lock()
                if next>=pages.count || cancelled() { lock.unlock();break }
                let index=next;next += 1;lock.unlock()
                let entry:BatchReport.Entry?=autoreleasepool {
                    let page=pages[index],config=recipes[index],name=names[index]
                    do {
                        if cancelled() { throw CancellationError() }
                        let destination=folder.appendingPathComponent(name)
                        guard !duplicates.contains(index),!FileManager.default.fileExists(atPath:destination.path) else { throw ProcessingError.message("输出名称冲突："+name) }
                        let value=try Pipeline.render(page,recipe:config,preview:false,pageIndex:indices[index],cancelled:cancelled,materialize:false,grayWorkspace:workspace)
                        if cancelled() { throw CancellationError() }
                        try Pipeline.write(value,to:destination,recipe:config)
                        return BatchReport.Entry(success:true,message:"OK\t\(page.path)\t\(name)\t\(value.description)\n")
                    } catch is CancellationError { return nil }
                    catch { return BatchReport.Entry(success:false,message:"ERROR\t\(page.path)\t\(error.localizedDescription)\n") }
                }
                lock.lock();entries[index]=entry;if entry != nil { done += 1 };let count=done;lock.unlock()
                progress(count)
            }
        }
        return BatchReport(entries:entries,workers:workers)
    }
}
