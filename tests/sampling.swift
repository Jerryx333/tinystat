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
        precondition(a["process_samples"] as! Int == 0 && a["gpu_samples"] as! Int == 1)
        demand.visible=true;demand.page = .details
        let initial=sampler.sample(demand)
        precondition(!initial.rankingReady)
        precondition(sampler.counters()["temperature_group_reads"] as! Int == 3) // closed CPU, then fresh visible CPU + GPU
        let basicCount=sampler.counters()["basic_samples"] as! Int
        let temperatureCount=sampler.counters()["temperature_group_reads"] as! Int
        let gpuCount=sampler.counters()["gpu_samples"] as! Int
        let rapid=sampler.sample(demand)
        precondition(rapid.history.count == initial.history.count)
        precondition(sampler.counters()["basic_samples"] as! Int == basicCount)
        precondition(sampler.counters()["process_samples"] as! Int == 1)
        precondition(sampler.counters()["gpu_samples"] as! Int == gpuCount)
        precondition(sampler.counters()["temperature_group_reads"] as! Int == temperatureCount)
        // Simulate an early/manual refresh within the timer period.
        Thread.sleep(forTimeInterval:1.1)
        let second=sampler.sample(demand)
        precondition(sampler.counters()["temperature_group_reads"] as! Int == temperatureCount + 2)
        precondition(bytes(gib) == "1.0 GiB" && bytes(1_048_576) == "1 MiB")
        precondition(second.rankingReady && second.rows.count<=5)
        sampler.resetDetails()
        let reopened=sampler.sample(demand)
        precondition(!reopened.rankingReady)
        demand.rank = .memory
        let memory=sampler.sample(demand)
        precondition(memory.rankingReady && memory.rows.count>0)
        demand.page = .overview
        let overview=sampler.sample(demand)
        precondition(overview.rows.isEmpty && !overview.rankingReady && overview.coverage.read == 0)
        let overviewCounts=sampler.counters()
        _=sampler.sample(demand)
        precondition(sampler.counters()["process_samples"] as! Int == overviewCounts["process_samples"] as! Int)
        precondition(sampler.counters()["gpu_samples"] as! Int == overviewCounts["gpu_samples"] as! Int)
        demand.page = .details
        let memoryReopened=sampler.sample(demand)
        precondition(memoryReopened.rankingReady && !memoryReopened.rows.isEmpty)
        demand.visible=false
        let closed=sampler.sample(demand)
        precondition(closed.rows.isEmpty && closed.coverage.read == 0)
        let counts=sampler.counters()
        _=sampler.sample(demand)
        precondition(sampler.counters()["process_samples"] as! Int == counts["process_samples"] as! Int)
        precondition(sampler.counters()["gpu_samples"] as! Int == counts["gpu_samples"] as! Int)
        precondition(first.history.count==0)
        precondition(first.metricHistory.count==1)
        precondition(first.metricHistory[0].gpu==(first.gpu?.valid == true ? first.gpu?.percent:nil))
        Thread.sleep(forTimeInterval:1.1)
        let background=sampler.sample(demand)
        precondition(sampler.counters()["gpu_samples"] as! Int == (counts["gpu_samples"] as! Int)+1)
        precondition(background.metricHistory.last!.gpu==(background.gpu?.valid == true ? background.gpu?.percent:nil))
        let retained=background.metricHistory.count
        demand.visible=true
        let reveal=sampler.sample(demand)
        precondition(reveal.metricHistory.count>=retained,"opening must retain background history")
        demand.visible=true;demand.page = .overview;demand.inspection = .memory;demand.rank = .memory
        let inspected=sampler.sample(demand)
        precondition(inspected.rankingReady && !inspected.rows.isEmpty)
        demand.inspection=nil
        let dismissed=sampler.sample(demand)
        precondition(dismissed.rows.isEmpty && dismissed.coverage.read==0)
        precondition(dismissed.metricHistory.count<=128)
        demand.visible=false
        sampler.reset()
        let reset=sampler.sample(demand)
        precondition(!reset.basic.cpu_valid && !reset.basic.swap_rate_valid && reset.history.isEmpty && reset.gpuTemperature == nil && reset.coverage.read == 0)
        ts_close()
        print("Sampling gates, short intervals, reopen, rank switch and reset: PASS")
    }
}
