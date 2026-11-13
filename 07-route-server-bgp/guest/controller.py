#!/usr/bin/env python3
"""FUTURE approved synthetic FRR/GRE guest actions. Never run on an operator host."""
import argparse,contextlib,fcntl,hashlib,http.client,ipaddress,json,os,re,signal,subprocess,sys,tempfile,time
from datetime import datetime,timezone
from pathlib import Path
A='10.10.1.10';R='10.30.1.20';D='172.20.50.10';PREFIX='172.20.50.0/24';ASN=65010
STATE=Path('/var/lib/azure-routeserver-lab');RUNTIME=Path('/run/azure-routeserver-lab')
FRRCONF=Path('/etc/frr/frr.conf');SYSFILE=Path('/etc/sysctl.d/90-azure-routeserver-lab.conf')
def utc():return datetime.now(timezone.utc).isoformat()
def read_json(p,default=None):
    try:return json.loads(Path(p).read_text())
    except FileNotFoundError:return default

def atomic_json(p,value,mode=0o600):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);fd,tmp=tempfile.mkstemp(dir=p.parent,prefix='.'+p.name)
    try:
        with os.fdopen(fd,'w') as f:json.dump(value,f,sort_keys=True);f.write('\n');f.flush();os.fsync(f.fileno())
        os.chmod(tmp,mode);os.replace(tmp,p)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)

def event(directory,name,**extra):
    p=Path(directory);p.mkdir(parents=True,exist_ok=True,mode=0o700);value={'event':name,'utc':utc(),**extra}
    fd=os.open(p/'events.jsonl',os.O_CREAT|os.O_APPEND|os.O_WRONLY,0o600)
    with os.fdopen(fd,'a') as f:f.write(json.dumps(value,sort_keys=True)+'\n');f.flush();os.fsync(f.fileno())
    try:print(json.dumps(value),flush=True)
    except BrokenPipeError:pass

def normalize(x):
    if isinstance(x,list):return [normalize(v) for v in x if not (isinstance(v,dict) and 'metainfo' in v)]
    if isinstance(x,dict):return {k:({} if k=='counter' and isinstance(v,dict) else normalize(v)) for k,v in x.items() if k not in ('handle','index')}
    return x

def digest(x):return hashlib.sha256(json.dumps(normalize(x),sort_keys=True,separators=(',',':')).encode()).hexdigest()
def config_digest(text):return hashlib.sha256('\n'.join(x.strip() for x in text.splitlines() if x.strip() and not x.startswith('!')).encode()).hexdigest()
def validate_config(c):
    if not isinstance(c,dict):raise ValueError('Expected guest configuration object')
    role=c.get('role')
    if role not in ('nva1','nva2','remote'):raise ValueError('Unexpected guest role')
    if c.get('private_ip')!={'nva1':'10.0.2.4','nva2':'10.0.2.5','remote':R}[role]:raise ValueError('Incorrect owned underlay address')
    if (c.get('app_ip'),c.get('remote_ip'),c.get('destination_ip'))!=(A,R,D):raise ValueError('Incorrect fixed fixture addresses')
    asn=c.get('rs_asn')
    if type(asn) is not int or not 1<=asn<=4294967295 or asn==ASN:raise ValueError('Invalid or conflicting service ASN')
    peers=c.get('rs_peer_ips')
    if not isinstance(peers,list) or len(peers)!=2 or any(type(p) is not str for p in peers) or len(set(peers))!=2:raise ValueError('Expected two distinct string IPv4 peer addresses')
    for peer in peers:
        address=ipaddress.ip_address(peer)
        if address.version!=4 or str(address)!=peer or address not in ipaddress.ip_network('10.0.1.0/26'):raise ValueError('Peer is not canonical IPv4 in dedicated service subnet')
    if type(c.get('frr_version')) is not str or not re.fullmatch(r'10\.4(?:\.\d+)?',c['frr_version']):raise ValueError('Expected approved exact10.4-family FRR version')
    return c

