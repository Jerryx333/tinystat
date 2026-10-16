// Grade actual assistant behavior with synthetic evidence and no machine/private data.
// Run: bash scripts/verify-assistant-quality-live.sh
// Requires authenticated native Claude; three remote model requests, no tools/actions.
import Foundation
@main struct QualityLive {
    static func main()throws {
        let backend=AgentBackend();var settings=AgentSettings();settings.kind="claude"
        let cases:[(String,[String:Any])]=[
            ("missing-evidence",["request":["text":"这些 Python 到底在干嘛？别让我自己去活动监视器查。"],"conversation":[],"budget":["remainingBatches":2,"checksAllowed":true],"actionableTargets":[],"inspectableTargets":[["id":"synthetic-python","name":"python3","pid":"123"]],"backend":["kind":"claude","configured":"unknown","reported":"unknown"]]),
            ("ranking-continuity",["request":["text":"刚才那个 Python 不在前8了，是不是退出了？"],"conversation":[],"budget":["remainingBatches":2,"checksAllowed":true],"actionableTargets":[],"inspectableTargets":[["id":"synthetic-python","name":"python3","pid":"123"]],"focus":["id":"synthetic-python","name":"python3"],"evidence":["selection":"top8","processes":[]],"backend":["kind":"claude","configured":"unknown","reported":"unknown"]]),
            ("swap-budget",["request":["text":"swap 15GB 是不是之前内存压力大导致的？现在该处理吗？"],"conversation":[],"budget":["remainingBatches":0,"checksAllowed":false],"actionableTargets":[],"inspectableTargets":[],"evidence":["memoryPressure":"normal","swapUsedBytes":15000000000,"swapOutBytesPerSecond":0,"limitations":"synthetic single snapshot, no historical pressure evidence"],"backend":["kind":"claude","configured":"unknown","reported":"unknown"]])
        ]
        let selected=CommandLine.arguments.contains("--swap-only") ? cases.filter{$0.0=="swap-budget"}:cases
        for (name,context) in selected {
            let data=try JSONSerialization.data(withJSONObject:context),start=Date();var done=false,error:Error?
            backend.send(settings:settings,prompt:String(decoding:data,as:UTF8.self)){result in
                do{
                    let reply=try AssistantReply.parse(try result.get(),allowed:[],inspectable:["synthetic-python"])
                    guard reply.actions.isEmpty else{throw AssistantFailure("Unexpected write proposal")}
                    if name=="swap-budget"{guard reply.checks.isEmpty else{throw AssistantFailure("Ignored exhausted check budget")}}
                    else{guard !reply.checks.isEmpty else{throw AssistantFailure("Did not request missing evidence")}}
                    print("CASE",name,"seconds",Date().timeIntervalSince(start));print(reply.explanation)
                    print("CHECKS",reply.checks.map{$0.kind+":"+$0.targetID}.joined(separator:","))
                }catch let failure{error=failure};done=true
            }
            let until=Date().addingTimeInterval(125);while !done && Date()<until{RunLoop.current.run(until:Date().addingTimeInterval(0.05))}
            guard done,error==nil else{backend.shutdown();throw error ?? AssistantFailure("Quality test timed out")}
        }
        backend.shutdown();print("PASS: synthetic live protocol cases; explanations require human evidence review")
    }
}
