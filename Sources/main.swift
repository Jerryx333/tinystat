import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let worker = DispatchQueue(label:"local.tinystat.sampling",qos:.utility)
    private let sampler = Sampler()
    private var timer: DispatchSourceTimer?
    private var scheduledInterval:Double?
    private var inFlight = false
    private var pending = false
    private var generation = 0
    private var sleeping = false
    private var diagnosticSampling=false
    private var lastHealth = ""
    private var status: NSStatusItem!
    private var panel: NSPanel!
    private var scroll: NSScrollView!
    private var detailPanel:NSPanel?
    private var detailView:MetricDetails?
    private var hoverWork:DispatchWorkItem?
    private var hoverMetric:Metric?
    private var detailCloseWork:DispatchWorkItem?
    private var dashboard: Dashboard!
    private var demand = Demand()
    private var snapshot = Snapshot()
    private var snapshotDate = Date()
    private var overviewDraft = ""
    private lazy var assistant = AssistantController(snapshot: { [weak self] completion in
        guard let self=self else{return};guard !self.sleeping else{completion(Snapshot(),Date());return}
        let version=self.generation
        self.diagnosticSampling=true
        self.worker.async {
            var selected=Demand();selected.visible=true
            // Establish a post-request baseline before the fresh CPU window.
            _ = self.sampler.sample(selected,forceReadings:true)
            self.worker.asyncAfter(deadline:.now()+1.1) {
                let result=self.sampler.sample(selected,forceReadings:true),date=Date()
                DispatchQueue.main.async {
                    self.diagnosticSampling=false
                    guard !self.sleeping else{completion(Snapshot(),Date());return}
                    if version==self.generation {self.snapshot=result;self.snapshotDate=date;self.render()}
                    completion(result,date)
                }
            }
        }
    })
    private lazy var processes = ProcessController(snapshot: { [weak self] in
        (self?.snapshot ?? Snapshot(),self?.snapshotDate ?? Date())
    })
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var closeWork: DispatchWorkItem?
    private var exitArmed = false
    private var benchmarkMode: String?
    private var benchmarkFile: String?
    private var benchmarkDuration = 0.0
    private var benchmarkStart = 0.0
    private var benchmarkBaseline = TSResources()
    private var benchCounters: [String:Any] = [:]
    private var peakRSS = 0.0
    private var peakFootprint = 0.0
    private var openedAt = 0.0
    private var firstUpdateLatency: Double?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args=CommandLine.arguments
        if let i=args.firstIndex(of:"--benchmark"), args.count>i+3 {
            benchmarkMode=args[i+1];benchmarkDuration=Double(args[i+2]) ?? 30;benchmarkFile=args[i+3]
            guard ["closed","after-close","overview","cpu","memory","advanced"].contains(benchmarkMode!),benchmarkDuration>=10 else { fputs("Invalid benchmark arguments\n",stderr);exit(64) }
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier:"local.tinystat.app").contains(where:{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}) && benchmarkMode == nil { exit(0) }
        // Stable identity lets macOS restore a user-selected menu-bar position.
        // New installs start near the right edge, ahead of menu-bar managers' hidden sections.
        let positionKey="NSStatusItem Preferred Position TinyStat.Monitor"
        if UserDefaults.standard.object(forKey:positionKey) == nil {
            UserDefaults.standard.set(220.0,forKey:positionKey)
        }
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        status.autosaveName="TinyStat.Monitor"
        guard let button=status.button else {exit(1)}
        button.title="CPU —  ·  MEM —";button.font = .monospacedDigitSystemFont(ofSize:11,weight:.medium);button.target=self;button.action=#selector(toggle)
        button.setAccessibilityLabel("TinyStat 系统监控")
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(sleep),name:NSWorkspace.willSleepNotification,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(wake),name:NSWorkspace.didWakeNotification,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(sleep),name:NSWorkspace.screensDidSleepNotification,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(wake),name:NSWorkspace.screensDidWakeNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(thermalChanged),name:ProcessInfo.thermalStateDidChangeNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(screenChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        for name in [NSWindow.didChangeOcclusionStateNotification,NSWindow.didMiniaturizeNotification,NSWindow.didDeminiaturizeNotification,NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(self,selector:#selector(windowVisibilityChanged),name:name,object:nil)
        }
        if args.contains("--diagnose-status") {
            DispatchQueue.main.asyncAfter(deadline:.now()+2) { [weak self] in
                guard let self=self, let button=self.status.button else { return }
                print("STATUS visible=\(self.status.isVisible) length=\(self.status.length) title=\(button.title) frame=\(String(describing:button.window?.frame))")
                for screen in NSScreen.screens { print("SCREEN \(screen.frame)") }
                fflush(stdout)
            }
        }
        let menu=NSMenu(),edit=NSMenu(title:"编辑"),item=NSMenuItem(title:"编辑",action:nil,keyEquivalent:"")
        for (title,selector,key) in [("撤销","undo:","z"),("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")] {
            edit.addItem(withTitle:title,action:Selector(selector),keyEquivalent:key)
        }
        item.submenu=edit;menu.addItem(item);NSApp.mainMenu=menu
        assistant.onProcesses={ [weak self] in self?.processes.show() }
        assistant.onReceipt={ [weak self] text in self?.processes.showReceipt(text) }
        processes.onAsk={ [weak self] process in self?.assistant.ask(process:process) }
        processes.onQuit={ [weak self] process in self?.assistant.reviewQuit(process:process) }
        startTimer();requestSample()
        if args.contains("--show") && benchmarkMode == nil { openPanel() }
        if args.contains("--show-assistant") && benchmarkMode == nil { assistant.show() }
        if args.contains("--show-processes") && benchmarkMode == nil { processes.show() }
        if let mode=benchmarkMode {
            if mode != "closed" {
                demand.page=mode=="overview" ? .overview : .details;demand.rank=mode=="memory" ? .memory : .cpu;demand.advanced=mode=="advanced";openPanel()
            }
            if mode == "after-close" { DispatchQueue.main.asyncAfter(deadline:.now()+10) { [weak self] in self?.closePanel() } }
            // Warm up frameworks and two delta samples before recording steady state.
            DispatchQueue.main.asyncAfter(deadline:.now()+11) { [weak self] in self?.beginBenchmark() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !demand.visible { openPanel() }; return true
    }
    private func preparePanel() {
        guard panel == nil else { return }
        dashboard=Dashboard(frame:NSRect(x:0,y:0,width:Dashboard.width,height:426))
        dashboard.draft=overviewDraft
        dashboard.action={ [weak self] in self?.handle($0) }
        dashboard.inspect={ [weak self] in self?.showDetails($0) }
        assistant.onBack={ [weak self] in self?.openPanel() }
        dashboard.ask={ [weak self] question in
            guard let self=self else{return};self.closePanel();self.assistant.show(question:question)
        }
        panel=MonitorPanel(contentRect:dashboard.bounds,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.acceptsMouseMovedEvents=true;panel.isReleasedWhenClosed=false;panel.level = .popUpMenu;panel.hasShadow=true;panel.isOpaque=false;panel.backgroundColor = .clear
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.transient];panel.hidesOnDeactivate=false
        scroll=NSScrollView(frame:dashboard.bounds);scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.scrollerStyle = .overlay;scroll.drawsBackground=false;scroll.documentView=dashboard
        panel.contentView=scroll;scroll.wantsLayer=true;scroll.layer?.cornerRadius=16;scroll.layer?.masksToBounds=true
        dashboard.layer?.cornerRadius=16;dashboard.layer?.masksToBounds=true
    }
    private var refreshInterval:Double {
        let opened=demand.visible || NSApp.windows.contains{$0.styleMask.contains(.titled) && $0.isVisible && !$0.isMiniaturized}
        return opened ? RefreshCadence.opened:RefreshCadence.closed
    }
    @objc private func windowVisibilityChanged(){
        DispatchQueue.main.async{[weak self] in self?.startTimer()}
    }
    private func startTimer() {
        guard !sleeping else{return}
        let interval=refreshInterval
        guard timer==nil || scheduledInterval != interval else{return}
        timer?.cancel();scheduledInterval=interval
        let source=DispatchSource.makeTimerSource(queue:.main)
        source.schedule(deadline:.now()+interval,repeating:interval,leeway:.milliseconds(500))
        source.setEventHandler{ [weak self] in self?.requestSample() };timer=source;source.resume()
    }
    private func requestSample() {
        guard !sleeping,!diagnosticSampling else{return}
        if inFlight { pending=true;return }
        inFlight=true
        let selected=demand,version=generation
        worker.async { [weak self] in
            guard let self=self else{return}
            let result=autoreleasepool { self.sampler.sample(selected) }
            DispatchQueue.main.async {
                self.inFlight=false
                if version==self.generation && !self.sleeping { self.snapshot=result;self.snapshotDate=Date();self.render() }
                if self.pending {self.pending=false;self.requestSample()}
            }
        }
    }
    private func render() {
        let s=snapshot
        let title="● CPU \(percent(s.cpu)) · \(temperature(s.cpuTemperature))  MEM \(percent(s.memoryPercent))"
        if status.button?.title != title || lastHealth != s.health.0 {
            lastHealth=s.health.0
            let text=NSMutableAttributedString(string:title,attributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:11,weight:.medium),.foregroundColor:NSColor.labelColor]);text.addAttribute(.foregroundColor,value:NSColor.secondaryLabelColor,range:NSRange(location:0,length:1));status.button?.attributedTitle=text
        }
        let tooltip="\(s.health.0) · \(s.pressure)\nCPU 温度：映射 SMC 最高值（不含 HID） \(s.cpuTemperature?.found ?? 0)/\(s.cpuTemperature?.expected ?? 0)\n点击展开；点击外部或 Esc 收起"
        if status.button?.toolTip != tooltip { status.button?.toolTip=tooltip }
        if demand.visible {
            dashboard.snapshot=s;dashboard.snapshotDate=snapshotDate;dashboard.needsDisplay=true
            dashboard.setAccessibilityValue("\(s.health.0)，CPU \(percent(s.cpu))，\(temperature(s.cpuTemperature))，GPU \(percent(s.gpu?.valid == true ? s.gpu?.percent : nil))，\(temperature(s.gpuTemperature))，内存 \(percent(s.memoryPercent))，\(s.pressure)")
            if firstUpdateLatency == nil && openedAt>0 {firstUpdateLatency=ProcessInfo.processInfo.systemUptime-openedAt}
        }
        detailView?.update(s,at:snapshotDate)
        if benchmarkStart>0 {let r=ts_resources();peakRSS=max(peakRSS,r.rss);peakFootprint=max(peakFootprint,r.footprint)}
    }
    @objc private func toggle() { demand.visible ? closePanel() : openPanel() }
    private func openPanel() {
        preparePanel();demand.visible=true;generation+=1;openedAt=ProcessInfo.processInfo.systemUptime;firstUpdateLatency=nil
        dashboard.page=demand.page;dashboard.rank=demand.rank;dashboard.advanced=demand.advanced;dashboard.snapshot=snapshot;dashboard.configure()
        positionPanel();panel.makeKeyAndOrderFront(nil);installMonitors();startTimer();requestSample()
    }
    private func positionPanel() {
        guard let w=status.button?.window else{return}
        let screen=w.screen ?? NSScreen.main;let bounds=screen?.visibleFrame ?? w.frame
        let h=min(dashboard.desiredHeight,bounds.height-12)
        var x=w.frame.maxX-Dashboard.width;x=max(bounds.minX+6,min(x,bounds.maxX-Dashboard.width-6))
        let top=w.frame.minY-3
        panel.setFrame(NSRect(x:x,y:max(bounds.minY+6,top-h),width:Dashboard.width,height:h),display:true)
        dashboard.frame=NSRect(x:0,y:0,width:Dashboard.width,height:dashboard.desiredHeight)
        dashboard.scroll(.zero)
    }
    private func closePanel() {
        hideDetails()
        closeWork?.cancel();closeWork=nil;demand.visible=false;demand.page = .overview;demand.advanced=false;generation+=1
        panel?.orderOut(nil);removeMonitors()
        overviewDraft=dashboard?.draft ?? overviewDraft
        let oldPanel=panel
        panel=nil;scroll=nil;dashboard=nil
        DispatchQueue.main.async { oldPanel?.contentView=nil }
        worker.async { [weak self] in self?.sampler.resetDetails() }
        if !sleeping { startTimer() }
        // In-flight reads finish once, their obsolete result is discarded. No new detail reads are scheduled.
    }
    private func handle(_ id:String) {
        hideDetails()
        switch id {
        case "assistant":closePanel();assistant.showSettings();return
        case "chat":closePanel();assistant.show();return
        case "processes":closePanel();processes.show();return
        case "back":demand.page = .overview;demand.advanced=false
        case "cpu":demand.rank = .cpu
        case "memory":demand.rank = .memory
        case "advanced":demand.advanced.toggle()
        case "settings":
            demand.page = .settings;demand.advanced=false
            dashboard.startup=SMAppService.mainApp.status == .enabled
        case "close":closePanel();return
        case "startup":
            do {
                if SMAppService.mainApp.status == .enabled {try SMAppService.mainApp.unregister()} else {try SMAppService.mainApp.register()}
                dashboard.startup=SMAppService.mainApp.status == .enabled
                dashboard.startupMessage=SMAppService.mainApp.status == .requiresApproval ? "请在系统设置 › 登录项中允许。" : ""
            } catch {dashboard.startupMessage="启动项设置失败：\(error.localizedDescription)"}
        case "quit":NSApp.terminate(nil);return
        default:return
        }
        generation+=1;dashboard.page=demand.page;dashboard.rank=demand.rank;dashboard.advanced=demand.advanced
        // Clear old rank immediately so a changed unit cannot label old values.
        snapshot.rows=[];snapshot.rankingReady=false;snapshot.coverage=TSProcessCoverage();dashboard.snapshot=snapshot
        dashboard.configure();positionPanel();requestSample()
    }
    private func installMonitors() {
        removeMonitors();exitArmed=false
        let mask:NSEvent.EventTypeMask=[.mouseMoved,.leftMouseDragged,.rightMouseDragged,.leftMouseDown,.rightMouseDown,.keyDown]
        localMonitor=NSEvent.addLocalMonitorForEvents(matching:mask){[weak self] event in
            if event.type == .keyDown && event.keyCode==53 {if let text=self?.panel?.firstResponder as? NSTextView,text.hasMarkedText(){return event};self?.closePanel();return nil}
            self?.trackPointer(event);return event
        }
        globalMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.mouseMoved,.leftMouseDragged,.rightMouseDragged,.leftMouseDown,.rightMouseDown]){[weak self] in self?.trackPointer($0)}
    }
    private func removeMonitors() {if let m=localMonitor{NSEvent.removeMonitor(m)};if let m=globalMonitor{NSEvent.removeMonitor(m)};localMonitor=nil;globalMonitor=nil}
    private func trackPointer(_ event:NSEvent) {
        guard demand.visible,benchmarkMode == nil else{return}
        let point=NSEvent.mouseLocation
        let inPanel=panel.frame.contains(point)
        let inDetail=detailPanel?.frame.contains(point) ?? false
        if event.type == .mouseMoved || event.type == .leftMouseDragged {
            if inPanel,let content=dashboard {
                let local=content.convert(panel.convertPoint(fromScreen:point),from:nil)
                if let metric=content.metric(at:local){
                    detailCloseWork?.cancel();detailCloseWork=nil
                    if demand.inspection==metric{hoverWork?.cancel();hoverWork=nil;hoverMetric=nil}
                    else if hoverMetric != metric {
                        hoverWork?.cancel();hoverMetric=metric
                        let work=DispatchWorkItem{[weak self] in
                            guard let self=self,self.hoverMetric==metric else{return}
                            guard self.currentHoveredMetric==metric else{self.hoverMetric=nil;self.hoverWork=nil;return}
                            self.showDetails(metric)
                        };hoverWork=work
                        DispatchQueue.main.asyncAfter(deadline:.now()+(detailPanel==nil ? 0.18:0.08),execute:work)
                    }
                }else{scheduleDetailClose()}
            }else if inDetail{detailCloseWork?.cancel();detailCloseWork=nil;hoverWork?.cancel();hoverWork=nil;hoverMetric=nil}
            else{scheduleDetailClose()}
        }
        let bridge=detailPanel.map{detail -> Bool in
            let left=detail.frame.maxX<=panel.frame.minX ? detail.frame.maxX:panel.frame.maxX
            let right=detail.frame.maxX<=panel.frame.minX ? panel.frame.minX:detail.frame.minX
            return right>=left && NSRect(x:left,y:max(detail.frame.minY,panel.frame.minY),width:right-left,height:max(0,min(detail.frame.maxY,panel.frame.maxY)-max(detail.frame.minY,panel.frame.minY))).contains(point)
        } ?? false
        if inDetail || bridge{closeWork?.cancel();closeWork=nil;return}
        let inButton=status.button?.window?.frame.contains(point) ?? false
        if inPanel {exitArmed=true;closeWork?.cancel();closeWork=nil;return}
        if inButton {closeWork?.cancel();closeWork=nil;return}
        // A short grace bridges the menu-bar/panel gap; no persistent mouse polling.
        if event.type == .leftMouseDown || event.type == .rightMouseDown {closePanel();return}
        if panel.isKeyWindow { return }
        if closeWork == nil {
            let work=DispatchWorkItem{[weak self] in self?.closePanel()};closeWork=work
            DispatchQueue.main.asyncAfter(deadline:.now()+(exitArmed ? 0.12 : 0.3),execute:work)
        }
    }
    private var currentHoveredMetric:Metric? {
        guard demand.visible,let panel=panel,let dashboard=dashboard,panel.frame.contains(NSEvent.mouseLocation) else{return nil}
        return dashboard.metric(at:dashboard.convert(panel.convertPoint(fromScreen:NSEvent.mouseLocation),from:nil))
    }
    private func scheduleDetailClose(){
        hoverWork?.cancel();hoverWork=nil;hoverMetric=nil
        guard detailPanel != nil,detailCloseWork==nil else{return}
        let work=DispatchWorkItem{[weak self] in self?.hideDetails()};detailCloseWork=work
        DispatchQueue.main.asyncAfter(deadline:.now()+0.45,execute:work)
    }
    private func showDetails(_ metric:Metric){
        guard demand.visible,demand.page != .settings else{return}
        hoverWork?.cancel();hoverWork=nil;hoverMetric=nil;detailCloseWork?.cancel();detailCloseWork=nil
        guard demand.inspection != metric || detailPanel==nil else{return}
        demand.inspection=metric;demand.rank=metric == .memory ? .memory:.cpu;generation+=1
        snapshot.rows=[];snapshot.rankingReady=false;snapshot.coverage=TSProcessCoverage()
        if detailPanel==nil {
            let view=MetricDetails(frame:NSRect(x:0,y:0,width:MetricDetails.width,height:MetricDetails.height))
            view.openProcesses={ [weak self] in self?.closePanel();self?.processes.show();self?.startTimer() }
            let detail=NSPanel(contentRect:view.bounds,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            detail.acceptsMouseMovedEvents=true;detail.isReleasedWhenClosed=false;detail.level = .popUpMenu;detail.hasShadow=true;detail.isOpaque=false;detail.backgroundColor = .clear
            detail.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.transient];detail.hidesOnDeactivate=false
            let scroll=NSScrollView(frame:view.bounds);scroll.documentView=view;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.scrollerStyle = .overlay;scroll.drawsBackground=false
            scroll.autoresizingMask=[.width,.height];scroll.wantsLayer=true;scroll.layer?.cornerRadius=14;scroll.layer?.masksToBounds=true
            detail.contentView=scroll;detailPanel=detail;detailView=view
        }
        detailPanel?.title="tinyStat · "+metric.rawValue.uppercased()
        detailView?.metric=metric;detailView?.update(snapshot,at:snapshotDate)
        detailView?.scroll(.zero);positionDetails();detailPanel?.orderFront(nil);requestSample()
    }
    private func positionDetails(){
        guard let detail=detailPanel,let panel=panel else{return}
        let bounds=(panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        let width=MetricDetails.width,height=min(MetricDetails.height,bounds.height-12)
        let left=panel.frame.minX-width-8
        let x=left>=bounds.minX+6 ? left:min(bounds.maxX-width-6,panel.frame.maxX+8)
        let y=max(bounds.minY+6,min(panel.frame.maxY-height,bounds.maxY-height-6))
        detail.setFrame(NSRect(x:max(bounds.minX+6,x),y:y,width:width,height:height),display:true)
    }
    private func hideDetails(){
        hoverWork?.cancel();hoverWork=nil;hoverMetric=nil;detailCloseWork?.cancel();detailCloseWork=nil
        let oldDetail=detailPanel;oldDetail?.orderOut(nil);detailPanel=nil;detailView=nil
        DispatchQueue.main.async{oldDetail?.contentView=nil}
        if demand.inspection != nil {
            demand.inspection=nil;generation+=1
            worker.async{[weak self] in self?.sampler.resetDetails()}
        }
    }
    @objc private func sleep() {assistant.suspend();processes.suspend();sleeping=true;timer?.cancel();timer=nil;closePanel();worker.async{[weak self] in self?.sampler.reset()}}
    @objc private func wake() {guard sleeping else{return};sleeping=false;processes.resume();generation+=1;startTimer();requestSample()}
    @objc private func thermalChanged() {DispatchQueue.main.async{[weak self] in guard let self=self else{return};self.snapshot.thermal=ProcessInfo.processInfo.thermalState;self.render()}}
    @objc private func screenChanged() {if demand.visible{positionPanel();positionDetails()}}
    private func beginBenchmark() {
        worker.async { [weak self] in guard let self=self else{return};let counters=self.sampler.counters();DispatchQueue.main.async {self.benchCounters=counters} }
        benchmarkBaseline=ts_resources();benchmarkStart=ProcessInfo.processInfo.systemUptime;peakRSS=benchmarkBaseline.rss;peakFootprint=benchmarkBaseline.footprint
        DispatchQueue.main.asyncAfter(deadline:.now()+benchmarkDuration){[weak self] in self?.finishBenchmark()}
    }
    private func finishBenchmark() {
        let end=ts_resources(),elapsed=ProcessInfo.processInfo.systemUptime-benchmarkStart
        let report:[String:Any]=["mode":benchmarkMode!,"elapsed_seconds":elapsed,"cpu_seconds":end.cpu_seconds-benchmarkBaseline.cpu_seconds,"cpu_percent_one_core":(end.cpu_seconds-benchmarkBaseline.cpu_seconds)/elapsed*100,"rss_bytes":end.rss,"peak_sampled_rss_bytes":max(peakRSS,end.rss),"physical_footprint_bytes":end.footprint,"peak_sampled_footprint_bytes":max(peakFootprint,end.footprint),"idle_wakeups":end.wakeups-benchmarkBaseline.wakeups,"first_panel_sample_seconds":firstUpdateLatency.map { $0 as Any } ?? NSNull(),"interval_seconds":scheduledInterval ?? refreshInterval]
        worker.async { [weak self] in
            guard let self=self else{return};var merged=report;merged["sampling_counters_including_warmup"]=self.sampler.counters();merged["sampling_counters_at_start"]=self.benchCounters
            do {let data=try JSONSerialization.data(withJSONObject:merged,options:[.prettyPrinted,.sortedKeys]);try data.write(to:URL(fileURLWithPath:self.benchmarkFile!),options:.atomic);DispatchQueue.main.async{NSApp.terminate(nil)}}
            catch{fputs("Benchmark report failed: \(error)\n",stderr);exit(1)}
        }
    }
    func applicationWillTerminate(_ notification:Notification){assistant.shutdown();processes.suspend();timer?.cancel();removeMonitors();worker.sync{ts_close()}}
}
let application=NSApplication.shared
let delegate=AppDelegate()
application.delegate=delegate
application.setActivationPolicy(.accessory)
application.run()
