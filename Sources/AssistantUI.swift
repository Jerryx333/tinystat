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
    private var history:[[String:String]]=[]
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
    init(snapshot:@escaping(@escaping(Snapshot,Date)->Void)->Void){self.snapshot=snapshot;super.init()}
    private func button(_ title:String,primary:Bool=false,_ action:@escaping()->Void)->NSButton {
        let b=NSButton(title:title,target:self,action:#selector(invoke(_:)));Obsidian.style(b,primary:primary);handlers[ObjectIdentifier(b)]=action;return b
    }
    @objc private func invoke(_ sender:NSButton){handlers[ObjectIdentifier(sender)]?()}
    private func prepare(){
        guard window==nil else{return}
        let w=AssistantWindow(contentRect:NSRect(x:0,y:0,width:620,height:760),styleMask:[.titled,.closable,.resizable,.miniaturizable,.fullSizeContentView],backing:.buffered,defer:false)
        w.title="tinyStat";w.titleVisibility = .hidden;w.titlebarAppearsTransparent=true;w.appearance=NSAppearance(named:.darkAqua);w.backgroundColor=Obsidian.background
        w.minSize=NSSize(width:520,height:570);w.isReleasedWhenClosed=false;w.delegate=self;window=w
        w.focusInput={ [weak self] in self?.composer.focus() };w.escape={ [weak self] in if self?.busy == true{self?.stopClicked()}else{self?.window?.orderOut(nil);self?.onBack?()} }
        let root=NSView();w.contentView=root
        let back=button("‹"){[weak self] in self?.window?.orderOut(nil);self?.onBack?()};back.setAccessibilityLabel("返回概览")
        let brand=stack([back,label("tinyStat",size:14,bold:true)],vertical:false)
        let fresh=button("＋ 新对话"){[weak self] in self?.newChat()}
        let settings=button("连接"){[weak self] in self?.showSettings()}
        let inventory=button("进程列表"){[weak self] in self?.onProcesses?()}
        let top=stack([brand,NSView(),inventory,fresh,settings],vertical:false)
        let subtitle=label("诊断会话  /  操作前由你确认",size:11,color:Obsidian.quiet)
        latestReceipt.isHidden=true;latestReceipt.maximumNumberOfLines=3
        let intro=stack([subtitle,latestReceipt],spacing:10)
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
        updateStatus();append("tinyStat","进程列表可直接查看正在运行的程序。每次提问附带一份新快照；采样依据默认收起。",color:Obsidian.secondary);w.center()
    }
    func show(question:String?=nil){prepare();window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);if let q=question{focusedDraft=nil;if busy || operating{append("待发送的问题",q+"\n当前检查或操作尚未结束。",color:Obsidian.secondary);if composer.value.isEmpty{composer.value=q}}else{composer.value=q;submit()}}else{composer.focus()}}
    func ask(process:DiagnosticProcess){
        prepare();guard !busy,!operating else{show();append("tinyStat","请等待当前检查或操作完成，再询问所选进程。",color:Obsidian.secondary);return}
        show();composer.value="看看进程 \(displayIdentity(process.name))（PID \(process.pid)）的占用，是否需要处理？";focusedDraft=(process.id,composer.value);composer.focus()
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
    func cancel(){generation+=1;collector.cancel();backend.cancel();setBusy(false)}
    func shutdown(){cancel();backend.shutdown()}
    func suspend(){let active=busy;cancel();if active{append("tinyStat","设备休眠，本次检查已取消。已发生的操作以回执为准。",color:Obsidian.secondary)}}
    func windowWillClose(_ notification:Notification){if composer.value==focusedDraft?.text{composer.value=""};focusedDraft=nil;cancel()}
    private func setBusy(_ value:Bool){busy=value;composer.busy=value;composer.enabled = !operating;modelButton.isEnabled = !value && !operating;if value && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion{progress.startAnimation(nil)}else{progress.stopAnimation(nil)};if !value{updateStatus()}}
    private func updateStatus(){let settings=AgentSettings.load();modelButton.title=settings.kind=="codex" ? "Codex ↗":"Claude Code ↗";status.stringValue="每轮附带新快照 · 不读文件内容"+(protection.count>0 ? " · 已保护 \(protection.count) 项":"");status.toolTip="发送至 \(settings.destination)。每轮发送最新快照、文字历史和操作回执；旧快照不整包重复发送。文件只发送路径与大小。对话仅保留在本次运行。"}
    private func append(_ who:String,_ text:String,color:NSColor=Obsidian.ink){
        let heading=label(who=="你" ? "›  你":"•  "+who,size:11,color:who=="你" ? Obsidian.accent:Obsidian.secondary)
        heading.font = .monospacedSystemFont(ofSize:11,weight:.regular)
        let body=transcriptText(text,color:color)
        let row=stack([heading,body],spacing:9)
        body.translatesAutoresizingMaskIntoConstraints=false;body.widthAnchor.constraint(equalTo:row.widthAnchor).isActive=true
        add(row)
    }
    private func removeHandlers(_ view:NSView){handlers.removeValue(forKey:ObjectIdentifier(view));for child in view.subviews{removeHandlers(child)}}
    private func add(_ view:NSView){
        if log.arrangedSubviews.count>=120,let oldest=log.arrangedSubviews.first{removeHandlers(oldest);log.removeArrangedSubview(oldest);oldest.removeFromSuperview()}
        log.addArrangedSubview(view);view.translatesAutoresizingMaskIntoConstraints=false;view.widthAnchor.constraint(equalTo:log.widthAnchor,constant:-56).isActive=true
        window?.contentView?.layoutSubtreeIfNeeded();scrollToEnd()
    }
    private func scrollToEnd(){DispatchQueue.main.async{[weak self] in guard let self=self else{return};self.window?.contentView?.layoutSubtreeIfNeeded();self.scroller.contentView.scroll(to:NSPoint(x:0,y:max(0,self.log.bounds.height-self.scroller.contentView.bounds.height)));self.scroller.reflectScrolledClipView(self.scroller.contentView)}}
    private func invalidateActions(){actionButtons.forEach{$0.isEnabled=false};actionButtons.removeAll();targetFiles.removeAll();targetApps.removeAll()}
    private func newChat(){
        guard !operating,let window=window else{return}
        let alert=NSAlert();alert.messageText="开始新对话？";alert.informativeText="清空当前对话、所选文件与本会话的保留规则。";alert.addButton(withTitle:"取消");alert.addButton(withTitle:"新建对话");alert.buttons[0].keyEquivalent="\r";alert.buttons[1].keyEquivalent=""
        alert.beginSheetModal(for:window){[weak self] response in guard let self=self,response == .alertSecondButtonReturn else{return};self.cancel();self.invalidateActions();self.history.removeAll();self.files.removeAll();self.protection=ActionProtection();self.evidence=nil;self.focusedDraft=nil;self.latestReceipt.isHidden=true;for v in self.log.arrangedSubviews{self.removeHandlers(v);self.log.removeArrangedSubview(v);v.removeFromSuperview()};self.composer.value="";self.updateStatus();self.append("tinyStat","新对话已开始。发送问题时重新检查。");self.composer.focus()}
    }
    @objc private func stopClicked(){cancel();append("检查已停止","停止本轮分析。之前的处理结果仍以操作回执为准。",color:Obsidian.secondary)}
    @objc private func submit(){
        let question=String(composer.value.trimmingCharacters(in:.whitespacesAndNewlines).prefix(4000))
        guard !busy,!operating,!question.isEmpty else{return}
        if history.filter({$0["role"]=="user"}).count>=12{append("tinyStat","本次对话已达到 12 轮，请开启新对话。",color:Obsidian.secondary);return}
        let settings=AgentSettings.load()
        do{try settings.validate();_ = try settings.resolvedExecutable();if settings.custom{_ = try AgentKeychain.read(settings)}}catch{append("连接设置",error.localizedDescription);showSettings();return}
        invalidateActions();generation+=1;let token=generation;composer.value="";append("你",question);history.append(["role":"user","text":question]);setBusy(true);status.stringValue="正在采样主要进程…"
        let selectedID=focusedDraft?.text==question ? focusedDraft?.id:nil;focusedDraft=nil
        snapshot{[weak self] current,date in guard let self=self,self.generation==token else{return}
            self.collector.collect(snapshot:current,at:date,focusID:selectedID){[weak self] result in guard let self=self,self.generation==token else{return}
                switch result{
                case .failure(let error):self.failed(error)
                case .success(let evidence):
                    self.evidence=evidence;self.showEvidence(evidence)
                    let apps=evidence.processes.compactMap{QuitTarget.capture($0)}
                    self.targetApps=Dictionary(uniqueKeysWithValues:apps.filter{self.protection.allows($0)}.map{($0.id,$0)})
                    self.targetFiles=Dictionary(uniqueKeysWithValues:self.files.filter{self.protection.allows($0)}.map{($0.id,$0)})
                    var targets=self.targetApps.values.sorted{$0.id<$1.id}.map{["id":$0.id,"kind":"quitApp","name":displayIdentity($0.name),"impact":"正常退出整个应用，可能中断任务或丢失未保存工作"]}
                    targets += self.targetFiles.values.map{["id":$0.id,"kind":"trashFile","name":displayIdentity($0.description),"impact":"移到废纸篓，可恢复，不保证释放内存"]}
                    do{
                        let context:[String:Any]=["history":self.history,"evidence":try JSONSerialization.jsonObject(with:Data(evidence.json.utf8)),"actionableTargets":targets]
                        let prompt=String(data:try JSONSerialization.data(withJSONObject:context,options:.sortedKeys),encoding:.utf8)!
                        self.status.stringValue="\(settings.destination) 正在分析…可随时停止。"
                        self.backend.send(settings:settings,prompt:prompt){[weak self] result in guard let self=self,self.generation==token else{return};self.setBusy(false)
                            do{let reply=try AssistantReply.parse(try result.get(),allowed:Set(self.targetApps.keys).union(self.targetFiles.keys))
                                for action in reply.actions{guard action.kind=="quitApp" ? self.targetApps[action.targetID] != nil:self.targetFiles[action.targetID] != nil else{throw AssistantFailure("操作类型与对象不匹配，已拒绝。")}}
                                self.append(settings.kind=="codex" ? "Codex":"Claude Code",reply.explanation);self.history.append(["role":"assistant","text":String(reply.explanation.prefix(12000))]);for action in reply.actions{self.showAction(action)}
                            }catch{self.failed(error)}
                        }
                    }catch{self.failed(error)}
                }
            }
        }
    }
    private func failed(_ error:Error){setBusy(false);append("检查未完成",error.localizedDescription);history.append(["role":"system","text":"上一轮检查失败，未执行操作。"])}
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
        let app=targetApps[proposal.targetID],file=targetFiles[proposal.targetID]
        guard app.map({protection.allows($0)}) ?? file.map({protection.allows($0)}) ?? false else{return}
        let title=proposal.kind=="quitApp" ? "正常退出应用":"移到废纸篓"
        let target=displayIdentity(app.map{"\($0.name) · \($0.bundle) · PID \($0.pid)"} ?? file?.description ?? "")
        let result=label("等待你的决定",size:11,color:Obsidian.quiet)
        let review=button("查看并确认 ↗",primary:true){[weak self,weak result] in self?.confirm(proposal,target:target,result:result)}
        let keep=button("先保留"){[weak self,weak result] in self?.protect(app:app,file:file);result?.stringValue="已保留 · 本地规则保护"}
        actionButtons += [review,keep]
        add(card([label("建议操作 · \(title)",size:11,color:Obsidian.secondary),label(target,bold:true),label(proposal.reason,size:12,color:Obsidian.secondary),stack([keep,review],vertical:false),result]))
    }
    private func confirm(_ proposal:ActionProposal,target:String,result:NSTextField?){
        guard !busy,!operating,let window=window else{return}
        let app=targetApps[proposal.targetID],file=targetFiles[proposal.targetID]
        guard app.map({protection.allows($0)}) ?? file.map({protection.allows($0)}) ?? false else{return}
        let alert=NSAlert();alert.messageText=proposal.kind=="quitApp" ? "正常退出此应用？":"将此文件移到废纸篓？"
        alert.informativeText=target+"\n\n"+(proposal.kind=="quitApp" ? "可能中断任务或丢失未保存工作。请先保存；不会强制结束。":"只移动上述文件，可从废纸篓恢复。清理磁盘不等于释放内存。")
        alert.addButton(withTitle:"取消");alert.addButton(withTitle:proposal.kind=="quitApp" ? "正常退出":"移到废纸篓");alert.buttons[0].keyEquivalent="\r";alert.buttons[1].keyEquivalent=""
        operating=true;setBusy(false)
        alert.beginSheetModal(for:window){[weak self,weak result] response in guard let self=self else{return}
            guard response == .alertSecondButtonReturn else{self.operating=false;self.setBusy(false);return}
            guard app.map({self.protection.allows($0)}) ?? file.map({self.protection.allows($0)}) ?? false else{self.operating=false;self.setBusy(false);return}
            self.invalidateActions();result?.stringValue="已确认，正在处理并核验…";self.setBusy(false)
            if let app=app{app.requestQuit{[weak self,weak result] text in self?.receipt(text,result:result)}}
            else if let file=file{do{let text=try file.trash();self.files.removeAll{$0.id==file.id};self.receipt(text,result:result)}catch{self.receipt("未移动：\(error.localizedDescription)",result:result)}}
        }
    }
    private func receipt(_ text:String,result:NSTextField?){
        operating=false;setBusy(true);status.stringValue="正在复查…";result?.stringValue="操作回执 · "+displayIdentity(text)
        latestReceipt.stringValue="最近操作 · "+displayIdentity(text);latestReceipt.isHidden=false;onReceipt?(text);append("操作回执",text,color:Obsidian.accent)
        history.append(["role":"system","text":"操作回执："+text]);generation+=1;let token=generation
        snapshot{[weak self] current,date in guard let self=self,self.generation==token else{return}
            self.collector.collect(snapshot:current,at:date){[weak self] outcome in guard let self=self,self.generation==token else{return};self.setBusy(false)
                switch outcome{case .success(let evidence):self.evidence=evidence;self.showEvidence(evidence);self.history.append(["role":"system","text":"操作后复查："+evidence.summary]);case .failure(let error):self.append("复查失败",error.localizedDescription)}
            }
        }
    }
    @objc private func selectFile(){guard !busy,!operating,let window=window else{return};let picker=NSOpenPanel();picker.canChooseDirectories=false;picker.canChooseFiles=true;picker.allowsMultipleSelection=true;picker.message="只发送路径与大小，不读取内容。移动前需要单独确认。";picker.beginSheetModal(for:window){[weak self] response in guard let self=self,response == .OK else{return};do{let urls=picker.urls.filter{u in !self.files.contains{$0.url==u.standardizedFileURL}};guard urls.count+self.files.count<=5 else{throw AssistantFailure("每次最多选择 5 个文件。")};let selected=try urls.map{try FileTarget(url:$0)};self.files+=selected;for file in selected{self.add(card([label(displayIdentity(file.description),size:12),self.button("保留此文件"){[weak self] in self?.protect(app:nil,file:file)}]))};self.append("文件已选择","下次发送时附带路径与大小。尚未发送或移动。",color:Obsidian.secondary)}catch{self.append("未添加文件",error.localizedDescription)}}}
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