def frr_config(c):
    peers=sorted(c['rs_peer_ips']);extra=' set as-path prepend 65010 65010\n' if c['role']=='nva2' else ''
    text=f'''frr defaults traditional
hostname {c['role']}
log stdout
service integrated-vtysh-config
ip prefix-list RS-EXACT seq 10 permit {PREFIX}
ip prefix-list RS-IN-DENY seq 10 deny 0.0.0.0/0 le 32
route-map RS-EXPORT-CLOSED deny 10
route-map RS-EXPORT-OPEN permit 10
 match ip address prefix-list RS-EXACT
{extra}route-map RS-EXPORT-OPEN deny 100
router bgp 65010
 bgp router-id {c['private_ip']}
 bgp no-rib
 bgp network import-check
 no bgp default ipv4-unicast
 no bgp graceful-restart
'''
    for p in peers:text+=f' neighbor {p} remote-as {c["rs_asn"]}\n neighbor {p} ebgp-multihop 255\n neighbor {p} update-source {c["private_ip"]}\n neighbor {p} timers 60 180\n'
    text+=f' address-family ipv4 unicast\n  network {PREFIX}\n'
    for p in peers:text+=f'  neighbor {p} activate\n  neighbor {p} prefix-list RS-IN-DENY in\n  neighbor {p} route-map RS-EXPORT-CLOSED out\n  neighbor {p} soft-reconfiguration inbound\n  neighbor {p} maximum-prefix 20 force\n  neighbor {p} maximum-prefix-out 1\n'
    return text+' exit-address-family\n!\n'

def nft_source(c,opened):
    role=c['role'];ip=c['private_ip'];remote=role=='remote'
    text='table inet rs_remote {\n' if remote else 'table inet rs_nva {\n'
    text+=' chain input { type filter hook input priority 0; policy accept;\n'
    if remote:
        for n in (1,2):
            overlay=f'10.255.{n}.1'
            text+=f'  iifname "rs-gre{n}" ip saddr {overlay} ip daddr {D} tcp dport {{ 8080, 8081 }} accept\n'
        text+='  iifname { "rs-gre1", "rs-gre2" } counter drop comment "deny-other-decapsulated-input"\n'
        for n in (1,2):
            peer=f'10.0.2.{n+3}'
            text+=f'  ip saddr {peer} ip daddr {R} ip protocol gre accept\n  ip saddr {peer} ip daddr {R} counter drop\n'
        text+=f'  iifname "lo" ip daddr {D} tcp dport {{ 8080, 8081 }} accept\n  ip daddr {D} tcp dport {{ 8080, 8081 }} counter drop\n  ip protocol gre counter drop\n }}\n'
    else:
        peers=', '.join(sorted(c['rs_peer_ips']));n=1 if role=='nva1' else 2
        text+=f'  iifname "rs-gre{n}" ip saddr {D} ip daddr 10.255.{n}.1 tcp sport {{ 8080, 8081 }} ct state established accept comment "local-tunnel-readiness-reply"\n  iifname "rs-gre{n}" counter drop comment "deny-other-decapsulated-input"\n'
        text+=f'  ip saddr {R} ip daddr {ip} ip protocol gre accept\n  ip saddr {R} ip daddr {ip} counter drop\n'
        text+=f'  ip saddr {{ {peers} }} ip daddr {ip} tcp dport 179 accept\n  ip saddr {{ {peers} }} ip daddr {ip} tcp sport 179 ct state established accept\n  tcp dport 179 counter drop\n  ip protocol gre counter drop\n }}\n'
    text+=' chain forward { type filter hook forward priority 0; policy drop;\n  ct state invalid counter drop\n'
    if not remote:
        n=1 if role=='nva1' else 2;gre=f'rs-gre{n}';overlay=f'10.255.{n}.1'
        text+=f'  ip saddr {A} ip daddr {D} tcp dport 8081 counter drop comment "deny-alternate-8081"\n'
        if opened:
            text+=f'  oifname "{gre}" ip saddr {A} ip daddr {D} tcp dport 8080 tcp flags & (syn | rst) == syn tcp option maxseg size set 1360\n'
            text+=f'  oifname "{gre}" ip saddr {A} ip daddr {D} tcp dport 8080 ct state new tcp flags & (fin | syn | rst | ack) == syn counter accept comment "allow-new-syn-8080"\n'
            text+=f'  oifname "{gre}" ip saddr {A} ip daddr {D} tcp dport 8080 ct state established counter accept\n'
            text+=f'  iifname "{gre}" ip saddr {D} ip daddr {A} tcp sport 8080 ct state established counter accept comment "allow-reverse-snat-reply"\n'
    text+='  counter drop comment "drop-other-forward"\n }\n'
    if not remote:
        text+=f' chain postrouting {{ type nat hook postrouting priority srcnat; policy accept;\n  oifname "{gre}" ip saddr {A} ip daddr {D} tcp dport 8080 counter snat ip to {overlay} comment "scoped-overlay-snat"\n }}\n'
    return text+'}\n'

