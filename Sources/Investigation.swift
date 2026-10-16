import AppKit
import Security

/// Registered identities only; model-provided IDs are looked up, never interpreted.
struct InvestigationBudget {
    private(set) var batches=0
    private(set) var count=0
    mutating func authorize(_ checks:[DiagnosticCheck])throws {
        guard batches<2,!checks.isEmpty,checks.count<=3,count+checks.count<=6 else{throw AssistantFailure("本问题的补查预算已用完，请根据已有证据回答。")}
        batches+=1;count+=checks.count
    }
}
final class Investigation {
    private let queue=DispatchQueue(label:"local.tinystat.investigation",qos:.utility)
    private let lock=NSLock()
    private var generation=0
    func cancel(){lock.lock();generation+=1;lock.unlock()}
    private func version()->Int{lock.lock();defer{lock.unlock()};return generation}
    static func status(_ p:DiagnosticProcess)->String {
        switch ts_process_status(p.pid,p.start){case 0:return "running";case 1:return "absent";case 2:return "pid_reused";default:return "unknown_or_unreadable"}
    }
    static func inventory()throws->[DiagnosticProcess] {
        var raw=[TSProcess](repeating:TSProcess(),count:4096)
        let c=raw.withUnsafeMutableBufferPointer{ts_processes($0.baseAddress,Int32($0.count))}
        guard c.error==0 else{throw AssistantFailure("进程读取失败（\(c.error)）。")}
        return raw.prefix(Int(c.read)).map{p in
            var name=[CChar](repeating:0,count:256);ts_process_name(p.pid,p.start,&name,256)
            return DiagnosticProcess(id:"p\(p.pid)-\(p.start)",pid:p.pid,start:p.start,name:displayIdentity(String(cString:name)),cpuPercentOneCore:nil,memoryBytes:p.memory)
        }
    }
    func run(_ check:DiagnosticCheck,process:DiagnosticProcess?,file:FileTarget?,completion:@escaping(Result<([String:Any],[DiagnosticProcess]),Error>)->Void) {
        let token=version()
        queue.async { [weak self] in
            guard let self=self,self.version()==token else{return}
            let result=Result{()->([String:Any],[DiagnosticProcess]) in
                if check.kind=="readFile" {
                    guard let file=file else{throw AssistantFailure("文件选择已失效。")}
                    return(["kind":check.kind,"targetID":check.targetID,"text":try file.readText(),"limitBytes":8192],[])
                }
                if check.kind=="searchProcesses" {
                    let all=try Self.inventory(),matches=all.filter{$0.name.localizedCaseInsensitiveContains(check.query) || String($0.pid)==check.query}
                    let selected=Array(matches.sorted{$0.memoryBytes>$1.memoryBytes}.prefix(20))
                    return(["kind":check.kind,"query":check.query,"matchedReadable":matches.count,"returned":selected.count,"readable":all.count,"coverage":"Readable processes only, capped at 4096; not total machine process count. Same name does not establish same application."],selected)
                }
                guard let p=process else{throw AssistantFailure("进程选择已失效。")}
                var result:[String:Any]=["kind":check.kind,"targetID":p.id,"status":Self.status(p)]
                guard Self.status(p)=="running" else{return(result,[])}
                if check.kind=="inspectProcess" {
                    var parent:Int32=0,uid:UInt32=0,ruid:UInt32=0
                    if ts_process_parent(p.pid,p.start,&parent,&uid,&ruid)==1 {
                        result["ownedByCurrentUser"]=uid==getuid() && ruid==getuid()
                        let all=try Self.inventory()
                        if let ancestor=all.first(where:{$0.pid==parent && $0.start<p.start}){result["parentPID"]=parent;result["parentName"]=ancestor.name}
                        result["relationshipLimit"]="Parent at sample time only; not proof of application ownership or purpose. No command arguments or paths read."
                    }else{result["parentStatus"]="unknown"}
                    return(result,[])
                }
                guard check.kind=="sampleProcess" else{throw AssistantFailure("不支持的检查。")}
                var points:[[String:Any]]=[]
                let began=ProcessInfo.processInfo.systemUptime
                var previous:TSProcess?,previousTime=began
                for index in 0..<3 {
                    if index>0{for _ in 0..<20{guard self.version()==token else{throw AssistantFailure("检查已取消。")};Thread.sleep(forTimeInterval:0.1)}}
                    guard self.version()==token else{throw AssistantFailure("检查已取消。")}
                    let time=ProcessInfo.processInfo.systemUptime
                    var current=TSProcess()
                    let sampled=ts_process_sample(p.pid,p.start,&current)
                    var point:[String:Any]=["seconds":time-began,"status":["running","absent","pid_reused","unknown_or_unreadable"][min(3,max(0,Int(sampled)))]]
                    if sampled==0 {
                        point["memoryBytes"]=current.memory
                        if let old=previous,time>previousTime,current.cpu_ns>=old.cpu_ns{point["cpuPercentOneCore"]=Double(current.cpu_ns-old.cpu_ns)/1e9/(time-previousTime)*100;point["deltaMemoryBytes"]=Double(current.memory)-Double(old.memory)}
                        previous=current;previousTime=time
                    }else{previous=nil}
                    points.append(point)
                }
                result["points"]=points;result["limitations"]="Short CPU/memory observation only, cannot establish a leak. Missing process is not inferred from top lists."
                return(result,[])
            }
            DispatchQueue.main.async{guard self.version()==token else{return};completion(result)}
        }
    }
}

