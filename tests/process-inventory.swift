// Measure real local inventory collection and cancellation without printing process identities.
// Run: bash scripts/verify-process-inventory.sh
// Requires the built telemetry object and macOS AppKit.
import AppKit
@main struct InventoryCheck {
    static func main(){
        let collector=DiagnosticCollector();let baseline=ts_resources(),start=ProcessInfo.processInfo.systemUptime
        var peak=baseline.footprint,completed=0,count=0,cancelledDelivered=false
        func spin(_ done:()->Bool){let limit=Date().addingTimeInterval(15);while !done() && Date()<limit{RunLoop.current.run(until:Date().addingTimeInterval(0.02));peak=max(peak,ts_resources().footprint)};precondition(done(),"inventory did not complete")}
        collector.collect(snapshot:Snapshot(),at:Date(),allProcesses:true){_ in cancelledDelivered=true};collector.cancel()
        for _ in 0..<3 {
            var finished=false
            collector.collect(snapshot:Snapshot(),at:Date(),allProcesses:true){result in
                let e=try! result.get();precondition(e.processes.count==e.readable && e.readable<=4096)
                precondition(Set(e.processes.map{$0.id}).count==e.processes.count)
                count=e.readable;completed+=1;finished=true
            };spin{finished}
        }
        precondition(!cancelledDelivered)
        let end=ts_resources()
        print(String(format:"PASS inventory: cycles=%d readable=%d wall=%.3fs cpu=%.3fs sampled_peak_footprint=%.2fMiB",completed,count,ProcessInfo.processInfo.systemUptime-start,end.cpu_seconds-baseline.cpu_seconds,peak/1048576))
    }
}
