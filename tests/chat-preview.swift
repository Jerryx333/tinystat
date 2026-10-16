// Synthetic conversation preview; no model requests, machine telemetry or actions.
// Run: bash scripts/preview-chat.sh
// Concatenated after AssistantUI.swift so fixtures can exercise private rendering.
extension AssistantController {
    func previewConversation(){
        show()
        append("你","退出了吗？")
        append("Claude Code","示例应用的原进程已确认退出。\n\n内存压力仍然偏高，退出一个应用不一定立即恢复正常。先继续观察，不必为了降低百分比而关闭正在使用的程序。\n\n- 这是一段合成示例，不是你的实时诊断。\n- 需要具体数据时，展开采样依据，或打开进程列表。")
        latestReceipt.stringValue="最近操作 · 示例应用原进程已退出（合成预览）";latestReceipt.isHidden=false
        let detail=label("合成采样依据 · CPU 24% · 内存 62%\n示例进程 · PID 123 · 12 MiB",color:Obsidian.secondary);detail.isHidden=true
        let toggle=button("采样依据 · 合成示例 · 展开 / 收起"){[weak self,weak detail] in detail?.isHidden.toggle();self?.window?.contentView?.layoutSubtreeIfNeeded()}
        add(stack([toggle,detail]));composer.enabled=false
    }
}
@main struct ChatPreview {
    static func main(){
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        let controller=AssistantController(snapshot:{_ in fatalError("Preview must not collect telemetry")})
        controller.previewConversation();withExtendedLifetime(controller){app.run()}
    }
}