class Backend:
    def __init__(self,c):self.c=validate_config(c);self.role=c['role'];self.ip=c['private_ip'];self.remote=self.role=='remote';self.table_name='rs_remote' if self.remote else 'rs_nva';self.n=1 if self.role=='nva1' else 2
    def run(self,args,check=True):
        r=subprocess.run(args,capture_output=True,text=True,timeout=15)
        if check and r.returncode:raise RuntimeError('Command failed: '+' '.join(args)+': '+r.stderr.strip())
        return r
    def interface(self):
        rows=json.loads(self.run(['ip','-j','-4','addr','show']).stdout);names=[r['ifname'] for r in rows if r['ifname']!='lo' and any(a.get('local')==self.ip for a in r.get('addr_info',[]))]
        if len(names)!=1 or not re.fullmatch(r'[A-Za-z0-9_-]+',names[0]):raise RuntimeError('Exact underlay NIC/IP missing')
        return names[0]
    def table(self):return json.loads(self.run(['nft','-j','list','table','inet',self.table_name]).stdout)
    def apply_policy(self,opened):
        exists=self.run(['nft','list','table','inet',self.table_name],False).returncode==0
        text=('delete table inet '+self.table_name+'\n' if exists else '')+nft_source(self.c,opened)
        with tempfile.NamedTemporaryFile('w',prefix='rs-owned-',suffix='.nft',delete=False) as f:f.write(text);path=f.name
        try:self.run(['nft','-c','-f',path]);self.run(['nft','-f',path])
        finally:os.unlink(path)
    def values(self):
        scopes=['all','default',self.interface()]+(['rs-gre1','rs-gre2'] if self.remote else [f'rs-gre{self.n}'])
        keys=['net.ipv4.ip_forward','net.netfilter.nf_conntrack_tcp_loose']+[f'net.ipv4.conf.{scope}.{key}' for scope in scopes for key in ('rp_filter','accept_redirects','send_redirects','accept_source_route')]
        return {k:int(self.run(['sysctl','-n',k]).stdout.strip()) for k in keys}
    def set_values(self,values,persist=True):
        keys=['net.ipv4.ip_forward']+[k for k in values if k!='net.ipv4.ip_forward']
        for k in keys:self.run(['sysctl','-w',f'{k}={values[k]}'])
        if self.values()!=values:raise RuntimeError('Owned sysctl verification failed')
        if persist:SYSFILE.write_text('# Owned RS lab values; tunnels are created before restoration.\n'+''.join(f'{k}={values[k]}\n' for k in keys))
    def setup_underlay(self):
        iface=self.interface();gateway='10.30.1.1' if self.remote else '10.0.2.1'
        # Never replace default/cloud-agent routes. Only owned exact prefixes, proto186.
        prefixes=['10.0.0.0/16'] if self.remote else ['10.10.0.0/16','10.30.0.0/16','10.0.1.0/26']
        for prefix in prefixes:self.run(['ip','route','replace',prefix,'via',gateway,'dev',iface,'proto','186'])
        for n in ((1,2) if self.remote else (self.n,)):
            name=f'rs-gre{n}';peer=f'10.0.2.{n+3}' if self.remote else R;own_overlay=f'10.255.{n}.{2 if self.remote else 1}/30'
            existing=self.run(['ip','-d','-j','link','show','dev',name],False)
            if existing.returncode==0:
                data=json.loads(existing.stdout)[0];info=data.get('linkinfo',{});detail=info.get('info_data',{})
                if info.get('info_kind')!='gre' or detail.get('local')!=self.ip or detail.get('remote')!=peer:raise RuntimeError('Owned tunnel name collides with unexpected existing interface')
            else:self.run(['ip','tunnel','add',name,'mode','gre','local',self.ip,'remote',peer,'ttl','64'])
            self.run(['ip','addr','replace',own_overlay,'dev',name]);self.run(['ip','link','set','dev',name,'mtu','1400','up'])
        if self.remote:self.run(['ip','addr','replace',D+'/32','dev','lo'])
        else:self.run(['ip','route','replace',PREFIX,'via',f'10.255.{self.n}.2','dev',f'rs-gre{self.n}','proto','186'])
    def strict_values(self,opened):
        values=self.values()
        if not (STATE/'original-sysctl.json').exists():atomic_json(STATE/'original-sysctl.json',{'node':self.role,'values':values})
        desired={k:(int(opened and not self.remote) if k=='net.ipv4.ip_forward' else 2 if k.endswith('.rp_filter') else 0) for k in values}
        self.set_values(desired)
    def frr(self,command):return self.run(['vtysh','-c',command]).stdout
    def configure(self,commands):
        args=['vtysh','-c','configure terminal','-c','router bgp 65010']
        for c in commands:args+=['-c',c]
        out=self.run(args).stdout
        if re.search(r'(?im)^%|unknown command|ambiguous command|error:',out):raise RuntimeError('FRR rejected configuration: '+out)
    def exports(self,enabled):
        self.configure(['address-family ipv4 unicast']+[f'neighbor {p} route-map RS-EXPORT-{"OPEN" if enabled else "CLOSED"} out' for p in sorted(self.c['rs_peer_ips'])])
        for p in self.c['rs_peer_ips']:self.frr(f'clear bgp ipv4 unicast {p} soft out')
        lines={line.strip() for line in self.frr('show running-config').splitlines()}
        expected='OPEN' if enabled else 'CLOSED';opposite='CLOSED' if enabled else 'OPEN'
        for p in self.c['rs_peer_ips']:
            if f'neighbor {p} route-map RS-EXPORT-{expected} out' not in lines or f'neighbor {p} route-map RS-EXPORT-{opposite} out' in lines:raise RuntimeError('Two-peer export policy change not observed locally; outcome may be partial')
    def shutdown(self,peer,disabled):
        if peer not in self.c['rs_peer_ips']:raise RuntimeError('Peer not one of actual RS instances')
        self.configure([('' if disabled else 'no ')+f'neighbor {peer} shutdown'])
    def frr_base_check(self):
        version=self.frr('show version');m=re.search(r'FRRouting\s+(\d+\.\d+(?:\.\d+)?)',version)
        if not m or m.group(1)!=self.c['frr_version']:raise RuntimeError('Installed FRR version differs from exact approved input')
        text=self.frr('show running-config');lines={x.strip() for x in text.splitlines()}
        required={'frr defaults traditional','bgp no-rib',f'network {PREFIX}','ip prefix-list RS-EXACT seq 10 permit '+PREFIX,'route-map RS-EXPORT-OPEN permit 10','route-map RS-EXPORT-OPEN deny 100','route-map RS-EXPORT-CLOSED deny 10','match ip address prefix-list RS-EXACT'}
        for p in self.c['rs_peer_ips']:required|={f'neighbor {p} remote-as {self.c["rs_asn"]}',f'neighbor {p} update-source {self.ip}',f'neighbor {p} prefix-list RS-IN-DENY in',f'neighbor {p} maximum-prefix 20 force',f'neighbor {p} maximum-prefix-out 1'}
        if 'no bgp network import-check' in lines:raise RuntimeError('Network import check disabled')
        # FRR10.4 defaults import-check on and omits that default in show running-config.
        if not required<=lines or any(('redistribute ' in x or 'default-originate' in x or 'aggregate-address ' in x or (x.startswith('network ') and x!=f'network {PREFIX}')) for x in lines):raise RuntimeError('FRR baseline configuration absent or unsafe')
        expected_prefixes={'ip prefix-list RS-EXACT seq 10 permit '+PREFIX,'ip prefix-list RS-IN-DENY seq 10 deny 0.0.0.0/0 le 32'}
        if {x for x in lines if x.startswith('ip prefix-list ')}!=expected_prefixes:raise RuntimeError('Unexpected inbound/export prefix policy')
        expected_maps={'route-map RS-EXPORT-CLOSED deny 10','route-map RS-EXPORT-OPEN permit 10','route-map RS-EXPORT-OPEN deny 100'}
        if {x for x in lines if x.startswith('route-map ')}!=expected_maps:raise RuntimeError('Unexpected export route-map')
        route_commands={x for x in lines if x.startswith(('match ','set ','call ','on-match '))}
        expected_commands={'match ip address prefix-list RS-EXACT'}|({'set as-path prepend 65010 65010'} if self.role=='nva2' else set())
        if route_commands!=expected_commands:raise RuntimeError('Unexpected route-map body')
        actual_peers={m.group(1) for x in lines if (m:=re.match(r'neighbor (\S+) remote-as ',x))}
        if actual_peers!=set(self.c['rs_peer_ips']):raise RuntimeError('Unexpected FRR neighbors')
        if self.role=='nva2' and 'set as-path prepend 65010 65010' not in lines:raise RuntimeError('Backup path prepend missing')
        return text
    def verify_withdrawn(self):
        text=self.frr_base_check();lines={line.strip() for line in text.splitlines()}
        for peer in self.c['rs_peer_ips']:
            if f'neighbor {peer} route-map RS-EXPORT-CLOSED out' not in lines or f'neighbor {peer} route-map RS-EXPORT-OPEN out' in lines:raise RuntimeError('Both local peer export policies are not confirmed closed')
            report=json.loads(self.frr(f'show bgp ipv4 unicast neighbors {peer} advertised-routes json'))
            if not isinstance(report,dict) or not isinstance(report.get('advertisedRoutes'),dict) or report['advertisedRoutes'] or report.get('totalPrefixCounter')!=0:raise RuntimeError('Local peer advertisements not confirmed empty; retain marker and inspect evidence')
        return {'local_exports_verified_empty':True,'scope':'local-FRR-only-not-Azure-withdrawal-convergence'}
    def tunnel_check(self):
        route=json.loads(self.run(['ip','-j','route','get',D]).stdout)[0]
        if route.get('dev')!=f'rs-gre{self.n}' or route.get('gateway')!=f'10.255.{self.n}.2':raise RuntimeError('Synthetic destination route is not exact intended GRE path')
        for destination,gateway in [(A,'10.0.2.1'),(R,'10.0.2.1')]+[(p,'10.0.2.1') for p in self.c['rs_peer_ips']]:
            route=json.loads(self.run(['ip','-j','route','get',destination]).stdout)[0]
            if route.get('dev')!=self.interface() or route.get('gateway')!=gateway:raise RuntimeError('Underlay/control route is recursive or unexpected')
        for port in (8080,8081):
            conn=http.client.HTTPConnection(D,port,timeout=3,source_address=(f'10.255.{self.n}.1',0))
            try:
                case='readiness-'+str(time.time_ns());conn.request('GET','/probe',headers={'X-Lab-Case-ID':case});response=conn.getresponse();row=json.loads(response.read(8193))
                if (response.status,row.get('fixture'),row.get('case_id'),row.get('server_ip'),row.get('server_port'),row.get('peer_ip'))!=(200,'azure-routeserver-origin-v1',case,D,port,f'10.255.{self.n}.1'):raise RuntimeError('Remote tunnel/listener identity not ready')
            finally:conn.close()
    def summary(self):return json.loads(self.frr('show bgp ipv4 unicast summary json'))
    def sessions_ready(self):
        summary=self.summary();peers=summary.get('ipv4Unicast',summary).get('peers',{})
        return all(peers.get(p,{}).get('state')=='Established' for p in self.c['rs_peer_ips'])
    def checks(self,state,require_sessions=False):
        reasons=[]
        try:
            if state.get('mode')!='open':reasons.append('forwarding-closed')
            if digest(self.table())!=state.get('policy_digest'):reasons.append('owned-policy-drift')
            values=self.values()
            if values.get('net.ipv4.ip_forward')!=1 or values.get('net.netfilter.nf_conntrack_tcp_loose')!=0:reasons.append('forwarding-or-strict-conntrack-drift')
            if any(v!=(2 if k.endswith('.rp_filter') else 0) for k,v in values.items() if k not in ('net.ipv4.ip_forward','net.netfilter.nf_conntrack_tcp_loose')):reasons.append('owned-hardening-drift')
            text=self.frr_base_check()
            if state.get('frr_digest') and config_digest(text)!=state['frr_digest']:reasons.append('FRR-runtime-config-drift')
            self.tunnel_check()
            if require_sessions and not self.sessions_ready():reasons.append('both-RS-sessions-not-established')
        except (OSError,ValueError,RuntimeError,subprocess.SubprocessError,http.client.HTTPException) as exc:reasons.append(str(exc))
        return {'ready':not reasons,'reasons':reasons,'utc':utc(),'scope':'guest-local-plus-owned-tunnel-listeners-not-Azure-route-or-client-proof'}

