#!/usr/bin/env python3
"""Private fixed JSON/finite stream. No files, real data or external dependencies."""
import argparse,json,re,threading,time
from datetime import datetime,timezone
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from urllib.parse import parse_qs,urlsplit
class Handler(BaseHTTPRequestHandler):
    protocol_version='HTTP/1.1'
    def do_GET(self):
        if len(self.path)>256:self.send_error(414);return
        if sum(len(k)+len(v) for k,v in self.headers.items())>8192:self.send_error(431);return
        case=self.headers.get('X-Lab-Case-ID','local-ready')
        if not re.fullmatch(r'[A-Za-z0-9_.-]{1,128}',case):self.send_error(400);return
        target=urlsplit(self.path);duration=None
        if target.path=='/stream':
            q=parse_qs(target.query)
            try:
                assert set(q)=={'seconds'} and len(q['seconds'])==1
                duration=int(q['seconds'][0]);assert 5<=duration<=180 and self.server.server_address[1] in (8080,getattr(self.server,'test_port',-1))
            except (AssertionError,ValueError,KeyError):self.send_error(400);return
        elif self.path not in ('/probe','/health'):self.send_error(404);return
        def row(frame):return {'fixture':'azure-nva-origin-v1','case_id':case,'time_utc':datetime.now(timezone.utc).isoformat(),'frame':frame,'path':target.path,'peer_ip':self.client_address[0],'peer_port':self.client_address[1],'server_ip':self.server.server_address[0],'server_port':self.server.server_address[1]}
        first=row(0);body=(json.dumps(first)+'\n').encode()
        self.send_response(200);self.send_header('Content-Type','application/x-ndjson' if duration else 'application/json');self.send_header('Cache-Control','no-store');self.send_header('Connection','close')
        if not duration:self.send_header('Content-Length',str(len(body)))
        self.end_headers();self.close_connection=True
        try:
            self.wfile.write(body);self.wfile.flush();print(json.dumps(first),flush=True)
            if duration:
                deadline=time.monotonic()+duration
                frame=1
                while time.monotonic()<deadline:
                    time.sleep(min(1,max(0,deadline-time.monotonic())))
                    current=row(frame);current['stream_end']=time.monotonic()>=deadline;self.wfile.write((json.dumps(current)+'\n').encode());self.wfile.flush();print(json.dumps(current),flush=True);frame+=1
        except (BrokenPipeError,ConnectionResetError,TimeoutError):pass
    def do_POST(self):self.send_error(405)
    def log_message(self,*args):pass
class BoundedServer(ThreadingHTTPServer):
    daemon_threads=True
    request_queue_size=16
    def __init__(self,*a,**kw):self.slots=threading.BoundedSemaphore(32);super().__init__(*a,**kw)
    def get_request(self):
        sock,address=super().get_request();sock.settimeout(5);return sock,address
    def process_request(self,request,address):
        if not self.slots.acquire(False):self.shutdown_request(request);return
        try:super().process_request(request,address)
        except BaseException:self.slots.release();raise
    def process_request_thread(self,request,address):
        try:super().process_request_thread(request,address)
        finally:self.slots.release()
def make_server(bind,port):return BoundedServer((bind,port),Handler)
def main():
    p=argparse.ArgumentParser();p.add_argument('--bind',required=True,choices=['10.20.1.20']);p.add_argument('--port',type=int,required=True,choices=[8080,8081]);a=p.parse_args()
    server=make_server(a.bind,a.port);print(json.dumps({'event':'listening','bind':a.bind,'port':a.port}),flush=True);server.serve_forever()
if __name__=='__main__':main()
