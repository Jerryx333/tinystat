// Exercise scoped checks, local archives and file boundaries with synthetic fixtures.
// Run: bash scripts/verify-assistant-v2.sh
// Requires macOS SDK; no remote models or user process termination.
import AppKit
@main struct VerifyV2 {
    static func rejects(_ f:()throws->Void){do{try f();preconditionFailure("Expected failure")}catch{}}
    static func main()throws {
        if CommandLine.arguments.count==3,CommandLine.arguments[1]=="--stop-fixture",let pid=Int32(CommandLine.arguments[2]) {
            guard let p=try Investigation.inventory().first(where:{$0.pid==pid && $0.name=="test-stop-target"}),let target=StopTarget.capture(p) else{throw AssistantFailure("Fixture stop target rejected")}
            var result:String?
            target.request{result=$0}
            let deadline=Date().addingTimeInterval(8)
            while result==nil && Date()<deadline{RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
            guard let result=result,result.contains("已观察到") else{throw AssistantFailure("Fixture stop did not confirm exit: \(result ?? "timeout")")}
            print("PASS: explicitly registered synthetic sibling process SIGTERM and observed exit");return
        }
        let base=URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Caches/tinystat-v2-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:base)}
        let store=ConversationStore(directory:base.appendingPathComponent("sessions"))
        var record=ChatSession();try record.append(role:"你",text:"这个进程为什么高？")
        try store.save(record);precondition(try! store.load(record.id).messages.count==1)
        for _ in 0..<150{try record.append(role:"Claude Code",text:String(repeating:"合成文本 ",count:50))}
        try store.save(record)
        let context=record.context();precondition(context.messages.count<=24 && context.omitted>0)
        precondition(try! JSONSerialization.data(withJSONObject:context.messages).count<26*1024)
        let loaded=try store.load(record.id);precondition(loaded.messages.count==151)
        var st=stat();precondition(lstat(store.directory.appendingPathComponent(record.id.uuidString+".json").path,&st)==0 && st.st_mode&0o777==0o600)
        for _ in 0..<29{try store.save(ChatSession())};precondition(try! store.list().count==30)
        rejects{try store.save(ChatSession())};try store.save(record);try store.remove(record.id);precondition(try! store.list().count==29)
        var full=ChatSession();for _ in 0..<200{try full.append(role:"你",text:"x")};rejects{try full.append(role:"你",text:"201")}
        let file=base.appendingPathComponent("sample.txt");try Data("synthetic original".utf8).write(to:file)
        let selected=try FileTarget(url:file);precondition(try! selected.readText()=="synthetic original")
        let exported=base.appendingPathComponent("output.txt");try TextExport.write("new content",to:exported)
        rejects{try TextExport.write("overwrite",to:exported)};precondition(try! String(contentsOf:exported)=="new content")
        try FileManager.default.moveItem(at:file,to:base.appendingPathComponent("old.txt"));try Data("replacement".utf8).write(to:file);rejects{_ = try selected.readText()}
        let link=base.appendingPathComponent("link.txt");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:file);rejects{_ = try FileTarget(url:link)}
        let oversized=String(repeating:"x",count:12000)
        var bytesLimited=ChatSession();for _ in 0..<21{try bytesLimited.append(role:"你",text:oversized)};rejects{try bytesLimited.append(role:"你",text:oversized)}
        precondition(lstat(exported.path,&st)==0 && st.st_mode&0o777==0o600)
        let linkedStore=base.appendingPathComponent("linked-sessions");try FileManager.default.createSymbolicLink(at:linkedStore,withDestinationURL:store.directory)
        rejects{_ = try ConversationStore(directory:linkedStore).list()}
        let good="{\"explanation\":\"需要补查\",\"actions\":[],\"checks\":[{\"kind\":\"inspectProcess\",\"targetID\":\"known\",\"query\":\"\",\"reason\":\"查看父进程\"}]}"
        let reply=try AssistantReply.parse(good,allowed:[],inspectable:["known"]);precondition(reply.checks.count==1)
        rejects{_ = try AssistantReply.parse(good,allowed:[],inspectable:[])}
        rejects{_ = try AssistantReply.parse(good.replacingOccurrences(of:"inspectProcess",with:"readFile"),allowed:[],inspectable:["known"])}
        rejects{_ = try AssistantReply.parse(good.replacingOccurrences(of:"inspectProcess",with:"shell"),allowed:[],inspectable:["known"])}
        var budget=InvestigationBudget();try budget.authorize(reply.checks);try budget.authorize(reply.checks);rejects{try budget.authorize(reply.checks)}
        let all=try Investigation.inventory(),me=all.first{$0.pid==getpid()}!
        precondition(Investigation.status(me)=="running");precondition(StopTarget.capture(me)==nil)
        var changed=me;changed=DiagnosticProcess(id:me.id,pid:me.pid,start:me.start+1,name:me.name,cpuPercentOneCore:nil,memoryBytes:0)
        precondition(Investigation.status(changed)=="pid_reused")
        var delivered=false;let runner=Investigation()
        runner.run(DiagnosticCheck(kind:"sampleProcess",targetID:me.id,query:"",reason:"fixture"),process:me,file:nil){_ in delivered=true};runner.cancel()
        RunLoop.current.run(until:Date().addingTimeInterval(0.25));precondition(!delivered)
        print("PASS v2: bounded archives/context, round budget, registered target checks, file identity/read/export/no-overwrite, own-process exclusion, reuse status, cancelled callback")
    }
}
