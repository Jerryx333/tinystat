import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let worker = DispatchQueue(label:"local.tinystat.sampling",qos:.utility)
    private let sampler = Sampler()
    private var timer: DispatchSourceTimer?
    private var inFlight = false
    private var pending = false
    private var generation = 0
    private var sleeping = false
    private var lastHealth = ""
    private var status: NSStatusItem!
    private var panel: NSPanel!
    private var scroll: NSScrollView!
    private var dashboard: Dashboard!
    private var demand = Demand()
    private var snapshot = Snapshot()
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
        demand.interval=UserDefaults.standard.double(forKey:"interval")==10 ? 10 : 5
        if benchmarkMode != nil { demand.interval=5 }
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
        if args.contains("--diagnose-status") {
            DispatchQueue.main.asyncAfter(deadline:.now()+2) { [weak self] in
                guard let self=self, let button=self.status.button else { return }
                print("STATUS visible=\(self.status.isVisible) length=\(self.status.length) title=\(button.title) frame=\(String(describing:button.window?.frame))")
                for screen in NSScreen.screens { print("SCREEN \(screen.frame)") }
                fflush(stdout)
            }
        }
        startTimer();requestSample()
        if args.contains("--show") && benchmarkMode == nil { openPanel() }
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
        dashboard=Dashboard(frame:NSRect(x:0,y:0,width:310,height:250));dashboard.interval=demand.interval
        dashboard.startup=SMAppService.mainApp.status == .enabled
        dashboard.action={ [weak self] in self?.handle($0) }
        panel=NSPanel(contentRect:dashboard.bounds,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed=false;panel.level = .popUpMenu;panel.hasShadow=true;panel.isOpaque=false;panel.backgroundColor = .clear
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.transient];panel.hidesOnDeactivate=false
        scroll=NSScrollView(frame:dashboard.bounds);scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.scrollerStyle = .overlay;scroll.drawsBackground=false;scroll.documentView=dashboard
        panel.contentView=scroll;scroll.wantsLayer=true;scroll.layer?.cornerRadius=11;scroll.layer?.masksToBounds=true
        dashboard.layer?.cornerRadius=11;dashboard.layer?.masksToBounds=true
    }
    private func startTimer() {
        timer?.cancel()
        let source=DispatchSource.makeTimerSource(queue:.main)
        let interval=demand.visible ? demand.interval : max(10,demand.interval)
        source.schedule(deadline:.now()+interval,repeating:interval,leeway:.milliseconds(500))
        source.setEventHandler{ [weak self] in self?.requestSample() };timer=source;source.resume()
    }
    private func requestSample() {
        guard !sleeping else{return}
        if inFlight { pending=true;return }
        inFlight=true
        let selected=demand,version=generation
        worker.async { [weak self] in
            guard let self=self else{return}
            let result=autoreleasepool { self.sampler.sample(selected) }
            DispatchQueue.main.async {
                self.inFlight=false
                if version==self.generation && !self.sleeping { self.snapshot=result;self.render() }
                if self.pending {self.pending=false;self.requestSample()}
            }
        }
    }
    private func render() {
        let s=snapshot
        let title="● CPU \(percent(s.cpu)) · \(temperature(s.cpuTemperature))  MEM \(percent(s.memoryPercent))"
        if status.button?.title != title || lastHealth != s.health.0 {
            lastHealth=s.health.0
            let text=NSMutableAttributedString(string:title,attributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:11,weight:.medium),.foregroundColor:NSColor.labelColor]);text.addAttribute(.foregroundColor,value:s.health.1,range:NSRange(location:0,length:1));status.button?.attributedTitle=text
        }
        let tooltip="\(s.health.0) · \(s.pressure)\nCPU 温度：已识别传感器最高值 \(s.cpuTemperature?.found ?? 0)/10\n点击展开，移出面板自动关闭"
        if status.button?.toolTip != tooltip { status.button?.toolTip=tooltip }
        if demand.visible {
            dashboard.snapshot=s;dashboard.needsDisplay=true
            dashboard.setAccessibilityValue("\(s.health.0)，CPU \(percent(s.cpu))，\(temperature(s.cpuTemperature))，GPU \(percent(s.gpu?.valid == true ? s.gpu?.percent : nil))，\(temperature(s.gpuTemperature))，内存 \(percent(s.memoryPercent))，\(s.pressure)")
            if firstUpdateLatency == nil && openedAt>0 {firstUpdateLatency=ProcessInfo.processInfo.systemUptime-openedAt}
        }
        if benchmarkStart>0 {let r=ts_resources();peakRSS=max(peakRSS,r.rss);peakFootprint=max(peakFootprint,r.footprint)}
    }
    @objc private func toggle() { demand.visible ? closePanel() : openPanel() }
    private func openPanel() {
        preparePanel();demand.visible=true;generation+=1;openedAt=ProcessInfo.processInfo.systemUptime;firstUpdateLatency=nil
        dashboard.page=demand.page;dashboard.rank=demand.rank;dashboard.advanced=demand.advanced;dashboard.snapshot=snapshot;dashboard.configure()
        positionPanel();panel.orderFrontRegardless();installMonitors();startTimer();requestSample()
    }
    private func positionPanel() {
        guard let w=status.button?.window else{return}
        let screen=w.screen ?? NSScreen.main;let bounds=screen?.visibleFrame ?? w.frame
        let h=min(dashboard.desiredHeight,bounds.height-12)
        var x=w.frame.maxX-310;x=max(bounds.minX+6,min(x,bounds.maxX-316))
        let top=w.frame.minY-3
        panel.setFrame(NSRect(x:x,y:max(bounds.minY+6,top-h),width:310,height:h),display:true)
        dashboard.frame=NSRect(x:0,y:0,width:310,height:dashboard.desiredHeight)
        dashboard.scroll(.zero)
    }
    private func closePanel() {
        closeWork?.cancel();closeWork=nil;demand.visible=false;demand.page = .overview;demand.advanced=false;generation+=1
        panel?.orderOut(nil);removeMonitors()
        let oldPanel=panel
        panel=nil;scroll=nil;dashboard=nil
        DispatchQueue.main.async { oldPanel?.contentView=nil }
        worker.async { [weak self] in self?.sampler.resetDetails() }
        if !sleeping { startTimer() }
        // In-flight reads finish once, their obsolete result is discarded. No new detail reads are scheduled.
    }
    private func handle(_ id:String) {
        switch id {
        case "cpuRow","gpuRow":demand.page = .details;demand.rank = .cpu
        case "memoryRow":demand.page = .details;demand.rank = .memory
        case "back":demand.page = .overview;demand.advanced=false
        case "cpu":demand.rank = .cpu
        case "memory":demand.rank = .memory
        case "advanced":demand.advanced.toggle()
        case "settings":demand.page = .settings;demand.advanced=false
        case "close":closePanel();return
        case "interval":demand.interval=demand.interval==5 ? 10 : 5;dashboard.interval=demand.interval;UserDefaults.standard.set(demand.interval,forKey:"interval");startTimer()
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
            if event.type == .keyDown && event.keyCode==53 {self?.closePanel();return nil}
            self?.trackPointer(event);return event
        }
        globalMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.mouseMoved,.leftMouseDragged,.rightMouseDragged,.leftMouseDown,.rightMouseDown]){[weak self] in self?.trackPointer($0)}
    }
    private func removeMonitors() {if let m=localMonitor{NSEvent.removeMonitor(m)};if let m=globalMonitor{NSEvent.removeMonitor(m)};localMonitor=nil;globalMonitor=nil}
    private func trackPointer(_ event:NSEvent) {
        guard demand.visible,benchmarkMode == nil else{return}
        let point=NSEvent.mouseLocation
        let inPanel=panel.frame.contains(point)
        let inButton=status.button?.window?.frame.contains(point) ?? false
        if inPanel {exitArmed=true;closeWork?.cancel();closeWork=nil;return}
        if inButton {closeWork?.cancel();closeWork=nil;return}
        // A short grace bridges the menu-bar/panel gap; no persistent mouse polling.
        if event.type == .leftMouseDown || event.type == .rightMouseDown {closePanel();return}
        if closeWork == nil {
            let work=DispatchWorkItem{[weak self] in self?.closePanel()};closeWork=work
            DispatchQueue.main.asyncAfter(deadline:.now()+(exitArmed ? 0.12 : 0.3),execute:work)
        }
    }
    @objc private func sleep() {sleeping=true;timer?.cancel();timer=nil;closePanel();worker.async{[weak self] in self?.sampler.reset()}}
    @objc private func wake() {guard sleeping else{return};sleeping=false;generation+=1;startTimer();requestSample()}
    @objc private func thermalChanged() {DispatchQueue.main.async{[weak self] in guard let self=self else{return};self.snapshot.thermal=ProcessInfo.processInfo.thermalState;self.render()}}
    @objc private func screenChanged() {if demand.visible{positionPanel()}}
    private func beginBenchmark() {
        worker.async { [weak self] in guard let self=self else{return};let counters=self.sampler.counters();DispatchQueue.main.async {self.benchCounters=counters} }
        benchmarkBaseline=ts_resources();benchmarkStart=ProcessInfo.processInfo.systemUptime;peakRSS=benchmarkBaseline.rss;peakFootprint=benchmarkBaseline.footprint
        DispatchQueue.main.asyncAfter(deadline:.now()+benchmarkDuration){[weak self] in self?.finishBenchmark()}
    }
    private func finishBenchmark() {
        let end=ts_resources(),elapsed=ProcessInfo.processInfo.systemUptime-benchmarkStart
        let report:[String:Any]=["mode":benchmarkMode!,"elapsed_seconds":elapsed,"cpu_seconds":end.cpu_seconds-benchmarkBaseline.cpu_seconds,"cpu_percent_one_core":(end.cpu_seconds-benchmarkBaseline.cpu_seconds)/elapsed*100,"rss_bytes":end.rss,"peak_sampled_rss_bytes":max(peakRSS,end.rss),"physical_footprint_bytes":end.footprint,"peak_sampled_footprint_bytes":max(peakFootprint,end.footprint),"idle_wakeups":end.wakeups-benchmarkBaseline.wakeups,"first_panel_sample_seconds":firstUpdateLatency.map { $0 as Any } ?? NSNull(),"interval_seconds":demand.visible ? demand.interval : max(10,demand.interval)]
        worker.async { [weak self] in
            guard let self=self else{return};var merged=report;merged["sampling_counters_including_warmup"]=self.sampler.counters();merged["sampling_counters_at_start"]=self.benchCounters
            do {let data=try JSONSerialization.data(withJSONObject:merged,options:[.prettyPrinted,.sortedKeys]);try data.write(to:URL(fileURLWithPath:self.benchmarkFile!),options:.atomic);DispatchQueue.main.async{NSApp.terminate(nil)}}
            catch{fputs("Benchmark report failed: \(error)\n",stderr);exit(1)}
        }
    }
    func applicationWillTerminate(_ notification:Notification){timer?.cancel();removeMonitors();worker.sync{ts_close()}}
}
let application=NSApplication.shared
let delegate=AppDelegate()
application.delegate=delegate
application.setActivationPolicy(.accessory)
application.run()
