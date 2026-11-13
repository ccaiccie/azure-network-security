#!/usr/bin/env python3
"""Offline mocks + loopback HTTP only. NEVER actual nft/sysctl/Azure mutation."""
import contextlib,copy,http.client,importlib.util,io,json,os,signal,socket,subprocess,sys,tempfile,threading,time,unittest
from pathlib import Path
from unittest.mock import patch
sys.dont_write_bytecode=True
R=Path(__file__).resolve().parents[1]
def load(name,path):
 s=importlib.util.spec_from_file_location(name,R/path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
ctl=load('controller','guest/controller.py');fixture=load('fixture','fixtures/server.py');probe=load('probe','guest/probe.py')
class FakeBackend(ctl.Backend):
 def __init__(self):
  super().__init__({'role':'nva1','private_ip':'10.0.2.4'});self.opened=False;self.calls=[];self.drift=False;self.nat=False
  self.vals={'net.ipv4.ip_forward':0,'net.netfilter.nf_conntrack_tcp_loose':1}
  self.vals.update({f'net.ipv4.conf.{scope}.{name}':(2 if name=='rp_filter' else 0) for scope in ('all','default','eth0') for name in ('rp_filter','accept_redirects','send_redirects','accept_source_route')})
 def run(self,*a,**kw):raise AssertionError('No real subprocess allowed in controller mocks')
 def interface(self):return 'eth0'
 def values(self):return dict(self.vals)
 def table(self):return {'nftables':[{'table':{'family':'inet','name':'azure_nva_lab','handle':1}},{'rule':{'expr':[{'counter':{'packets':8,'bytes':100}},{'accept' if self.opened else 'drop':None}],'comment':'DRIFT' if self.drift else 'mock-exact-policy'}}]}
 def ruleset(self):return {'nftables':[{'rule':{'expr':[{'masquerade':None}]}}]} if self.nat else self.table()
 def apply_policy(self,opened):self.calls.append(('policy',opened));self.opened=opened;self.drift=False;return ctl.digest(self.table())
 def set_values(self,values,persist=True):
  self.calls.append(('sysctls',copy.deepcopy(values)));self.vals=dict(values)
  if persist:ctl.SYSFILE.write_text('MOCK owned sysctls')
class ControlTests(unittest.TestCase):
 def setUp(self):
  self.t=tempfile.TemporaryDirectory();self.root=Path(self.t.name);self.backend=FakeBackend()
  self.patches=[patch.object(ctl,'STATE',self.root/'state'),patch.object(ctl,'RUNTIME',self.root/'run'),patch.object(ctl,'SYSFILE',self.root/'owned.conf'),patch.object(ctl.os,'geteuid',return_value=0)]
  for p in self.patches:p.start()
 def tearDown(self):
  for p in reversed(self.patches):p.stop()
  self.t.cleanup()
 def action(self,action,**kw):
  with contextlib.redirect_stdout(io.StringIO()):return ctl.control(self.backend,action,confirmed=True,**kw)
 def open(self):self.action('activate')
 def advertise(self):self.open();self.action('advertise')
 def test_explicit_confirmation_before_writes(self):
  with self.assertRaises(RuntimeError):ctl.control(self.backend,'activate')
  self.assertEqual(list(self.root.iterdir()),[]);self.assertEqual(self.backend.calls,[])
 def test_pending_recovery_blocks_baseline_changes(self):
  self.advertise();ctl.atomic_json(ctl.STATE/'failure-recovery.json',{'node':'nva1'})
  for action in ('activate','advertise','restore-original'):
   with self.assertRaises(RuntimeError):self.action(action)
 def test_leftover_recovery_allows_close_after_lock_release(self):
  self.advertise();ctl.atomic_json(ctl.STATE/'failure-recovery.json',{'node':'nva1'})
  self.action('close');self.assertFalse(self.backend.opened);self.assertTrue((ctl.STATE/'failure-recovery.json').exists())
 def test_active_experiment_lock_blocks_mutation_not_status(self):
  self.advertise();before=list(self.backend.calls)
  with (ctl.RUNTIME/'control.lock').open('a') as held:
   ctl.fcntl.flock(held,ctl.fcntl.LOCK_EX|ctl.fcntl.LOCK_NB)
   for action in ('close','withdraw','recover'):
    with self.assertRaises(BlockingIOError):self.action(action)
   self.assertTrue(self.action('status')['state']['advertised']);self.assertEqual(self.backend.calls,before)
  self.action('close');self.assertFalse(self.backend.opened)
 def test_boot_closed(self):
  self.action('boot');s=ctl.read_json(ctl.STATE/'state.json');self.assertEqual(s['mode'],'closed');self.assertFalse(s['advertised']);self.assertEqual(self.backend.vals['net.ipv4.ip_forward'],0)
 def test_activate_closed_first_and_still_withdrawn(self):
  self.open();s=ctl.read_json(ctl.STATE/'state.json');self.assertEqual([x for x in self.backend.calls if x[0]=='policy'],[('policy',False),('policy',True)]);self.assertEqual(s['mode'],'open');self.assertFalse(s['advertised']);self.assertEqual(self.backend.vals['net.netfilter.nf_conntrack_tcp_loose'],0)
 def test_advertise_requires_open_readiness(self):
  self.action('boot')
  with self.assertRaises(RuntimeError):self.action('advertise')
 def test_advertise_valid_open(self):
  self.advertise();s=ctl.read_json(ctl.STATE/'state.json');self.assertTrue(ctl.local_checks(self.backend,s)['ready'])
 def test_withdraw_does_not_reload_policy_or_sysctls(self):
  self.advertise();before=list(self.backend.calls);self.action('withdraw');self.assertEqual(before,self.backend.calls);self.assertFalse(ctl.read_json(ctl.STATE/'state.json')['advertised'])
 def test_withdraw_does_not_bless_policy_drift(self):
  self.advertise();self.backend.drift=True;self.action('withdraw')
  with self.assertRaises(RuntimeError):self.action('advertise')
 def test_close_preserves_sysctls_but_blocks_forwarding(self):
  self.advertise();before=self.backend.values();self.action('close');self.assertFalse(self.backend.opened);self.assertEqual(before,self.backend.values());self.assertFalse(ctl.read_json(ctl.STATE/'state.json')['advertised'])
 def test_policy_drift_not_ready(self):
  self.advertise();self.backend.drift=True;self.assertIn('owned-policy-drift',self.action('status')['health']['reasons'])
 def test_nat_not_ready(self):
  self.advertise();self.backend.nat=True;self.assertIn('NAT-present-in-nft-ruleset',self.action('status')['health']['reasons'])
 def test_ip_forward_not_ready(self):
  self.advertise();self.backend.vals['net.ipv4.ip_forward']=0;self.assertIn('ipv4-forwarding-not-1',self.action('status')['health']['reasons'])
 def test_loose_conntrack_not_ready(self):
  self.advertise();self.backend.vals['net.netfilter.nf_conntrack_tcp_loose']=1;self.assertIn('conntrack-pickup-not-strict',self.action('status')['health']['reasons'])
 def test_rpf_not_ready(self):
  self.advertise();self.backend.vals['net.ipv4.conf.eth0.rp_filter']=0;self.assertIn('rp-filter-not-loose-mode2',self.action('status')['health']['reasons'])
 def test_redirect_drift_not_ready(self):
  self.advertise();self.backend.vals['net.ipv4.conf.eth0.accept_redirects']=1;self.assertIn('redirect-or-source-route-hardening-drift',self.action('status')['health']['reasons'])
 def test_fail_forwarding_restores_exact_state_without_sysctl_toggle(self):
  self.advertise();prior=self.backend.values();before_count=len([x for x in self.backend.calls if x[0]=='sysctls'])
  def during(_):self.assertFalse(self.backend.opened);self.assertFalse(ctl.read_json(ctl.STATE/'state.json')['advertised']);self.assertEqual(self.backend.values(),prior)
  with patch.object(ctl.time,'sleep',side_effect=during):self.action('fail-forwarding',seconds=5)
  self.assertTrue(self.backend.opened);self.assertTrue(ctl.read_json(ctl.STATE/'state.json')['advertised']);self.assertFalse((ctl.STATE/'failure-recovery.json').exists());self.assertEqual(before_count,len([x for x in self.backend.calls if x[0]=='sysctls']))
 def test_failure_events_persist_start_and_restoration(self):
  self.advertise()
  with patch.object(ctl.time,'sleep'):self.action('fail-forwarding',seconds=5)
  logs=list((ctl.STATE/'experiments').glob('*/events.jsonl'));self.assertEqual(len(logs),1)
  events=[json.loads(x) for x in logs[0].read_text().splitlines()];self.assertEqual([x['event'] for x in events],['fail-forwarding-start','fail-forwarding-restored']);self.assertTrue(all(x['node']=='nva1' and 'utc' in x for x in events))
 def test_withdraw_for_restores_without_table_reload(self):
  self.advertise();before=list(self.backend.calls)
  with patch.object(ctl.time,'sleep'):self.action('withdraw-for',seconds=5)
  self.assertEqual(before,self.backend.calls);self.assertTrue(ctl.read_json(ctl.STATE/'state.json')['advertised'])
 def test_hangup_finally_restores(self):
  self.advertise()
  with patch.object(ctl.time,'sleep',side_effect=SystemExit(128+signal.SIGHUP)):
   with self.assertRaises(SystemExit):self.action('fail-forwarding',seconds=5)
  self.assertTrue(self.backend.opened);self.assertTrue(ctl.read_json(ctl.STATE/'state.json')['advertised']);self.assertFalse((ctl.STATE/'failure-recovery.json').exists())
 def test_interrupt_finally_restores(self):
  self.advertise()
  with patch.object(ctl.time,'sleep',side_effect=KeyboardInterrupt):
   with self.assertRaises(KeyboardInterrupt):self.action('withdraw-for',seconds=5)
  self.assertTrue(self.action('status')['health']['ready'])
 def test_three_signal_handlers(self):
  with patch.object(ctl.signal,'signal') as install:ctl.install_interrupt_handlers()
  self.assertEqual({c.args[0] for c in install.call_args_list},{signal.SIGHUP,signal.SIGINT,signal.SIGTERM})
  for call in install.call_args_list:
   with self.assertRaises(SystemExit):call.args[1](call.args[0],None)
 def test_failure_requires_verified_open(self):
  self.action('boot')
  with self.assertRaises(RuntimeError):self.action('fail-forwarding',seconds=5)
 def test_failure_duration_bounds(self):
  self.advertise()
  for seconds in (0,4,121):
   with self.assertRaises(RuntimeError):self.action('withdraw-for',seconds=seconds)
 def test_recovery_record_prevents_second_failure(self):
  self.advertise();ctl.atomic_json(ctl.STATE/'failure-recovery.json',{'node':'nva1'})
  with self.assertRaises(RuntimeError):self.action('fail-forwarding',seconds=5)
 def test_recover_after_closed_reboot_restores_recorded_owned_values(self):
  self.advertise();saved={**ctl.read_json(ctl.STATE/'state.json'),'restore_sysctls':self.backend.values()};ctl.atomic_json(ctl.STATE/'failure-recovery.json',saved)
  self.action('close');self.backend.vals['net.ipv4.ip_forward']=0;self.action('recover');self.assertTrue(self.action('status')['health']['ready']);self.assertFalse((ctl.STATE/'failure-recovery.json').exists())
 def test_wrong_node_recovery_rejected(self):
  self.advertise();saved={**ctl.read_json(ctl.STATE/'state.json'),'node':'nva2'};ctl.atomic_json(ctl.STATE/'failure-recovery.json',saved)
  with self.assertRaises(RuntimeError):self.action('recover')
 def test_restore_original_closes_and_restores_owned_values(self):
  original=self.backend.values();self.advertise();self.action('restore-original');self.assertEqual(original,self.backend.values());self.assertFalse(self.backend.opened);self.assertFalse(ctl.SYSFILE.exists())
 def test_status_no_files_written(self):
  self.action('status');self.assertEqual(list(self.root.iterdir()),[])
 def test_digest_ignores_counters_not_policy(self):
  before=self.backend.table();after=copy.deepcopy(before);after['nftables'][1]['rule']['expr'][0]['counter']['packets']=999
  self.assertEqual(ctl.digest(before),ctl.digest(after));after['nftables'][1]['rule']['comment']='changed';self.assertNotEqual(ctl.digest(before),ctl.digest(after))
 def test_health_snapshot_fresh_stale_missing_future(self):
  p=self.root/'health.json';self.assertEqual(ctl.health_snapshot(p,100)[0],503)
  ctl.atomic_json(p,{'ready':True,'time_epoch':99});self.assertEqual(ctl.health_snapshot(p,100)[0],200);self.assertEqual(ctl.health_snapshot(p,106)[0],503);self.assertEqual(ctl.health_snapshot(p,98)[0],503)
 def test_health_snapshot_false(self):
  p=self.root/'health.json';ctl.atomic_json(p,{'ready':False,'time_epoch':99});self.assertEqual(ctl.health_snapshot(p,100)[0],503)
 def test_nft_closed_has_no_forward_accept(self):
  text=ctl.nft_source('10.0.2.4',False).split('chain forward',1)[1];self.assertNotIn(' accept ',text);self.assertIn('deny-alternate-8081',text);self.assertIn('policy drop',text)
 def test_nft_open_exact_syn_and_established(self):
  text=ctl.nft_source('10.0.2.4',True);self.assertIn('ct state new tcp flags & (fin | syn | rst | ack) == syn',text);self.assertIn('allow-established-reply',text);self.assertNotIn('masquerade',text)
 def test_real_set_values_sequence_mocked_commands(self):
  desired=self.backend.values();desired['net.ipv4.ip_forward']=1;calls=[]
  def fake_run(args,check=True):
   calls.append(args);k,v=args[-1].split('=',1);self.backend.vals[k]=int(v);return None
  with patch.object(self.backend,'run',side_effect=fake_run):ctl.Backend.set_values(self.backend,desired)
  self.assertEqual(calls[0],['sysctl','-w','net.ipv4.ip_forward=1']);self.assertEqual(len(calls),len(desired))
class FixtureProbeTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.server=fixture.make_server('127.0.0.1',0);cls.port=cls.server.server_address[1];cls.server.test_port=cls.port;cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True);cls.thread.start()
 @classmethod
 def tearDownClass(cls):cls.server.shutdown();cls.server.server_close();cls.thread.join()
 def setUp(self):self.t=tempfile.TemporaryDirectory();self.out=Path(self.t.name)/'case';self.out.mkdir()
 def tearDown(self):self.t.cleanup()
 def request(self,path,extra=None):
  c=http.client.HTTPConnection('127.0.0.1',self.port,timeout=3);c.request('GET',path,headers={'X-Lab-Case-ID':'local-case',**(extra or {})});r=c.getresponse();status=r.status;body=r.read();c.close();return status,body
 def test_fixture_probe_identity(self):
  status,body=self.request('/probe');row=json.loads(body);self.assertEqual(status,200);self.assertEqual(row['fixture'],'azure-nva-origin-v1');self.assertEqual(row['case_id'],'local-case');self.assertEqual(row['peer_ip'],'127.0.0.1')
 def test_fixture_health(self):self.assertEqual(self.request('/health')[0],200)
 def test_fixture_rejects_unknown_query_path(self):
  for path in ['/','/probe?q=x','/../etc/passwd']:self.assertEqual(self.request(path)[0],404)
 def test_fixture_bounds(self):
  self.assertEqual(self.request('/'+'x'*300)[0],414);self.assertEqual(self.request('/probe',{'X-Extra':'x'*9000})[0],431)
 def test_fixture_bad_case(self):self.assertEqual(self.request('/probe',{'X-Lab-Case-ID':'bad case'})[0],400)
 def test_stream_bounds(self):
  for path in ['/stream?seconds=0','/stream?seconds=181','/stream?seconds=5&other=1']:self.assertEqual(self.request(path)[0],400)
 def test_direct_short_probe_records_identity_and_tuple(self):
  with patch.object(probe,'A','127.0.0.1'),patch.object(probe,'B','127.0.0.1'):
   r=probe.perform('127.0.0.1',self.port,'local-case',False,5,self.out,source='127.0.0.1')
  self.assertEqual(r['fixture_identity'],'MATCH');self.assertTrue(r['tcp_connect_completed']);self.assertGreater(r['attempted_local'][1],0);self.assertIn('completed_utc',r)
 def test_finite_stream_explicit_completion_no_reconnect(self):
  with patch.object(probe,'A','127.0.0.1'),patch.object(probe,'B','127.0.0.1'):
   r=probe.perform('127.0.0.1',self.port,'local-stream',True,5,self.out,source='127.0.0.1')
  self.assertTrue(r['stream_complete'],r);self.assertGreaterEqual(r['frames_received'],5);self.assertGreaterEqual(r['elapsed_seconds'],4)
 def test_timeout_retains_preconnect_tuple_and_no_case_sent(self):
  class TimeoutSocket:
   def settimeout(self,*a):pass
   def bind(self,value):self.bound=(value[0],45678)
   def getsockname(self):return self.bound
   def connect(self,target):
    saved=json.loads((self_outer.out/'connection.json').read_text());self_outer.assertEqual(saved['attempted_local'],['10.10.1.10',45678]);self_outer.assertFalse(saved['tcp_connect_completed']);raise TimeoutError('MOCK SYN dropped')
   def close(self):pass
  self_outer=self
  with patch.object(probe.socket,'socket',return_value=TimeoutSocket()):r=probe.perform('10.20.1.20',8081,'negative-case',False,5,self.out,source='10.10.1.10')
  self.assertEqual(r['attempted_destination'],['10.20.1.20',8081]);self.assertEqual(r['request_write_status'],'not-started');self.assertEqual(r['error_type'],'TimeoutError');self.assertIn('started_utc',r);self.assertIn('completed_utc',r);self.assertFalse(r['tcp_connect_completed'])
 def test_nonclobber_existing_out(self):
  (self.out/'keep').write_text('prior')
  with self.assertRaises(FileExistsError):probe.new_out(self.out,'other')
  self.assertEqual((self.out/'keep').read_text(),'prior')
 def test_nonclobber_symlink(self):
  link=Path(self.t.name)/'link';link.symlink_to(self.out,target_is_directory=True)
  with self.assertRaises(FileExistsError):probe.new_out(link,'other')
 def test_wrong_role_cli_stops_before_network(self):
  cfg=Path(self.t.name)/'config.json';cfg.write_text(json.dumps({'role':'backend','private_ip':'10.20.1.20','backend_ip':'10.20.1.20'}))
  r=subprocess.run(['python3',str(R/'guest/probe.py'),'positive'],env={**os.environ,'NVA_LAB_CONFIG':str(cfg)},capture_output=True);self.assertNotEqual(r.returncode,0)
if __name__=='__main__':unittest.main(verbosity=2)
