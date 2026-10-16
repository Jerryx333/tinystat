import Foundation

struct ChatMessage:Codable {
    let role:String
    let text:String
    let date:Date
    init(role:String,text:String){self.role=role;self.text=String(text.prefix(12000));date=Date()}
}
struct ChatSession:Codable {
    var id=UUID()
    var title="新对话"
    var updated=Date()
    var messages:[ChatMessage]=[]
    var source:String?=nil
    mutating func append(role:String,text:String)throws {
        var next=self;next.messages.append(ChatMessage(role:role,text:text));next.updated=Date()
        if next.title=="新对话",role=="你"{next.title=String(text.prefix(32))}
        guard next.messages.count<=200,try JSONEncoder().encode(next).count<=256*1024 else{throw AssistantFailure("本会话已满（200 条或 256 KiB），请新建会话；已有记录保留。")}
        self=next
    }
    func context(excludingLast:Bool=false)->(messages:[[String:String]],omitted:Int){
        let source=excludingLast ? Array(messages.dropLast()):messages
        var result:[[String:String]]=[],size=0
        for message in source.reversed(){
            let item=["role":message.role=="你" ? "user":"assistant","text":message.text]
            let cost=(try? JSONSerialization.data(withJSONObject:item).count) ?? 0
            if size+cost>24*1024 || result.count>=24{break}
            size+=cost;result.insert(item,at:0)
        }
        return(result,source.count-result.count)
    }
}
struct SessionSummary {let id:UUID;let title:String;let updated:Date;let count:Int}
/// One bounded record at a time; no retained archive cache or executable objects.
final class ConversationStore {
    let directory:URL
    init(directory:URL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("TinyStat/Conversations")){self.directory=directory}
    private func prepare()throws {
        let fm=FileManager.default
        guard directory.standardizedFileURL.path==directory.resolvingSymlinksInPath().path else{throw AssistantFailure("会话目录不能是符号链接。")}
        try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        var st=stat();guard lstat(directory.path,&st)==0,st.st_uid==getuid(),(st.st_mode&S_IFMT)==S_IFDIR else{throw AssistantFailure("会话目录身份不可确认。")}
        try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
    }
    private func path(_ id:UUID)->URL{directory.appendingPathComponent(id.uuidString+".json")}
    private func entries()throws->[URL]{
        try prepare()
        let entries=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).filter{$0.pathExtension=="json"}
        guard entries.count<=30 else{throw AssistantFailure("会话目录超过 30 项，请先在本机整理。")};return entries
    }
    func list()throws->[SessionSummary]{
        try entries().map{url in
            guard let id=UUID(uuidString:url.deletingPathExtension().lastPathComponent) else{throw AssistantFailure("会话文件名损坏。")}
            let record=try load(id);return SessionSummary(id:id,title:record.title,updated:record.updated,count:record.messages.count)
        }.sorted{$0.updated>$1.updated}
    }
    func load(_ id:UUID)throws->ChatSession {
        try prepare();let url=path(id),fd=open(url.path,O_RDONLY|O_NOFOLLOW)
        guard fd>=0 else{throw AssistantFailure("无法读取会话（\(errno)）。")};defer{close(fd)}
        var st=stat();guard fstat(fd,&st)==0,st.st_uid==getuid(),st.st_nlink==1,(st.st_mode&S_IFMT)==S_IFREG,st.st_size<=256*1024 else{throw AssistantFailure("会话文件身份或大小异常。")}
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:false),data=try handle.read(upToCount:256*1024+1) ?? Data()
        let record=try JSONDecoder().decode(ChatSession.self,from:data)
        guard record.id==id,record.messages.count<=200,data.count<=256*1024,record.title.count<=80 else{throw AssistantFailure("会话记录超限或损坏。")};return record
    }
    func save(_ session:ChatSession)throws {
        let files=try entries(),url=path(session.id)
        guard files.contains(where:{$0.lastPathComponent==url.lastPathComponent}) || files.count<30 else{throw AssistantFailure("已保存 30 个会话。请在历史中删除不需要的记录后继续。")}
        let data=try JSONEncoder().encode(session)
        guard data.count<=256*1024,session.messages.count<=200 else{throw AssistantFailure("会话存储容量已满。")}
        // A private directory gives atomic temporary writes the same access boundary.
        try data.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
    func remove(_ id:UUID)throws { _=try load(id);try FileManager.default.removeItem(at:path(id)) }
}
