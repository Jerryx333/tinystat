import AppKit

/// Hover or click a reading for local details; the composer enters a conversation.
final class Dashboard:NSView {
    var snapshot=Snapshot()
    var snapshotDate=Date()
    var page=Page.overview
    var rank=Rank.cpu
    var advanced=false
    var startup=false
    var startupMessage=""
    var action:((String)->Void)?
    var ask:((String)->Void)?
    var inspect:((Metric)->Void)?
    private var buttons:[String:NSButton]=[:]
    private let composer=MessageComposer(placeholder:"哪里不太对？问问 tinyStat。")
    var draft:String {get{composer.value}set{composer.value=newValue}}
    static let width:CGFloat=440
    override var isFlipped:Bool{true}
    override init(frame:NSRect){super.init(frame:frame);setup()}
    required init?(coder:NSCoder){fatalError("init(coder:) not supported")}
    private func setup(){
        appearance=NSAppearance(named:.darkAqua);Obsidian.apply(self,radius:16)
        for (id,title) in [("back","‹ 概览"),("settings","设置"),("close","收起"),("startup","登录启动"),("quit","退出 TinyStat"),("assistant","模型连接"),("chat","继续对话 ↗"),("processes","进程列表 ↗")] {
            let b=NSButton(title:title,target:self,action:#selector(clicked(_:)));b.identifier=NSUserInterfaceItemIdentifier(id)
            Obsidian.style(b);b.setAccessibilityLabel(title);addSubview(b);buttons[id]=b
        }
        for (i,metric) in [Metric.cpu,.gpu,.memory].enumerated(){
            let b=NSButton(title:"",target:self,action:#selector(inspectClicked(_:)))
            b.identifier=NSUserInterfaceItemIdentifier(metric.rawValue);b.isBordered=false;b.bezelStyle = .inline
            b.setAccessibilityLabel("查看 \(metric.rawValue.uppercased()) 详情")
            b.frame=NSRect(x:CGFloat(20+i*132),y:108,width:132,height:108)
            addSubview(b);buttons[metric.rawValue]=b
        }
        composer.onSend={ [weak self] question in self?.composer.value="";self?.ask?(question) };addSubview(composer)
        configure()
    }
    @objc private func inspectClicked(_ sender:NSButton){if let id=sender.identifier?.rawValue,let metric=Metric(rawValue:id){inspect?(metric)}}
    @objc private func clicked(_ sender:NSButton){if let id=sender.identifier?.rawValue{action?(id)}}
    func focusInput(){composer.focus()}
    override func performKeyEquivalent(with event:NSEvent)->Bool {
        if event.modifierFlags.contains(.command),event.charactersIgnoringModifiers=="k",page != .settings{focusInput();return true};return super.performKeyEquivalent(with:event)
    }
    var desiredHeight:CGFloat{page == .settings ? 270:426}
    func configure(){
        for b in buttons.values{b.isHidden=true}
        func place(_ id:String,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat){buttons[id]?.frame=NSRect(x:x,y:y,width:w,height:28);buttons[id]?.isHidden=false}
        composer.isHidden=page == .settings
        if page == .settings{
            place("back",18,16,65)
            place("startup",320,68,96);buttons["startup"]?.title=startup ? "已开启 ✓":"未开启"
            place("assistant",23,117,110);place("quit",23,173,110)
        }else{
            for metric in [Metric.cpu,.gpu,.memory]{buttons[metric.rawValue]?.isHidden=false}
            composer.frame=NSRect(x:20,y:267,width:400,height:108)
            place("assistant",22,388,100);buttons["assistant"]?.title=AgentSettings.load().kind=="claude" ? "Claude Code":"Codex"
            place("chat",306,388,112);place("processes",299,242,120);buttons["processes"]?.frame.size.height=24
        }
        place("settings",319,15,52);place("close",375,15,48)
        toolTip=nil
        needsDisplay=true
    }
    func metric(at point:NSPoint)->Metric? {
        guard page != .settings,point.y>=108,point.y<216 else{return nil}
        for (i,metric) in [Metric.cpu,.gpu,.memory].enumerated() {
            if NSRect(x:CGFloat(20+i*132),y:108,width:132,height:108).contains(point){return metric}
        };return nil
    }
    override func mouseDown(with event:NSEvent){
        if let metric=metric(at:convert(event.locationInWindow,from:nil)){inspect?(metric)}else{super.mouseDown(with:event)}
    }
    private func text(_ s:String,_ x:CGFloat,_ y:CGFloat,_ width:CGFloat,_ size:CGFloat=12,_ color:NSColor=Obsidian.ink,_ weight:NSFont.Weight = .regular){
        let p=NSMutableParagraphStyle();p.lineBreakMode = .byTruncatingTail
        (s as NSString).draw(in:NSRect(x:x,y:y,width:width,height:max(24,size+6)),withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:size,weight:weight),.foregroundColor:color,.paragraphStyle:p])
    }
    override func draw(_ dirtyRect:NSRect){
        Obsidian.surface.setFill();bounds.fill();let s=snapshot
        if page == .settings{
            text("设置",200,21,80,13);text("登录时启动",28,76,230)
            text(startupMessage,28,229,385,11,Obsidian.secondary);return
        }
        text("▥  tinyStat",27,22,180,14,Obsidian.ink,.semibold)
        text("你的 Mac，此刻。",28,75,330,13,Obsidian.secondary)
        let names=["CPU","GPU","MEMORY"],values=[percent(s.cpu),percent(s.gpu?.valid == true ? s.gpu?.percent:nil),percent(s.memoryPercent)]
        let extras=[temperature(s.cpuTemperature),temperature(s.gpuTemperature),s.pressure]
        for i in 0..<3{
            let x=CGFloat(28+i*132)
            if i>0{Obsidian.line.setFill();NSRect(x:x-16,y:113,width:1,height:100).fill()}
            text(names[i],x,113,118,10,Obsidian.secondary)
            text(values[i],x,135,125,38,Obsidian.ink,.light)
            text(extras[i],x,187,120,11,Obsidian.secondary)
        }
        text(s.basic.memory_valid ? "\(bytes(s.basic.used)) / \(bytes(s.basic.total))":"内存读数不可用",28,220,240,11,Obsidian.secondary)
        let formatter=DateFormatter();formatter.dateFormat="HH:mm:ss"
        text("采样 "+formatter.string(from:snapshotDate),307,220,113,10,Obsidian.quiet)
        text(s.health.0,28,245,260,11,Obsidian.secondary)
    }
}
final class MonitorPanel:NSPanel {override var canBecomeKey:Bool{true}}
