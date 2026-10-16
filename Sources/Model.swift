import Foundation
import AppKit

let gib = 1_073_741_824.0
func bytes(_ value: Double) -> String { value >= gib ? String(format: "%.1f GiB", value / gib) : String(format: "%.0f MiB", value / 1_048_576) }
func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "—" }
func temperature(_ value: TSTemperature?) -> String {
    guard let v = value else { return "—" }; guard v.found > 0, v.maximum.isFinite else { return "不可用" }
    return String(format: "%.0f°C", v.maximum) + (v.found < v.expected ? "*" : "")
}
enum Metric:String {case cpu,gpu,memory}
struct MetricPoint {let time:Double;let cpu:Double?;let gpu:Double?;let memory:Double?}
enum Page: String { case overview, details, settings }
enum Rank: String { case cpu, memory }
enum RefreshCadence {
    static let opened=2.0
    static let closed=5.0
}
struct Demand: Equatable {
    var visible = false
    var page = Page.overview
    var rank = Rank.cpu
    var advanced = false
    var inspection:Metric?
    var processes: Bool { visible && (page == .details || inspection == .cpu || inspection == .memory) }
    var gpuTemperature: Bool { visible && page != .settings }
    var cores: Bool { processes && (advanced || inspection == .cpu) }
}
struct HistoryPoint { let time: Double; let user: Double; let system: Double }
struct ProcessRow { let pid: Int32; let name: String; let value: Double }
struct ProcessIdentity: Hashable { let pid: Int32; let start: UInt64 }
struct CPUCounter { let cpu: UInt64; let time: Double }
struct Snapshot {
    var basic = TSBasic()
    var gpu: TSGPU?
    var cpuTemperature: TSTemperature?
    var gpuTemperature: TSTemperature?
    var history: [HistoryPoint] = []
    var metricHistory:[MetricPoint]=[]
    var rows: [ProcessRow] = []
    var coverage = TSProcessCoverage()
    var rankingReady = false
    var thermal = ProcessInfo.ThermalState.nominal
    var highLoadCount = 0
    var cpu: Double? { basic.cpu_valid ? basic.user + basic.system : nil }
    var memoryPercent: Double? { basic.memory_valid && basic.total > 0 ? basic.used / basic.total * 100 : nil }
    var pressure: String {
        guard basic.pressure_valid else { return "压力未知" }
        switch basic.pressure { case 1: return "压力正常"; case 2: return "内存吃紧"; case 4: return "压力严重"; default: return "压力未知" }
    }
    var pressureColor: NSColor { basic.pressure_valid ? (basic.pressure == 4 ? .systemRed : basic.pressure == 2 ? .systemOrange : .systemTeal) : .secondaryLabelColor }
    var health: (String, NSColor) {
        if thermal == .critical || thermal == .serious { return ("散热压力严重", .systemRed) }
        if basic.pressure_valid && basic.pressure == 4 { return ("内存压力严重", .systemRed) }
        if thermal == .fair { return ("散热压力升高", .systemOrange) }
        if basic.pressure_valid && basic.pressure == 2 { return ("内存吃紧", .systemOrange) }
        if !basic.cpu_valid || !basic.memory_valid || !basic.pressure_valid || ![1,2,4].contains(basic.pressure) { return ("部分数据不可用", .secondaryLabelColor) }
        if highLoadCount >= 3 { return ("CPU 持续繁忙", .systemOrange) }
        return ("运行正常", .systemTeal)
    }
}

// All mutable telemetry ownership lives on one serial utility queue.
final class Sampler {
    private var state = Snapshot()
    private var lastBasicDate = -Double.infinity
    private var lastProcessDate = -Double.infinity
    private var raw: [TSProcess] = []
    private var previous: [ProcessIdentity: CPUCounter] = [:]
    private var priorDemand = Demand()
    private var highLoadSince: Double?
    private(set) var basicSamples = 0
    private(set) var samples = 0
    private(set) var processSamples = 0
    private(set) var gpuSamples = 0
    private(set) var temperatureSamples = 0
    private(set) var sampleCPU = 0.0

