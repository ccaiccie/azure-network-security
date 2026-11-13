"""Pure explanatory longest-prefix model; not Azure effective-route verification."""
import ipaddress,unittest

def select(destination,routes):
 matches=[(ipaddress.ip_network(prefix).prefixlen,next_hop) for prefix,next_hop in routes if ipaddress.ip_address(destination) in ipaddress.ip_network(prefix)]
 return max(matches)[1] if matches else None
APP=[('0.0.0.0/0','F'),('10.0.0.0/16','hub-peering'),('10.40.0.0/16','management-peering')]
FW=[('0.0.0.0/0','E'),('10.20.0.0/16','app-peering'),('10.30.0.0/16','perimeter-peering'),('10.40.0.0/16','management-peering')]
EDGE=[('0.0.0.0/0','Internet'),('10.20.0.0/16','F'),('10.0.0.0/16','hub-peering'),('10.40.0.0/16','management-peering')]
class RouteModelTests(unittest.TestCase):
 def test_app_public_via_firewall(self):self.assertEqual(select('20.42.0.10',APP),'F')
 def test_firewall_public_via_perimeter(self):self.assertEqual(select('20.42.0.10',FW),'E')
 def test_perimeter_public_not_back_to_firewall(self):self.assertEqual(select('20.42.0.10',EDGE),'Internet')
 def test_preserved_return_to_app_via_firewall(self):self.assertEqual(select('10.20.1.10',EDGE),'F')
 def test_private_snat_return_via_hub(self):self.assertEqual(select('10.0.1.7',EDGE),'hub-peering')
 def test_firewall_app_return_not_default(self):self.assertEqual(select('10.20.1.10',FW),'app-peering')
 def test_management_return_does_not_use_defaults(self):
  for routes in (APP,FW,EDGE):self.assertEqual(select('10.40.2.5',routes),'management-peering')
 def test_missing_return_would_leak_toward_default(self):self.assertEqual(select('10.20.1.10',[r for r in EDGE if r[0]!='10.20.0.0/16']),'Internet')
