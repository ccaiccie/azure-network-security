#!/usr/bin/env python3
"""Bounded synthetic HTTPS observations. No automatic WAF or proxy-path verdict."""
import argparse,contextlib,datetime,hashlib,http.client,ipaddress,json,os,re,signal,socket,ssl,tempfile,time,uuid
from pathlib import Path
MODES=('edge-positive','edge-block','regional-block','direct-gateway','direct-backend','fdid-missing','fdid-wrong','fdid-duplicate','fdid-duplicate-valid','fdid-case','fdid-correct')
MARKER='azure-waf-origin-v1'
DEFAULT_CA='/etc/ssl/certs/ca-certificates.crt'
KEYS={'edge_fqdn','origin_fqdn','gateway_public_ip','backend_fqdn','frontdoor_id','operator_cidr'}
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
def public_ip(v):
 if not isinstance(v,str):raise ValueError('IPv4 must be a canonical string')
 p=ipaddress.ip_address(v)
 if p.version!=4 or str(p)!=v or not p.is_global or p.is_multicast or p.is_reserved or p.is_unspecified:raise ValueError('Actual public unicast IPv4 required')
 return v
def validate_config(c):
 if not isinstance(c,dict) or set(c)!=KEYS:raise ValueError('Exactly the six documented public fields are required')
 for key,suffix in [('edge_fqdn','.azurefd.net'),('backend_fqdn','.azurewebsites.net'),('origin_fqdn',None)]:
  v=c[key]
  if not isinstance(v,str) or len(v)>253 or not re.fullmatch(r'(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}',v) or v.endswith(('.invalid','.localhost','.example')):raise ValueError('Invalid public hostname')
  if suffix and not v.endswith(suffix):raise ValueError('Wrong service hostname suffix')
 public_ip(c['gateway_public_ip'])
 if not isinstance(c['operator_cidr'],str) or not c['operator_cidr'].endswith('/32'):raise ValueError('Operator scope must be /32')
 public_ip(c['operator_cidr'][:-3])
 if c['gateway_public_ip']==c['operator_cidr'][:-3]:raise ValueError('Gateway and client must differ')
 if not isinstance(c['frontdoor_id'],str) or not re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}',c['frontdoor_id']):raise ValueError('Canonical public Front Door GUID required')
 return c
def new_out(value):
 if value is None:return Path(tempfile.mkdtemp(prefix='azure-waf-case-'))
 p=Path(value)
 if p.exists() or p.is_symlink() or any(x.is_symlink() for x in p.parents):raise ValueError('Refuse existing output or symlink ancestor')
 p.mkdir(parents=True,mode=0o700)
 return p