    private func clearProcesses() {
        raw.removeAll();previous.removeAll();state.rows.removeAll()
        state.rankingReady = false; state.coverage = TSProcessCoverage(); lastProcessDate = -.infinity
    }
    func resetDetails() {
        clearProcesses();priorDemand = Demand()
    }
    func reset() {
        ts_reset(); resetDetails(); state = Snapshot(); highLoadSince=nil
        lastBasicDate = -.infinity
    }
    func sample(_ demand: Demand, forceReadings:Bool=false) -> Snapshot {
        let start = ProcessInfo.processInfo.systemUptime
        samples += 1
        if !demand.processes {
            clearProcesses()
        } else if demand.rank != priorDemand.rank || !priorDemand.processes {
            previous.removeAll(keepingCapacity: true); state.rows.removeAll(keepingCapacity: true)
            state.rankingReady = false; lastProcessDate = -.infinity
        }
        // User interaction may request an immediate update; never turn a few CPU ticks into a new rate.
        let refreshReadings = forceReadings || start - lastBasicDate >= 1
        if refreshReadings {
            ts_basic(&state.basic, demand.cores); basicSamples += 1
            lastBasicDate = start
            if let cpu = state.cpu, cpu >= 90 {
                if highLoadSince == nil { highLoadSince=start }
                state.highLoadCount = start - highLoadSince! >= 10 ? 3 : 1
            } else { highLoadSince=nil; state.highLoadCount=0 }
            if state.basic.cpu_valid {
                state.history.append(HistoryPoint(time: start, user: state.basic.user, system: state.basic.system))
            }
        }
        state.thermal = ProcessInfo.processInfo.thermalState
        state.history.removeAll { start - $0.time > 120 }
        if state.history.count > 64 { state.history.removeFirst(state.history.count - 64) }
        if refreshReadings || (demand.gpuTemperature && !priorDemand.gpuTemperature) { state.cpuTemperature = ts_temperature(false); temperatureSamples += 1 }
        // Retain actual GPU history even while closed; temperature sensors remain demand-driven.
        if refreshReadings {state.gpu=ts_gpu();gpuSamples+=1}
        if demand.gpuTemperature {
            if refreshReadings || !priorDemand.gpuTemperature {state.gpuTemperature=ts_temperature(true);temperatureSamples+=1}
        }else{state.gpuTemperature=nil}
        if refreshReadings {
            state.metricHistory.append(MetricPoint(time:start,cpu:state.cpu,gpu:state.gpu?.valid == true ? state.gpu?.percent:nil,memory:state.memoryPercent))
            state.metricHistory.removeAll{start-$0.time>120}
            if state.metricHistory.count>128{state.metricHistory.removeFirst(state.metricHistory.count-128)}
        }
        if demand.processes && start - lastProcessDate >= 1 {
            processSamples += 1
            if raw.isEmpty { raw = [TSProcess](repeating:TSProcess(),count:4096) }
            state.coverage = raw.withUnsafeMutableBufferPointer { ts_processes($0.baseAddress, Int32($0.count)) }
            let now = ProcessInfo.processInfo.systemUptime
            var next: [ProcessIdentity: CPUCounter] = [:]
            next.reserveCapacity(Int(state.coverage.read))
            var ranked: [(index: Int, value: Double)] = []
            ranked.reserveCapacity(Int(state.coverage.read))
            for i in 0..<Int(state.coverage.read) {
                let p = raw[i]
                let id = ProcessIdentity(pid: p.pid, start: p.start)
                var value: Double?
                if demand.rank == .memory { value = Double(p.memory) }
                else {
                    if let old = previous[id], now - old.time >= 1, p.cpu_ns >= old.cpu { value = Double(p.cpu_ns - old.cpu) / 1e9 / (now - old.time) * 100 }
                    next[id] = CPUCounter(cpu: p.cpu_ns, time: now)
                }
                if let value = value, value.isFinite { ranked.append((i,value)) }
            }
            previous = next; lastProcessDate = now
            ranked.sort { $0.value == $1.value ? raw[$0.index].pid < raw[$1.index].pid : $0.value > $1.value }
            state.rows = ranked.prefix(5).map { row in
                let p = raw[row.index]; var name = [CChar](repeating: 0, count: 256)
                ts_process_name(p.pid, p.start, &name, Int32(name.count))
                return ProcessRow(pid: p.pid, name: String(cString: name), value: row.value)
            }
            state.rankingReady = demand.rank == .memory || !ranked.isEmpty
        }
        priorDemand = demand
        sampleCPU += ProcessInfo.processInfo.systemUptime - start
        return state
    }
    func counters() -> [String: Any] { ["basic_samples":basicSamples,"samples":samples,"process_samples":processSamples,"gpu_samples":gpuSamples,"temperature_group_reads":temperatureSamples,"sample_wall_seconds":sampleCPU] }
}
