#!/usr/bin/env python3
"""Owned Linux perimeter forwarding/SNAT teaching control. No Azure/VPN/NGFW code.
Future approved guest actions only. Tests replace every system command.
"""
import argparse,contextlib,fcntl,hashlib,ipaddress,json,os,re,signal,subprocess,sys,tempfile,time,uuid
from datetime import datetime,timezone
from pathlib import Path
TABLE='azure_forced_lab'
STATE=Path('/var/lib/azure-forced-lab');RUNTIME=Path('/run/azure-forced-lab')
CONFIG='/etc/azure-forced-lab.json'
FIELDS={'role','private_ip','firewall_private_ip','app_ip','origin_public_ip','perimeter_public_ip','source_mode'}
def utc():return datetime.now(timezone.utc).isoformat()
def public_ip(value):
    if not isinstance(value,str):raise ValueError('Canonical IPv4 string required')
    ip=ipaddress.ip_address(value)
    if ip.version!=4 or not ip.is_global or ip.is_multicast or ip.is_reserved or ip in ipaddress.ip_network('192.0.0.0/24') or ip in ipaddress.ip_network('192.88.99.0/24'):raise ValueError('Actual global unicast IPv4 required')
    if str(ip)!=value:raise ValueError('Canonical IPv4 string required')
    return str(ip)
def validate_config(cfg):
    if not isinstance(cfg,dict) or set(cfg)!=FIELDS:raise ValueError('Exact documented perimeter config fields required')
    if cfg['role']!='perimeter' or cfg['private_ip']!='10.30.1.4' or cfg['app_ip']!='10.20.1.10' or cfg['source_mode'] not in ('preserve','firewall_private'):raise ValueError('Unexpected fixed perimeter identity/mode')
    if not isinstance(cfg['firewall_private_ip'],str):raise ValueError('Firewall IP must be a canonical IPv4 string')
    f=ipaddress.ip_address(cfg['firewall_private_ip']);subnet=ipaddress.ip_network('10.0.1.0/26')
    if f not in subnet or int(f)-int(subnet.network_address)<4 or f==subnet.broadcast_address:raise ValueError('Unexpected allocated Firewall private IP')
    if public_ip(cfg['origin_public_ip'])==public_ip(cfg['perimeter_public_ip']):raise ValueError('Origin D and perimeter P must differ')
    return dict(cfg)
def read_json(path,default=None):
    try:return json.loads(Path(path).read_text())
    except FileNotFoundError:return default
def sync_dir(path):
    fd=os.open(path,os.O_RDONLY|os.O_DIRECTORY)
    try:os.fsync(fd)
    finally:os.close(fd)
def atomic_json(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    fd,tmp=tempfile.mkstemp(prefix='.'+path.name+'-',dir=path.parent)
    try:
        with os.fdopen(fd,'w') as f:json.dump(value,f,sort_keys=True);f.write('\n');f.flush();os.fsync(f.fileno())
        os.chmod(tmp,0o600);os.replace(tmp,path);sync_dir(path.parent)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)
def remove_record(path):path.unlink(missing_ok=True);sync_dir(path.parent)
def normalize(v):
    if isinstance(v,list):return [normalize(x) for x in v if not(isinstance(x,dict) and 'metainfo' in x)]
    if isinstance(v,dict):return {k:({} if k=='counter' and isinstance(x,dict) else normalize(x)) for k,x in v.items() if k not in ('handle','index')}
    return v
