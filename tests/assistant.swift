// Verify assistant boundaries and process-family cleanup with local fixtures.
// Run: bash scripts/verify-assistant.sh
// Requires Apple SDK; no model calls or private process data are printed.
import AppKit
@main struct VerifyAssistant {
    static func spin(_ predicate:()->Bool,seconds:Double=8) {
        let end=Date().addingTimeInterval(seconds)
        while !predicate() && Date()<end {RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
        precondition(predicate(),"asynchronous check timed out")
    }
    static func rejects(_ work:()throws->Void){do{try work();preconditionFailure("unexpected success")}catch{}}
    static func main()throws {
        if CommandLine.arguments.count>1 {
            let args=CommandLine.arguments
            if args[1]=="--codex-args" {
                var settings=AgentSettings();settings.custom=true;settings.endpoint=args[2];settings.model="test-model"
                let dir=URL(fileURLWithPath:args[3]),schema=URL(fileURLWithPath:args[3]).appendingPathComponent("reply-schema.json")
                try JSONSerialization.data(withJSONObject:AssistantReply.schema).write(to:schema)
                print(String(data:try JSONSerialization.data(withJSONObject:AgentBackend.codexArguments(settings:settings,directory:dir,schema:schema)),encoding:.utf8)!);return
            }
            if args[1]=="--parse-codex" {
                let reply=try AgentBackend.response(Data(contentsOf:URL(fileURLWithPath:args[2])),kind:"codex")
                let parsed=try AssistantReply.parse(reply,allowed:[]);precondition(parsed.actions.isEmpty);print("PASS: real Codex CLI successful event stream and schema parsed");return
            }
        }
        if CommandLine.arguments.count>1,CommandLine.arguments[1]=="--sandbox-args" {
            var settings=AgentSettings();settings.kind=CommandLine.arguments.contains("--codex") ? "codex":"claude";settings.custom = !CommandLine.arguments.contains("--login");if let i=CommandLine.arguments.firstIndex(of:"--endpoint"),CommandLine.arguments.count>i+1{settings.endpoint=CommandLine.arguments[i+1]}
            let sandbox=try AgentSandbox(executable:CommandLine.arguments[2],directory:URL(fileURLWithPath:CommandLine.arguments[3]),settings:settings)
            print(String(data:try JSONEncoder().encode(sandbox.arguments),encoding:.utf8)!);return
        }
        let good="{\"explanation\":\"观察到占用，原因待核实\",\"actions\":[]}"
        let reply=try AssistantReply.parse(good,allowed:[]);precondition(reply.actions.isEmpty)
        rejects{_ = try AssistantReply.parse("{\"explanation\":\"x\",\"actions\":[{\"kind\":\"shell\",\"targetID\":\"p1\",\"reason\":\"x\"}]}",allowed:["p1"])}
        rejects{_ = try AssistantReply.parse("{\"explanation\":\"x\",\"actions\":[{\"kind\":\"quitApp\",\"targetID\":\"p2\",\"reason\":\"x\"}]}",allowed:["p1"])}
        let codex=Data(("{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"answer\"}}\n{\"type\":\"turn.completed\"}\n").utf8)
        let answer=try AgentBackend.response(codex,kind:"codex");precondition(answer=="answer")
        rejects{_ = try AgentBackend.response(Data("{\"type\":\"item.started\",\"item\":{\"type\":\"command_execution\"}}\n".utf8),kind:"codex")}
        rejects{_ = try AgentBackend.response(Data("{\"type\":\"turn.completed\"}\n".utf8),kind:"codex")}
        rejects{_ = try AgentBackend.response(Data("{\"type\":\"system\",\"subtype\":\"init\",\"tools\":[\"Bash\"]}\n".utf8),kind:"claude")}
        var blockedCodex=AgentSettings();blockedCodex.kind="codex";rejects{try blockedCodex.validate()}
        var settings=AgentSettings();settings.custom=true;settings.endpoint="http://example.com";settings.model="test";rejects{try settings.validate()}
        settings.endpoint="https://example.com/v1";try settings.validate()
        settings.endpoint="https://secret@example.com/v1";rejects{try settings.validate()}
        var rows=[TSProcess](repeating:TSProcess(),count:4096)
        let c=rows.withUnsafeMutableBufferPointer{ts_processes($0.baseAddress,Int32($0.count))}
        let me=rows.prefix(Int(c.read)).first{$0.pid==getpid()}!
        precondition(ts_process_matches(me.pid,me.start));precondition(!ts_process_matches(me.pid,me.start+1))
        precondition(ts_process_threads(me.pid,me.start)>0);precondition(ts_process_threads(me.pid,me.start+1)==(-1))
        rejects{_ = try AgentBackend.response(Data("{\"type\":\"result\",\"result\":\"ok\",\"is_error\":false}\n".utf8),kind:"claude")}
        var protection=ActionProtection()
        let protected=QuitTarget(id:"p1",pid:111,start:1,name:"Editor",bundle:"test.editor",launch:Date())
        protection.protect(protected)
        let restarted=QuitTarget(id:"p2",pid:222,start:2,name:"Renamed",bundle:"test.editor",launch:Date())
        precondition(!protection.allows(restarted),"protection must survive process restarts")
        precondition(displayIdentity("app\n\u{202e}safe")=="app��safe")
        let p=DiagnosticProcess(id:"self",pid:me.pid,start:me.start,name:"test",cpuPercentOneCore:0,memoryBytes:0)
        precondition(QuitTarget.capture(p)==nil)
        let directory=URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Caches/tinystat-test-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:directory)}
        let file=directory.appendingPathComponent("sample.txt");try Data("sample".utf8).write(to:file)
        let selected=try FileTarget(url:file);try selected.validate();protection.protect(selected);let reselected=try FileTarget(url:file);precondition(!protection.allows(reselected),"reselect must not unlock protected file")
        try FileManager.default.moveItem(at:file,to:directory.appendingPathComponent("original.txt"));try Data("sample".utf8).write(to:file)
        rejects{try selected.validate()}
        let link=directory.appendingPathComponent("link");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:file);rejects{_ = try FileTarget(url:link)}
        let job=AgentJob();var result:Result<Data,Error>?
        job.run(path:"/bin/cat",arguments:[],environment:["PATH":"/usr/bin:/bin"],directory:directory,input:Data(repeating:65,count:80_000)){result=$0}
        spin{result != nil};let echoed=try result!.get();precondition(echoed.count==80_000)
        let pidFile=directory.appendingPathComponent("child.pid")
        let parent=AgentJob();var cancelled=false
        parent.run(path:"/bin/sh",arguments:["-c","sleep 60 & echo $! > child.pid; wait"],environment:["PATH":"/usr/bin:/bin"],directory:directory,input:Data("test".utf8)){r in if case .failure = r{cancelled=true}}
        spin{FileManager.default.fileExists(atPath:pidFile.path)}
        let child=Int32(try String(contentsOf:pidFile).trimmingCharacters(in:.whitespacesAndNewlines))!
        parent.cancel();spin{cancelled};spin{kill(child,0) != 0}
        let term=AgentJob();var termDone=false
        term.run(path:"/bin/sh",arguments:["-c","trap 'echo yes > term; exit 0' TERM; echo ready > ready; while :; do sleep 1; done"],environment:["PATH":"/usr/bin:/bin"],directory:directory,input:Data("test".utf8)){_ in termDone=true}
        spin{FileManager.default.fileExists(atPath:directory.appendingPathComponent("ready").path)}
        term.cancel();spin{termDone};precondition(FileManager.default.fileExists(atPath:directory.appendingPathComponent("term").path),"SIGTERM must reach the child")
        let timeout=AgentJob();var timedOut=false
        timeout.run(path:"/bin/sleep",arguments:["60"],environment:["PATH":"/usr/bin:/bin"],directory:directory,input:Data("test".utf8),timeout:0.15){r in if case .failure = r{timedOut=true}}
        spin{timedOut}
        let forbidden=AgentJob();var rejected=false
        forbidden.run(path:"/bin/sh",arguments:["-c","echo '{\"type\":\"item.started\",\"item\":{\"type\":\"request_user_input\"}}'; sleep 60"],environment:["PATH":"/usr/bin:/bin"],directory:directory,input:Data("test".utf8),validateLine:{try AgentBackend.validateEvent($0,kind:"codex")}){r in if case .failure=r{rejected=true}}
        spin{rejected}
        let collector=DiagnosticCollector();var evidence:DiagnosticEvidence?
        collector.collect(snapshot:Snapshot(),at:Date()){r in evidence=try? r.get()}
        spin{evidence != nil};precondition(evidence!.processes.count<=16);precondition(evidence!.cpuPercent==nil);precondition(evidence!.samplingSeconds>=1)
        evidence=nil
        collector.collect(snapshot:Snapshot(),at:Date(),allProcesses:true){evidence=try? $0.get()}
        spin{evidence != nil}
        precondition(evidence!.processes.count==evidence!.readable)
        precondition(evidence!.processes.contains{$0.pid==getpid() && ($0.threadCount ?? 0)>0})
        evidence=nil
        collector.collect(snapshot:Snapshot(),at:Date(),focusID:"p\(me.pid)-\(me.start)"){evidence=try? $0.get()}
        spin{evidence != nil};precondition(evidence!.processes.count<=17)
        precondition(evidence!.processes.contains{$0.pid==getpid()})
        precondition(evidence!.focus?.status=="present")
        evidence=nil
        collector.collect(snapshot:Snapshot(),at:Date(),focusID:"nonexistent-synthetic-process"){evidence=try? $0.get()}
        spin{evidence != nil};precondition(evidence!.focus?.status=="exited_or_unreadable")
        print("PASS: reply contracts, invalid actions, CLI protocol, URL validation, process identity, file replacement/symlink rejection, pipe backpressure, cancellation descendants, timeout, bounded diagnostics")
    }
}
