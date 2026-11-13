"""Offline fake-CLI tests. Never run real Azure/Terraform, network or deployment."""
import hashlib,json,os,shutil,subprocess,tempfile,unittest,zipfile
from pathlib import Path
R=Path(__file__).resolve().parents[1]
SUB='11111111-2222-3333-4444-555555555555'
RG='inspection-waf'
BASE=f'/subscriptions/{SUB}/resourceGroups/{RG}/providers/'
GATES=['deploy_lab','certificate_access_confirmed','origin_dns_verified','fixture_publish_enabled','fixture_ready','backend_access_enabled','backend_health_verified','gateway_ingress_enabled','fdid_diagnostic_ingress_enabled','diagnostic_ingress_authorized','fdid_negative_cases_verified','edge_route_enabled']
def outputs():
 d={'deployment_enabled':True,'resource_group_name':RG,'gateway_name':'regional-gateway','gateway_public_ip':'8.8.8.8','backend_name':'offline-backend','edge_fqdn':'offline-edge.z01.azurefd.net','backend_fqdn':'offline-backend.azurewebsites.net','origin_fqdn':'origin.lab.example.com','operator_cidr':'8.8.4.4/32','frontdoor_id':'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee','workspace_customer_id':'bbbbbbbb-cccc-dddd-eeee-ffffffffffff','gateway_identity_id':f'/subscriptions/{SUB}/resourceGroups/security/providers/Microsoft.ManagedIdentity/userAssignedIdentities/approved','publication_enabled':False,'gate_state':{k:k in ['deploy_lab','certificate_access_confirmed'] for k in GATES}}
 ids={'gateway_id':'Microsoft.Network/applicationGateways/regional-gateway','gateway_public_ip_id':'Microsoft.Network/publicIPAddresses/gateway-public','gateway_subnet_id':'Microsoft.Network/virtualNetworks/gateway/subnets/appgateway','gateway_nsg_id':'Microsoft.Network/networkSecurityGroups/gateway-nsg','gateway_waf_policy_id':'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies/gateway-waf-policy','edge_waf_policy_id':'Microsoft.Network/frontDoorWebApplicationFirewallPolicies/wafedgepolicy','frontdoor_profile_id':'Microsoft.Cdn/profiles/layered-frontdoor','origin_group_id':'Microsoft.Cdn/profiles/layered-frontdoor/originGroups/regional-gateway-group','origin_id':'Microsoft.Cdn/profiles/layered-frontdoor/originGroups/regional-gateway-group/origins/regional-gateway-origin','security_policy_id':'Microsoft.Cdn/profiles/layered-frontdoor/securityPolicies/owned-edge-security','workspace_id':'Microsoft.OperationalInsights/workspaces/waf-observability','backend_id':'Microsoft.Web/sites/offline-backend','edge_endpoint_id':'Microsoft.Cdn/profiles/layered-frontdoor/afdEndpoints/offline-edge','edge_route_id':'Microsoft.Cdn/profiles/layered-frontdoor/afdEndpoints/offline-edge/routes/owned-https-route'}
 d.update({k:BASE+v for k,v in ids.items()});return {k:{'value':v} for k,v in d.items()}
