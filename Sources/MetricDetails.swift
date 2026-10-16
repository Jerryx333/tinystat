import AppKit

/// Read-only inspector. All charts are actual samples with fixed percentage axes.
final class MetricDetails:NSView {
    var metric=Metric.cpu
    var snapshot=Snapshot()
    var sampledAt=Date()
    var openProcesses:(()->Void)?
    private let more=NSButton(title:"查看全部进程 ↗",target:nil,action:nil)
    static let width:CGFloat=344
    static let height:CGFloat=510
    override var isFlipped:Bool{true}
    override init(frame:NSRect){
        super.init(frame:frame);appearance=NSAppearance(named:.darkAqua)
        Obsidian.apply(self,color:Obsidian.background,radius:14)
        more.target=self;more.action=#selector(openList);Obsidian.style(more);addSubview(more)
        more.frame=NSRect(x:18,y:470,width:145,height:26)
    }
    required init?(coder:NSCoder){fatalError("init(coder:) not supported")}
    @objc private func openList(){openProcesses?()}
    func update(_ value:Snapshot,at:Date){snapshot=value;sampledAt=at;more.isHidden=metric == .gpu;needsDisplay=true
        setAccessibilityElement(true);setAccessibilityRole(.group)
        setAccessibilityLabel("\(metric.rawValue.uppercased()) 详情")
        setAccessibilityValue("\(percent(reading))，\(metric == .memory ? value.pressure:temperature(metric == .cpu ? value.cpuTemperature:value.gpuTemperature))")
    }
    private var reading:Double?{switch metric{case .cpu:return snapshot.cpu;case .gpu:return snapshot.gpu?.valid == true ? snapshot.gpu?.percent:nil;case .memory:return snapshot.memoryPercent}}
    private func text(_ value:String,_ x:CGFloat,_ y:CGFloat,_ width:CGFloat,_ size:CGFloat=11,_ color:NSColor=Obsidian.secondary){
        let p=NSMutableParagraphStyle();p.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(in:NSRect(x:x,y:y,width:width,height:max(20,size+7)),withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:size,weight:.regular),.foregroundColor:color,.paragraphStyle:p])
    }
    private func rule(_ y:CGFloat){Obsidian.line.setFill();NSRect(x:20,y:y,width:bounds.width-40,height:1).fill()}
    private func pair(_ name:String,_ value:String,_ y:CGFloat){text(name,22,y,170);text(value,200,y,125,11,Obsidian.ink)}
    private func chart(){
        let r=NSRect(x:22,y:96,width:300,height:88),now=ProcessInfo.processInfo.systemUptime
        Obsidian.inset.setFill();NSBezierPath(roundedRect:r,xRadius:7,yRadius:7).fill()
        for i in 1...3{Obsidian.line.setFill();NSRect(x:r.minX,y:r.minY+CGFloat(i)*r.height/4,width:r.width,height:0.5).fill()}
        var previous:MetricPoint?,previousPoint:NSPoint?,count=0
        let line=NSBezierPath();line.lineWidth=1.6
        for sample in snapshot.metricHistory where now-sample.time<=120 {
            let value:Double?;switch metric{case .cpu:value=sample.cpu;case .gpu:value=sample.gpu;case .memory:value=sample.memory}
            guard let value=value,value.isFinite else{previous=nil;previousPoint=nil;continue}
            let point=NSPoint(x:r.minX+r.width*CGFloat(max(0,min(1,1-(now-sample.time)/120))),y:r.maxY-r.height*CGFloat(max(0,min(100,value))/100))
            if let old=previous,previousPoint != nil,sample.time-old.time<=8{line.line(to:point)}else{line.move(to:point)}
            previous=sample;previousPoint=point;count+=1
            Obsidian.accent.setFill();NSBezierPath(ovalIn:NSRect(x:point.x-1.5,y:point.y-1.5,width:3,height:3)).fill()
        }
        Obsidian.accent.setStroke();line.stroke()
        text("近 2 分钟 · 实测",22,189,180,10,Obsidian.quiet);text("0–100%",257,189,70,10,Obsidian.quiet)
        if count<2{text(count==0 ? "暂无有效采样":"正在积累趋势",40,128,250,11,Obsidian.secondary)}
    }
    override func draw(_ dirtyRect:NSRect){
        super.draw(dirtyRect)
        text(metric.rawValue.uppercased(),22,18,180,13,Obsidian.ink)
        let time=DateFormatter.localizedString(from:sampledAt,dateStyle:.none,timeStyle:.medium)
        text(time,237,20,90,10,Obsidian.quiet)
        text(percent(reading),22,41,180,34,Obsidian.ink)
        text(metric == .memory ? snapshot.pressure:temperature(metric == .cpu ? snapshot.cpuTemperature:snapshot.gpuTemperature),213,56,112,12)
        chart()
        let b=snapshot.basic
        switch metric {
        case .cpu:
            pair("用户 / 系统",b.cpu_valid ? "\(percent(b.user)) / \(percent(b.system))":"—",218)
            let cores=withUnsafeBytes(of:b.cores){Array($0.bindMemory(to:Double.self).prefix(Int(b.cores_count)))}
            text("每核使用率",22,245,140,10,Obsidian.quiet)
            if cores.isEmpty{text("正在采样…",160,245,160,10,Obsidian.quiet)}else{
                let shown=Array(cores.prefix(32)),width=300/CGFloat(shown.count)
                for (i,value) in shown.enumerated(){
                    let r=NSRect(x:22+CGFloat(i)*width,y:267,width:max(2,width-4),height:22)
                    Obsidian.inset.setFill();r.fill();guard value.isFinite else{continue};Obsidian.accent.withAlphaComponent(0.65).setFill()
                    NSRect(x:r.minX,y:r.maxY-r.height*CGFloat(max(0,min(100,value))/100),width:r.width,height:r.height*CGFloat(max(0,min(100,value))/100)).fill()
                }
            }
        case .memory:
            pair("应用 / 有线",b.memory_valid ? "\(bytes(b.app)) / \(bytes(b.wired))":"—",218)
            pair("压缩 / 缓存",b.memory_valid ? "\(bytes(b.compressed)) / \(bytes(b.cache))":"—",241)
            pair("交换空间",b.swap_valid ? bytes(b.swap_used):"—",264)
        case .gpu:
            pair("GPU 驱动采样值",percent(reading),223)
            pair("SMC 最高温度",temperature(snapshot.gpuTemperature),250)
            pair("温度传感器覆盖","\(snapshot.gpuTemperature?.found ?? 0) / \(snapshot.gpuTemperature?.expected ?? 0)",277)
            rule(312)
            text("当前没有可靠的逐进程 GPU 归因。",22,333,300)
            text("不以 CPU 或内存排行代替 GPU 排行。",22,356,300)
            text("0%：本次驱动报告为零；—：不可用。",22,400,300,10,Obsidian.quiet)
            text("非整个刷新间隔的平均值，可能错过短时负载。",22,422,300,10,Obsidian.quiet)
            return
        }
        rule(301)
        text("占用最高的进程",22,313,180,10,Obsidian.quiet)
        text(metric == .cpu ? "CPU · 单核 100%":"物理内存",226,313,100,10,Obsidian.quiet)
        if snapshot.coverage.error != 0{text("进程采样失败",22,344,280)}
        else if !snapshot.rankingReady{text("正在采样进程…",22,344,280)}
        else {
            for (index,row) in snapshot.rows.prefix(5).enumerated(){
                let y=CGFloat(337+index*24)
                text(displayIdentity(row.name),22,y,188,11,Obsidian.ink)
                text(metric == .cpu ? String(format:"%.1f%%",row.value):bytes(row.value),225,y,100,11,Obsidian.ink)
            }
        }
        text("可读 \(snapshot.coverage.read)/\(snapshot.coverage.listed)\(snapshot.coverage.truncated ? " · 已截断":"")",177,477,150,10,Obsidian.quiet)
    }
}
