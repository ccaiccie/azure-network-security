#!/usr/bin/env python3
"""Synthetic Linux forwarding control, readiness publisher and unprivileged health HTTP.
Only future approved guest actions may run control commands. No Azure APIs, NAT,
state replication, external package installation or global ruleset flush.
"""
import argparse,contextlib,fcntl,hashlib,json,os,re,signal,subprocess,sys,tempfile,time
from datetime import datetime,timezone
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
A='10.10.1.10';B='10.20.1.20';TABLE='azure_nva_lab'
STATE=Path('/var/lib/azure-nva-lab');RUNTIME=Path('/run/azure-nva-lab')
SYSFILE=Path('/etc/sysctl.d/90-azure-nva-lab.conf')
def utc():return datetime.now(timezone.utc).isoformat()
def read_json(path,default=None):
    try:return json.loads(Path(path).read_text())
    except FileNotFoundError:return default

def atomic_json(path,value,mode=0o644):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    fd,temp=tempfile.mkstemp(prefix='.'+path.name+'-',dir=path.parent)
    try:
        with os.fdopen(fd,'w') as f:json.dump(value,f,sort_keys=True);f.write('\n');f.flush();os.fsync(f.fileno())
        os.chmod(temp,mode);os.replace(temp,path)
    finally:
        if os.path.exists(temp):os.unlink(temp)

def record_event(directory,event):
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=True,mode=0o700)
    fd=os.open(directory/'events.jsonl',os.O_WRONLY|os.O_CREAT|os.O_APPEND,0o600)
    with os.fdopen(fd,'a') as f:f.write(json.dumps(event,sort_keys=True)+'\n');f.flush();os.fsync(f.fileno())
    try:print(json.dumps(event),flush=True)
    except BrokenPipeError:pass # SSH output loss must not prevent recorded recovery.

def normalize(value):
    if isinstance(value,list):return [normalize(x) for x in value if not (isinstance(x,dict) and 'metainfo' in x)]
    if isinstance(value,dict):return {k:({} if k=='counter' and isinstance(v,dict) else normalize(v)) for k,v in value.items() if k not in ('handle','index')}
    return value

def digest(value):return hashlib.sha256(json.dumps(normalize(value),sort_keys=True,separators=(',',':')).encode()).hexdigest()
def has_nat(value):
    if isinstance(value,dict):return bool(set(value)&{'snat','dnat','masquerade','redirect'}) or any(has_nat(v) for v in value.values())
    if isinstance(value,list):return any(has_nat(v) for v in value)
    return False

def nft_source(ip,opened):
    assert ip in ('10.0.2.4','10.0.2.5')
    rules='''    ct state invalid counter drop comment "drop-invalid"
    ip saddr 10.10.1.10 ip daddr 10.20.1.20 tcp dport 8081 counter drop comment "deny-alternate-8081"
'''
    if opened:
        rules+='''    ip saddr 10.10.1.10 ip daddr 10.20.1.20 tcp dport 8080 ct state new tcp flags & (fin | syn | rst | ack) == syn counter accept comment "allow-new-syn-8080"
    ip saddr 10.10.1.10 ip daddr 10.20.1.20 tcp dport 8080 ct state established counter accept comment "allow-established-forward"
    ip saddr 10.20.1.20 ip daddr 10.10.1.10 tcp sport 8080 ct state established counter accept comment "allow-established-reply"
'''
    rules+='    counter drop comment "drop-other-forward"\n'
    return f'''table inet {TABLE} {{
  chain health_input {{
    type filter hook input priority 0; policy accept;
    iifname "lo" tcp dport 8008 accept comment "health-local"
    ip saddr 168.63.129.16 ip daddr {ip} tcp dport 8008 accept comment "health-azure-probe"
    tcp dport 8008 counter drop comment "deny-other-health-source"
  }}
  chain forward {{
    type filter hook forward priority 0; policy drop;
{rules}  }}
}}
'''

