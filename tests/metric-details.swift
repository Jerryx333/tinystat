// Verify native inspector rendering and hit regions with synthetic values.
// Run: bash scripts/verify-metric-details.sh after scripts/build.sh.
// Requires macOS AppKit; no model requests or process actions.
import AppKit
@main struct DetailCheck {
    static func main(){
        _=NSApplication.shared
        let dashboard=Dashboard(frame:NSRect(x:0,y:0,width:440,height:426))
        precondition(dashboard.metric(at:NSPoint(x:70,y:150)) == .cpu)
        precondition(dashboard.metric(at:NSPoint(x:210,y:150)) == .gpu)
        precondition(dashboard.metric(at:NSPoint(x:345,y:150)) == .memory)
        precondition(dashboard.metric(at:NSPoint(x:60,y:285)) == nil)
        dashboard.page = .settings;dashboard.configure();precondition(dashboard.metric(at:NSPoint(x:70,y:150)) == nil)
        precondition(dashboard.toolTip==nil)
        let view=MetricDetails(frame:NSRect(x:0,y:0,width:344,height:510))
        var s=Snapshot();s.basic.cpu_valid=true;s.basic.user=24;s.basic.system=8
        s.basic.memory_valid=true;s.basic.total=32*gib;s.basic.used=24*gib;s.basic.app=12*gib;s.basic.wired=4*gib;s.basic.compressed=8*gib
        let now=ProcessInfo.processInfo.systemUptime
        for i in 0..<60 {
            let time=now-Double(59-i)*2
            let gpu:Double?=i%5==0 ? nil:Double(i%20)
            s.metricHistory.append(MetricPoint(time:time,cpu:Double(20+i%30),gpu:gpu,memory:Double(60+i%15)))
        }
        s.rows=[ProcessRow(pid:123,name:"Synthetic process",value:42)];s.rankingReady=true
        for metric in [Metric.cpu,.gpu,.memory]{
            view.metric=metric;view.update(s,at:Date())
            guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{fatalError("No inspector backing")}
            view.cacheDisplay(in:view.bounds,to:bitmap)
            let data=bitmap.representation(using:.png,properties:[:])!
            try! data.write(to:URL(fileURLWithPath:"build/inspector-\(metric.rawValue).png"))
        }
        print("PASS: CPU/GPU/memory native inspector rendering, hit regions, settings exclusion, no blocking tooltip")
    }
}
