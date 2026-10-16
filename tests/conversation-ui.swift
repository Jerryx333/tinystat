// Exercise actual chat UI, grant cancellation and bounded views using a synthetic model.
// Run: bash scripts/verify-conversation-ui.sh
// Requires macOS AppKit; no real model, user file reads or user process actions.
import AppKit
extension AssistantController {
    func exerciseConversation()throws {
        show();let initialHandlers=handlers.count
        let baseline=ts_resources(),begin=ProcessInfo.processInfo.systemUptime
        var peak=baseline.footprint
        for cycle in 0..<6 {
            autoreleasepool{
            resetSessionState();session=ChatSession()
            for i in 0..<180 {
                autoreleasepool{append(i%2==0 ? "你":"Claude Code",String(repeating:"合成会话用于资源边界验证。",count:12));RunLoop.current.run(until:Date().addingTimeInterval(0.002))}
                precondition(log.arrangedSubviews.count<=60)
                peak=max(peak,ts_resources().footprint)
            }
            turnPage(older:true);precondition(log.arrangedSubviews.count<=40)
            turnPage(older:false);precondition(log.arrangedSubviews.count<=40)
            autoreleasepool{window?.performClose(nil);RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
            precondition(log.arrangedSubviews.isEmpty && actionButtons.isEmpty && evidence==nil && files.isEmpty)
            precondition(handlers.count==initialHandlers)
            show();precondition(log.arrangedSubviews.count<=40)
            }
            print("UI bounded cycle",cycle,"footprint",ts_resources().footprint)
        }
        resetSessionState();session=ChatSession();currentQuestion="查一下进程";setBusy(true)
        var settings=AgentSettings();settings.model="synthetic"
        var calls=0
        modelRequest={_,prompt,completion in
            calls+=1
            let o=try! JSONSerialization.jsonObject(with:Data(prompt.utf8)) as! [String:Any]
            precondition((o["request"] as! [String:String])["text"]=="查一下进程")
            completion(.success("{\"explanation\":\"需要授权\",\"actions\":[],\"checks\":[{\"kind\":\"searchProcesses\",\"targetID\":\"\",\"query\":\"synthetic\",\"reason\":\"fixture\"}]}"))
        }
        sendRound(settings:settings,token:generation)
        precondition(grantSheet != nil && operating)
        let cancelledGeneration=generation
        cancel();precondition(generation != cancelledGeneration && grantSheet==nil && !operating && !busy)
        RunLoop.current.run(until:Date().addingTimeInterval(0.1));precondition(calls==1 && checkResults.isEmpty)
        // A successful synthetic read stays within the real collector/grant flow.
        currentQuestion="查一下进程";budget=InvestigationBudget();setBusy(true)
        let fixture=try Investigation.inventory().first{$0.pid==getpid()}!
        registered[fixture.id]=fixture
        modelRequest={_,prompt,completion in
            calls+=1
            if calls==2{completion(.success("{\"explanation\":\"核验进程\",\"actions\":[],\"checks\":[{\"kind\":\"inspectProcess\",\"targetID\":\"\(fixture.id)\",\"query\":\"\",\"reason\":\"synthetic self inspection\"}]}"))}
            else{
                let o=try! JSONSerialization.jsonObject(with:Data(prompt.utf8)) as! [String:Any]
                precondition(!(o["checks"] as! [[String:Any]]).isEmpty)
                completion(.success("{\"explanation\":\"检查结果已收到\",\"actions\":[],\"checks\":[]}"))
            }
        }
        sendRound(settings:settings,token:generation)
        precondition(grantSheet != nil)
        window!.endSheet(grantSheet!.window,returnCode:.alertSecondButtonReturn)
        let deadline=Date().addingTimeInterval(10)
        while busy && Date()<deadline{RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
        precondition(!busy && calls==3 && checkResults.isEmpty)
        modelRequest=nil;window?.performClose(nil)
        RunLoop.current.run(until:Date().addingTimeInterval(0.1))
        let end=ts_resources()
        print(String(format:"PASS native conversation UI: 1080 synthetic messages, 6 close/reopen cycles, 40/page 60-row cap, stable handlers, denied/allowed read flow. wall=%.3fs cpu=%.3fs baseline=%.2fMiB final=%.2fMiB sampledPeak=%.2fMiB",ProcessInfo.processInfo.systemUptime-begin,end.cpu_seconds-baseline.cpu_seconds,baseline.footprint/1048576,end.footprint/1048576,peak/1048576))
    }
}
@main struct ConversationUIValidation {
    static func main()throws{_ = NSApplication.shared;NSApp.setActivationPolicy(.accessory);let controller=AssistantController(snapshot:{_ in fatalError("Synthetic test must not refresh system telemetry")},persistent:false);try controller.exerciseConversation()}
}
