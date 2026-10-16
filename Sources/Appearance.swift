import AppKit

/// Shared neutral palette. Monitoring and action state are also expressed in text.
enum Obsidian {
    static let background=NSColor(srgbRed:0.145,green:0.155,blue:0.175,alpha:1)
    static let surface=NSColor(srgbRed:0.16,green:0.17,blue:0.19,alpha:1)
    static let inset=NSColor(srgbRed:0.125,green:0.135,blue:0.155,alpha:1)
    static let ink=NSColor(srgbRed:0.75,green:0.77,blue:0.81,alpha:1)
    static let secondary=NSColor(srgbRed:0.60,green:0.63,blue:0.68,alpha:1)
    static let quiet=NSColor(srgbRed:0.49,green:0.52,blue:0.57,alpha:1)
    static let accent=NSColor(srgbRed:0.55,green:0.66,blue:0.78,alpha:1)
    static let line=NSColor(white:1,alpha:0.10)
    static func apply(_ view:NSView,color:NSColor=surface,radius:CGFloat=12,border:Bool=true) {
        view.wantsLayer=true;view.layer?.backgroundColor=color.cgColor;view.layer?.cornerRadius=radius
        view.layer?.borderColor=line.cgColor;view.layer?.borderWidth=border ? 1:0
    }
    static func style(_ button:NSButton,primary:Bool=false) {
        button.bezelStyle = .inline;button.isBordered=false;button.font = .systemFont(ofSize:12,weight:.medium)
        button.contentTintColor=primary ? background:secondary
        apply(button,color:primary ? ink:.clear,radius:7,border:primary)
        button.focusRingType = .exterior
    }
}

