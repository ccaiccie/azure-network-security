#!/usr/bin/env python3
"""Controlled Private Endpoint Blob probes. Future approved guest actions only.
No proxies, redirects, retries, account keys, SAS, token cache or token output.
"""
import argparse,contextlib,hashlib,http.client,ipaddress,json,os,re,signal,socket,ssl,subprocess,sys,tempfile,time,uuid
from datetime import datetime,timezone
from email.utils import formatdate
from pathlib import Path
CONFIG='/etc/azure-pe-lab.json'
CA_BUNDLE='/etc/ssl/certs/ca-certificates.crt'
FIELDS={'role','private_ip','firewall_private_ip','endpoint_ip','storage_account_name','blob_fqdn','container','blob_name'}
IPS={'reader':'10.10.1.10','seed':'10.10.1.11'}
PAYLOAD=b'azure-pe-lab-v1\nPrivate Endpoint inspection proof.\n'
PAYLOAD_SHA256=hashlib.sha256(PAYLOAD).hexdigest()
TOKEN_PATH='/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F'
BODY_LIMIT=8192

def utc():return datetime.now(timezone.utc).isoformat()
def validate_config(c):
 if not isinstance(c,dict) or set(c)!=FIELDS:raise ValueError('Exact documented nonsecret runtime fields required')
 role=c['role']
 if role not in IPS or c['private_ip']!=IPS[role] or c['endpoint_ip']!='10.30.1.7' or c['container']!='lab-data' or c['blob_name']!='proof.txt':raise ValueError('Unexpected fixed role/address/object')
 name=c['storage_account_name']
 if not isinstance(name,str) or not re.fullmatch(r'[a-z0-9]{3,24}',name) or c['blob_fqdn']!=name+'.blob.core.windows.net':raise ValueError('Exact ordinary owned Blob hostname required')
 f=c['firewall_private_ip']
 if not isinstance(f,str):raise ValueError('Canonical Firewall IPv4 string required')
 ip=ipaddress.ip_address(f);net=ipaddress.ip_network('10.0.1.0/26')
 if ip.version!=4 or str(ip)!=f or ip not in net or int(ip)-int(net.network_address)<4 or ip==net.broadcast_address:raise ValueError('Unexpected allocated Firewall address')
 return dict(c)
def write_json(path,value):
 with Path(path).open('x',encoding='utf-8') as f:json.dump(value,f,indent=2,sort_keys=True);f.write('\n')
 os.chmod(path,0o600)
def new_out(requested,case):
 if requested:
  path=Path(requested)
  if any(parent.is_symlink() for parent in [path,*path.parents]):raise FileExistsError('Symlink output path component refused')
  path.parent.mkdir(parents=True,exist_ok=True,mode=0o700);path.mkdir(mode=0o700,exist_ok=False)
 else:path=Path(tempfile.mkdtemp(prefix='pe-'+case+'-'))
 return path
@contextlib.contextmanager
def deadline(seconds):
 # Single-process Linux CLI. A wall-clock alarm also bounds blocking DNS/TLS reads.
 old=signal.getsignal(signal.SIGALRM)
 def timeout(_sig,_frame):raise TimeoutError('bounded operation expired')
 signal.signal(signal.SIGALRM,timeout);signal.setitimer(signal.ITIMER_REAL,seconds)
 try:yield
 finally:signal.setitimer(signal.ITIMER_REAL,0);signal.signal(signal.SIGALRM,old)
def local_nic(c):
 rows=json.loads(subprocess.run(['ip','-j','-4','addr','show'],check=True,capture_output=True,text=True,timeout=5).stdout)
 names=[r.get('ifname') for r in rows if r.get('ifname') not in (None,'lo') and any(a.get('local')==c['private_ip'] for a in r.get('addr_info',[]))]
 if len(names)!=1:raise ValueError('Exact private source must be on one non-loopback NIC')
 return names[0]
def resolve(c):
 rows=socket.getaddrinfo(c['blob_fqdn'],443,family=socket.AF_INET,type=socket.SOCK_STREAM)
 answers=sorted({r[4][0] for r in rows})
 if answers!=[c['endpoint_ip']]:raise ValueError('Ordinary Blob hostname must resolve only the owned PE IPv4')
 return answers

def ready(c):
 c=validate_config(c)
 with deadline(20):
  iface=local_nic(c);answers=resolve(c)
  rows={}
  for q in (c['blob_fqdn'],c['storage_account_name']+'.privatelink.blob.core.windows.net'):
   result=subprocess.run(['dig','@'+c['firewall_private_ip'],q,'A','+noall','+answer','+time=2','+tries=1'],capture_output=True,text=True,timeout=5,check=True)
   text=result.stdout
   if len(text)>8192:raise ValueError('DNS evidence exceeded bound')
   a=[line.split()[-1] for line in text.splitlines() if len(line.split())>=5 and line.split()[3]=='A']
   if sorted(set(a))!=[c['endpoint_ip']]:raise ValueError('Firewall DNS proxy did not return only owned PE A record')
   rows[q]=text
  ca=Path(CA_BUNDLE)
  if not ca.is_file():raise ValueError('Approved image public CA bundle is missing')
  context=ssl.create_default_context(cafile=CA_BUNDLE)
  if not context.check_hostname or context.verify_mode!=ssl.CERT_REQUIRED:raise ValueError('Strict TLS context unavailable')
  return {'status':'LOCAL_DNS_CLIENT_READY','role':c['role'],'interface':iface,'os_ipv4_answers':answers,'firewall_dns_answers':rows,'ca_bundle_path':CA_BUNDLE,'ca_bundle_sha256':hashlib.sha256(ca.read_bytes()).hexdigest(),'completed_utc':utc(),'scope':'Local NIC/tools/CA and DNS only; no token, Blob operation, TLS handshake, route or Firewall inspection proof'}

