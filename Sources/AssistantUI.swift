import AppKit

private func label(_ text:String,size:CGFloat=13,color:NSColor=Obsidian.ink,bold:Bool=false)->NSTextField {
    let v=NSTextField(wrappingLabelWithString:text);v.font = .systemFont(ofSize:size,weight:bold ? .medium:.regular);v.textColor=color;v.isSelectable=true
    v.setContentCompressionResistancePriority(.defaultLow,for:.horizontal);return v
}
private func stack(_ views:[NSView],vertical:Bool=true,spacing:CGFloat=10)->NSStackView {
    let s=NSStackView(views:views);s.orientation=vertical ? .vertical:.horizontal;s.alignment=vertical ? .leading:.centerY;s.spacing=spacing;return s
}
private func card(_ views:[NSView],color:NSColor=Obsidian.surface)->NSStackView {
    let v=stack(views,spacing:12);v.edgeInsets=NSEdgeInsets(top:16,left:16,bottom:16,right:16);Obsidian.apply(v,color:color,radius:10)
    for child in views where !(child is NSButton){child.translatesAutoresizingMaskIntoConstraints=false;child.widthAnchor.constraint(equalTo:v.widthAnchor,constant:-32).isActive=true};return v
}
private final class ChatLog:NSStackView {override var isFlipped:Bool{true}}
final class AssistantController:NSObject,NSWindowDelegate {
    private let snapshot:(@escaping(Snapshot,Date)->Void)->Void
    private let collector=DiagnosticCollector(),backend=AgentBackend()
    private var window:AssistantWindow?
    private var settingsWindow:AgentSettingsWindow?
    private let log=ChatLog(),scroller=NSScrollView()
    private let composer=MessageComposer(placeholder:"继续问，或者告诉我你的决定…",attachment:true)
    private let status=label("",size:11,color:Obsidian.quiet)
    private let modelButton=NSButton(title:"",target:nil,action:nil)
    private let progress=NSProgressIndicator()
    private var session=ChatSession()
    private let store=ConversationStore()
    private let investigation=Investigation()
    private var sessionList:[SessionSummary]=[]
    private var previousEvidence:DiagnosticEvidence?
    private var registered:[String:DiagnosticProcess]=[:]
    private var targetStops:[String:StopTarget]=[:]
    private var focus:DiagnosticProcess?
    private var budget=InvestigationBudget()
    private var checkResults:[[String:Any]]=[]
    private var currentQuestion=""
    private var requestConversation:[[String:String]]=[]
    private var omittedMessages=0
    private var saveError:String?
    private var droppedRecord=false
    private var readSeconds=0.0
    private var modelSource=""
    var modelRequest:((AgentSettings,String,@escaping(Result<String,Error>)->Void)->Void)?
    private var pageOffset=0
    private var scrollScheduled=false
    private var restoring=false
    private var persistent=true
    private let focusButton=NSButton(title:"",target:nil,action:nil)
    private var grantSheet:NSAlert?

