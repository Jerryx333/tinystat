// Optional live model handshake using synthetic data only.
// Run: bash scripts/verify-assistant-live.sh claude
// Requires a locally installed and already authenticated CLI; no telemetry sent.
import Foundation
@main struct LiveCheck {
    static func main() {
        var settings=AgentSettings();settings.kind=CommandLine.arguments.dropFirst().first ?? "claude"
        let backend=AgentBackend();var done=false,success=false
        backend.send(settings:settings,prompt:"Synthetic integration check only. No machine information. Return JSON with explanation set to TinyStat connection OK, actions empty."){result in
            switch result {
            case .success(let text):do{let reply=try AssistantReply.parse(text,allowed:[]);success=reply.actions.isEmpty;print(success ? "PASS: synthetic model reply validated":"FAIL: unexpected actions")}catch{print("FAIL: \(error.localizedDescription)")}
            case .failure(let error):print("FAIL: \(error.localizedDescription)")
            }
            done=true
        }
        let until=Date().addingTimeInterval(130)
        while !done && Date()<until{RunLoop.current.run(until:Date().addingTimeInterval(0.05))}
        backend.shutdown();exit(success ? 0:1)
    }
}