def digest(value):return hashlib.sha256(json.dumps(normalize(value),sort_keys=True,separators=(',',':')).encode()).hexdigest()
def owner():return 'azure-forced-lab:perimeter:10.30.1.4'
def source_prefix(cfg):return '10.20.1.10/32' if cfg['source_mode']=='preserve' else '10.0.1.0/26'
def nft_source(cfg,iface,opened=False):
    validate_config(cfg)
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,15}',iface):raise ValueError('Unsafe interface name')
    src=source_prefix(cfg);d=cfg['origin_public_ip'];e=cfg['private_ip']
    rules=f'''    ct state invalid counter drop comment "deny-invalid"
    ip saddr {src} ip daddr {d} tcp dport 8082 counter drop comment "deny-perimeter-8082-forward"
    ip saddr {d} ip daddr {src} tcp sport 8082 counter drop comment "deny-perimeter-8082-reverse"
'''
    if opened:
        rules+=f'''    iifname "{iface}" oifname "{iface}" ip saddr {src} ip daddr {d} tcp dport {{ 8080, 8081 }} ct state new tcp flags & (fin | syn | rst | ack) == syn counter accept comment "allow-new-test-syn"
    iifname "{iface}" oifname "{iface}" ip saddr {src} ip daddr {d} tcp dport {{ 8080, 8081 }} ct state established counter accept comment "allow-established-test-forward"
    iifname "{iface}" oifname "{iface}" ip saddr {d} ip daddr {src} tcp sport {{ 8080, 8081 }} ct state established counter accept comment "allow-established-test-return"
'''
    else:
        rules+=f'''    ip saddr {src} ip daddr {d} tcp dport {{ 8080, 8081 }} counter drop comment "deny-closed-test-forward"
    ip saddr {d} ip daddr {src} tcp sport {{ 8080, 8081 }} counter drop comment "deny-closed-test-return"
'''
    nat=f'    oifname "{iface}" ip saddr {src} ip daddr {d} tcp dport {{ 8080, 8081 }} counter snat ip to {e} comment "snat-only-owned-test-to-E"\n' if opened else ''
    return f'''table inet {TABLE} {{
  comment "{owner()}"
  chain forward {{
    type filter hook forward priority 0; policy drop;
{rules}    counter drop comment "deny-other-forward"
  }}
  chain postrouting {{
    type nat hook postrouting priority srcnat; policy accept;
{nat}  }}
}}
'''
class Backend:
    def __init__(self,cfg):self.cfg=validate_config(cfg)
    def run(self,args,check=True):
        r=subprocess.run(args,capture_output=True,text=True,timeout=10)
        if check and r.returncode:raise RuntimeError('Command failed: '+' '.join(args)+': '+r.stderr.strip())
        return r
    def interface(self):
        rows=json.loads(self.run(['ip','-j','-4','addr','show']).stdout)
        names=[row['ifname'] for row in rows if any(x.get('local')==self.cfg['private_ip'] for x in row.get('addr_info',[]))]
        if len(names)!=1 or names[0]=='lo' or not re.fullmatch(r'[A-Za-z0-9_-]{1,15}',names[0]):raise RuntimeError('Expected exact local perimeter NIC missing')
        return names[0]
    def values(self):
        iface=self.interface();keys=['net.ipv4.ip_forward','net.netfilter.nf_conntrack_tcp_loose']+[f'net.ipv4.conf.{scope}.{item}' for scope in ('all','default',iface) for item in ('rp_filter','accept_redirects','send_redirects','accept_source_route')]
        return {k:int(self.run(['sysctl','-n',k]).stdout.strip()) for k in keys}
    def set_values(self,values):
        # ip_forward resets router/host defaults. Set it FIRST; then owned captured values.
        keys=['net.ipv4.ip_forward']+[k for k in values if k!='net.ipv4.ip_forward']
        for k in keys:self.run(['sysctl','-w',f'{k}={values[k]}'])
        actual=self.values()
        if any(actual.get(k)!=v for k,v in values.items()):raise RuntimeError('Owned sysctl verification failed')
    def table_exists(self):
        rows=json.loads(self.run(['nft','-j','list','tables']).stdout)
        return any(x.get('table',{}).get('family')=='inet' and x.get('table',{}).get('name')==TABLE for x in rows.get('nftables',[]))
    def table(self):return json.loads(self.run(['nft','-j','list','table','inet',TABLE]).stdout)
    def assert_table_owned(self):
        if self.table_exists():
            tables=[x['table'] for x in self.table().get('nftables',[]) if 'table' in x]
            if len(tables)!=1 or tables[0].get('comment')!=owner():raise RuntimeError('Owned table name collides with unrecognized policy')
    def original(self):
        row=read_json(STATE/'original.json')
        if not row or row.get('config')!=self.cfg or row.get('interface')!=self.interface():raise RuntimeError('Missing/mismatched original ownership record; do not overwrite or reopen')
        return row
    def enroll(self):
        self.assert_table_owned()
        if (STATE/'original.json').exists():return self.original()
        if self.table_exists():raise RuntimeError('Table exists without original ownership record')
        values=self.values()
        if values['net.ipv4.ip_forward']!=0:raise RuntimeError('Dedicated approved image must start with IPv4 forwarding disabled')
        row={'config':self.cfg,'interface':self.interface(),'values':values,'created_utc':utc()};atomic_json(STATE/'original.json',row);return row
    def apply_policy(self,opened):
        self.original();self.assert_table_owned();present=self.table_exists()
        source=('delete table inet '+TABLE+'\n' if present else '')+nft_source(self.cfg,self.interface(),opened)
        fd,path=tempfile.mkstemp(prefix='azure-forced-',suffix='.nft')
        try:
            with os.fdopen(fd,'w') as f:f.write(source)
            self.run(['nft','-c','-f',path]);self.run(['nft','-f',path])
        finally:os.unlink(path)
        return digest(self.table())
    def desired_values(self):
        values=self.original()['values']
        return {k:(1 if k=='net.ipv4.ip_forward' else 0) for k in values}
    def prepare(self):
        self.enroll();policy=self.apply_policy(False);self.set_values(self.desired_values());return policy
    def check(self,state,ignore_pending=False):
        reasons=[]
        if state.get('mode') not in ('closed','allow-test'):reasons.append('not-prepared-stable-mode')
        if state.get('phase')!='stable':reasons.append('recorded-phase-not-stable')
        if not ignore_pending and (STATE/'pending.json').exists():reasons.append('pending-or-uncertain-transition')
        try:
            self.original();self.assert_table_owned()
            if digest(self.table())!=state.get('policy_digest'):reasons.append('owned-policy-drift')
            if self.values()!=self.desired_values():reasons.append('owned-sysctl-drift')
        except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as exc:reasons.append(str(exc))
        return {'ready':not reasons,'reasons':reasons,'scope':'local owned policy/sysctls only, not Azure routes/NAT/path proof','time_utc':utc()}
    def emergency_close(self):
        # Never change a guest whose ownership enrollment was rejected or lost.
        try:self.original()
        except BaseException as exc:return ['ownership not verified; no emergency mutation: '+str(exc)]
        errors=[]
        try:self.apply_policy(False)
        except BaseException as exc:errors.append('closed-table: '+str(exc))
        if errors:
            # Independent fallback only on the dedicated owned appliance; report uncertainty.
            try:self.run(['sysctl','-w','net.ipv4.ip_forward=0'])
            except BaseException as exc:errors.append('forwarding-off fallback: '+str(exc))
        return errors
    def restore_original(self):
        original=self.original();self.apply_policy(False);self.set_values(original['values']);self.assert_table_owned()
        if self.table_exists():self.run(['nft','delete','table','inet',TABLE])
        if self.table_exists():raise RuntimeError('Owned table removal not verified')
