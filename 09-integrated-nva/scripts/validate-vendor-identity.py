#!/usr/bin/env python3
"""Compare projected nonsecret Azure identity fields. NOT license/policy/path proof."""
import json,sys
from pathlib import Path

def verify(outputs,nva,app):
    v={k:row['value'] for k,row in outputs.items()};p=v['vendor_profile'];errors=[]
    def eq(actual,want,label,casefold=False):
        if not isinstance(actual,str) or (actual.lower() if casefold else actual)!=(want.lower() if casefold else want):errors.append(label)
    eq(nva.get('id'),p['nva_resource_id'],'NVA resource ID',True)
    eq(nva.get('type'),'Microsoft.Network/networkVirtualAppliances','NVA resource type',True)
    eq(nva.get('hub_id'),v['hub_id'],'NVA actual linked hub',True)
    eq(nva.get('location'),v['location'],'NVA region',True)
    eq(nva.get('provisioning_state'),'Succeeded','NVA provisioning state')
    eq(nva.get('vendor'),p['nva_vendor'],'NVA SKU vendor')
    eq(nva.get('marketplace_version'),p['marketplace_version'],'NVA Marketplace version')
    eq(nva.get('scale_unit'),p['scale_unit'],'NVA scale unit')
    eq(app.get('id'),p['managed_application_id'],'managed application ID',True)
    eq(app.get('type'),'Microsoft.Solutions/applications','managed application type',True)
    eq(app.get('managed_resource_group_id'),p['managed_resource_group_id'],'managed resource group',True)
    eq(app.get('provisioning_state'),'Succeeded','managed application provisioning state')
    eq(app.get('publisher'),p['marketplace_publisher'],'Marketplace publisher')
    eq(app.get('product'),p['marketplace_offer'],'Marketplace offer')
    eq(app.get('plan_name'),p['marketplace_plan'],'Marketplace plan')
    return {'identity_comparison':'MISMATCH' if errors else 'MATCH','mismatches':errors,
            'vendor_compatibility_license_health_policy_snat_routes':'NOT_VERIFIED',
            'note':'Projected metadata match only. Exact supported profile, complete E pool, installed vendor revision/logging and routes require independent current evidence.'}

def main():
    if len(sys.argv)!=4:raise SystemExit('Usage: validate-vendor-identity.py TF_OUTPUTS PROJECTED_NVA PROJECTED_APP')
    result=verify(*(json.loads(Path(p).read_text()) for p in sys.argv[1:]));print(json.dumps(result,indent=2))
    raise SystemExit(0 if result['identity_comparison']=='MATCH' else 4)
if __name__=='__main__':main()