def write_state(b,mode,exports,disabled=None):
    value={'node':b.role,'mode':mode,'exports':exports,'disabled_peers':disabled or [],'policy_digest':digest(b.table()),'changed_utc':utc()}
    if not b.remote:value['frr_digest']=config_digest(b.frr('show running-config'))
    atomic_json(STATE/'state.json',value);return value

def restore_impl(b,saved,live=False):
    if saved['node']!=b.role:raise RuntimeError('Recovery belongs to another node')
    # Normal bounded restoration does not gratuitously flap unrelated BGP exports.
    # Explicit recovery after uncertain process/VM failure starts withdrawn.
    if not live:b.exports(False)
    b.setup_underlay();b.set_values(saved['sysctls']);b.apply_policy(saved['mode']=='open')
    for peer in b.c['rs_peer_ips']:b.shutdown(peer,peer in saved.get('disabled_peers',[]))
    current=write_state(b,saved['mode'],bool(live and saved.get('action')!='withdraw-for' and saved['exports']),saved.get('disabled_peers',[]))
    if saved['exports']:
        readiness=b.checks(current,False)
        if not readiness['ready']:
            b.exports(False);write_state(b,saved['mode'],False,saved.get('disabled_peers',[]))
            raise RuntimeError('Restoration keeps exports withdrawn: '+','.join(readiness['reasons']))
        if not current['exports']:b.exports(True)
    return write_state(b,saved['mode'],saved['exports'],saved.get('disabled_peers',[]))