def initial_state():return {'mode':'unprepared','phase':'unknown','policy_digest':None}
def write_state(mode,policy=None,phase='stable'):
    row={'mode':mode,'phase':phase,'policy_digest':policy,'changed_utc':utc()};atomic_json(STATE/'state.json',row);return row
def private_directory(path):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True,mode=0o700);path.mkdir(mode=0o700,exist_ok=False);return path
def event(path,name,**details):
    fd=os.open(Path(path)/'events.jsonl',os.O_WRONLY|os.O_CREAT|os.O_APPEND,0o600)
    with os.fdopen(fd,'a') as f:f.write(json.dumps({'event':name,'utc':utc(),**details})+'\n');f.flush();os.fsync(f.fileno())
def snapshot(backend,destination=None):
    value={'started_utc':utc(),'config':backend.cfg,'state':read_json(STATE/'state.json',initial_state()),'pending':read_json(STATE/'pending.json'),'observations':{},'errors':{}}
    for name,call in [('owned_nft_table',backend.table),('owned_sysctls',backend.values),('interface',backend.interface)]:
        try:value['observations'][name]=call()
        except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as exc:value['errors'][name]=str(exc)
    value['readiness']=backend.check(value['state']);value['completed_utc']=utc()
    if destination:atomic_json(destination,value)
    return value
@contextlib.contextmanager
def exclusive_lock():
    RUNTIME.mkdir(parents=True,exist_ok=True,mode=0o700)
    with (RUNTIME/'control.lock').open('a') as f:
        try:fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError as exc:raise RuntimeError('Another control/evidence operation holds the exclusive lock') from exc
        yield
