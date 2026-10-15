import AppKit

final class Dashboard: NSView {
    var snapshot = Snapshot()
    var page = Page.overview
    var rank = Rank.cpu
    var advanced = false
    var interval = 5.0
    var startup = false
    var startupMessage = ""
    var action: ((String) -> Void)?
    private var buttons: [String:NSButton] = [:]
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
    private func setup() {
        wantsLayer = true
        for (id, title) in [("cpuRow",""),("gpuRow",""),("memoryRow",""),("back","‹ 概览"),("cpu","CPU"),("memory","内存"),("advanced","更多指标 ›"),("settings","⚙ 设置"),("close","收起 ↗"),("interval","5 秒"),("startup","登录启动"),("quit","退出 TinyStat")] {
            let b = NSButton(title:title,target:self,action:#selector(clicked(_:)))
            b.identifier = NSUserInterfaceItemIdentifier(id); b.isBordered = false
            b.font = .systemFont(ofSize:11); b.contentTintColor = .secondaryLabelColor
            b.setAccessibilityLabel(title.isEmpty ? (id == "memoryRow" ? "查看内存进程排行" : "查看统一详情") : title)
            addSubview(b); buttons[id] = b
        }
        setAccessibilityElement(true); setAccessibilityRole(.group)
        configure()
    }
    @objc private func clicked(_ sender: NSButton) { if let id = sender.identifier?.rawValue { action?(id) } }
    var desiredHeight: CGFloat { page == .overview ? 250 : page == .settings ? 240 : advanced ? 654 : 430 }
    func configure() {
        for b in buttons.values { b.isHidden = true }
        func place(_ id:String,_ r:NSRect) { buttons[id]?.frame=r; buttons[id]?.isHidden=false }
        if page == .overview {
            place("cpuRow",NSRect(x:12,y:99,width:286,height:35));place("gpuRow",NSRect(x:12,y:134,width:286,height:35));place("memoryRow",NSRect(x:12,y:169,width:286,height:35))
        } else {
            place("back",NSRect(x:8,y:7,width:60,height:24))
        }
        if page == .details {
            place("cpu",NSRect(x:201,y:169,width:42,height:23));place("memory",NSRect(x:248,y:169,width:48,height:23))
            buttons["cpu"]?.contentTintColor = rank == .cpu ? .controlAccentColor : .secondaryLabelColor
            buttons["memory"]?.contentTintColor = rank == .memory ? .controlAccentColor : .secondaryLabelColor
            place("advanced",NSRect(x:11,y:365,width:136,height:24));buttons["advanced"]?.title = advanced ? "收起更多指标 ⌃" : "更多指标 ›"
        }
        if page == .settings {
            place("interval",NSRect(x:208,y:51,width:85,height:25));buttons["interval"]?.title="\(Int(interval)) 秒 ▾"
            place("startup",NSRect(x:198,y:91,width:95,height:25));buttons["startup"]?.title=startup ? "已开启 ✓" : "未开启"
            place("quit",NSRect(x:12,y:174,width:100,height:28))
        }
        place("settings",NSRect(x:8,y:desiredHeight-28,width:58,height:22));place("close",NSRect(x:244,y:desiredHeight-28,width:58,height:22))
        toolTip = "温度：M1 CPU/GPU 已识别传感器最高值。* 表示部分传感器不可用。状态依据系统热状态及内存压力，不按单一温度判定过载。"
        needsDisplay = true
    }
    private func text(_ s:String,_ x:CGFloat,_ y:CGFloat,_ width:CGFloat = 286,_ size:CGFloat = 12,_ color:NSColor = .labelColor,_ bold:Bool = false,_ alignment:NSTextAlignment = .left) {
        let p=NSMutableParagraphStyle();p.alignment=alignment;p.lineBreakMode = .byTruncatingTail
        (s as NSString).draw(in:NSRect(x:x,y:y,width:width,height:24),withAttributes:[.font:bold ? NSFont.monospacedDigitSystemFont(ofSize:size,weight:.medium) : NSFont.systemFont(ofSize:size),.foregroundColor:color,.paragraphStyle:p])
    }
    private func line(_ y:CGFloat) { NSColor.separatorColor.setFill();NSRect(x:12,y:y,width:286,height:0.5).fill() }
    private func bar(_ x:CGFloat,_ y:CGFloat,_ width:CGFloat,_ value:Double,_ color:NSColor) {
        NSColor.quaternaryLabelColor.setFill();NSBezierPath(roundedRect:NSRect(x:x,y:y,width:width,height:6),xRadius:3,yRadius:3).fill()
        color.setFill();NSBezierPath(roundedRect:NSRect(x:x,y:y,width:width*CGFloat(max(0,min(1,value))),height:6),xRadius:3,yRadius:3).fill()
    }
    private func chart(_ rect:NSRect) {
        NSColor.quaternaryLabelColor.withAlphaComponent(0.08).setFill();NSBezierPath(roundedRect:rect,xRadius:4,yRadius:4).fill()
        guard snapshot.history.count > 1 else { text("采集趋势中…",rect.minX+8,rect.minY+10,rect.width-16,10,.secondaryLabelColor);return }
        let now=ProcessInfo.processInfo.systemUptime
        for combined in [true,false] {
            let path=NSBezierPath();let pts=snapshot.history
            let firstX=rect.minX+rect.width*CGFloat(max(0,1-(now-pts[0].time)/120))
            path.move(to:NSPoint(x:firstX,y:rect.maxY))
            for point in pts {
                let value=point.user+(combined ? point.system : 0)
                path.line(to:NSPoint(x:rect.minX+rect.width*CGFloat(max(0,min(1,1-(now-point.time)/120))),y:rect.maxY-rect.height*CGFloat(value/100)))
            }
            let lastX=rect.minX+rect.width*CGFloat(max(0,min(1,1-(now-pts.last!.time)/120)))
            path.line(to:NSPoint(x:lastX,y:rect.maxY));path.close()
            (combined ? NSColor.systemTeal : NSColor.systemBlue).withAlphaComponent(0.85).setFill();path.fill()
        }
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.windowBackgroundColor.setFill();bounds.fill()
        let s=snapshot,b=s.basic
        if page != .overview { text(page == .settings ? "设置" : "系统详情",88,11,142,12,.labelColor,true,.center);line(37) }
        if page == .settings {
            text("刷新间隔",14,57);text("登录时启动",14,97);text("收起与温度每 10 秒刷新，外观随系统。",14,132,286,10,.secondaryLabelColor)
            text(startupMessage.isEmpty ? "仅当前可见详情采集排行。" : startupMessage,14,149,286,10,.secondaryLabelColor)
        } else {
            let y:CGFloat=page == .overview ? 12 : 48
            s.health.1.setFill();NSBezierPath(ovalIn:NSRect(x:14,y:y+4,width:6,height:6)).fill();text(s.health.0,26,y,215,11,s.health.1,true)
            if page == .overview {
                text("CPU · 最近 2 分钟",14,39,200,9,.secondaryLabelColor);chart(NSRect(x:14,y:56,width:282,height:38))
                let rows=[("CPU",percent(s.cpu),temperature(s.cpuTemperature)),("GPU",percent(s.gpu?.valid == true ? s.gpu?.percent : nil),temperature(s.gpuTemperature)),("内存",percent(s.memoryPercent),s.pressure)]
                for (i,row) in rows.enumerated() {let top=CGFloat(109+i*35);text(row.0,14,top,50,12,.secondaryLabelColor);text(row.1,73,top,74,12,.labelColor,true);text(row.2,159,top,120,11,i==2 ? s.pressureColor : .labelColor,false,.right);text("›",287,top,12,12,.secondaryLabelColor);if i<2{line(top+25)}}
            } else {
                let names=["CPU","GPU","内存"], values=[percent(s.cpu),percent(s.gpu?.valid == true ? s.gpu?.percent : nil),percent(s.memoryPercent)], extras=[temperature(s.cpuTemperature),temperature(s.gpuTemperature),s.pressure]
                for i in 0..<3 {let x=CGFloat(14+i*99);text(names[i],x,75,92,10,.secondaryLabelColor);text(values[i],x,92,92,21,.labelColor,true);text(extras[i],x,119,92,10,i==2 ? s.pressureColor : .secondaryLabelColor)}
                text(b.memory_valid ? "\(bytes(b.used)) / \(bytes(b.total))" : "内存不可用",14,141,180,10,.secondaryLabelColor)
                text(b.swap_valid ? "Swap \(bytes(b.swap_used))" : "Swap —",194,141,103,10,.secondaryLabelColor,false,.right)
                if b.memory_valid {bar(14,159,282,b.used/b.total,.systemBlue)}
                text("进程排行",14,174,140,11,.labelColor,true)
                text("前 5 项 · 按进程",14,203,145,9,.secondaryLabelColor);text(rank == .cpu ? "CPU · 单核 100%" : "物理占用",164,203,132,9,.secondaryLabelColor,false,.right)
                if s.coverage.error != 0 { text("采集失败：\(s.coverage.error)",14,238,282,12,.systemRed) }
                else if !s.rankingReady { text("采样中，下次刷新显示排行…",14,238,282,11,.secondaryLabelColor) }
                else {
                    for (i,row) in s.rows.enumerated() {let top=CGFloat(226+i*24);text(row.name,14,top,188,11);text(rank == .cpu ? String(format:"%.1f%%",row.value) : bytes(row.value),204,top,92,11,.labelColor,true,.right)}
                }
                let coverage=s.coverage
                text("可读 \(coverage.read)/\(coverage.listed) · 不可访问或已退出 \(coverage.skipped)\(coverage.truncated ? " · 已截断" : "")",14,348,282,9,.secondaryLabelColor)
                if advanced {
                    line(394)
                    text("各核心负载",14,403,140,10,.secondaryLabelColor)
                    let n=Int(b.cores_count)
                    if n>0 { withUnsafeBytes(of:b.cores) { raw in
                        let vals=raw.bindMemory(to:Double.self);let w=282.0/CGFloat(n)
                        for i in 0..<n where vals[i].isFinite {NSColor.systemBlue.setFill();NSRect(x:14+CGFloat(i)*w,y:447-CGFloat(vals[i])*0.24,width:max(1,w-3),height:CGFloat(vals[i])*0.24).fill()}
                    }} else {text("采样中…",14,426,282,10,.secondaryLabelColor)}
                    let load=withUnsafeBytes(of:b.load){Array($0.bindMemory(to:Double.self))}
                    let items:[(String,String)]=[
                        ("平均负载 · 1 / 5 / 15 分钟",load.map{$0.isFinite ? String(format:"%.2f",$0) : "—"}.joined(separator:" / ")),
                        ("运行时间",b.uptime.isFinite ? "\(Int(b.uptime)/86400) 天 \(Int(b.uptime)%86400/3600) 小时" : "—"),
                        ("GPU 统一内存",s.gpu?.memory.isFinite == true ? bytes(s.gpu!.memory) : "—"),
                        ("应用 / 有线 / 压缩",b.memory_valid ? "\(bytes(b.app)) / \(bytes(b.wired)) / \(bytes(b.compressed))" : "—"),
                        ("缓存（可回收）",b.memory_valid ? bytes(b.cache) : "—"),
                        ("换入 / 换出",b.swap_rate_valid ? String(format:"%.1f / %.1f MB/s",b.swap_in/1_048_576,b.swap_out/1_048_576) : "—")]
                    for (i,item) in items.enumerated(){let y=CGFloat(455+i*22);text(item.0,14,y,139,9,.secondaryLabelColor);text(item.1,147,y,150,9,.labelColor,false,.right)}
                    text("温度：已识别传感器最高值 · CPU \(s.cpuTemperature?.found ?? 0)/10 · GPU \(s.gpuTemperature?.found ?? 0)/4",14,591,282,9,.secondaryLabelColor)
                    text("GPU 内存属于统一内存，不能重复相加。",14,608,282,9,.secondaryLabelColor)
                }
            }
        }
        line(bounds.height-32);text("每 \(Int(interval)) 秒刷新",82,bounds.height-23,150,9,.secondaryLabelColor,false,.center)
    }
}