class Backend:
    def __init__(self,cfg):
        self.cfg=cfg;self.ip=cfg['private_ip']
        assert cfg['role'] in ('nva1','nva2') and self.ip=={'nva1':'10.0.2.4','nva2':'10.0.2.5'}[cfg['role']]
    def run(self,args,check=True):
        r=subprocess.run(args,capture_output=True,text=True,timeout=10)
        if check and r.returncode:raise RuntimeError('Command failed: '+' '.join(args)+': '+r.stderr.strip())
        return r
    def interface(self):
        rows=json.loads(self.run(['ip','-j','-4','addr','show']).stdout)
        names=[r['ifname'] for r in rows if any(a.get('local')==self.ip for a in r.get('addr_info',[]))]
        if len(names)!=1 or not re.fullmatch(r'[A-Za-z0-9_-]+',names[0]):raise RuntimeError('Expected exact local NVA IP/interface missing')
        return names[0]
    def values(self):
        iface=self.interface();keys=['net.ipv4.ip_forward','net.netfilter.nf_conntrack_tcp_loose']
        keys += [f'net.ipv4.conf.{scope}.{name}' for scope in ('all','default',iface) for name in ('rp_filter','accept_redirects','send_redirects','accept_source_route')]
        return {k:int(self.run(['sysctl','-n',k]).stdout.strip()) for k in keys}
    def table(self):return json.loads(self.run(['nft','-j','list','table','inet',TABLE]).stdout)
    def ruleset(self):return json.loads(self.run(['nft','-j','list','ruleset']).stdout)
    def apply_policy(self,opened):
        present=self.run(['nft','list','table','inet',TABLE],check=False).returncode==0
        text=('delete table inet '+TABLE+'\n' if present else '')+nft_source(self.ip,opened)
        with tempfile.NamedTemporaryFile('w',prefix='azure-nva-',suffix='.nft',delete=False) as f:f.write(text);path=f.name
        try:
            self.run(['nft','-c','-f',path]) # Check the whole atomic batch before mutation.
            self.run(['nft','-f',path])    # Only the owned table; never flush ruleset.
        finally:os.unlink(path)
        return digest(self.table())
    def set_values(self,values,persist=True):
        # ip_forward can reset IPv4 defaults: set it FIRST, then explicitly restore
        # intended RP and strict conntrack values, and verify all after the changes.
        keys=['net.ipv4.ip_forward']+[k for k in values if k!='net.ipv4.ip_forward']
        for k in keys:self.run(['sysctl','-w',f'{k}={values[k]}'])
        actual=self.values()
        if any(actual.get(k)!=v for k,v in values.items()):raise RuntimeError('Sysctl verification failed; keep health withdrawn')
        if persist:
            text='# Owned by this disposable NVA lab.\n'+''.join(f'{k}={values[k]}\n' for k in keys)
            SYSFILE.write_text(text);os.chmod(SYSFILE,0o644)
    def activate_values(self):
        original=self.values()
        if not (STATE/'original-sysctl.json').exists():atomic_json(STATE/'original-sysctl.json',{'node':self.cfg['role'],'values':original},0o600)
        desired={k:(1 if k=='net.ipv4.ip_forward' else (2 if k.endswith('.rp_filter') else 0)) for k in original}
        self.set_values(desired)

def local_checks(backend,state,require_advertised=True):
    reasons=[]
    if state.get('mode')!='open':reasons.append('forwarding-policy-closed')
    if require_advertised and not state.get('advertised',False):reasons.append('health-withdrawn')
    try:
        values=backend.values()
        if values.get('net.ipv4.ip_forward')!=1:reasons.append('ipv4-forwarding-not-1')
        if values.get('net.netfilter.nf_conntrack_tcp_loose')!=0:reasons.append('conntrack-pickup-not-strict')
        if any(v!=2 for k,v in values.items() if k.endswith('.rp_filter')):reasons.append('rp-filter-not-loose-mode2')
        if any(v!=0 for k,v in values.items() if k.endswith(('.accept_redirects','.send_redirects','.accept_source_route'))):reasons.append('redirect-or-source-route-hardening-drift')
        if digest(backend.table())!=state.get('policy_digest'):reasons.append('owned-policy-drift')
        if has_nat(backend.ruleset()):reasons.append('NAT-present-in-nft-ruleset')
    except (ValueError,OSError,RuntimeError,subprocess.SubprocessError) as exc:reasons.append('local-check-error:'+str(exc))
    return {'ready':not reasons,'reasons':reasons,'node':backend.cfg['role'],'private_ip':backend.ip,'time_utc':utc(),'time_epoch':time.time(),'scope':'local-only-not-end-to-end-or-Azure-eligibility'}