    private var files:[FileTarget]=[]
    private var protection=ActionProtection()
    private var generation=0,busy=false,operating=false
    private var actionButtons:[NSButton]=[]
    private var handlers:[ObjectIdentifier:()->Void]=[:]
    private var targetFiles:[String:FileTarget]=[:],targetApps:[String:QuitTarget]=[:]
    private var evidence:DiagnosticEvidence?
    var onBack:(()->Void)?
    var onProcesses:(()->Void)?
    var onReceipt:((String)->Void)?
    private var focusedDraft:(id:String,text:String)?
    private let latestReceipt=label("",size:12,color:Obsidian.accent)
    init(snapshot:@escaping(@escaping(Snapshot,Date)->Void)->Void,persistent:Bool=true){self.snapshot=snapshot;self.persistent=persistent;super.init()}
    private func button(_ title:String,primary:Bool=false,_ action:@escaping()->Void)->NSButton {
        let b=NSButton(title:title,target:self,action:#selector(invoke(_:)));Obsidian.style(b,primary:primary);handlers[ObjectIdentifier(b)]=action;return b
    }
    @objc private func invoke(_ sender:NSButton){handlers[ObjectIdentifier(sender)]?()}
    private func prepare(){
        guard window==nil else{return}
        let w=AssistantWindow(contentRect:NSRect(x:0,y:0,width:620,height:760),styleMask:[.titled,.closable,.resizable,.miniaturizable,.fullSizeContentView],backing:.buffered,defer:false)
        w.title="tinyStat";w.titleVisibility = .hidden;w.titlebarAppearsTransparent=true;w.appearance=NSAppearance(named:.darkAqua);w.backgroundColor=Obsidian.background
        w.minSize=NSSize(width:520,height:570);w.isReleasedWhenClosed=false;w.delegate=self;window=w
        w.focusInput={ [weak self] in self?.composer.focus() };w.escape={ [weak self] in if self?.busy == true{self?.stopClicked()}else{self?.window?.performClose(nil);self?.onBack?()} }
        let root=NSView();w.contentView=root
        let back=button("‹"){[weak self] in self?.window?.performClose(nil);self?.onBack?()};back.setAccessibilityLabel("返回概览")
        let brand=stack([back,label("tinyStat",size:14,bold:true)],vertical:false)
        let archive=button("历史"){[weak self] in self?.showHistory()}
        let fresh=button("＋ 新对话"){[weak self] in self?.newChat()}
        let settings=button("连接"){[weak self] in self?.showSettings()}
        let inventory=button("进程列表"){[weak self] in self?.onProcesses?()}
        let top=stack([brand,NSView(),inventory,archive,fresh,settings],vertical:false)
        let subtitle=label("诊断会话  /  操作前由你确认",size:11,color:Obsidian.quiet)
        latestReceipt.isHidden=true;latestReceipt.maximumNumberOfLines=3
        focusButton.target=self;focusButton.action=#selector(clearFocus);Obsidian.style(focusButton);focusButton.isHidden=true
        let earlier=button("‹ 较早 40 条"){[weak self] in self?.turnPage(older:true)}
        let later=button("最近 / 较新 ›"){[weak self] in self?.turnPage(older:false)}
        let intro=stack([subtitle,focusButton,latestReceipt,stack([earlier,later],vertical:false)],spacing:6)
        log.orientation = .vertical;log.alignment = .leading;log.spacing=24;log.edgeInsets=NSEdgeInsets(top:8,left:28,bottom:18,right:28)
        scroller.hasVerticalScroller=true;scroller.autohidesScrollers=true;scroller.scrollerStyle = .overlay;scroller.drawsBackground=false;scroller.documentView=log
        log.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([log.leadingAnchor.constraint(equalTo:scroller.contentView.leadingAnchor),log.trailingAnchor.constraint(equalTo:scroller.contentView.trailingAnchor),log.topAnchor.constraint(equalTo:scroller.contentView.topAnchor)])
        composer.onSend={ [weak self] _ in self?.submit() };composer.onStop={ [weak self] in self?.stopClicked() };composer.onAttach={ [weak self] in self?.selectFile() }
        modelButton.target=self;modelButton.action=#selector(modelSettings);Obsidian.style(modelButton)
        progress.style = .spinning;progress.controlSize = .small;progress.isDisplayedWhenStopped=false
        let footer=stack([modelButton,NSView(),label("⌘ K 输入 · Shift ↵ 换行",size:11,color:Obsidian.quiet)],vertical:false)
        let state=stack([progress,status],vertical:false,spacing:7)
        for v in [top,intro,scroller,state,composer,footer]{root.addSubview(v);v.translatesAutoresizingMaskIntoConstraints=false}
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo:root.topAnchor,constant:36),top.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:24),top.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-24),top.heightAnchor.constraint(equalToConstant:30),
            intro.topAnchor.constraint(equalTo:top.bottomAnchor,constant:20),intro.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:28),intro.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-28),
            scroller.topAnchor.constraint(equalTo:intro.bottomAnchor,constant:16),scroller.leadingAnchor.constraint(equalTo:root.leadingAnchor),scroller.trailingAnchor.constraint(equalTo:root.trailingAnchor),scroller.bottomAnchor.constraint(equalTo:state.topAnchor,constant:-8),
            state.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:28),state.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-28),state.bottomAnchor.constraint(equalTo:composer.topAnchor,constant:-12),
            composer.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:20),composer.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-20),composer.bottomAnchor.constraint(equalTo:footer.topAnchor,constant:-10),
            footer.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:26),footer.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-26),footer.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-16),footer.heightAnchor.constraint(equalToConstant:24)
        ])
        updateStatus();append("tinyStat","进程列表可直接查看正在运行的程序。按需申请读取与发送，操作由你确认。文字与回执保存在本机历史（最多30个会话），旧消息按页查看；检查正文与授权不保存。",color:Obsidian.secondary);w.center()
    }
    func show(question:String?=nil){prepare();if log.arrangedSubviews.isEmpty && !session.messages.isEmpty{renderPage()};window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);if let q=question{focusedDraft=nil;if busy || operating{append("待发送的问题",q+"\n当前检查或操作尚未结束。",color:Obsidian.secondary);if composer.value.isEmpty{composer.value=q}}else{composer.value=q;submit()}}else{composer.focus()}}
    func ask(process:DiagnosticProcess){
        prepare();guard !busy,!operating else{show();append("tinyStat","请等待当前检查或操作完成，再询问所选进程。",color:Obsidian.secondary);return}
        show();composer.value="看看进程 \(displayIdentity(process.name))（PID \(process.pid)）的占用，是否需要处理？";focusedDraft=(process.id,composer.value);focus=process;registered[process.id]=process;updateStatus();composer.focus()
    }
    func reviewQuit(process:DiagnosticProcess){
        show();guard !busy,!operating else{append("tinyStat","请等待当前检查或操作完成。",color:Obsidian.secondary);return}
        guard let app=QuitTarget.capture(process) else{append("无法正常退出","该进程不是可正常退出的前台应用，或已退出。不会强制结束系统、后台或辅助进程。",color:Obsidian.secondary);return}
        guard protection.allows(app) else{append("本地保护","此应用已设为保留，本会话内不会退出。",color:Obsidian.secondary);return}
        invalidateActions();targetApps[app.id]=app
        showAction(ActionProposal(kind:"quitApp",targetID:app.id,reason:"你在进程列表中选择了正常退出。确认后由本机执行，无需模型。"))
    }
    @objc private func modelSettings(){showSettings()}
    func showSettings(){prepare();guard !busy,!operating else{append("连接","请先停止或完成当前检查，再修改连接。",color:Obsidian.secondary);return};if settingsWindow==nil{settingsWindow=AgentSettingsWindow()};settingsWindow?.onSave={ [weak self] in self?.updateStatus() };settingsWindow?.showWindow(nil);NSApp.activate(ignoringOtherApps:true)}
    func cancel(){
        generation+=1;collector.cancel();investigation.cancel();backend.cancel()
        if let sheet=grantSheet,let w=window{w.endSheet(sheet.window,returnCode:.abort);grantSheet=nil;operating=false}
        checkResults=[];setBusy(false)
    }
    func shutdown(){cancel();backend.shutdown()}
    func suspend(){let active=busy;cancel();if active{append("tinyStat","设备休眠，本次检查已取消。已发生的操作以回执为准。",color:Obsidian.secondary)}}
    func windowShouldClose(_ sender:NSWindow)->Bool{!operating}
    func windowWillClose(_ notification:Notification){
        cancel();invalidateActions();files=[];registered=[:];inspectedIDs=[];focus=nil;evidence=nil;previousEvidence=nil;requestConversation=[];currentQuestion="";clearLog();updateStatus()
    }
    private func setBusy(_ value:Bool){busy=value;composer.busy=value;composer.enabled = !operating;modelButton.isEnabled = !value && !operating;if value && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion{progress.startAnimation(nil)}else{progress.stopAnimation(nil)};if !value{updateStatus()}}
    private func updateStatus(){
        let settings=AgentSettings.load();modelButton.title=settings.kind=="codex" ? "Codex ↗":"Claude Code ↗"
        status.stringValue="按需授权 · 本机历史 \(session.messages.count)/200"+(protection.count>0 ? " · 已保护 \(protection.count) 项":"")
        if let error=saveError{status.stringValue=error}
        status.toolTip="文字与回执保存在本机；最近上下文最多24 KiB。扩展检查每个问题单独授权，原始检查结果不保存到历史。"
        focusButton.isHidden=focus==nil;focusButton.title=focus.map{"正在讨论 \(displayIdentity($0.name)) · PID \($0.pid) · 清除 ×"} ?? ""
    }
    @objc private func clearFocus(){guard !busy,!operating else{return};focus=nil;focusedDraft=nil;updateStatus()}
    private func clearLog(){for v in log.arrangedSubviews{removeHandlers(v);log.removeArrangedSubview(v);v.removeFromSuperview()};actionButtons=[]}
    private func renderPage(){
        invalidateActions();clearLog();restoring=true
        let end=max(0,session.messages.count-pageOffset),start=max(0,end-40)
        for m in session.messages[start..<end]{append(m.role,m.text)}
        restoring=false;updateStatus()
    }
    private func turnPage(older:Bool){guard !busy,!operating else{return};pageOffset=older ? min(max(0,session.messages.count-1),pageOffset+40):max(0,pageOffset-40);renderPage()}
    private func saveRecord(){guard persistent,session.messages.contains(where:{$0.role=="你" || $0.role=="操作回执"}) else{return};do{try store.save(session);if !droppedRecord{saveError=nil}}catch{saveError="记录未保存："+error.localizedDescription;status.stringValue=saveError!}}
    private func append(_ who:String,_ text:String,color:NSColor=Obsidian.ink){
        if !restoring {
            var appended=true
            do{try session.append(role:who,text:text);saveRecord()}catch{appended=false;droppedRecord=true;saveError="有消息未保存："+error.localizedDescription;status.stringValue=saveError!}
            if pageOffset>0{pageOffset=0;renderPage();if appended{return}}
        }
        let heading=label(who=="你" ? "›  你":"•  "+who,size:11,color:who=="你" ? Obsidian.accent:Obsidian.secondary)
        heading.font = .monospacedSystemFont(ofSize:11,weight:.regular)
        let body=transcriptText(text,color:color)
        let row=stack([heading,body],spacing:9)
        body.translatesAutoresizingMaskIntoConstraints=false;body.widthAnchor.constraint(equalTo:row.widthAnchor).isActive=true
        add(row)
    }
    private func removeHandlers(_ view:NSView){handlers.removeValue(forKey:ObjectIdentifier(view));for child in view.subviews{removeHandlers(child)}}
    private func add(_ view:NSView){
        if log.arrangedSubviews.count>=60,let oldest=log.arrangedSubviews.first{removeHandlers(oldest);log.removeArrangedSubview(oldest);oldest.removeFromSuperview()}
        log.addArrangedSubview(view);view.translatesAutoresizingMaskIntoConstraints=false;view.widthAnchor.constraint(equalTo:log.widthAnchor,constant:-56).isActive=true
        window?.contentView?.layoutSubtreeIfNeeded();scrollToEnd()
    }
    private func scrollToEnd(){
        guard !scrollScheduled else{return};scrollScheduled=true
        DispatchQueue.main.async{[weak self] in
            guard let self=self else{return};self.scrollScheduled=false
            guard self.window?.isVisible==true else{return}
            self.window?.contentView?.layoutSubtreeIfNeeded();self.scroller.contentView.scroll(to:NSPoint(x:0,y:max(0,self.log.bounds.height-self.scroller.contentView.bounds.height)));self.scroller.reflectScrolledClipView(self.scroller.contentView)
        }
    }
    private func invalidateActions(){actionButtons.forEach{$0.isEnabled=false};actionButtons.removeAll();targetFiles.removeAll();targetApps.removeAll();targetStops.removeAll()}
    private func resetSessionState(){
        cancel();invalidateActions();files=[];protection=ActionProtection();evidence=nil;previousEvidence=nil;registered=[:];inspectedIDs=[];protectedProcesses=[];focus=nil;focusedDraft=nil;latestReceipt.isHidden=true;checkResults=[];requestConversation=[];currentQuestion="";saveError=nil;droppedRecord=false;pageOffset=0;composer.value="";clearLog()
    }
    private func newChat(){
        guard !busy,!operating else{return}
        do{if persistent{saveRecord();guard saveError==nil || droppedRecord else{throw AssistantFailure("当前会话尚未保存，不能切换。请先处理存储错误。")};guard try store.list().count<30 else{throw AssistantFailure("已保存30个会话，请先在历史中清理。")}}}
        catch{status.stringValue=error.localizedDescription;return}
        resetSessionState();session=ChatSession();append("tinyStat","新会话。读取与写入分别授权；旧会话可在历史中继续。");updateStatus()
    }
    private func showHistory(){
        guard !busy,!operating,let w=window else{return}
        do{if persistent{saveRecord()};sessionList=try store.list()}catch{status.stringValue=error.localizedDescription;return}
        guard !sessionList.isEmpty else{status.stringValue="暂无已保存会话";return}
        let picker=NSPopUpButton(frame:NSRect(x:0,y:0,width:380,height:28))
        picker.addItems(withTitles:sessionList.map{"\($0.title) · \($0.count)条"})
        let alert=NSAlert();alert.messageText="本机会话历史";alert.informativeText="最多30个会话；只加载选中会话。恢复不会恢复授权、文件或操作按钮。";alert.accessoryView=picker
        for title in ["取消","继续","重命名","删除"]{alert.addButton(withTitle:title)}
        operating=true;setBusy(false)
        alert.beginSheetModal(for:w){[weak self] result in
            guard let self=self else{return};self.operating=false;self.setBusy(false)
            guard self.sessionList.indices.contains(picker.indexOfSelectedItem) else{return};let chosen=self.sessionList[picker.indexOfSelectedItem]
            if result == .alertSecondButtonReturn{do{guard self.saveError==nil || self.droppedRecord else{throw AssistantFailure("当前会话尚未保存，不能切换。")};let record=try self.store.load(chosen.id);self.resetSessionState();self.session=record;self.renderPage();self.append("tinyStat","历史已恢复。旧授权、文件选择与保护规则已重置；历史文字不能授权新的操作。")}catch{self.status.stringValue=error.localizedDescription}}
            else if result == .alertThirdButtonReturn{self.renameSession(chosen)}
            else if result.rawValue==1003{self.deleteSession(chosen)}
        }
    }
    private func renameSession(_ selected:SessionSummary){
        guard let w=window else{return};let field=NSTextField(frame:NSRect(x:0,y:0,width:340,height:26));field.stringValue=selected.title
        let a=NSAlert();a.messageText="重命名会话";a.accessoryView=field;a.addButton(withTitle:"取消");a.addButton(withTitle:"保存");operating=true
        a.beginSheetModal(for:w){[weak self] r in guard let self=self else{return};self.operating=false;guard r == .alertSecondButtonReturn else{return};do{var record=selected.id==self.session.id ? self.session:try self.store.load(selected.id);record.title=String(field.stringValue.prefix(80));try self.store.save(record);if self.session.id==record.id{self.session=record};self.updateStatus()}catch{self.status.stringValue=error.localizedDescription}}
    }
    private func deleteSession(_ selected:SessionSummary){
        guard let w=window else{return};let a=NSAlert();a.messageText="删除本机会话？";a.informativeText=selected.title+"\n永久删除该会话文字与回执，不操作用户文件。";a.addButton(withTitle:"取消");a.addButton(withTitle:"删除");operating=true
        a.beginSheetModal(for:w){[weak self] r in guard let self=self else{return};self.operating=false;guard r == .alertSecondButtonReturn else{return};do{try self.store.remove(selected.id);if self.session.id==selected.id{self.resetSessionState();self.session=ChatSession();self.updateStatus()}}catch{self.status.stringValue=error.localizedDescription}}
    }
    @objc private func stopClicked(){cancel();append("检查已停止","停止本轮分析。之前的处理结果仍以操作回执为准。",color:Obsidian.secondary)}
    @objc private func submit(){
        let question=String(composer.value.trimmingCharacters(in:.whitespacesAndNewlines).prefix(4000))
        guard !busy,!operating,!question.isEmpty else{return}
        guard session.messages.count<185,(try? JSONEncoder().encode(session).count) ?? 0 < 180*1024 else{status.stringValue="本会话容量已满，请新建会话；历史保留。";return}
        let settings=AgentSettings.load()
        do{try settings.validate();_ = try settings.resolvedExecutable();if settings.custom{_ = try AgentKeychain.read(settings)}}catch{append("连接设置",error.localizedDescription);showSettings();return}
        let source=settings.contextSource
        if !modelSource.isEmpty,modelSource != source{evidence=nil;previousEvidence=nil;registered=[:];files=[];focus=nil;inspectedIDs=[]}
        modelSource=source
        let history=session.context()
        if let old=session.source,old != source {
            status.stringValue="连接已更换；旧会话上下文不会发送，请新建会话继续。";return
        }
        if session.source==nil,session.messages.contains(where:{$0.role=="你"}) {
            status.stringValue="此历史没有接收方记录，请新建会话后向当前连接提问。";return
        }
        session.source=source;requestConversation=history.messages;omittedMessages=history.omitted
        invalidateActions();generation+=1;currentQuestion=question;readSeconds=0;budget=InvestigationBudget();checkResults=[];composer.value=""
        append("你",question)
        if ["你现在是哪个模型","你是什么模型","你是哪个模型"].contains(question.trimmingCharacters(in:CharacterSet(charactersIn:"？?。"))){
            let identity=backend.reportedModel.map{"CLI上报："+$0} ?? (settings.model.isEmpty ? "CLI默认，具体型号未知":"配置型号："+settings.model)
            append("tinyStat","连接方式：\(settings.kind)。\(identity)。这是连接元数据，不能独立验证服务商实际使用的模型。");return
        }
        setBusy(true);sendRound(settings:settings,token:generation)
    }
    private func registerEvidence(_ e:DiagnosticEvidence){
        previousEvidence=evidence;evidence=e
        for p in e.processes{registered[p.id]=p}
        if let focus=focus{registered[focus.id]=focus}
        if registered.count>80{let retained=Set(e.processes.map{$0.id}+[focus?.id].compactMap{$0});registered=registered.filter{retained.contains($0.key)}}
        showEvidence(e)
    }
    private func sendRound(settings:AgentSettings,token:Int){
        guard generation==token else{return}
        do{
            targetApps=Dictionary(uniqueKeysWithValues:registered.values.compactMap{QuitTarget.capture($0)}.filter{protection.allows($0)}.map{($0.id,$0)})
            targetFiles=Dictionary(uniqueKeysWithValues:files.filter{protection.allows($0)}.map{($0.id,$0)})
            // Stopping is proposed only for a selected process or explicit inspection result, never every baseline row.
            targetStops=[:]
            if let p=focus,let target=StopTarget.capture(p),!protectedProcesses.contains(p.id){targetStops[p.id]=target}
            for id in inspectedIDs{if let p=registered[id],let target=StopTarget.capture(p),!protectedProcesses.contains(id){targetStops[id]=target}}
            var targets=targetApps.values.map{["id":$0.id,"kind":"quitApp","name":displayIdentity($0.name)]}
            targets+=targetStops.values.map{["id":$0.process.id,"kind":"stopProcess","name":displayIdentity($0.process.name)]}
            targets+=targetFiles.values.flatMap{f in ["trashFile","saveText"].map{["id":f.id,"kind":$0,"name":displayIdentity(f.description)]}}
            var context:[String:Any]=["request":["text":currentQuestion],"conversation":requestConversation,"omittedMessages":omittedMessages,"actionableTargets":targets,"budget":["remainingBatches":2-budget.batches,"checksAllowed":budget.batches<2],"checks":checkResults,"backend":["kind":settings.kind,"configured":settings.model.isEmpty ? "unknown":settings.model,"reported":backend.reportedModel ?? "unknown"],"inspectableTargets":registered.values.map{["id":$0.id,"name":$0.name,"pid":String($0.pid)]},"selectedFiles":files.map{["id":$0.id,"name":displayIdentity($0.description)]}]
            if let e=evidence{context["evidence"]=try JSONSerialization.jsonObject(with:Data(e.json.utf8))}
            if let old=previousEvidence{context["previousEvidence"]=["id":old.id,"at":ISO8601DateFormatter().string(from:old.capturedAt),"processes":old.processes.map{["id":$0.id,"name":$0.name,"note":"Historical observation, absence from latest ranking does not establish exit"]}]}
            if let p=focus{context["focus"]=["id":p.id,"name":p.name]}
            let data=try JSONSerialization.data(withJSONObject:context,options:.sortedKeys)
            guard data.count<=120_000 else{throw AssistantFailure("本轮证据超过容量，请减少检查或开启新会话。")}
            status.stringValue="\(settings.destination) 正在分析…"
            let completion:(Result<String,Error>)->Void = {[weak self] result in
                guard let self=self,self.generation==token else{return}
                do{
                    let reply=try AssistantReply.parse(try result.get(),allowed:Set(self.targetApps.keys).union(self.targetFiles.keys).union(self.targetStops.keys),inspectable:Set(self.registered.keys),readableFiles:Set(self.files.map{$0.id}))
                    for a in reply.actions{guard (a.kind=="quitApp" && self.targetApps[a.targetID] != nil) || (a.kind=="stopProcess" && self.targetStops[a.targetID] != nil) || (["trashFile","saveText"].contains(a.kind) && self.targetFiles[a.targetID] != nil) else{throw AssistantFailure("操作与目标类型不匹配。")}}
                    self.append(settings.kind=="codex" ? "Codex":"Claude Code",reply.explanation)
                    if !reply.checks.isEmpty{
                        if self.budget.batches>=2{self.setBusy(false);self.checkResults=[];self.append("补查已结束","本问题已完成两批检查。以上仅代表已获取的证据，未执行进一步读取或写入。")}
                        else{try self.budget.authorize(reply.checks);self.authorizeChecks(reply.checks,settings:settings,token:token)}
                    }
                    else{self.setBusy(false);self.checkResults=[];for a in reply.actions{self.showAction(a)}}
                }catch{self.failed(error)}
            }
            let prompt=String(decoding:data,as:UTF8.self)
            if let request=modelRequest{request(settings,prompt,completion)}else{backend.send(settings:settings,prompt:prompt,completion:completion)}
        }catch{failed(error)}
    }
    private var inspectedIDs=Set<String>()
    private var protectedProcesses=Set<String>()
    private func authorizeChecks(_ checks:[DiagnosticCheck],settings:AgentSettings,token:Int){
        guard let w=window else{setBusy(false);return}
        let descriptions=checks.map{c in
            let name=registered[c.targetID].map{"\($0.name) · PID \($0.pid)"} ?? files.first{$0.id==c.targetID}?.description ?? c.query
            return "• \(c.kind)：\(displayIdentity(name))\n  \(displayIdentity(c.reason))"
        }.joined(separator:"\n")
        let alert=NSAlert();alert.messageText="允许这批读取并发送？"
        alert.informativeText=descriptions+"\n\n结果将发送至 \(settings.destination)，用于本问题最多3次模型调用。系统快照与检查发现的进程身份可在本会话后续提问复用；文件正文及其他补查结果仅用于本问题。文件上限8 KiB；原始检查结果不保存，会话文字可能包含模型引用。不会授权写入。"
        alert.addButton(withTitle:"取消");alert.addButton(withTitle:"允许本次");alert.buttons[0].keyEquivalent="\r";alert.buttons[1].keyEquivalent=""
        grantSheet=alert;operating=true;setBusy(true)
        alert.beginSheetModal(for:w){[weak self] answer in
            guard let self=self,self.generation==token else{return};self.grantSheet=nil;self.operating=false
            guard answer == .alertSecondButtonReturn else{self.setBusy(false);self.checkResults=[];self.append("读取未授权","未执行这批读取或发送。");return}
            self.runChecks(checks,index:0,settings:settings,token:token)
        }
    }
    private func runChecks(_ checks:[DiagnosticCheck],index:Int,settings:AgentSettings,token:Int){
        guard generation==token else{return}
        guard index<checks.count else{sendRound(settings:settings,token:token);return}
        guard readSeconds<20 else{failed(AssistantFailure("本问题的读取时间预算已到20秒，未继续检查。"));return}
        let began=ProcessInfo.processInfo.systemUptime
        let c=checks[index];status.stringValue="正在检查 \(c.kind)…可停止"
        if c.kind=="refresh"{
            snapshot{[weak self] s,date in guard let self=self,self.generation==token else{return};self.collector.collect(snapshot:s,at:date,focusID:self.focus?.id){[weak self] result in guard let self=self,self.generation==token else{return};switch result{case .success(let e):self.readSeconds+=ProcessInfo.processInfo.systemUptime-began;self.registerEvidence(e);self.runChecks(checks,index:index+1,settings:settings,token:token);case .failure(let error):self.failed(error)}}};return
        }
        investigation.run(c,process:registered[c.targetID],file:files.first{$0.id==c.targetID}){[weak self] result in
            guard let self=self,self.generation==token else{return}
            switch result{
            case .failure(let error):self.failed(error)
            case .success(let (value,processes)):
                self.readSeconds+=ProcessInfo.processInfo.systemUptime-began
                var value=value
                for p in processes{self.registered[p.id]=p}
                if self.registered.count>80{let keep=Set(processes.map{$0.id}+[self.focus?.id].compactMap{$0});self.registered=self.registered.filter{keep.contains($0.key)}}
                value["processes"]=processes.map{["id":$0.id,"name":$0.name,"pid":String($0.pid),"memoryBytes":String($0.memoryBytes)]}
                self.checkResults.append(value)
                if c.kind=="inspectProcess"{self.inspectedIDs.insert(c.targetID);self.inspectedIDs.formIntersection(self.registered.keys)}
                self.append("检查回执",c.kind+" · 完成（结果用于本问题，原始内容不存入历史）",color:Obsidian.secondary)
                self.runChecks(checks,index:index+1,settings:settings,token:token)
            }
        }
    }
    private func failed(_ error:Error){checkResults=[];setBusy(false);append("检查未完成",error.localizedDescription)}
    private func showEvidence(_ e:DiagnosticEvidence){
        let content=stack([label(e.summary,size:11,color:Obsidian.quiet)],spacing:0)
        for p in e.processes{
            let text="\(displayIdentity(p.name)) · PID \(p.pid)\nCPU \(p.cpuPercentOneCore.map{String(format:"%.1f%%",$0)} ?? "—") · \(bytes(Double(p.memoryBytes))) · 线程 \(p.threadCount.map{String($0)} ?? "—")"
            let detail=label(text,size:12,color:Obsidian.secondary)
            var views:[NSView]=[detail]
            if let app=QuitTarget.capture(p),protection.allows(app){let keep=button("保留此应用"){[weak self] in self?.protect(app:app,file:nil)};views.append(keep)}
            let row=stack(views,vertical:false,spacing:14);row.edgeInsets=NSEdgeInsets(top:10,left:0,bottom:10,right:0);content.addArrangedSubview(row)
        }
        content.addArrangedSubview(label("按进程 CPU / 内存前 8 项与指定进程合并，未按应用归组。CPU 单核为 100%；不能据此证明泄漏或定位 GPU 应用。",size:11,color:Obsidian.quiet));content.isHidden=true
        let time=DateFormatter.localizedString(from:e.capturedAt,dateStyle:.none,timeStyle:.short)
        let toggle=button("采样依据 · \(time) · 展开 / 收起"){[weak self,weak content] in content?.isHidden.toggle();self?.window?.contentView?.layoutSubtreeIfNeeded()}
        toggle.font = .monospacedSystemFont(ofSize:10,weight:.regular);toggle.contentTintColor=Obsidian.quiet
        add(stack([toggle,content],spacing:6))
    }
    private func protect(app:QuitTarget?,file:FileTarget?){
        guard !operating else{append("操作进行中","请等待当前操作完成，再设置保留规则。",color:Obsidian.secondary);return};if let app=app{protection.protect(app)};if let file=file{protection.protect(file)}
        // Cancel in-flight inference: its action allowlist may have contained this target.
        if busy{cancel()};invalidateActions();updateStatus()
        append("本地保护已生效",displayIdentity(app?.name ?? file?.description ?? "对象")+"\n本会话内不会执行该对象的操作；模型不能解除。开启新对话可重置。",color:Obsidian.secondary)
        composer.focus()
    }
    private func showAction(_ proposal:ActionProposal){
        let app=targetApps[proposal.targetID],file=targetFiles[proposal.targetID],stop=targetStops[proposal.targetID]
        let allowed=app.map{protection.allows($0)} ?? file.map{protection.allows($0)} ?? stop.map{!protectedProcesses.contains($0.process.id)} ?? false
        guard allowed else{return}
        let titles=["quitApp":"正常退出应用","trashFile":"移到废纸篓","stopProcess":"停止后台进程","saveText":"另存文本到新文件"]
        let target=displayIdentity(app.map{"\($0.name) · \($0.bundle) · PID \($0.pid)"} ?? file?.description ?? stop.map{"\($0.process.name) · PID \($0.process.pid)"} ?? "")
        let result=label("等待你的决定",size:11,color:Obsidian.quiet)
        let review=button("查看并确认 ↗",primary:true){[weak self,weak result] in self?.confirm(proposal,target:target,result:result)}
        let keep=button("先保留"){[weak self,weak result] in
            guard let self=self else{return}
            if let stop=stop{guard self.protectedProcesses.count<80 else{self.status.stringValue="保护规则已满，请新建会话。";return};self.protectedProcesses.insert(stop.process.id);self.invalidateActions();self.append("本地保护已生效","本会话不停止该进程；恢复历史时需重新设置。")}else{self.protect(app:app,file:file)}
            result?.stringValue="已保留 · 本地规则保护"
        }
        actionButtons += [review,keep]
        add(card([label("建议操作 · \(titles[proposal.kind] ?? proposal.kind)",size:11,color:Obsidian.secondary),label(target,bold:true),label(displayIdentity(proposal.reason),size:12,color:Obsidian.secondary),stack([keep,review],vertical:false),result]))
    }
    private func confirm(_ proposal:ActionProposal,target:String,result:NSTextField?){
        guard !busy,!operating,let window=window else{return}
        let app=targetApps[proposal.targetID],file=targetFiles[proposal.targetID],stop=targetStops[proposal.targetID],token=generation
        let allowed=app.map{protection.allows($0)} ?? file.map{protection.allows($0)} ?? stop.map{!protectedProcesses.contains($0.process.id)} ?? false
        guard allowed else{return}
        let alert=NSAlert();alert.messageText=["quitApp":"正常退出此应用？","trashFile":"将此文件移到废纸篓？","stopProcess":"发送停止请求？","saveText":"预览并另存文本？"][proposal.kind] ?? "确认操作"
        alert.informativeText=target+"\n\n"+(proposal.kind=="stopProcess" ? "向这个后台进程发送 SIGTERM，可能中断工作或丢失未保存数据。不会强杀，也不代表所有子进程都停止。":proposal.kind=="saveText" ? "以下是完整新文本。确认后选择新的保存位置；不覆盖原文件。控制字符按 Unicode 标记显示。":proposal.kind=="quitApp" ? "可能中断任务或丢失未保存工作。请先保存；不会强制结束。":"仅移动上述文件，可从废纸篓恢复。")
        if proposal.kind=="saveText"{
            let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:480,height:260)),view=NSTextView(frame:NSRect(x:0,y:0,width:460,height:260))
            view.isEditable=false;view.isRichText=false;view.font = .monospacedSystemFont(ofSize:12,weight:.regular)
            view.string=proposal.text.unicodeScalars.map{v in (CharacterSet.controlCharacters.contains(v) && v.value != 10 && v.value != 9) || (0x202a...0x202e).contains(v.value) || (0x2066...0x2069).contains(v.value) ? String(format:"[U+%04X]",v.value):String(v)}.joined()
            view.isVerticallyResizable=true;view.autoresizingMask=[.width];view.textContainer?.widthTracksTextView=true;scroll.hasVerticalScroller=true;scroll.documentView=view;alert.accessoryView=scroll
        }
        alert.informativeText+="\n操作回执保存在本机会话，后续提问会随文字历史发送给当前连接。"
        alert.addButton(withTitle:"取消");alert.addButton(withTitle:"确认此操作");alert.buttons[0].keyEquivalent="\r";alert.buttons[1].keyEquivalent=""
        operating=true;setBusy(false)
        alert.beginSheetModal(for:window){[weak self,weak result] response in
            guard let self=self else{return}
            guard response == .alertSecondButtonReturn,self.generation==token else{self.operating=false;self.setBusy(false);return}
            if let app=app,!self.protection.allows(app){self.operating=false;self.setBusy(false);return}
            if let file=file,!self.protection.allows(file){self.operating=false;self.setBusy(false);return}
            if let stop=stop,self.protectedProcesses.contains(stop.process.id){self.operating=false;self.setBusy(false);return}
            self.invalidateActions();result?.stringValue="已确认，正在处理并核验…"
            if proposal.kind=="saveText",let file=file{self.saveText(proposal.text,source:file,token:token,result:result)}
            else if let app=app{app.requestQuit{[weak self,weak result] text in self?.receipt(text,result:result)}}
            else if let stop=stop{stop.request{[weak self,weak result] text in self?.receipt(text,result:result)}}
            else if let file=file{do{let text=try file.trash();self.files.removeAll{$0.id==file.id};self.receipt(text,result:result)}catch{self.receipt("未移动：\(error.localizedDescription)",result:result)}}
        }
    }
    private func saveText(_ text:String,source:FileTarget,token:Int,result:NSTextField?){
        guard let w=window else{return}
        let panel=NSSavePanel();panel.title="另存为新文件";panel.nameFieldStringValue=source.url.deletingPathExtension().lastPathComponent+"-edited.txt"
        panel.beginSheetModal(for:w){[weak self,weak result] response in
            guard let self=self else{return}
            guard response == .OK,self.generation==token,let url=panel.url else{self.operating=false;self.setBusy(false);return}
            do{try TextExport.write(text,to:url);self.receipt("已保存新文件："+url.path+"。原文件未修改。",result:result)}catch{self.receipt("未完成另存："+error.localizedDescription,result:result)}
        }
    }
    private func receipt(_ text:String,result:NSTextField?){
        if session.source==nil{session.source=AgentSettings.load().contextSource}
        operating=false;setBusy(true);status.stringValue="正在复查…";result?.stringValue="操作回执 · "+displayIdentity(text)
        latestReceipt.stringValue="最近操作 · "+displayIdentity(text);latestReceipt.isHidden=false;onReceipt?(text);append("操作回执",text,color:Obsidian.accent)
        generation+=1;let token=generation
        snapshot{[weak self] current,date in guard let self=self,self.generation==token else{return}
            self.collector.collect(snapshot:current,at:date){[weak self] outcome in guard let self=self,self.generation==token else{return};self.setBusy(false)
                switch outcome{case .success(let evidence):self.showEvidence(evidence);self.append("操作后复查","本地复查已完成，数据仅在采样依据显示，未授权发送给模型。");case .failure(let error):self.append("复查失败",error.localizedDescription)}
            }
        }
    }
    @objc private func selectFile(){guard !busy,!operating,let window=window else{return};if pageOffset>0{pageOffset=0;renderPage()};let picker=NSOpenPanel();picker.canChooseDirectories=false;picker.canChooseFiles=true;picker.allowsMultipleSelection=true;picker.message="选择只登记路径与大小。读取正文及发送给模型、移动或另存文本都需要分别确认。";let token=generation;operating=true;setBusy(false);picker.beginSheetModal(for:window){[weak self] response in guard let self=self else{return};self.operating=false;self.setBusy(false);guard response == .OK,self.generation==token else{return};do{let urls=picker.urls.filter{u in !self.files.contains{$0.url==u.standardizedFileURL}};guard urls.count+self.files.count<=5 else{throw AssistantFailure("每次最多选择 5 个文件。")};let selected=try urls.map{try FileTarget(url:$0)};self.files+=selected;for file in selected{self.add(card([label(displayIdentity(file.description),size:12),self.button("保留此文件"){[weak self] in self?.protect(app:nil,file:file)}]))};self.append("文件已选择","下次发送时附带路径与大小。尚未发送或移动。",color:Obsidian.secondary)}catch{self.append("未添加文件",error.localizedDescription)}}}
}
final class AgentSettingsWindow:NSWindowController {
    var onSave:(()->Void)?
    private let kind=NSPopUpButton()
    private let executable=NSTextField()
    private let model=NSTextField()
    private let endpoint=NSTextField()
    private let key=NSSecureTextField()
    private let custom=NSButton(checkboxWithTitle:"使用自定义服务商",target:nil,action:nil)
    private let bearer=NSButton(checkboxWithTitle:"Claude 使用 Bearer（否则 x-api-key）",target:nil,action:nil)
    private let message=label("",size:11,color:Obsidian.secondary)
    init(){
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:520,height:480),styleMask:[.titled,.closable],backing:.buffered,defer:false);w.title="tinyStat · 模型连接";w.isReleasedWhenClosed=false;w.appearance=NSAppearance(named:.darkAqua);w.backgroundColor=Obsidian.surface
        super.init(window:w)
        let settings=AgentSettings.load();kind.addItems(withTitles:["Codex","Claude Code"]);kind.selectItem(at:settings.kind=="claude" ? 1:0)
        executable.stringValue=settings.executable;executable.placeholderString="留空自动查找原生 CLI；不支持 shell / Node 包装"
        model.stringValue=settings.model;model.placeholderString="留空使用 CLI 默认；自定义服务商必填"
        endpoint.stringValue=settings.endpoint;endpoint.placeholderString="https://你的服务商/v1"
        key.placeholderString="只存入 Keychain；留空保留已有密钥";custom.state=settings.custom ? .on:.off;bearer.state=settings.bearer ? .on:.off
        let save=NSButton(title:"保存",target:self,action:#selector(saveSettings));save.bezelStyle = .rounded
        let form=stack([label("连接你已安装的助手",size:18,bold:true),kind,label("CLI 路径",size:11),executable,label("模型",size:11),model,custom,endpoint,key,bearer,label("Codex 需要配置自定义服务商（Responses API）。Claude 可使用 CLI 登录或 Anthropic 兼容服务。仅支持原生 CLI，未登录时请先在终端完成登录。",size:11,color:.secondaryLabelColor),message,save],spacing:8)
        w.contentView?.addSubview(form);form.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([form.leadingAnchor.constraint(equalTo:w.contentView!.leadingAnchor,constant:22),form.trailingAnchor.constraint(equalTo:w.contentView!.trailingAnchor,constant:-22),form.topAnchor.constraint(equalTo:w.contentView!.topAnchor,constant:20)])
        for v in [executable,model,endpoint,key,message]{v.widthAnchor.constraint(equalTo:form.widthAnchor).isActive=true}
        w.center()
    }
    required init?(coder:NSCoder){fatalError("init(coder:) not supported")}
    @objc private func saveSettings(){do{let settings=AgentSettings(kind:kind.indexOfSelectedItem==1 ? "claude":"codex",executable:executable.stringValue.trimmingCharacters(in:.whitespacesAndNewlines),model:model.stringValue.trimmingCharacters(in:.whitespacesAndNewlines),endpoint:endpoint.stringValue.trimmingCharacters(in:.whitespacesAndNewlines),custom:custom.state == .on,bearer:bearer.state == .on);try settings.validate();_ = try settings.resolvedExecutable();if settings.custom{try AgentKeychain.write(key.stringValue,settings:settings);_ = try AgentKeychain.read(settings)};try settings.save();key.stringValue="";onSave?();close()}catch{message.stringValue=error.localizedDescription}}
}
