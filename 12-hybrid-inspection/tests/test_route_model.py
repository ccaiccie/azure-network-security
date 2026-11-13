"""Tiny documented route-selection model only; not Azure route or packet testing."""
import ipaddress,unittest
# Prefix length first, then documented equal-prefix source priority for these examples.
PRIORITY={'User':3,'Gateway':2,'System':1}
def select(destination,routes,propagation=True):
 candidates=[r for r in routes if ipaddress.ip_address(destination) in ipaddress.ip_network(r[0]) and (propagation or r[1]!='Gateway')]
 return max(candidates,key=lambda r:(ipaddress.ip_network(r[0]).prefixlen,PRIORITY[r[1]])) if candidates else None
class RouteModelTests(unittest.TestCase):
 def test_gateway_equal_spoke_prefix_uses_udr(self):
  self.assertEqual(select('10.20.1.20',[('10.20.0.0/16','User','Firewall'),('10.20.0.0/16','System','Peering')])[2],'Firewall')
 def test_branch_learned_spoke_beats_default_discard(self):
  self.assertEqual(select('10.20.1.20',[('0.0.0.0/0','User','None'),('10.0.0.0/8','System','None'),('10.20.0.0/16','Gateway','VPN')])[2],'VPN')
 def test_missing_branch_spoke_route_is_blocked_not_working_tunnel(self):
  self.assertEqual(select('10.20.1.20',[('0.0.0.0/0','User','None'),('10.0.0.0/8','System','None')])[2],'None')
 def test_spoke_propagation_off_removes_more_specific_bypass(self):
  self.assertEqual(select('172.16.10.10',[('172.16.0.0/16','User','Firewall'),('172.16.10.0/24','Gateway','VPN'),('0.0.0.0/0','User','None')],False)[2],'Firewall')
 def test_more_specific_bypass_if_propagation_reenabled(self):
  self.assertEqual(select('172.16.10.10',[('172.16.0.0/16','User','Firewall'),('172.16.10.0/24','Gateway','VPN')],True)[2],'VPN')
 def test_firewall_branch_route_is_gateway_not_self(self):
  self.assertEqual(select('172.16.10.10',[('172.16.0.0/12','System','None'),('172.16.0.0/16','Gateway','VPN')])[2],'VPN')
 def test_management_peering_beats_workload_default(self):
  self.assertEqual(select('10.40.2.7',[('0.0.0.0/0','User','None'),('172.16.0.0/16','User','Firewall'),('10.40.0.0/16','System','Peering')])[2],'Peering')
 def test_branch_bastion_local_not_remote_gateway(self):
  self.assertEqual(select('172.16.250.7',[('0.0.0.0/0','User','None'),('172.16.0.0/16','System','Local'),('10.20.0.0/16','Gateway','VPN')])[2],'Local')
if __name__=='__main__':unittest.main()