def write_state(backend,mode,advertised,policy_digest=None):
    value={'node':backend.cfg['role'],'mode':mode,'advertised':advertised,'policy_digest':digest(backend.table()) if policy_digest is None else policy_digest,'changed_utc':utc()}
    atomic_json(STATE/'state.json',value);return value

def restore_recorded(backend,saved):
    if saved['node']!=backend.cfg['role']:raise RuntimeError('Recovery belongs to a different node')
    # Reboot may have restored the safe closed state. Recover the recorded owned
    # sysctls only when different, setting ip_forward before the RP/security values.
    if saved.get('restore_sysctls') and backend.values()!=saved['restore_sysctls']:
        backend.set_values(saved['restore_sysctls'])
    if digest(backend.table())!=saved.get('policy_digest'):
        backend.apply_policy(saved['mode']=='open')
    # Health-only withdrawal does not reload the unchanged data-plane table/counters.
    write_state(backend,saved['mode'],saved['advertised'])

def control(backend,action,seconds=30,confirmed=False):
    if action=='status':
        state=read_json(STATE/'state.json',{'mode':'closed','advertised':False})
        return {'state':state,'health':local_checks(backend,state),'recovery_available':(STATE/'failure-recovery.json').exists()}
    if action!='boot' and not confirmed:raise RuntimeError('Explicit --confirm-guest-change required after approval for this node/action')
    if os.geteuid()!=0:raise RuntimeError('Run approved guest changes as root')
    STATE.mkdir(mode=0o755,parents=True,exist_ok=True);RUNTIME.mkdir(mode=0o755,parents=True,exist_ok=True)
    os.chmod(STATE,0o755);os.chmod(RUNTIME,0o755)
    with (RUNTIME/'control.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        state=read_json(STATE/'state.json',{'node':backend.cfg['role'],'mode':'closed','advertised':False})
        if action=='boot':
            backend.apply_policy(False) # Closed first even when restoring an approved open state.
            if state['mode']=='open':backend.activate_values();backend.apply_policy(True)
            else:
                # New images must not be used as routers before activation.
                values=backend.values();values['net.ipv4.ip_forward']=0;backend.set_values(values)
            return write_state(backend,state['mode'],state['advertised'])
        if action in ('activate','advertise','restore-original') and (STATE/'failure-recovery.json').exists():
            raise RuntimeError('Unresolved recovery record exists; inspect and explicitly recover before changing the recorded baseline')
        if action=='activate':
            backend.apply_policy(False);backend.activate_values();backend.apply_policy(True)
            return write_state(backend,'open',False) # Separate explicit health advertisement.
        if action=='close':
            backend.apply_policy(False);return write_state(backend,'closed',False)
        if action=='withdraw':return write_state(backend,state['mode'],False,state.get('policy_digest',''))
        if action=='advertise':
            result=local_checks(backend,state,require_advertised=False)
            if not result['ready']:raise RuntimeError('Cannot advertise: '+','.join(result['reasons']))
            return write_state(backend,state['mode'],True,state.get('policy_digest',''))
        if action=='restore-original':
            saved=read_json(STATE/'original-sysctl.json')
            if not saved or saved['node']!=backend.cfg['role']:raise RuntimeError('No matching original sysctl record')
            backend.apply_policy(False);write_state(backend,'closed',False);backend.set_values(saved['values'],persist=False)
            SYSFILE.unlink(missing_ok=True)
            return {'restored_original_sysctls':True,'mode':'closed','advertised':False}
        if action=='recover':
            saved=read_json(STATE/'failure-recovery.json')
            if not saved:raise RuntimeError('No saved bounded-failure recovery record')
            restore_recorded(backend,saved)
            if saved.get('attempt_directory'):record_event(saved['attempt_directory'],{'event':'manual-recovered','node':backend.cfg['role'],'utc':utc()})
            (STATE/'failure-recovery.json').unlink();return {'recovered':True}
        if action in ('withdraw-for','fail-forwarding'):
            if not 5<=seconds<=120:raise RuntimeError('Bounded failure must be5..120 seconds')
            if (STATE/'failure-recovery.json').exists():raise RuntimeError('Unresolved recovery record exists; inspect and recover before another failure')
            if state.get('mode')!='open' or not local_checks(backend,state,require_advertised=False)['ready']:
                raise RuntimeError('Bounded failure requires verified open owned forwarding first')
            attempt=STATE/'experiments'/f'{action}-{time.time_ns()}'
            state={**state,'restore_sysctls':backend.values(),'attempt_directory':str(attempt)}
            atomic_json(STATE/'failure-recovery.json',state,0o600)
            try:
                record_event(attempt,{'event':action+'-start','node':backend.cfg['role'],'utc':utc(),'seconds':seconds,'recorded_mode':state['mode'],'recorded_advertised':state['advertised']})
                if action=='fail-forwarding':backend.apply_policy(False);write_state(backend,'closed',False)
                else:write_state(backend,state['mode'],False,state.get('policy_digest',''))
                time.sleep(seconds)
            finally:
                pending=sys.exc_info()[0].__name__ if sys.exc_info()[0] else None
                try:
                    restore_recorded(backend,state)
                    record_event(attempt,{'event':action+'-restored','node':backend.cfg['role'],'utc':utc(),'interruption':pending})
                    (STATE/'failure-recovery.json').unlink()
                except BaseException as exc:
                    record_event(attempt,{'event':action+'-restore-failed','node':backend.cfg['role'],'utc':utc(),'error_type':type(exc).__name__,'error':str(exc)})
                    raise
            return {'restored_recorded_state':True}
        raise RuntimeError('Unsupported action')

def monitor(backend):
    RUNTIME.mkdir(mode=0o755,parents=True,exist_ok=True)
    while True:
        state=read_json(STATE/'state.json',{'mode':'closed','advertised':False})
        atomic_json(RUNTIME/'health.json',local_checks(backend,state))
        time.sleep(2)

def health_snapshot(path=RUNTIME/'health.json',now=None):
    now=time.time() if now is None else now
    try:
        value=read_json(path)
        if not value or not 0<=now-value['time_epoch']<=6:return 503,{'ready':False,'reason':'missing-or-stale-local-monitor'}
        return (200 if value.get('ready') else 503),value
    except (OSError,ValueError,KeyError,TypeError):return 503,{'ready':False,'reason':'invalid-monitor-snapshot'}
class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path!='/healthz':self.send_error(404);return
        status,value=health_snapshot();body=(json.dumps(value)+'\n').encode()
        self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.send_header('Connection','close');self.end_headers();self.wfile.write(body)
    def log_message(self,*args):pass
class HealthServer(ThreadingHTTPServer):
    daemon_threads=True
    def get_request(self):
        sock,address=super().get_request();sock.settimeout(3);return sock,address

def install_interrupt_handlers():
    # SSH hangup as well as INT/TERM reaches the bounded test's finally block.
    # SIGKILL and power loss remain unrecoverable in-process; use saved recover.
    def interrupted(signum,frame):raise SystemExit(128+signum)
    for signum in (signal.SIGHUP,signal.SIGINT,signal.SIGTERM):signal.signal(signum,interrupted)

def main():
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='command',required=True)
    ctl=sub.add_parser('control');ctl.add_argument('action',choices=['boot','status','activate','close','advertise','withdraw','withdraw-for','fail-forwarding','recover','restore-original']);ctl.add_argument('--seconds',type=int,default=30);ctl.add_argument('--confirm-guest-change',action='store_true')
    sub.add_parser('monitor');sub.add_parser('health')
    args=parser.parse_args();cfg=read_json(os.environ.get('NVA_LAB_CONFIG','/etc/azure-nva-lab.json'));backend=Backend(cfg)
    if args.command=='health':HealthServer((backend.ip,8008),HealthHandler).serve_forever();return
    if args.command=='monitor':monitor(backend);return
    install_interrupt_handlers()
    print(json.dumps(control(backend,args.action,args.seconds,args.confirm_guest_change),sort_keys=True))
if __name__=='__main__':main()
