import AppKit

/// Local-only inventory; collection stops and rows are released when the window closes.
final class ProcessController:NSObject,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate,NSSearchFieldDelegate {
    private let snapshot:()->(Snapshot,Date)
    private let collector=DiagnosticCollector()
    private var window:NSWindow?
    private let table=NSTableView(),search=NSSearchField(),sort=NSPopUpButton()
    private let status=NSTextField(labelWithString:""),receipt=NSTextField(wrappingLabelWithString:"只在本机查看；不会发送给模型。")
    private var rows:[DiagnosticProcess]=[],filtered:[DiagnosticProcess]=[]
    private var timer:Timer?,busy=false,suspended=false
    var onAsk:((DiagnosticProcess)->Void)?
    var onQuit:((DiagnosticProcess)->Void)?
    init(snapshot:@escaping()->(Snapshot,Date)){self.snapshot=snapshot;super.init()}
    private func button(_ title:String,_ selector:Selector)->NSButton {
        let b=NSButton(title:title,target:self,action:selector);Obsidian.style(b);return b
    }
    private func prepare(){
        guard window==nil else{return}
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:600),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        w.title="tinyStat · 正在运行";w.appearance=NSAppearance(named:.darkAqua);w.backgroundColor=Obsidian.background;w.minSize=NSSize(width:640,height:420);w.isReleasedWhenClosed=false;w.delegate=self;window=w
        search.placeholderString="搜索进程名或 PID";search.delegate=self
        sort.addItems(withTitles:["内存 ↓","CPU ↓","线程数 ↓","名称"]);sort.target=self;sort.action=#selector(filterChanged)
        let refresh=button("刷新",#selector(refreshClicked))
        let controls=NSStackView(views:[search,sort,refresh]);controls.spacing=12
        table.headerView=NSTableHeaderView();table.rowHeight=31;table.intercellSpacing=NSSize(width:12,height:3);table.backgroundColor=Obsidian.background;table.usesAlternatingRowBackgroundColors=false;table.style = .plain
        for (id,title,width) in [("name","进程",300.0),("pid","PID",70.0),("cpu","CPU %",85.0),("memory","内存",100.0),("threads","线程数",65.0)] {
            let c=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id));c.title=title;c.width=width;c.minWidth=id=="name" ? 160:60;table.addTableColumn(c)
        }
        table.delegate=self;table.dataSource=self;table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.setAccessibilityLabel("本机进程列表")
        let scroll=NSScrollView();scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.drawsBackground=false
        status.font = .monospacedSystemFont(ofSize:11,weight:.regular);status.textColor=Obsidian.secondary
        receipt.font = .systemFont(ofSize:12);receipt.textColor=Obsidian.secondary;receipt.maximumNumberOfLines=3
        let note=NSTextField(wrappingLabelWithString:"CPU 单核为 100%，可超过 100%。内存为单进程物理占用，未按应用合并；线程数不是线程占用。— 表示不可读或尚无采样。")
        note.font = .systemFont(ofSize:11);note.textColor=Obsidian.quiet
        let actions=NSStackView(views:[button("询问此进程",#selector(askSelected)),button("正常退出…",#selector(quitSelected))]);actions.spacing=16
        let root=w.contentView!
        for v in [controls,scroll,status,note,receipt,actions]{root.addSubview(v);v.translatesAutoresizingMaskIntoConstraints=false}
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo:root.topAnchor,constant:18),controls.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:20),controls.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-20),search.widthAnchor.constraint(greaterThanOrEqualToConstant:270),
            status.topAnchor.constraint(equalTo:controls.bottomAnchor,constant:14),status.leadingAnchor.constraint(equalTo:controls.leadingAnchor),status.trailingAnchor.constraint(equalTo:controls.trailingAnchor),
            scroll.topAnchor.constraint(equalTo:status.bottomAnchor,constant:12),scroll.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:14),scroll.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-14),scroll.bottomAnchor.constraint(equalTo:note.topAnchor,constant:-12),
            note.leadingAnchor.constraint(equalTo:controls.leadingAnchor),note.trailingAnchor.constraint(equalTo:controls.trailingAnchor),note.bottomAnchor.constraint(equalTo:receipt.topAnchor,constant:-10),
            receipt.leadingAnchor.constraint(equalTo:controls.leadingAnchor),receipt.trailingAnchor.constraint(equalTo:controls.trailingAnchor),receipt.bottomAnchor.constraint(equalTo:actions.topAnchor,constant:-12),
            actions.leadingAnchor.constraint(equalTo:controls.leadingAnchor),actions.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-16)
        ]);w.center()
    }
    func show(){prepare();window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);start();refresh()}
    private func start(){timer?.invalidate();guard !suspended,window?.isMiniaturized==false else{return};timer=Timer.scheduledTimer(withTimeInterval:RefreshCadence.opened,repeats:true){[weak self] _ in self?.refresh()}}
    func suspend(){suspended=true;timer?.invalidate();timer=nil;collector.cancel();busy=false;status.stringValue="采样已暂停"}
    func resume(){suspended=false;if window?.isVisible==true{start();refresh()}}
    func windowWillClose(_ notification:Notification){timer?.invalidate();timer=nil;collector.cancel();busy=false;rows=[];filtered=[];table.reloadData()}
    func windowDidMiniaturize(_ notification:Notification){timer?.invalidate();timer=nil;collector.cancel();busy=false;status.stringValue="采样已暂停"}
    func windowDidDeminiaturize(_ notification:Notification){start();refresh()}
    func showReceipt(_ text:String){receipt.stringValue="操作回执 · "+displayIdentity(text);collector.cancel();busy=false;rows=[];applyFilter();refresh()}
    @objc private func refreshClicked(){refresh()}
    private func refresh(){
        guard !busy,!suspended,window?.isVisible==true,window?.isMiniaturized==false else{return};busy=true
        status.stringValue=rows.isEmpty ? "正在采样进程…":"正在刷新 · 上次结果保留至新采样完成"
        let (s,date)=snapshot()
        collector.collect(snapshot:s,at:date,allProcesses:true){[weak self] result in
            guard let self=self else{return};self.busy=false
            switch result {
            case .failure(let error):self.rows=[];self.applyFilter();self.status.stringValue="采样失败："+error.localizedDescription
            case .success(let e):
                self.rows=e.processes;self.applyFilter()
                let time=DateFormatter.localizedString(from:e.capturedAt,dateStyle:.none,timeStyle:.medium)
                self.status.stringValue="\(time) · 可读 \(e.readable)/\(e.listed) · 不可读/已退出 \(e.skipped)\(e.truncated ? " · 已截断":"")"
            }
        }
    }
    func controlTextDidChange(_ obj:Notification){applyFilter()}
    @objc private func filterChanged(){applyFilter()}
    private func applyFilter(){
        let selected=selectedProcess?.id,q=search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        filtered=rows.filter{q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || String($0.pid).contains(q)}.sorted{a,b in
            switch sort.indexOfSelectedItem {
            case 1:if a.cpuPercentOneCore != b.cpuPercentOneCore{return (a.cpuPercentOneCore ?? -1)>(b.cpuPercentOneCore ?? -1)}
            case 2:if a.threadCount != b.threadCount{return (a.threadCount ?? -1)>(b.threadCount ?? -1)}
            case 3:let comparison=a.name.localizedStandardCompare(b.name);if comparison != .orderedSame{return comparison == .orderedAscending}
            default:if a.memoryBytes != b.memoryBytes{return a.memoryBytes>b.memoryBytes}
            };return a.pid<b.pid
        }
        table.reloadData();table.deselectAll(nil)
        if let selected=selected,let index=filtered.firstIndex(where:{$0.id==selected}){table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)}
    }
    private var selectedProcess:DiagnosticProcess?{filtered.indices.contains(table.selectedRow) ? filtered[table.selectedRow]:nil}
    @objc private func askSelected(){guard let p=selectedProcess else{status.stringValue="请先选择一个进程。";return};onAsk?(p)}
    @objc private func quitSelected(){guard let p=selectedProcess else{status.stringValue="请先选择一个进程。";return};guard QuitTarget.capture(p) != nil else{status.stringValue="该进程不能正常退出，或已退出；不会强制结束。";return};onQuit?(p)}
    func numberOfRows(in tableView:NSTableView)->Int{filtered.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        guard filtered.indices.contains(row),let column=tableColumn else{return nil};let p=filtered[row]
        let cell=(tableView.makeView(withIdentifier:column.identifier,owner:self) as? NSTextField) ?? NSTextField(labelWithString:"")
        cell.identifier=column.identifier;cell.font = .monospacedSystemFont(ofSize:12,weight:.regular);cell.textColor=Obsidian.ink;cell.lineBreakMode = .byTruncatingTail
        switch column.identifier.rawValue {
        case "name":cell.stringValue=displayIdentity(p.name)
        case "pid":cell.stringValue=String(p.pid)
        case "cpu":cell.stringValue=p.cpuPercentOneCore.map{String(format:"%.1f",$0)} ?? "—"
        case "memory":cell.stringValue=bytes(Double(p.memoryBytes))
        default:cell.stringValue=p.threadCount.map{String($0)} ?? "—"
        };cell.toolTip=cell.stringValue;return cell
    }
}