def acquire_token(c):
 # Never include the token response/body or exception text in evidence or logs.
 conn=http.client.HTTPConnection('169.254.169.254',80,timeout=5,source_address=(c['private_ip'],0))
 try:
  conn.request('GET',TOKEN_PATH,headers={'Metadata':'true','Connection':'close'})
  response=conn.getresponse()
  if response.status!=200:raise ValueError('IMDS token request did not succeed')
  raw=response.read(32769)
  if len(raw)>32768:raise ValueError('IMDS response exceeded bound')
  row=json.loads(raw)
  token=row.get('access_token')
  expiry=int(row.get('expires_on',0))
  if not isinstance(token,str) or not re.fullmatch(r'[A-Za-z0-9._~-]{20,16384}',token) or str(row.get('token_type','')).lower()!='bearer' or row.get('resource')!='https://storage.azure.com/' or not time.time()+30<expiry<time.time()+86400:raise ValueError('IMDS token envelope invalid')
  return token
 finally:conn.close()

def safe_headers(response,forbidden=()):
 out={}
 patterns={'x-ms-request-id':r'[0-9a-fA-F-]{1,80}','x-ms-client-request-id':r'[0-9a-fA-F-]{1,80}','x-ms-error-code':r'[A-Za-z0-9]{1,128}','content-length':r'[0-9]{1,12}','etag':r'"?[0-9a-zA-Zx-]{1,96}"?'}
 for name,pattern in patterns.items():
  value=response.getheader(name)
  if isinstance(value,str) and re.fullmatch(pattern,value) and not any(secret and secret in value for secret in forbidden):out[name]=value
 return out