def control(backend,action,seconds=30,confirmed=False,acknowledged=False):
    if action=='status':return snapshot(backend)
    if action not in ('boot','prepare','allow-test','close','reconcile','recover','restore-original','fail-forwarding'):raise ValueError('Unsupported action')
    if action!='boot' and not confirmed:raise RuntimeError('Explicit --confirm-guest-change required for approved action')
    if os.geteuid()!=0:raise RuntimeError('Approved guest mutation requires root')
    if action in ('allow-test','restore-original') and not acknowledged:raise RuntimeError('Use --acknowledge-reviewed-scope for the reviewed source/NAT envelope or isolated restoration')
    if action=='fail-forwarding' and not 5<=seconds<=120:raise ValueError('Failure interval must be 5..120 seconds')
    STATE.mkdir(parents=True,exist_ok=True,mode=0o700)
    with exclusive_lock():
        before=read_json(STATE/'state.json',initial_state());old=read_json(STATE/'pending.json')
        if action=='boot' and before.get('mode')=='restored' and not old:return {'outcome':'remains-restored','state':before,'completed_utc':utc()}
        if old and action not in ('close','boot','recover','reconcile'):raise RuntimeError('Pending/uncertain state requires reconciliation before reopening')
        if action in ('allow-test','restore-original','fail-forwarding'):
            check=backend.check(before)
            if not check['ready']:raise RuntimeError('Preflight failed: '+','.join(check['reasons']))
        if action=='restore-original' and before.get('mode')!='closed':raise RuntimeError('Close before isolated restoration')
        if action=='fail-forwarding' and before.get('mode')!='allow-test':raise RuntimeError('Bounded failure requires a verified open baseline')
        attempt=private_directory(STATE/'operations'/(action+'-'+uuid.uuid4().hex))
        pending={'action':action,'before':before,'phase':'pending','started_utc':utc(),'attempt_directory':str(attempt),'prior_pending':bool(old)}
        atomic_json(STATE/'pending.json',pending) # No mutation if this durable write fails.
        removal_started=False
        try:
            event(attempt,'pending-persisted',action=action);write_state(before.get('mode','unknown'),before.get('policy_digest'),'pending');snapshot(backend,attempt/'before.json')
            if action in ('prepare','boot','reconcile','recover'):after=write_state('closed',backend.prepare())
            elif action=='allow-test':after=write_state('allow-test',backend.apply_policy(True))
            elif action=='close':after=write_state('closed',backend.apply_policy(False))
            elif action=='restore-original':backend.restore_original();after=write_state('restored',phase='restored')
            else:
                write_state('closed',backend.apply_policy(False));event(attempt,'forwarding-closed',seconds=seconds,conntrack='retained; not a crash/state-loss test');time.sleep(seconds)
                closed=read_json(STATE/'state.json');check=backend.check(closed,ignore_pending=True)
                if not check['ready']:raise RuntimeError('Restoration precheck failed: '+','.join(check['reasons']))
                after=write_state('allow-test',backend.apply_policy(True));event(attempt,'prior-open-policy-restored',warning='old conntrack may remain; no seamless-flow claim')
            if action!='restore-original':
                check=backend.check(after,ignore_pending=True)
                if not check['ready']:raise RuntimeError('Post-action verification failed: '+','.join(check['reasons']))
            preserve=bool(old and action in ('boot','close'))
            if preserve:
                pending.update(phase='uncertain',reason='Prior interrupted operation requires explicit reconcile');atomic_json(STATE/'pending.json',pending);after=write_state('closed',after['policy_digest'],'uncertain')
            event(attempt,'verified-before-finalization',completed_utc=utc(),state=after)
            snapshot(backend,attempt/'after-before-finalization.json')
            response={'outcome':'reconciliation-required' if preserve else 'verified-before-current-status-check','action':action,'state':after,'completed_utc':utc(),'evidence_directory':str(attempt),'note':'Recorded intent/local checks only; query current status and live path independently'}
            if not preserve:
                # Persist non-ready intent before unlink. A failed unlink/fsync must not
                # leave the earlier stable closed record looking like a success.
                write_state(after['mode'],after.get('policy_digest'),'finalizing')
                removal_started=True;remove_record(STATE/'pending.json')
                after=write_state(after['mode'],after.get('policy_digest'),after.get('phase','stable'))
                response['state']=after
            return response
        except BaseException as exc:
            errors=[]
            try:closure=backend.emergency_close()
            except BaseException as close_error:closure=['emergency-close uncertain: '+str(close_error)]
            try:write_state('unknown' if closure else 'closed',phase='uncertain')
            except BaseException as e:errors.append('state write: '+str(e))
            pending.update(phase='uncertain',failed_utc=utc(),error_type=type(exc).__name__,error=str(exc),closure_errors=closure,recovery_errors=errors,removal_started=removal_started)
            marker=False
            try:atomic_json(STATE/'pending.json',pending);marker=True
            except BaseException as e:errors.append('pending write: '+str(e))
            try:event(attempt,'failed',pending=pending,marker_write_verified=marker)
            except BaseException as e:errors.append('event write: '+str(e))
            try:snapshot(backend,attempt/'failure.json')
            except BaseException as e:errors.append('snapshot write: '+str(e))
            with contextlib.suppress(BaseException):print(json.dumps({'outcome':'uncertain','error':str(exc),'closure_errors':closure,'recovery_errors':errors,'marker_write_verified':marker,'note':'After unlink/fsync plus failed rewrite the marker may be absent; no all-clear from missing file'}),file=sys.stderr,flush=True)
            raise