def restore(b,saved,live=False):
    if saved['node']!=b.role:raise RuntimeError('Recovery belongs to another node')
    try:return restore_impl(b,saved,live)
    except BaseException as original:
        errors=[];withdrawn=False;closed=False
        try:b.exports(False);withdrawn=True
        except BaseException as exc:errors.append('withdraw:'+str(exc))
        try:b.apply_policy(False);closed=True
        except BaseException as exc:errors.append('close:'+str(exc))
        atomic_json(STATE/'state.json',{'node':b.role,'mode':'closed' if closed else 'uncertain','exports':False if withdrawn else None,'recovery_safety_errors':errors,'changed_utc':utc()})
        raise RuntimeError('Restoration failed; recovery record retained. Safety attempts: '+json.dumps({'withdrawn':withdrawn,'closed':closed,'errors':errors})+'; original: '+str(original)) from original

@contextlib.contextmanager
def transition(b,action,state):
    path=STATE/'transition.json';previous=read_json(path)
    if previous and previous.get('node')!=b.role:raise RuntimeError('Transition marker belongs to another node')
    record={'node':b.role,'action':action,'status':'pending','started_utc':utc(),'last_recorded_intent':state,'previous_unresolved':previous}
    atomic_json(path,record) # If marker cannot be persisted, no mutation starts.
    try:
        yield
        if previous and action!='reconcile':
            atomic_json(path,{**record,'status':'needs-reconciliation','completed_utc':utc()})
        else:path.unlink()
    except BaseException as original:
        errors=[];withdrawn=False;closed=False
        try:b.exports(False);withdrawn=True
        except BaseException as exc:errors.append('withdraw:'+str(exc))
        try:b.apply_policy(False);closed=True
        except BaseException as exc:errors.append('close:'+str(exc))
        uncertain={**record,'status':'uncertain','completed_utc':utc(),'error':str(original),'withdraw_command_succeeded':withdrawn,'close_command_succeeded':closed,'safety_errors':errors,'note':'Command success is not observed two-peer/Azure withdrawal.'}
        try:atomic_json(path,uncertain)
        except BaseException as exc:print('Unable to update transition marker; original pending marker remains unless storage failed: '+str(exc),file=sys.stderr)
        try:atomic_json(STATE/'state.json',{'node':b.role,'mode':'uncertain','exports':None,'last_recorded_intent':state,'changed_utc':utc(),'transition_pending':True})
        except BaseException as exc:print('Unable to record uncertain state; inspect transition marker and actual policy/BGP: '+str(exc),file=sys.stderr)
        raise


