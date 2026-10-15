// Verify actual sampler demand transitions and delta throttling.
// Run: bash scripts/verify.sh
// Requires Apple SDK; no private process data is printed.
import Foundation
@main struct Verify {
    static func main() {
        let sampler=Sampler()
        var demand=Demand()
        let first=sampler.sample(demand)
        precondition(!first.basic.swap_rate_valid)
        let a=sampler.counters()
        precondition(a["process_samples"] as! Int == 0 && a["gpu_samples"] as! Int == 0)
        demand.visible=true;demand.page = .details
        let initial=sampler.sample(demand)
        precondition(!initial.rankingReady)
        let basicCount=sampler.counters()["basic_samples"] as! Int
        let gpuCount=sampler.counters()["gpu_samples"] as! Int
        let rapid=sampler.sample(demand)
        precondition(rapid.history.count == initial.history.count)
        precondition(sampler.counters()["basic_samples"] as! Int == basicCount)
        precondition(sampler.counters()["process_samples"] as! Int == 1)
        precondition(sampler.counters()["gpu_samples"] as! Int == gpuCount)
        Thread.sleep(forTimeInterval:1.1)
        let second=sampler.sample(demand)
        precondition(second.rankingReady && second.rows.count<=5)
        sampler.resetDetails()
        let reopened=sampler.sample(demand)
        precondition(!reopened.rankingReady)
        demand.rank = .memory
        let memory=sampler.sample(demand)
        precondition(memory.rankingReady && memory.rows.count>0)
        demand.visible=false
        _=sampler.sample(demand)
        let counts=sampler.counters()
        _=sampler.sample(demand)
        precondition(sampler.counters()["process_samples"] as! Int == counts["process_samples"] as! Int)
        precondition(sampler.counters()["gpu_samples"] as! Int == counts["gpu_samples"] as! Int)
        precondition(first.history.count==0)
        sampler.reset()
        let reset=sampler.sample(demand)
        precondition(!reset.basic.cpu_valid && !reset.basic.swap_rate_valid && reset.history.isEmpty && reset.gpu == nil && reset.coverage.read == 0)
        ts_close()
        print("Sampling gates, short intervals, reopen, rank switch and reset: PASS")
    }
}
