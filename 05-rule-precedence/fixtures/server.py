#!/usr/bin/env python3
"""Private synthetic policy fixture. No files, credentials, downloads or real data."""
import argparse
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import re
import threading

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def do_GET(self):
        if len(self.path)>256:
            self.send_error(414); return
        if sum(len(k)+len(v) for k,v in self.headers.items())>8192:
            self.send_error(431); return
        if self.path not in ('/probe','/health'):
            self.send_error(404); return
        port=self.server.server_address[1]
        host=self.headers.get('Host','')
        # The explicit expected port is injected only by local unit tests at an ephemeral port.
        accepted_port=getattr(self.server,'expected_host_port',port)
        if host not in (f'allowed.policy.test:{accepted_port}',f'denied.policy.test:{accepted_port}'):
            self.send_error(400); return
        case=self.headers.get('X-Lab-Case-ID','readiness')
        if not re.fullmatch(r'[A-Za-z0-9_.-]{1,128}',case):
            self.send_error(400); return
        row={'time_utc':datetime.now(timezone.utc).isoformat(),'fixture':'azure-policy-origin-v1',
             'case_id':case,'host':host,'path':self.path,'peer_ip':self.client_address[0],
             'peer_port':self.client_address[1],'server_ip':self.server.server_address[0],
             'server_port':port,'user_agent':self.headers.get('User-Agent','')[:256],
             'xff_untrusted':self.headers.get('X-Forwarded-For','')[:512]}
        body=(json.dumps(row,sort_keys=True)+'\n').encode()
        print(json.dumps(row,sort_keys=True),flush=True)
        self.send_response(200)
        for key,value in [('Content-Type','application/json'),('Content-Length',str(len(body))),('Cache-Control','no-store'),('Connection','close')]:self.send_header(key,value)
        self.end_headers();self.wfile.write(body);self.close_connection=True
    def do_POST(self):self.send_error(405)
    def log_message(self,*args):pass

class BoundedServer(ThreadingHTTPServer):
    daemon_threads=True
    request_queue_size=16
    def __init__(self,*args,**kwargs):
        self.slots=threading.BoundedSemaphore(32)
        super().__init__(*args,**kwargs)
    def get_request(self):
        sock,address=super().get_request();sock.settimeout(5);return sock,address
    def process_request(self,request,address):
        if not self.slots.acquire(blocking=False):self.shutdown_request(request);return
        try:super().process_request(request,address)
        except BaseException:self.slots.release();raise
    def process_request_thread(self,request,address):
        try:super().process_request_thread(request,address)
        finally:self.slots.release()

def make_server(address,port):return BoundedServer((address,port),Handler)
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bind',required=True)
    parser.add_argument('--port',required=True,type=int,choices=(8080,8081))
    args=parser.parse_args()
    if str(ipaddress.ip_address(args.bind))!='10.20.1.10':parser.error('Bind only the declared backend private IPv4 10.20.1.10')
    server=make_server(args.bind,args.port)
    print(json.dumps({'event':'listening','bind':args.bind,'port':args.port,'time_utc':datetime.now(timezone.utc).isoformat()}),flush=True)
    server.serve_forever()
if __name__=='__main__':main()