def write_json(p,v):
 with os.fdopen(os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as f:json.dump(v,f,indent=2);f.write('\n')
@contextlib.contextmanager
def deadline(seconds):
 def expired(*_):raise TimeoutError('Bounded operation deadline')
 old=signal.signal(signal.SIGALRM,expired);signal.setitimer(signal.ITIMER_REAL,seconds)
 try:yield
 finally:signal.setitimer(signal.ITIMER_REAL,0);signal.signal(signal.SIGALRM,old)
def resolve(host):
 ips=sorted({r[4][0] for r in socket.getaddrinfo(host,443,family=socket.AF_INET,type=socket.SOCK_STREAM)})
 if not ips or len(ips)>32:raise ValueError('DNS IPv4 set empty or exceeds bounded scope')
 return [public_ip(v) for v in ips]
def load_ca_bundle(path):
 with Path(path).open('rb') as f:data=f.read(4194305)
 if not data or len(data)>4194304 or b'BEGIN CERTIFICATE' not in data or b'PRIVATE KEY' in data:raise ValueError('Approved public CA PEM bundle required')
 return data.decode('ascii'),hashlib.sha256(data).hexdigest()
def request_headers(c,mode,case):
 h=[('Host',c['edge_fqdn'] if mode.startswith('edge-') or mode=='regional-block' else c['backend_fqdn'] if mode=='direct-backend' else c['origin_fqdn']),('User-Agent','azure-waf-lab/'+case),('X-Lab-Case-Id',case),('Cache-Control','no-cache'),('Connection','close')]
 if mode=='edge-block':h.append(('X-Lab-Edge-Block','1'))
 if mode=='regional-block':h.append(('X-Lab-Regional-Block','1'))
 f=c['frontdoor_id'];wrong='00000000-0000-0000-0000-000000000000'
 if mode in ('direct-gateway','fdid-correct'):h.append(('X-Azure-FDID',f))
 elif mode=='fdid-wrong':h.append(('X-Azure-FDID',wrong))
 elif mode=='fdid-duplicate':h.extend([('X-Azure-FDID',f),('X-Azure-FDID',wrong)])
 elif mode=='fdid-duplicate-valid':h.extend([('X-Azure-FDID',f),('X-Azure-FDID',f)])
 elif mode=='fdid-case':h.append(('x-azure-fdid',f.upper()))
 return h
def run(c,mode,out,confirm=False,local_address='0.0.0.0',ca_file=DEFAULT_CA):
 validate_config(c)
 if mode not in MODES:raise ValueError('Unknown mode')
 if mode.startswith('fdid-') and not confirm:raise ValueError('FDID diagnostic request requires explicit authorized narrow ingress acknowledgement')
 if not isinstance(local_address,str) or str(ipaddress.IPv4Address(local_address))!=local_address:raise ValueError('Canonical local bind IPv4 required')
 case=str(uuid.uuid4());path='/probe/'+case;start=time.monotonic()
 result={'case_id':case,'mode':mode,'started_utc':utc(),'tcp_connect_completed':False,'tls_completed':False,'http_request_sent':False,'fixture_content_match':False,'waf_block_proven':False,'three_tls_legs_proven':False,'observation':'NOT_COMPLETED','origin_header_protection_proven':False,'ipv4_only':True,'local_bind_address':local_address}
 write_json(out/'public-config.json',c)
 raw=tls=conn=None;stage='trust-bundle'
 try:
  with deadline(20):
   ca_pem,ca_hash=load_ca_bundle(ca_file);result['ca_bundle_sha256']=ca_hash;result['trust_source']='explicit operator-reviewed public CA bundle; system/env stores not loaded'
   stage='dns'
   host=c['edge_fqdn'] if mode.startswith('edge-') or mode=='regional-block' else c['backend_fqdn'] if mode=='direct-backend' else c['origin_fqdn']
   result['sni_host']=host;result['request_path']=path
   ips=resolve(host);result['dns_ipv4']=ips
   if host==c['origin_fqdn'] and ips!=[c['gateway_public_ip']]:raise ValueError('Origin DNS must resolve only to the owned gateway IPv4 before direct tests')
   dest=c['gateway_public_ip'] if host==c['origin_fqdn'] else ips[0]
   result['attempted_destination']=[dest,443]
   stage='bind';raw=socket.socket(socket.AF_INET,socket.SOCK_STREAM);raw.settimeout(5);raw.bind((local_address,0))
   result['attempted_local']=list(raw.getsockname())
   write_json(out/'attempt.json',{'case_id':case,'started_utc':result['started_utc'],'attempted_local':result['attempted_local'],'attempted_destination':[dest,443],'hostname':host,'note':'Wildcard bound address is not the selected local interface or observed public NAT source'})
   stage='connect';raw.connect((dest,443));result['tcp_connect_completed']=True;result['connected_local']=list(raw.getsockname());result['connected_peer']=list(raw.getpeername())
   stage='tls';ctx=ssl.create_default_context(cadata=ca_pem);ctx.minimum_version=ssl.TLSVersion.TLSv1_2;ctx.set_alpn_protocols(['http/1.1'])
   if ctx.verify_mode!=ssl.CERT_REQUIRED or not ctx.check_hostname:raise ValueError('Strict TLS verification required')
   tls=ctx.wrap_socket(raw,server_hostname=host);result['tls_completed']=True;result['tls_version']=tls.version();result['certificate_sha256']=hashlib.sha256(tls.getpeercert(binary_form=True)).hexdigest()
   stage='http';conn=http.client.HTTPConnection(host,443,timeout=5);conn.auto_open=0;conn.sock=tls
   conn.putrequest('GET',path,skip_host=True,skip_accept_encoding=True)
   for k,v in request_headers(c,mode,case):conn.putheader(k,v)
   conn.endheaders();result['http_request_sent']=True
   response=conn.getresponse();result['http_status']=response.status;body=response.read(8193)
   if len(body)>8192:raise ValueError('Response body exceeds 8192-byte bound')
   result['http_status']=response.status;result['body_bytes']=len(body);result['body_sha256']=hashlib.sha256(body).hexdigest();result['response_headers']={}
   for name,pattern,limit in [('X-Azure-Ref',r'[A-Za-z0-9_+=/:-]+',256),('X-Lab-Fixture',r'[A-Za-z0-9-]+',80),('Content-Length',r'[0-9]{1,8}',8),('Content-Type',r'[A-Za-z0-9/+; =._-]+',100)]:
    value=response.getheader(name)
    if isinstance(value,str) and len(value)<=limit and re.fullmatch(pattern,value):result['response_headers'][name.lower()]=value
   try: parsed=json.loads(body)
   except (ValueError,UnicodeError):parsed=None
   expected={'fixture':MARKER,'case_id':case,'message':'Layered WAF inspection proof.'}
   result['fixture_content_match']=response.status==200 and parsed==expected
   result['observation']='FIXTURE_RESPONSE' if result['fixture_content_match'] else 'HTTP_RESPONSE_NEEDS_ATTRIBUTION'
 except (Exception,KeyboardInterrupt) as e:
  result['observation']='FAILED_BEFORE_COMPLETE_RESPONSE';result['error_class']=type(e).__name__;result['error_stage']=stage;result['error_message']='Inspect scoped route, TLS, policy and health evidence; raw exception text omitted'
 finally:
  for obj in (conn,tls,raw):
   if obj is not None:
    try:obj.close()
    except Exception:pass
  result['completed_utc']=utc();result['duration_seconds']=round(time.monotonic()-start,3)
  write_json(out/'result.json',result)
 return result
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--config',required=True);p.add_argument('--mode',choices=MODES,required=True);p.add_argument('--out');p.add_argument('--ca-file',default=DEFAULT_CA);p.add_argument('--local-address',default='0.0.0.0');p.add_argument('--confirm-diagnostic-ingress',action='store_true');a=p.parse_args()
 try:
  c=validate_config(json.loads(Path(a.config).read_text()))
  if a.mode.startswith('fdid-') and not a.confirm_diagnostic_ingress:raise ValueError('Diagnostic acknowledgement required')
  out=new_out(a.out);r=run(c,a.mode,out,a.confirm_diagnostic_ingress,a.local_address,a.ca_file)
 except (ValueError,OSError) as e:print(type(e).__name__+': invalid local configuration/output/approval; no details printed');return 2
 print(json.dumps({'out':str(out),'case_id':r['case_id'],'observation':r['observation'],'waf_block_proven':False}))
 return 3 if 'error_class' in r else 0
if __name__=='__main__':raise SystemExit(main())
