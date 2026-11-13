"""Pure model of the documented PE override eligibility, not Azure route proof."""
import ipaddress,unittest
E=ipaddress.ip_address('10.30.1.7');VNET=ipaddress.ip_network('10.30.0.0/16')
def eligible(prefix,policy):
 network=ipaddress.ip_network(prefix)
 return policy in ('Enabled','RouteTableEnabled') and E in network and network.prefixlen>=VNET.prefixlen
class RouteModelTests(unittest.TestCase):
 def test_host_route_enabled(self):self.assertTrue(eligible('10.30.1.7/32','Enabled'))
 def test_vnet_summary_is_eligible_not_automatically_wrong(self):self.assertTrue(eligible('10.30.0.0/16','Enabled'))
 def test_containing_subnet(self):self.assertTrue(eligible('10.30.1.0/24','RouteTableEnabled'))
 def test_broad_defaults_do_not_override(self):
  for prefix in ['0.0.0.0/0','10.0.0.0/8','10.30.0.0/15']:self.assertFalse(eligible(prefix,'Enabled'))
 def test_unrelated_specific_route(self):self.assertFalse(eligible('10.30.2.7/32','Enabled'))
 def test_nsg_only_is_not_route_override(self):self.assertFalse(eligible('10.30.1.7/32','NetworkSecurityGroupEnabled'))
 def test_disabled_policy_blocks_override_eligibility(self):self.assertFalse(eligible('10.30.1.7/32','Disabled'))
 def test_no_claim_of_generic_shorter_prefix_precedence(self):
  generic=max([(32,'InterfaceEndpoint'),(16,'UDR')]);self.assertEqual(generic[1],'InterfaceEndpoint')