def run_probe(c,mode,out,confirm_token=False,confirm_data=False):
 c=validate_config(c)
 if mode not in ('noauth','read','seed'):raise ValueError('Unknown mode')
 if mode=='read' and c['role']!='reader':raise ValueError('Authenticated read runs only on reader VM')
 if mode=='seed' and c['role']!='seed':raise ValueError('Seed write runs only on separate seed VM')
 if mode!='noauth' and not confirm_token:raise ValueError('Explicit --confirm-token-use required after operator authorization')
 if mode=='seed' and not confirm_data:raise ValueError('Explicit --confirm-data-operation required for fixed synthetic create-only object')
 case=str(uuid.uuid4());out=new_out(out,case);write_json(out/'runtime-config.json',c)
 result={'case_id':case,'mode':mode,'started_utc':utc(),'outcome':'NEEDS_REVIEW','role':c['role'],'attempted_source_ip':c['private_ip'],'attempted_destination':[c['endpoint_ip'],443],'hostname':c['blob_fqdn'],'path':'/lab-data/proof.txt','tcp_connect_completed':False,'tls_verified':False,'http_request_write_completed':False,'token_requested':False,'token_acquired':False,'authorized_blob_read_proven':False,'synthetic_blob_created':False,'private_path_proven':False,'firewall_inspection_proven':False,'expected_sha256':PAYLOAD_SHA256,'expected_bytes':len(PAYLOAD),'automatic_retry':False,'automatic_redirect':False,'total_deadline_seconds':30,'socket_timeout_seconds':5}
 raw=tls=conn=None;token=None;headers=None;phase='local-preflight';start=time.monotonic()
 try:
  with deadline(30):
   result['interface']=local_nic(c);result['os_ipv4_answers']=resolve(c)
   if mode!='noauth':
    phase='token-acquisition';result['token_requested']=True;token=acquire_token(c);result['token_acquired']=True
   phase='tcp-connect';raw=socket.socket(socket.AF_INET,socket.SOCK_STREAM);raw.settimeout(5);raw.bind((c['private_ip'],0));result['attempted_local']=list(raw.getsockname());write_json(out/'attempt.json',{'case_id':case,'attempted_local':result['attempted_local'],'attempted_destination':result['attempted_destination'],'started_utc':result['started_utc']})
   if result['attempted_local'][0]!=c['private_ip'] or not 1<=result['attempted_local'][1]<=65535:raise ValueError('Bound source mismatch')
   raw.connect((c['endpoint_ip'],443));result['tcp_connect_completed']=True
   if raw.getpeername()[0]!=c['endpoint_ip']:raise ValueError('Unexpected TCP peer')
   phase='tls-handshake';context=ssl.create_default_context(cafile=CA_BUNDLE);context.minimum_version=ssl.TLSVersion.TLSv1_2
   if not context.check_hostname or context.verify_mode!=ssl.CERT_REQUIRED:raise ValueError('Strict TLS required')
   tls=context.wrap_socket(raw,server_hostname=c['blob_fqdn']);raw=None
   result['tls_verified']=True;result['tls_version']=tls.version();result['certificate_sha256']=hashlib.sha256(tls.getpeercert(binary_form=True)).hexdigest();result['connected_peer']=list(tls.getpeername())
   # Existing verified TLS socket, auto_open disabled. No redirect/proxy code exists.
   conn=http.client.HTTPConnection(c['blob_fqdn'],443,timeout=5);conn.auto_open=0;conn.sock=tls;tls=None
   headers={'Host':c['blob_fqdn'],'x-ms-date':formatdate(usegmt=True),'x-ms-version':'2023-11-03','x-ms-client-request-id':case,'User-Agent':'azure-pe-lab/'+case,'Connection':'close'}
   if token is not None:headers['Authorization']='Bearer '+token
   if mode=='seed':headers.update({'x-ms-blob-type':'BlockBlob','If-None-Match':'*','Content-Type':'text/plain; charset=utf-8'})
   phase='https-request';conn.request('PUT' if mode=='seed' else 'GET','/lab-data/proof.txt',body=PAYLOAD if mode=='seed' else None,headers=headers);result['http_request_write_completed']=True
   # Keep token only in memory through response for explicit echo redaction.
   # Python cannot guarantee memory erasure; never serialize headers or the token.
   headers.pop('Authorization',None)
   phase='https-response';response=conn.getresponse();result['http_status']=response.status;result['service_headers']=safe_headers(response,(token,))
   body=response.read(BODY_LIMIT+1);result['response_body_bytes_observed']=len(body);result['response_body_truncated']=len(body)>BODY_LIMIT
   if len(body)>BODY_LIMIT:raise ValueError('Service response exceeded fixed bound')
   if token and token.encode() in body:
    result['response_sensitive_echo_detected']=True
    raise ValueError('Sensitive echo suppressed')
   result['response_body_sha256']=hashlib.sha256(body).hexdigest()
   result['authorized_blob_read_proven']=mode=='read' and response.status==200 and body==PAYLOAD
   result['synthetic_blob_created']=mode=='seed' and response.status==201 and len(body)==0
   result['observation']='AUTHORIZED_CONTENT_MATCH' if result['authorized_blob_read_proven'] else 'CREATE_ACCEPTED' if result['synthetic_blob_created'] else 'SERVICE_RESPONSE_REQUIRES_REVIEW'
   if mode=='noauth':result['note']='No bearer credential sent.403 or any service response is not authorized Blob access or inspection proof.'
   if mode=='seed' and response.status in (409,412):result['note']='Existing/conflicting object was not overwritten. Inspect authorized evidence; no automatic retry or deletion.'
 except BaseException as exc:
  # Class/stage only: raw exceptions, server bodies and token envelopes can contain secrets.
  result.update(error_type=type(exc).__name__,error_phase=phase,error_detail='Redacted; review approved private diagnostics without exposing token material',observation='INCOMPLETE_REQUIRES_REVIEW')
  if isinstance(exc,(KeyboardInterrupt,SystemExit)):result['interrupted']=True
 finally:
  if headers is not None:headers.pop('Authorization',None)
  token=None
  for value in (conn,tls,raw):
   if value is not None:
    with contextlib.suppress(BaseException):value.close()
  result['completed_utc']=utc();result['elapsed_seconds']=round(time.monotonic()-start,3)
  result['evidence_note']='Correlate client tuple/time/hostname with Firewall application action and service request IDs. Standard HTTPS does not decrypt or log HTTP client-request-id. Never infer S=F or a service caller-IP value. No token/Authorization/body is retained.'
  write_json(out/'result.json',result)
 return result,out

def main():
 os.umask(0o077);p=argparse.ArgumentParser(description=__doc__);p.add_argument('mode',choices=['ready','noauth','read','seed']);p.add_argument('--out');p.add_argument('--confirm-token-use',action='store_true');p.add_argument('--confirm-data-operation',action='store_true');args=p.parse_args()
 try:
  c=validate_config(json.loads(Path(os.environ.get('PE_LAB_CONFIG',CONFIG)).read_text()))
  if args.mode=='ready':
   if args.out or args.confirm_token_use or args.confirm_data_operation:raise ValueError('ready accepts no token/data/output options')
   print(json.dumps(ready(c),indent=2));return
  result,out=run_probe(c,args.mode,args.out,args.confirm_token_use,args.confirm_data_operation)
  print(json.dumps(result,indent=2));print('NEEDS_REVIEW; private evidence:',out)
  if result.get('error_type'):raise SystemExit(3)
 except (OSError,ValueError,subprocess.SubprocessError) as exc:
  p.exit(2,'Local preflight failed ('+type(exc).__name__+'); details suppressed to avoid sensitive data exposure.\n')
if __name__=='__main__':main()
