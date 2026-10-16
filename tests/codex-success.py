#!/usr/bin/env python3
# Exercise real Codex success events with product arguments against a fake local API.
# Run: python3 tests/codex-success.py after scripts/verify-assistant.sh.
# Requires Python 3, codex CLI, and build/test-assistant; no external model calls.
import http.server,json,os,pathlib,shutil,subprocess,tempfile,threading,time,tomllib
root=pathlib.Path(__file__).resolve().parents[1]
requests=[]
request_paths=[]
reply=json.dumps({'explanation':'Synthetic test OK','actions':[]})
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        request_paths.append(self.path)
        requests.append(json.loads(self.rfile.read(int(self.headers['Content-Length']))))
        item={'id':'msg_test','type':'message','status':'completed','role':'assistant','content':[{'type':'output_text','text':reply,'annotations':[]}]}
        base={'id':'resp_test','object':'response','created_at':int(time.time()),'model':'test-model','status':'in_progress','output':[]}
        events=[{'type':'response.created','response':base}, {'type':'response.output_item.added','output_index':0,'item':{**item,'status':'in_progress','content':[]}}, {'type':'response.content_part.added','item_id':'msg_test','output_index':0,'content_index':0,'part':{'type':'output_text','text':'','annotations':[]}}, {'type':'response.output_text.delta','item_id':'msg_test','output_index':0,'content_index':0,'delta':reply}, {'type':'response.output_text.done','item_id':'msg_test','output_index':0,'content_index':0,'text':reply}, {'type':'response.content_part.done','item_id':'msg_test','output_index':0,'content_index':0,'part':item['content'][0]}, {'type':'response.output_item.done','output_index':0,'item':item}, {'type':'response.completed','response':{**base,'status':'completed','output':[item],'usage':{'input_tokens':12,'output_tokens':8,'total_tokens':20,'input_tokens_details':{'cached_tokens':0},'output_tokens_details':{'reasoning_tokens':0}}}}]
        self.send_response(200);self.send_header('Content-Type','text/event-stream');self.end_headers()
        for i,event in enumerate(events):
            event['sequence_number']=i
            self.wfile.write(('event: '+event['type']+'\ndata: '+json.dumps(event)+'\n\n').encode())
        self.wfile.flush()
    def log_message(self,*args):pass
server=http.server.HTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='tinystat-codex-success-') as tmp:
        executable=str((pathlib.Path.home()/'.codex/packages/standalone/current/bin/codex').resolve());assert pathlib.Path(executable).exists()
        args=json.loads(subprocess.check_output([str(root/'build/test-assistant'),'--codex-args',f'http://127.0.0.1:{server.server_port}/v1',tmp],text=True))
        for index,value in enumerate(args):
            if value=='-c':tomllib.loads(args[index+1])
        env={'HOME':tmp,'CODEX_HOME':tmp,'PATH':os.path.dirname(executable)+':/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin','TINYSTAT_PROVIDER_KEY':'synthetic-not-a-credential'}
        sandbox=json.loads(subprocess.check_output([str(root/'build/test-assistant'),'--sandbox-args',executable,tmp,'--endpoint',f'http://127.0.0.1:{server.server_port}/v1'],text=True))
        completed=subprocess.run(['/usr/bin/sandbox-exec']+sandbox+[executable]+args,input='Synthetic greeting, reply with JSON.',text=True,env=env,cwd=tmp,capture_output=True,timeout=30)
        assert completed.returncode==0, f'CLI failed: status {completed.returncode}; '+completed.stderr[-1000:]
        assert requests and requests[-1].get('text',{}).get('format',{}).get('type')=='json_schema','output schema not transmitted'
        assert request_paths and all(path=='/v1/responses' for path in request_paths),request_paths
        output=pathlib.Path(tmp)/'events.jsonl';output.write_text(completed.stdout)
        subprocess.run([str(root/'build/test-assistant'),'--parse-codex',str(output)],check=True)
        print('PASS: product CLI arguments, structured output schema, synthetic successful Responses SSE, real CLI output parser')
finally:server.shutdown()