/// Plain text only. Enter sends; Shift+Enter inserts a newline; IME owns marked text.
final class MessageTextView:NSTextView {
    var send:(()->Void)?
    var placeholder="" {didSet{needsDisplay=true}}
    override func keyDown(with event:NSEvent) {
        if event.keyCode==36 || event.keyCode==76 {
            if !hasMarkedText(){if event.modifierFlags.contains(.shift){insertNewline(nil)}else{send?()};return}
        }
        super.keyDown(with:event)
    }
    override func draw(_ dirtyRect:NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            (placeholder as NSString).draw(at:NSPoint(x:textContainerInset.width+5,y:textContainerInset.height),withAttributes:[.font:font ?? NSFont.systemFont(ofSize:13),.foregroundColor:Obsidian.quiet])
        }
    }
}
final class MessageComposer:NSView,NSTextViewDelegate {
    let textView=MessageTextView()
    let sendButton=NSButton(title:"↑",target:nil,action:nil)
    let context=NSTextField(labelWithString:"附带当前系统快照")
    let auxiliary=NSButton(title:"选择文件…",target:nil,action:nil)
    private let scroll=NSScrollView()
    var onSend:((String)->Void)?
    var onStop:(()->Void)?
    var onAttach:(()->Void)?
    var busy=false {didSet{update()}}
    var enabled=true {didSet{update()}}
    var value:String {get{textView.string}set{textView.string=newValue;update();textView.needsDisplay=true}}
    init(placeholder:String,attachment:Bool=false) {
        super.init(frame:.zero);Obsidian.apply(self,color:Obsidian.inset,radius:12)
        textView.isRichText=false;textView.importsGraphics=false;textView.isAutomaticLinkDetectionEnabled=false
        textView.isAutomaticQuoteSubstitutionEnabled=false;textView.isAutomaticDashSubstitutionEnabled=false
        textView.drawsBackground=false;textView.textColor=Obsidian.ink;textView.insertionPointColor=Obsidian.ink
        textView.font = .systemFont(ofSize:13);textView.textContainerInset=NSSize(width:9,height:10)
        textView.placeholder=placeholder;textView.delegate=self;textView.send={ [weak self] in guard let self=self,!self.busy else{return};self.submit() }
        textView.isVerticallyResizable=true;textView.isHorizontallyResizable=false;textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView=true;textView.setAccessibilityLabel(placeholder)
        scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.documentView=textView
        context.font = .systemFont(ofSize:11);context.textColor=Obsidian.quiet
        sendButton.target=self;sendButton.action=#selector(submit);sendButton.font = .systemFont(ofSize:18,weight:.medium)
        sendButton.isBordered=false;sendButton.setAccessibilityLabel("发送消息")
        auxiliary.target=self;auxiliary.action=#selector(attach);Obsidian.style(auxiliary);auxiliary.isHidden = !attachment
        for v in [scroll,context,sendButton,auxiliary]{addSubview(v);v.translatesAutoresizingMaskIntoConstraints=false}
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant:108),scroll.leadingAnchor.constraint(equalTo:leadingAnchor,constant:3),scroll.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-3),scroll.topAnchor.constraint(equalTo:topAnchor,constant:3),scroll.heightAnchor.constraint(equalToConstant:63),
            context.leadingAnchor.constraint(equalTo:leadingAnchor,constant:14),context.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-14),context.trailingAnchor.constraint(lessThanOrEqualTo:sendButton.leadingAnchor,constant:-12),
            sendButton.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-12),sendButton.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-11),sendButton.widthAnchor.constraint(equalToConstant:30),sendButton.heightAnchor.constraint(equalToConstant:30),
            auxiliary.leadingAnchor.constraint(equalTo:leadingAnchor,constant:12),auxiliary.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-10),auxiliary.heightAnchor.constraint(equalToConstant:28)
        ])
        if attachment{context.isHidden=true};update()
    }
    required init?(coder:NSCoder){fatalError("init(coder:) not supported")}
    override func layout(){
        super.layout()
        let width=max(1,scroll.contentSize.width)
        textView.minSize=NSSize(width:0,height:scroll.contentSize.height)
        textView.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        textView.setFrameSize(NSSize(width:width,height:max(scroll.contentSize.height,textView.frame.height)))
        textView.textContainer?.containerSize=NSSize(width:width,height:CGFloat.greatestFiniteMagnitude)
    }
    func textDidChange(_ notification:Notification){update();textView.needsDisplay=true}
    func textDidBeginEditing(_ notification:Notification){layer?.borderColor=NSColor(white:0.42,alpha:1).cgColor}
    func textDidEndEditing(_ notification:Notification){layer?.borderColor=Obsidian.line.cgColor}
    func focus(){window?.makeFirstResponder(textView)}
    private func update(){
        textView.isEditable=enabled;sendButton.isEnabled=enabled && (busy || !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        sendButton.title=busy ? "■":"↑";sendButton.setAccessibilityLabel(busy ? "停止回复":"发送消息")
        sendButton.contentTintColor=sendButton.isEnabled ? Obsidian.background:Obsidian.quiet
        Obsidian.apply(sendButton,color:sendButton.isEnabled ? Obsidian.ink:NSColor(white:0.17,alpha:1),radius:busy ? 7:15,border:false)
        auxiliary.isEnabled=enabled && !busy
    }
    @objc private func submit(){guard enabled else{return};if busy{onStop?();return};let question=value.trimmingCharacters(in:.whitespacesAndNewlines);guard !question.isEmpty else{return};onSend?(String(question.prefix(4000)))}
    @objc private func attach(){onAttach?()}
}
final class AssistantWindow:NSWindow {
    var focusInput:(()->Void)?
    var escape:(()->Void)?
    override func performKeyEquivalent(with event:NSEvent)->Bool {
        if attachedSheet==nil,event.modifierFlags.contains(.command),event.charactersIgnoringModifiers=="k" {focusInput?();return true}
        return super.performKeyEquivalent(with:event)
    }
    override func cancelOperation(_ sender:Any?){if let text=firstResponder as? NSTextView,text.hasMarkedText(){return};if attachedSheet==nil{escape?()}}
}

/// Native selectable plain text with consistent display and selection typography.
func transcriptText(_ text:String,color:NSColor=Obsidian.ink)->NSTextField {
    let body=NSTextField(wrappingLabelWithString:text)
    body.font = .monospacedSystemFont(ofSize:12.5,weight:.regular);body.textColor=color
    body.isSelectable=true;body.allowsEditingTextAttributes=true
    body.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
    let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=5;paragraph.paragraphSpacing=8
    body.attributedStringValue=NSAttributedString(string:text,attributes:[.font:body.font!,.foregroundColor:color,.paragraphStyle:paragraph])
    return body
}