def control(b,action,confirmed=False,seconds=30,peer=None):
    if action=='status':
        state=read_json(STATE/'state.json',{'mode':'closed','exports':False});return {'state':state,'transition':read_json(STATE/'transition.json'),'recovery_available':(STATE/'recovery.json').exists(),'note':'State is last recorded intent, NOT observed BGP/forwarding/Azure state. Status does not acquire/check the lock.'}
    if action=='check':
        if b.remote:raise RuntimeError('Use remote-ready on the remote fixture; rs-control check is NVA-only')
        result=b.checks(read_json(STATE/'state.json',{}),True)
        for marker in ('transition.json','recovery.json'):
            if (STATE/marker).exists():result['ready']=False;result['reasons'].append('pending-'+marker)
        return result
    if action!='boot' and not confirmed:raise RuntimeError('Explicit --confirm-guest-change required after approval for this node/action')
    if os.geteuid()!=0:raise RuntimeError('Approved guest mutations require root')
    STATE.mkdir(parents=True,exist_ok=True,mode=0o700);RUNTIME.mkdir(parents=True,exist_ok=True,mode=0o700)
    with (RUNTIME/'control.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        state=read_json(STATE/'state.json',{'node':b.role,'mode':'closed','exports':False,'disabled_peers':[]})
        if action=='boot':
            b.apply_policy(False);b.setup_underlay();b.strict_values(False)
            if b.remote:return atomic_json(STATE/'state.json',{'node':b.role,'mode':'closed','exports':False,'changed_utc':utc()})
            # Dedicated image prerequisite: no preexisting user FRR configuration.
            FRRCONF.write_text(frr_config(b.c));os.chmod(FRRCONF,0o640)
            import pwd,grp
            os.chown(FRRCONF,pwd.getpwnam('frr').pw_uid,grp.getgrnam('frr').gr_gid)
            atomic_json(STATE/'state.json',{'node':b.role,'mode':'closed','exports':False,'disabled_peers':[],'changed_utc':utc()});return {'boot':'closed-export-deny-all'}
        if b.remote:raise RuntimeError('Remote role only supports boot/status; no BGP or forwarding activation')
        if action in ('prepare','advertise','restore-original') and (STATE/'recovery.json').exists():raise RuntimeError('Pending recovery record: inspect and recover before reopening or changing baseline')
        if (STATE/'transition.json').exists() and action not in ('withdraw','close','reconcile'):
            raise RuntimeError('Pending or uncertain ordinary transition; inspect then explicitly reconcile before reopening or recovery')
        if action=='advertise':
            ready=b.checks(state,True)
            if not ready['ready']:raise RuntimeError('Cannot advertise: '+','.join(ready['reasons']))
        if action=='restore-original':
            original=read_json(STATE/'original-sysctl.json')
            if not original or original.get('node')!=b.role:raise RuntimeError('No matching original sysctl baseline for this node')
        if action=='recover':
            saved=read_json(STATE/'recovery.json')
            if not saved or saved.get('node')!=b.role:raise RuntimeError('No matching pending recovery for this node')
        if action in ('prepare','advertise','withdraw','close','restore-original','recover','reconcile'):
            with transition(b,action,state):
                if action=='prepare':
                    b.exports(False);b.apply_policy(False);b.setup_underlay();b.strict_values(True);b.frr_base_check();b.apply_policy(True)
                    current=write_state(b,'open',False);ready=b.checks(current,False)
                    if not ready['ready']:b.apply_policy(False);write_state(b,'closed',False);raise RuntimeError('Prepare failed closed: '+','.join(ready['reasons']))
                    return current
                if action=='advertise':
                    b.exports(True);return write_state(b,state['mode'],True,state.get('disabled_peers',[]))
                if action=='withdraw':b.exports(False);return write_state(b,state['mode'],False,state.get('disabled_peers',[]))
                if action=='close':
                    try:b.exports(False)
                    finally:b.apply_policy(False)
                    return write_state(b,'closed',False,state.get('disabled_peers',[]))
                if action=='restore-original':
                    saved=read_json(STATE/'original-sysctl.json')
                    if not saved or saved['node']!=b.role:raise RuntimeError('Matching original sysctls unavailable')
                    b.exports(False);b.apply_policy(False);b.set_values(saved['values'],False);SYSFILE.unlink(missing_ok=True)
                    return write_state(b,'closed',False,state.get('disabled_peers',[]))
                if action=='reconcile':
                    b.exports(False);b.apply_policy(False);observation=b.verify_withdrawn()
                    result=write_state(b,'closed',False,state.get('disabled_peers',[]))
                    return {**result,**observation}
                if action=='recover':
                    saved=read_json(STATE/'recovery.json')
                    if not saved:raise RuntimeError('No pending recovery')
                    result=restore(b,saved);event(saved['attempt_directory'],'manual-recovered',node=b.role);(STATE/'recovery.json').unlink();return result
        if action in ('withdraw-for','session-down-for','fail-forwarding'):
            if not 5<=seconds<=120:raise RuntimeError('Bounded interval must be5..120 seconds')
            if action=='session-down-for' and peer not in b.c['rs_peer_ips']:raise RuntimeError('Select one exact actual RS peer IP')
            if (STATE/'recovery.json').exists():raise RuntimeError('Pending recovery record; no overlapping experiment')
            if not state.get('exports') or not b.checks(state,True)['ready']:raise RuntimeError('Experiment requires verified open/advertised state and both sessions')
            attempt=STATE/'experiments'/f'{action}-{time.time_ns()}';saved={**state,'sysctls':b.values(),'attempt_directory':str(attempt),'action':action}
            atomic_json(STATE/'recovery.json',saved)
            try:
                event(attempt,action+'-start',node=b.role,seconds=seconds,peer=peer)
                if action=='withdraw-for':b.exports(False);write_state(b,'open',False,state.get('disabled_peers',[]))
                elif action=='session-down-for':b.shutdown(peer,True);write_state(b,'open',True,[peer])
                else:b.apply_policy(False);write_state(b,'closed',True,state.get('disabled_peers',[])) # BGP deliberately remains alive/exporting.
                time.sleep(seconds)
            finally:
                interruption=sys.exc_info()[0].__name__ if sys.exc_info()[0] else None
                try:restore(b,saved,live=True);event(attempt,action+'-restored',node=b.role,interruption=interruption);(STATE/'recovery.json').unlink()
                except BaseException as exc:event(attempt,action+'-restore-failed',node=b.role,error=str(exc));raise
            return {'restored_recorded_state':True}
        raise RuntimeError('Unknown action')

def handlers():
    def interrupted(n,frame):raise SystemExit(128+n)
    for sig in (signal.SIGHUP,signal.SIGINT,signal.SIGTERM):signal.signal(sig,interrupted)
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['boot','status','check','prepare','advertise','withdraw','close','withdraw-for','session-down-for','fail-forwarding','recover','restore-original','reconcile']);p.add_argument('--confirm-guest-change',action='store_true');p.add_argument('--seconds',type=int,default=30);p.add_argument('--peer');a=p.parse_args()
    b=Backend(read_json(os.environ.get('RS_LAB_CONFIG','/etc/azure-routeserver-lab.json')));handlers();print(json.dumps(control(b,a.action,a.confirm_guest_change,a.seconds,a.peer),sort_keys=True))
if __name__=='__main__':main()