def capture_filter(backend):return f'host {backend.cfg["origin_public_ip"]} and tcp and (port 8080 or port 8081 or port 8082)'
def evidence(backend,do_capture=False,seconds=10,packets=200,acknowledged=False):
    if not 1<=seconds<=60 or not 1<=packets<=1000:raise ValueError('Capture bounds seconds1..60, packets1..1000')
    if do_capture and not acknowledged:raise RuntimeError('Use --acknowledge-sensitive-capture for bounded private payload evidence')
    if os.geteuid()!=0:raise RuntimeError('Read-only root evidence requires approved guest access')
    with exclusive_lock():
        out=private_directory(STATE/'evidence'/('capture-'+uuid.uuid4().hex));atomic_json(out/'before.json',snapshot(backend))
        records={}
        for name,args in [('route-to-D',['ip','-j','route','get',backend.cfg['origin_public_ip']]),('route-to-A',['ip','-j','route','get',backend.cfg['app_ip']]),('route-to-F',['ip','-j','route','get',backend.cfg['firewall_private_ip']]),('test-conntrack',['conntrack','-L','-p','tcp','--orig-dst',backend.cfg['origin_public_ip'],'-o','extended'])]:
            try:
                result=backend.run(args,check=False);records[name]={'exit':result.returncode,'stdout':result.stdout[:65536],'stderr':result.stderr[:8192],'retained_stdout_truncated':len(result.stdout)>65536,'retained_stderr_truncated':len(result.stderr)>8192}
            except (OSError,RuntimeError,subprocess.SubprocessError) as exc:records[name]={'error':str(exc)}
        atomic_json(out/'read-results.json',records)
        outcome={'started_utc':utc(),'capture_requested':do_capture,'filter':capture_filter(backend),'packet_limit':packets,'seconds_limit':seconds,'snaplen':256,'scope':'exact D/test ports, not filtered by expected pre-NAT source; may contain payload; guest route get is not Azure effective route'}
        capture_error=None
        try:
            if do_capture:
                iface=backend.interface();args=['tcpdump','-n','-U','-i',iface,'-s','256','-c',str(packets),'-w',str(out/'perimeter.pcap'),capture_filter(backend)]
                with (out/'tcpdump.stdout').open('x') as stdout,(out/'tcpdump.stderr').open('x') as stderr:
                    process=subprocess.Popen(args,stdout=stdout,stderr=stderr)
                    try:
                        try:outcome['exit']=process.wait(timeout=seconds)
                        except subprocess.TimeoutExpired:process.send_signal(signal.SIGINT);outcome['bounded_stop']=True;outcome['exit']=process.wait(timeout=3)
                    finally:
                        if process.poll() is None:process.kill();process.wait(timeout=3)
        except BaseException as exc:
            capture_error=exc;outcome.update(error_type=type(exc).__name__,error=str(exc))
        finally:
            if (out/'perimeter.pcap').exists():os.chmod(out/'perimeter.pcap',0o600)
            outcome['completed_utc']=utc();atomic_json(out/'capture-result.json',outcome);atomic_json(out/'after.json',snapshot(backend))
        if capture_error:raise capture_error
        return {'outcome':'NEEDS_REVIEW','evidence_directory':str(out),'completed_utc':utc(),'note':'No route, public NAT, kernel syntax or policy proof from collection alone'}
def install_interrupt_handlers():
    def interrupted(signum,_frame):raise SystemExit(128+signum)
    for signum in (signal.SIGHUP,signal.SIGINT,signal.SIGTERM):signal.signal(signum,interrupted)
def main():
    os.umask(0o077);p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    c=sub.add_parser('control');c.add_argument('action',choices=['boot','prepare','status','allow-test','close','reconcile','recover','restore-original','fail-forwarding']);c.add_argument('--seconds',type=int,default=30);c.add_argument('--confirm-guest-change',action='store_true');c.add_argument('--acknowledge-reviewed-scope',action='store_true')
    e=sub.add_parser('evidence');e.add_argument('--capture',action='store_true');e.add_argument('--seconds',type=int,default=10);e.add_argument('--packets',type=int,default=200);e.add_argument('--acknowledge-sensitive-capture',action='store_true')
    args=p.parse_args();backend=Backend(read_json(os.environ.get('FORCED_LAB_CONFIG',CONFIG)));install_interrupt_handlers()
    result=control(backend,args.action,args.seconds,args.confirm_guest_change,args.acknowledge_reviewed_scope) if args.command=='control' else evidence(backend,args.capture,args.seconds,args.packets,args.acknowledge_sensitive_capture)
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
