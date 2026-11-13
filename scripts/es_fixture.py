"""Protocol fixture, NOT a real Elasticsearch instance."""
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_GET(self):
        if self.path=='/': self.send_json({'name':'datax-protocol-fixture','version':{'number':'8.0.0'}})
        elif self.path.startswith('/_cat/indices?'): self.send_json([{'index':'datax-fixture','health':'green','docs.count':'1','store.size':'1kb'}])
        else: self.send_json({},404)
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))))
        if self.path=='/datax-fixture/_search' and body.get('size',501)<=500:
            self.send_json({'took':1,'hits':{'hits':[{'_index':'datax-fixture','_id':'1','_source':{'label':'协议测试'}}]}})
        else: self.send_json({},400)
    def send_json(self,obj,status=200):
        data=json.dumps(obj).encode(); self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
HTTPServer(('127.0.0.1',19200),Handler).serve_forever()