class Operator(unittest.TestCase):
 def setUp(self):
  self.t=tempfile.TemporaryDirectory();self.addCleanup(self.t.cleanup);self.p=Path(self.t.name);self.lab=self.p/'lab';self.lab.mkdir();shutil.copytree(R/'scripts',self.lab/'scripts');shutil.copytree(R/'origin',self.lab/'origin')
  self.bin=self.p/'bin';self.bin.mkdir();self.data=outputs();self.j=self.p/'outputs.json';self.log=self.p/'calls.jsonl';self.env=dict(os.environ,PATH=str(self.bin)+':'+os.environ['PATH'],SUBSCRIPTION_ID=SUB,MOCK_OUTPUTS=str(self.j),MOCK_LOG=str(self.log),PYTHONDONTWRITEBYTECODE='1')
  for name,src in {'terraform':'''#!/usr/bin/env python3
import os,sys
if sys.argv[1:]!=['output','-json']:raise SystemExit('Only mocked output read allowed')
print(open(os.environ['MOCK_OUTPUTS']).read())
''','az':'''#!/usr/bin/env python3
import hashlib,json,os,sys
args=sys.argv[1:]
entry={'args':args,'dynamic_install':os.environ.get('AZURE_EXTENSION_USE_DYNAMIC_INSTALL')}
if args[:2]==['webapp','deploy']:
 p=args[args.index('--src-path')+1];entry['uploaded_sha256']=hashlib.sha256(open(p,'rb').read()).hexdigest()
with open(os.environ['MOCK_LOG'],'a') as f:f.write(json.dumps(entry)+'\\n')
if os.environ.get('MOCK_AZ_FAIL')=='1':print('synthetic CLI error',file=sys.stderr);raise SystemExit(7)
print('{}')
'''}.items():
   f=self.bin/name;f.write_text(src);f.chmod(0o755)
 def call(self,script,*args,env=None):
  self.j.write_text(json.dumps(self.data));return subprocess.run(['bash',str(self.lab/'scripts'/script),*map(str,args)],capture_output=True,text=True,env=self.env| (env or {}),timeout=15)
 def context(self):
  self.j.write_text(json.dumps(self.data));return subprocess.run(['bash','-c','source "$1"; load_context','bash',str(self.lab/'scripts/common.sh')],capture_output=True,text=True,env=self.env,timeout=10)
 def calls(self):return [json.loads(x) for x in self.log.read_text().splitlines()] if self.log.exists() else []
 def package(self):
  p=self.p/'reviewed.zip'
  with zipfile.ZipFile(p,'w') as z:
   for n in ['server.js','package.json']:z.writestr(n,(R/'origin'/n).read_bytes())
  return p,hashlib.sha256(p.read_bytes()).hexdigest()
 def publish(self):self.data['publication_enabled']['value']=True;self.data['gate_state']['value']['fixture_publish_enabled']=True
 def test_valid_context(self):self.assertEqual(self.context().returncode,0)
 def test_every_required_id_missing(self):
  for k in [k for k in self.data if k.endswith('_id')]:
   with self.subTest(k=k):
    old=self.data.pop(k);self.assertNotEqual(self.context().returncode,0);self.data[k]=old
  self.assertFalse(self.calls())
 def test_every_required_id_null(self):
  for k in [k for k in self.data if k.endswith('_id')]:
   with self.subTest(k=k):
    old=self.data[k];self.data[k]={'value':None};self.assertNotEqual(self.context().returncode,0);self.data[k]=old
 def test_wrong_subscription(self):
  self.env['SUBSCRIPTION_ID']='99999999-2222-3333-4444-555555555555';self.assertNotEqual(self.context().returncode,0)
 def test_subscription_not_uuid(self):
  self.env['SUBSCRIPTION_ID']='not-approved';self.assertNotEqual(self.context().returncode,0)
 def test_wrong_scoped_id(self):
  self.data['edge_route_id']['value']+='/elsewhere';self.assertNotEqual(self.context().returncode,0)
 def test_wrong_backend_id(self):
  self.data['backend_id']['value']=BASE+'Microsoft.Web/sites/other';self.assertNotEqual(self.context().returncode,0)
 def test_wrong_identity_subscription(self):
  self.data['gateway_identity_id']['value']=self.data['gateway_identity_id']['value'].replace(SUB,'99999999-2222-3333-4444-555555555555');self.assertNotEqual(self.context().returncode,0)
 def test_invalid_ips(self):
  for v in [134744072,'192.0.2.10','10.0.0.4','224.0.0.1','100.64.0.1','::1','8.8.8.008']:
   with self.subTest(v=v):self.data['gateway_public_ip']['value']=v;self.assertNotEqual(self.context().returncode,0)
 def test_wrong_service_fqdn(self):
  self.data['backend_fqdn']['value']='wrong.example.com';self.assertNotEqual(self.context().returncode,0)
 def test_bad_gate_map(self):
  self.data['gate_state']['value']['edge_route_enabled']='false';self.assertNotEqual(self.context().returncode,0)
 def test_publication_mismatch(self):
  self.data['publication_enabled']['value']=True;self.assertNotEqual(self.context().returncode,0)
 def test_disabled(self):
  self.data['deployment_enabled']['value']=False;self.assertNotEqual(self.context().returncode,0)
 def test_conflicting_publication(self):
  self.publish();self.data['gate_state']['value']['edge_route_enabled']=True;self.assertNotEqual(self.context().returncode,0)
 def test_unapproved_diagnostic(self):
  self.data['gate_state']['value']['fdid_diagnostic_ingress_enabled']=True;self.assertNotEqual(self.context().returncode,0)
 def test_unready_edge(self):
  self.data['gate_state']['value']['edge_route_enabled']=True;self.assertNotEqual(self.context().returncode,0)
 def test_collector_scoped_private(self):
  out=self.p/'evidence';r=self.call('collect-control-plane.sh',out);self.assertEqual(r.returncode,0,r.stderr);self.assertTrue((out/'completed-utc.txt').exists());self.assertEqual(out.stat().st_mode&0o777,0o700)
  calls=self.calls();self.assertEqual(len(calls),14)
  for c in calls:self.assertEqual(c['args'][c['args'].index('--subscription')+1],SUB);self.assertEqual(c['dynamic_install'],'no')
  allargs=json.dumps(calls).lower()
  for absent in ['listkeys','publishing-credentials','appsettings','secret show','show-effective-route']:self.assertNotIn(absent,allargs)
  self.assertIn('client-side',(out/'PRIVATE-HANDLING-REQUIRED.txt').read_text())
 def test_collector_existing_refused(self):
  out=self.p/'old';out.mkdir();(out/'keep').write_text('keep');self.assertNotEqual(self.call('collect-control-plane.sh',out).returncode,0);self.assertFalse(self.calls());self.assertEqual((out/'keep').read_text(),'keep')
 def test_collector_failure_retained(self):
  out=self.p/'failed';r=self.call('collect-control-plane.sh',out,env={'MOCK_AZ_FAIL':'1'});self.assertNotEqual(r.returncode,0);self.assertIn('7',(out/'gateway.exit').read_text());self.assertTrue((out/'completed-utc.txt').exists())
 def test_config_exact_fields(self):
  p=self.p/'public.json';self.assertEqual(self.call('make-probe-config.sh',p).returncode,0);self.assertEqual(set(json.loads(p.read_text())),{'edge_fqdn','origin_fqdn','gateway_public_ip','backend_fqdn','frontdoor_id','operator_cidr'});self.assertEqual(p.stat().st_mode&0o777,0o600)
 def test_config_no_overwrite(self):
  p=self.p/'old';p.write_text('keep');self.assertNotEqual(self.call('make-probe-config.sh',p).returncode,0);self.assertEqual(p.read_text(),'keep')
 def test_publisher_requires_confirmation(self):
  p,h=self.package();self.assertNotEqual(self.call('deploy-origin.sh','no',p,h).returncode,0);self.assertFalse(self.calls())
 def test_publisher_closed_gate(self):
  p,h=self.package();self.assertNotEqual(self.call('deploy-origin.sh','--confirm-synthetic-origin-upload',p,h).returncode,0);self.assertFalse(self.calls())
 def test_publisher_wrong_hash(self):
  self.publish();p,h=self.package();self.assertNotEqual(self.call('deploy-origin.sh','--confirm-synthetic-origin-upload',p,'0'*64).returncode,0);self.assertFalse(self.calls())
 def test_publisher_exact_snapshot(self):
  self.publish();p,h=self.package();r=self.call('deploy-origin.sh','--confirm-synthetic-origin-upload',p,h);self.assertEqual(r.returncode,0,r.stderr);c=self.calls();self.assertEqual(len(c),1);self.assertEqual(c[0]['uploaded_sha256'],h);self.assertEqual(c[0]['args'][c[0]['args'].index('--subscription')+1],SUB);self.assertNotEqual(c[0]['args'][c[0]['args'].index('--src-path')+1],str(p))
 def test_publisher_extra_file_refused(self):
  self.publish();p,h=self.package()
  with zipfile.ZipFile(p,'a') as z:z.writestr('unreviewed.txt','extra')
  h=hashlib.sha256(p.read_bytes()).hexdigest();self.assertNotEqual(self.call('deploy-origin.sh','--confirm-synthetic-origin-upload',p,h).returncode,0);self.assertFalse(self.calls())
 def test_publisher_symlink_refused(self):
  self.publish();p,h=self.package();q=self.p/'link.zip';q.symlink_to(p);self.assertNotEqual(self.call('deploy-origin.sh','--confirm-synthetic-origin-upload',q,h).returncode,0);self.assertFalse(self.calls())
 def test_publisher_failed_call_not_retried(self):
  self.publish();p,h=self.package();self.assertNotEqual(self.call('deploy-origin.sh','--confirm-synthetic-origin-upload',p,h,env={'MOCK_AZ_FAIL':'1'}).returncode,0);self.assertEqual(len(self.calls()),1)
if __name__=='__main__':unittest.main()
