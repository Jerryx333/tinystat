import AppKit

struct QuitTarget {
    let id:String
    let pid:Int32
    let start:UInt64
    let name:String
    let bundle:String
    let launch:Date
    static func capture(_ p:DiagnosticProcess)->QuitTarget? {
        guard p.pid != getpid(),ts_process_matches(p.pid,p.start),let app=NSRunningApplication(processIdentifier:p.pid),app.activationPolicy == .regular,let bundle=app.bundleIdentifier,!["com.apple.finder","com.apple.loginwindow","com.apple.dock","local.tinystat.app"].contains(bundle.lowercased()),let launch=app.launchDate else{return nil}
        return QuitTarget(id:p.id,pid:p.pid,start:p.start,name:app.localizedName ?? p.name,bundle:bundle,launch:launch)
    }
    func requestQuit(completion:@escaping(String)->Void) {
        guard ts_process_matches(pid,start),let app=NSRunningApplication(processIdentifier:pid),app.bundleIdentifier==bundle,app.launchDate==launch,app.activationPolicy == .regular else {completion("未执行：目标应用已退出或身份发生变化，请重新检查。");return}
        guard app.terminate() else {completion("退出请求被拒绝；应用可能有未保存内容。未强制结束。");return}
        func check(_ remaining:Int) {
            if app.isTerminated || !ts_process_matches(pid,start) {completion("已确认 \(name) 原进程退出。内存变化需以复查结果为准。");return}
            if remaining==0 {completion("已请求 \(name) 正常退出，但尚未确认退出。请处理它的保存提示；未强制结束。");return}
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5){check(remaining-1)}
        }
        check(10)
    }
}
struct FileTarget {
    let id=UUID().uuidString
    let url:URL
    private let device:Int32
    private let inode:UInt64
    private let size:Int64
    private let modified:Int
    private let nanos:Int
    private let changed:Int
    private let changeNanos:Int
    var description:String {"\(url.path) · \(bytes(Double(size)))"}
    init(url:URL)throws {
        let normalized=url.standardizedFileURL
        guard normalized.path==normalized.resolvingSymlinksInPath().path else {throw AssistantFailure("暂不处理符号链接，请选择实际文件。")}
        var st=stat();guard lstat(normalized.path,&st)==0,(st.st_mode & S_IFMT)==S_IFREG,st.st_uid==getuid() else {throw AssistantFailure("只支持你拥有的普通文件；不处理目录、链接或系统文件。")}
        let home=URL(fileURLWithPath:NSHomeDirectory()).standardizedFileURL.path
        guard normalized.path.hasPrefix(home+"/"),!normalized.path.hasPrefix(home+"/.Trash/") else {throw AssistantFailure("请选择个人目录中尚未进入废纸篓的文件。")}
        self.url=normalized;device=st.st_dev;inode=st.st_ino;size=st.st_size;modified=st.st_mtimespec.tv_sec;nanos=st.st_mtimespec.tv_nsec;changed=st.st_ctimespec.tv_sec;changeNanos=st.st_ctimespec.tv_nsec
    }
    func validate()throws {
        var st=stat()
        guard url.path==url.resolvingSymlinksInPath().path,lstat(url.path,&st)==0,st.st_dev==device,st.st_ino==inode,st.st_size==size,st.st_mtimespec.tv_sec==modified,st.st_mtimespec.tv_nsec==nanos,st.st_ctimespec.tv_sec==changed,st.st_ctimespec.tv_nsec==changeNanos,(st.st_mode&S_IFMT)==S_IFREG,st.st_uid==getuid() else {throw AssistantFailure("文件已变化或被替换，未移动；请重新选择。")}
    }
    func readText()throws->String {
        try validate()
        let fd=open(url.path,O_RDONLY|O_NOFOLLOW)
        guard fd>=0 else{throw AssistantFailure("无法打开所选文件。")};defer{close(fd)}
        var st=stat();guard fstat(fd,&st)==0,st.st_dev==device,st.st_ino==inode,st.st_size==size,size<=8192,st.st_nlink==1 else{throw AssistantFailure("仅支持未变化的 8 KiB 以内单链接文本文件。")}
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:false)
        let data=try handle.read(upToCount:8193) ?? Data()
        try validate()
        guard data.count==Int(size),let text=String(data:data,encoding:.utf8),!text.contains("\0") else{throw AssistantFailure("不是完整 UTF-8 文本，未发送。")};return text
    }
    func trash()throws -> String {
        try validate();var destination:NSURL?
        try FileManager.default.trashItem(at:url,resultingItemURL:&destination)
        return "已将 \(url.lastPathComponent) 移到废纸篓，可从废纸篓恢复。\(destination.map{"\n位置：\($0.path ?? "废纸篓")"} ?? "")\n未永久删除，也不代表内存已释放。"
    }
}

/// These decisions belong to the application, never to model text or history.
struct ActionProtection {
    private(set) var bundles=Set<String>()
    private(set) var files=Set<URL>()
    mutating func protect(_ app:QuitTarget){bundles.insert(app.bundle)}
    mutating func protect(_ file:FileTarget){files.insert(file.url)}
    func allows(_ app:QuitTarget)->Bool{!bundles.contains(app.bundle)}
    func allows(_ file:FileTarget)->Bool{!files.contains(file.url)}
    var count:Int{bundles.count+files.count}
}
func displayIdentity(_ value:String)->String {
    String(value.unicodeScalars.map{CharacterSet.controlCharacters.contains($0) || CharacterSet(charactersIn:"\u{202a}\u{202b}\u{202c}\u{202d}\u{202e}\u{2066}\u{2067}\u{2068}\u{2069}").contains($0) ? "�":String($0)}.joined().prefix(2048))
}

/// User-chosen output only. Exclusive creation cannot overwrite an existing path.
enum TextExport {
    static func write(_ text:String,to url:URL)throws {
        let data=Data(text.utf8)
        guard data.count<=8192,url.isFileURL else{throw AssistantFailure("另存文本超过8 KiB或路径无效。")}
        let parent=url.deletingLastPathComponent()
        guard parent.standardizedFileURL.path==parent.resolvingSymlinksInPath().path else{throw AssistantFailure("保存目录不能经过符号链接。")}
        let fd=open(url.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600)
        guard fd>=0 else{throw AssistantFailure("无法创建新文件（\(errno)）。已有文件不会覆盖。")};defer{close(fd)}
        var offset=0
        while offset<data.count {
            let n=data.withUnsafeBytes{Darwin.write(fd,$0.baseAddress!.advanced(by:offset),data.count-offset)}
            if n<0 && errno==EINTR{continue}
            guard n>0 else{throw AssistantFailure("写入未完成；部分新文件保留于 \(url.path)，原文件未修改。")};offset+=n
        }
        guard fsync(fd)==0 else{throw AssistantFailure("文件已写入但同步失败：\(url.path)。")}
    }
}
