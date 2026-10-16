// Verify native text input layout and keyboard semantics without model requests.
// Run through scripts/verify-ui.sh.
// Requires macOS AppKit and an interactive login session.
import AppKit
@main struct ComposerCheck {
    static func main(){
        _ = NSApplication.shared
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:180),styleMask:[.titled],backing:.buffered,defer:false)
        let c=MessageComposer(placeholder:"Test");c.frame=NSRect(x:10,y:10,width:480,height:108);w.contentView!.addSubview(c);w.contentView!.layoutSubtreeIfNeeded();c.layoutSubtreeIfNeeded()
        precondition(c.textView.frame.width>300 && c.textView.frame.height>=50,"text viewport must have real dimensions")
        var sent=0;c.onSend={_ in sent+=1};c.value="hello"
        func enter(_ flags:NSEvent.ModifierFlags)->NSEvent{NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:w.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!}
        c.textView.setSelectedRange(NSRange(location:5,length:0));c.textView.keyDown(with:enter(.shift));precondition(sent==0 && c.value.contains("\n"))
        c.textView.keyDown(with:enter([]));precondition(sent==1)
        c.busy=true;c.textView.keyDown(with:enter([]));precondition(sent==1,"Enter must not stop an active reply")
        c.textView.setMarkedText("拼",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:NSNotFound,length:0));c.busy=false;c.textView.keyDown(with:enter([]));precondition(sent==1,"IME confirmation must not send")
        let body=transcriptText(String(repeating:"这是一段较长的诊断回复，包含 CPU 和内存证据。\n",count:20))
        body.frame=NSRect(x:0,y:0,width:360,height:500)
        precondition(body.font==NSFont.monospacedSystemFont(ofSize:12.5,weight:.regular))
        precondition(body.isSelectable && body.allowsEditingTextAttributes)
        let style=body.attributedStringValue.attribute(.paragraphStyle,at:0,effectiveRange:nil) as! NSParagraphStyle
        precondition(style.lineSpacing==5 && style.paragraphSpacing==8)
        print("PASS: native text viewport, Shift+Enter, Enter, busy guard, IME confirmation")
    }
}