struct StopTarget {
    let process:DiagnosticProcess
    static func capture(_ p:DiagnosticProcess)->StopTarget? {
        guard p.pid>1,p.pid != getpid(),Investigation.status(p)=="running",NSRunningApplication(processIdentifier:p.pid)?.activationPolicy != .regular,NSRunningApplication(processIdentifier:p.pid)?.activationPolicy != .accessory else{return nil}
        var parent:Int32=0,uid:UInt32=0,ruid:UInt32=0
        guard ts_process_parent(p.pid,p.start,&parent,&uid,&ruid)==1,uid==getuid(),ruid==getuid() else{return nil}
        var path=[CChar](repeating:0,count:4096)
        guard ts_process_path(p.pid,p.start,&path,4096)==1 else{return nil}
        let executable=String(cString:path)
        guard !["/System/","/usr/","/bin/","/sbin/","/Library/Apple/"].contains(where:{executable.hasPrefix($0)}),!executable.contains("/Contents/MacOS/") else{return nil}
        var code:SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath:executable) as CFURL,[],&code)==errSecSuccess,let code=code else{return nil}
        var requirement:SecRequirement?
        guard SecRequirementCreateWithString("anchor apple" as CFString,[],&requirement)==errSecSuccess,let requirement=requirement else{return nil}
        if SecStaticCodeCheckValidity(code,[],requirement)==errSecSuccess{return nil}
        // Exclude the monitor's ancestors and descendants; unresolved chains fail closed.
        var raw=[TSProcess](repeating:TSProcess(),count:4096)
        let coverage=raw.withUnsafeMutableBufferPointer{ts_processes($0.baseAddress,Int32($0.count))}
        guard coverage.error==0,!coverage.truncated else{return nil};let all=raw.prefix(Int(coverage.read))
        func contains(_ start:Int32,_ target:Int32)->Bool? {
            var pid=start,seen=Set<Int32>()
            for _ in 0..<64 {
                if pid==target{return true};if pid<=1{return false}
                guard seen.insert(pid).inserted,let current=all.first(where:{$0.pid==pid}) else{return nil}
                var next:Int32=0,u:UInt32=0,r:UInt32=0
                guard ts_process_parent(pid,current.start,&next,&u,&r)==1 else{return nil};pid=next
            };return nil
        }
        guard contains(p.pid,getpid())==false,contains(getpid(),p.pid)==false else{return nil}
        return StopTarget(process:p)
    }
    func request(completion:@escaping(String)->Void){
        guard Self.capture(process) != nil else{completion("未执行：进程身份或停止资格已变化。");return}
        guard kill(process.pid,SIGTERM)==0 else{completion("停止请求失败（\(errno)），未强制结束。");return}
        let p=process
        func observe(_ remaining:Int){
            let state=Investigation.status(p)
            if state=="absent" || state=="pid_reused"{completion("已观察到 PID \(p.pid) 原进程结束；服务可能被重新启动，此结果不代表整个应用停止。");return}
            if remaining==0{completion("已向 PID \(p.pid) 发送 SIGTERM，尚未确认退出（\(state)）；未升级为强杀。");return}
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5){observe(remaining-1)}
        };observe(10)
    }
}
