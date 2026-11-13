#!/usr/bin/env python3
"""Disposable, stateless Azure GWLB bridge teaching controller.

Only approved guest execution may change the network. No guest L3 forwarding,
NAT, conntrack, global sysctls, installs, Azure calls or unrelated nft changes.
The public/private address union is capture-required, not a translation claim.
"""
import argparse
import contextlib
import fcntl
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from socketserver import TCPServer

BRIDGE = 'gwlb-br0'
EXTERNAL = 'gwlb-ext'
INTERNAL = 'gwlb-int'
PORTS = (EXTERNAL, INTERNAL)
DEVICES = (BRIDGE,) + PORTS
TABLE = 'azure_gwlb_lab'
STATE = Path('/var/lib/azure-gwlb-lab')
RUNTIME = Path('/run/azure-gwlb-lab')
CONFIG = '/etc/azure-gwlb-lab.json'
TOPOLOGY = {'nva1': '10.0.1.4', 'nva2': '10.0.1.5'}
FIELDS = {'role', 'private_ip', 'gwlb_frontend_ip', 'client_public_ip',
          'consumer_public_ip', 'backend_ip', 'underlay_mtu', 'inner_mtu'}


def utc():
    return datetime.now(timezone.utc).isoformat()


def read_json(path, default=None):
    try:
        return json.loads(Path(path).read_text())
    except FileNotFoundError:
        return default


def atomic_json(path, value, mode=0o600):
    """Fsync both file and directory so pending markers precede mutations."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, sort_keys=True)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, mode)
        os.replace(temp, path)
        sync_directory(path.parent)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def remove_record(path):
    path.unlink(missing_ok=True)
    sync_directory(path.parent)


def normalize(value):
    if isinstance(value, list):
        return [normalize(x) for x in value if not (isinstance(x, dict) and 'metainfo' in x)]
    if isinstance(value, dict):
        return {k: ({} if k == 'counter' and isinstance(v, dict) else normalize(v))
                for k, v in value.items() if k not in ('handle', 'index')}
    return value


def digest(value):
    return hashlib.sha256(json.dumps(normalize(value), sort_keys=True,
                                     separators=(',', ':')).encode()).hexdigest()


def validate_config(cfg):
    if not isinstance(cfg, dict) or set(cfg) != FIELDS:
        raise ValueError('Config must contain exactly: ' + ', '.join(sorted(FIELDS)))
    if cfg['role'] not in TOPOLOGY or cfg['private_ip'] != TOPOLOGY[cfg['role']]:
        raise ValueError('Role/private_ip must match nva1=10.0.1.4 or nva2=10.0.1.5')
    if cfg['gwlb_frontend_ip'] != '10.0.2.10' or cfg['backend_ip'] != '10.20.1.20':
        raise ValueError('Fixed teaching topology requires F=10.0.2.10, B=10.20.1.20')
    for key in ('client_public_ip', 'consumer_public_ip'):
        address = ipaddress.ip_address(cfg[key])
        if (not isinstance(address, ipaddress.IPv4Address) or not address.is_global
                or address.is_multicast or address.is_reserved
                or address in ipaddress.IPv4Network('192.0.0.0/24')
                or address in ipaddress.IPv4Network('192.88.99.0/24')
                or str(address) != cfg[key]):
            raise ValueError(key + ' must be an actual global unicast IPv4 address, not CIDR/example/private')
    if cfg['client_public_ip'] == cfg['consumer_public_ip']:
        raise ValueError('External client and consumer public IP must differ')
    if (type(cfg['underlay_mtu']) is not int or cfg['underlay_mtu'] != 1550
            or type(cfg['inner_mtu']) is not int or cfg['inner_mtu'] != 1500):
        raise ValueError('This bounded fixture requires underlay_mtu=1550 and inner_mtu=1500')
    return dict(cfg)


def link_is_up(row):
    return ('UP' in row.get('flags', []) and 'NO-CARRIER' not in row.get('flags', [])
            and row.get('operstate', 'UNKNOWN') not in ('DOWN', 'LOWERLAYERDOWN', 'DORMANT', 'NOTPRESENT'))


def owner(cfg, kind='table'):
    return 'azure-gwlb-lab:v1:' + cfg['role'] + ':' + kind


def nft_source(cfg, opened=False):
    """Default ACCEPT on unrelated bridges; every owned transit path ends DROP."""
    c, p, b = cfg['client_public_ip'], cfg['consumer_public_ip'], cfg['backend_ip']
    forward = f'''    iifname "{EXTERNAL}" oifname "{INTERNAL}" ether type ip ip saddr {c} ip daddr {{ {p}, {b} }} ip protocol tcp tcp dport 8081 counter drop comment "deny-alternate-8081-forward"
    iifname "{INTERNAL}" oifname "{EXTERNAL}" ether type ip ip saddr {{ {p}, {b} }} ip daddr {c} ip protocol tcp tcp sport 8081 counter drop comment "deny-alternate-8081-reverse"
'''
    if opened:
        forward += f'''    iifname "{EXTERNAL}" oifname "{INTERNAL}" ether type ip ip saddr {c} ip daddr {{ {p}, {b} }} ip protocol tcp tcp dport 8080 counter accept comment "allow-primary-8080-forward-capture-required"
    iifname "{INTERNAL}" oifname "{EXTERNAL}" ether type ip ip saddr {{ {p}, {b} }} ip daddr {c} ip protocol tcp tcp sport 8080 counter accept comment "allow-primary-8080-reverse-capture-required"
'''
    else:
        forward += f'''    iifname "{EXTERNAL}" oifname "{INTERNAL}" ether type ip ip saddr {c} ip daddr {{ {p}, {b} }} ip protocol tcp tcp dport 8080 counter drop comment "deny-primary-8080-forward"
    iifname "{INTERNAL}" oifname "{EXTERNAL}" ether type ip ip saddr {{ {p}, {b} }} ip daddr {c} ip protocol tcp tcp sport 8080 counter drop comment "deny-primary-8080-reverse"
'''
    forward += '    counter drop comment "deny-owned-default-including-ipv6-and-non-ip"\n'
    return f'''table bridge {TABLE} {{
  comment "{owner(cfg)}"
  chain owned_transit {{
{forward}  }}
  chain forward {{
    type filter hook forward priority -200; policy accept;
    iifname {{ "{EXTERNAL}", "{INTERNAL}" }} jump owned_transit
    oifname {{ "{EXTERNAL}", "{INTERNAL}" }} counter drop comment "deny-unexpected-owned-egress"
  }}
  chain input {{
    type filter hook input priority -200; policy accept;
    iifname {{ "{EXTERNAL}", "{INTERNAL}" }} counter drop comment "deny-owned-host-input"
  }}
  chain output {{
    type filter hook output priority -200; policy accept;
    oifname {{ "{EXTERNAL}", "{INTERNAL}" }} counter drop comment "deny-owned-host-output"
  }}
}}
'''


class Backend:
    def __init__(self, cfg):
        self.cfg = validate_config(cfg)
        self.ip = cfg['private_ip']

    def run(self, args, check=True):
        result = subprocess.run(args, capture_output=True, text=True, timeout=10)
        if check and result.returncode:
            raise RuntimeError('Command failed: ' + ' '.join(args) + ': ' + result.stderr.strip())
        return result

    def links(self):
        return json.loads(self.run(['ip', '-j', '-d', 'link', 'show']).stdout)

    def addresses(self):
        return json.loads(self.run(['ip', '-j', 'address', 'show']).stdout)

    def interface(self):
        names = [row['ifname'] for row in self.addresses()
                 if any(a.get('local') == self.ip for a in row.get('addr_info', []))]
        if (len(names) != 1 or names[0] in DEVICES
                or not re.fullmatch(r'[A-Za-z0-9_.-]{1,15}', names[0])):
            raise RuntimeError('Expected exact private IPv4 on one ordinary underlay interface')
        return names[0]

    def table_exists(self):
        data = json.loads(self.run(['nft', '-j', 'list', 'tables']).stdout)
        return any(x.get('table', {}).get('family') == 'bridge'
                   and x['table'].get('name') == TABLE for x in data['nftables'])

    def table(self):
        return json.loads(self.run(['nft', '-j', 'list', 'table', 'bridge', TABLE]).stdout)

    def assert_table_owned(self):
        if self.table_exists():
            rows = [x['table'] for x in self.table()['nftables'] if 'table' in x]
            if len(rows) != 1 or rows[0].get('comment') != owner(self.cfg):
                raise RuntimeError('Refusing table collision or missing ownership comment')

    def original(self):
        record = read_json(STATE / 'original.json')
        if not record or record.get('config_digest') != digest(self.cfg):
            raise RuntimeError('No original record for this exact config; do not overwrite another ownership record')
        return record

    def enroll(self):
        """Inspect all collisions before saving the original and before any mutation."""
        if (STATE / 'original.json').exists():
            self.original()
            self.assert_owned()
            return
        links = self.links()
        if any(x['ifname'] in DEVICES for x in links) or self.table_exists():
            raise RuntimeError('Owned name/table already exists without original record; refusing adoption')
        iface = self.interface()
        row = next(x for x in links if x['ifname'] == iface)
        if row.get('master') is not None:
            raise RuntimeError('Underlay must not be a member of any bridge or master')
        atomic_json(STATE / 'original.json', {
            'config_digest': digest(self.cfg), 'node': self.cfg['role'],
            'underlay': iface, 'underlay_ifindex': row['ifindex'],
            'underlay_mac': row.get('address'), 'underlay_mtu': row['mtu'],
            'created_utc': utc(), 'devices_absent': list(DEVICES), 'table_absent': True})

    def assert_owned(self):
        record = self.original()
        links = self.links()
        mapping = {x['ifname']: x for x in links}
        iface = self.interface()
        underlay = mapping[iface]
        if (iface != record['underlay'] or underlay.get('address') != record['underlay_mac']
                or underlay.get('master') is not None):
            raise RuntimeError('Original underlay identity/master changed; manual reconciliation required')
        for name in DEVICES:
            if name in mapping and mapping[name].get('ifalias') != owner(self.cfg, name):
                raise RuntimeError('Device ownership ambiguous: ' + name)
        bridge_index = mapping.get(BRIDGE, {}).get('ifindex')
        for row in links:
            if (row.get('master') in (BRIDGE, bridge_index) and row.get('master') is not None
                    and row['ifname'] not in PORTS):
                raise RuntimeError('Unexpected bridge member: ' + row['ifname'])
        self.assert_table_owned()
        return mapping

    def apply_policy(self, opened):
        self.assert_table_owned()
        present = self.table_exists()
        source = (f'delete table bridge {TABLE}\n' if present else '') + nft_source(self.cfg, opened)
        with tempfile.NamedTemporaryFile('w', prefix='gwlb-', suffix='.nft', dir=RUNTIME, delete=False) as stream:
            stream.write(source)
            path = stream.name
        try:
            self.run(['nft', '-c', '-f', path])
            self.run(['nft', '-f', path])  # One nft transaction; never flush another table.
        finally:
            os.unlink(path)
        return digest(self.table())

    def build_closed(self):
        self.enroll()
        mapping = self.assert_owned()
        self.apply_policy(False)  # Closed filtering exists BEFORE ports are created/up.
        # Reset only owned devices, refusing unexpected bridge membership above.
        for name in (EXTERNAL, INTERNAL, BRIDGE):
            if name in mapping:
                self.run(['ip', 'link', 'delete', 'dev', name])
        iface = self.original()['underlay']
        self.run(['ip', 'link', 'set', 'dev', iface, 'mtu', str(self.cfg['underlay_mtu'])])
        self.run(['ip', 'link', 'add', 'name', BRIDGE, 'alias', owner(self.cfg, BRIDGE),
                  'type', 'bridge', 'stp_state', '0', 'mcast_snooping', '0'])
        for name, vni, port in ((EXTERNAL, 801, 10801), (INTERNAL, 800, 10800)):
            self.run(['ip', 'link', 'add', 'name', name, 'alias', owner(self.cfg, name),
                      'type', 'vxlan', 'id', str(vni),
                      'local', self.ip, 'remote', self.cfg['gwlb_frontend_ip'],
                      'dev', iface, 'dstport', str(port), 'nolearning'])
            self.run(['ip', 'link', 'set', 'dev', name, 'master', BRIDGE])
        for name in DEVICES:
            self.run(['ip', 'link', 'set', 'dev', name, 'addrgenmode', 'none'])
            self.run(['ip', 'link', 'set', 'dev', name, 'mtu', str(self.cfg['inner_mtu'])])
            self.run(['ip', 'link', 'set', 'dev', name, 'up'])
        return digest(self.table())

    def topology_errors(self):
        mapping = self.assert_owned()
        record = self.original()
        errors = []
        iface = record['underlay']
        underlay = mapping[iface]
        if underlay.get('mtu') != self.cfg['underlay_mtu'] or not link_is_up(underlay):
            errors.append('underlay-link-or-mtu')
        for name in DEVICES:
            row = mapping.get(name)
            if not row:
                errors.append('missing:' + name)
                continue
            if row.get('mtu') != self.cfg['inner_mtu'] or not link_is_up(row):
                errors.append('link-or-mtu:' + name)
            info = row.get('linkinfo', {})
            if info.get('info_kind') != ('bridge' if name == BRIDGE else 'vxlan'):
                errors.append('wrong-kind:' + name)
            if name in PORTS:
                if row.get('master') not in (BRIDGE, mapping.get(BRIDGE, {}).get('ifindex')):
                    errors.append('wrong-master:' + name)
                data = info.get('info_data', {})
                vni, port = (801, 10801) if name == EXTERNAL else (800, 10800)
                if (data.get('id') != vni or data.get('port') != port
                        or data.get('local') != self.ip or data.get('remote') != self.cfg['gwlb_frontend_ip']
                        or data.get('learning') not in (False, 0)
                        or data.get('link') not in (iface, underlay.get('ifindex'))):
                    errors.append('vxlan-settings:' + name)
            elif row.get('master') is not None:
                errors.append('owned-bridge-has-master')
        for row in self.addresses():
            if row['ifname'] in DEVICES and row.get('addr_info'):
                errors.append('owned-device-addressed:' + row['ifname'])
        return errors

    def emergency_close(self):
        """Do not touch an ambiguous foreign device/table. Report every failed step."""
        errors = []
        try:
            self.original()
        except (OSError, ValueError, RuntimeError) as exc:
            return ['No matching enrollment; no network changes attempted: ' + str(exc)]
        try:
            self.apply_policy(False)
        except BaseException as exc:
            errors.append('closed-policy: ' + str(exc))
        try:
            mapping = {x['ifname']: x for x in self.links()}
            for name in PORTS:
                if name in mapping and mapping[name].get('ifalias') == owner(self.cfg, name):
                    try:
                        self.run(['ip', 'link', 'set', 'dev', name, 'down'])
                    except BaseException as exc:
                        errors.append(name + '-down: ' + str(exc))
        except BaseException as exc:
            errors.append('enumerate-owned-ports: ' + str(exc))
        return errors

    def restore_original(self):
        mapping = self.assert_owned()
        original = self.original()
        if mapping[original['underlay']]['mtu'] not in (original['underlay_mtu'], self.cfg['underlay_mtu']):
            raise RuntimeError('Underlay MTU changed outside this controller; refusing to overwrite it')
        self.apply_policy(False)
        for name in (EXTERNAL, INTERNAL, BRIDGE):
            if name in mapping:
                self.run(['ip', 'link', 'delete', 'dev', name])
        self.run(['ip', 'link', 'set', 'dev', original['underlay'], 'mtu', str(original['underlay_mtu'])])
        self.assert_table_owned()
        if self.table_exists():
            self.run(['nft', 'delete', 'table', 'bridge', TABLE])
        links = self.links()
        if (any(x['ifname'] in DEVICES for x in links) or self.table_exists()
                or next(x for x in links if x['ifname'] == original['underlay'])['mtu'] != original['underlay_mtu']):
            raise RuntimeError('Restoration verification failed')


def initial_state(backend):
    return {'node': backend.cfg['role'], 'config_digest': digest(backend.cfg),
            'mode': 'closed', 'advertised': False, 'phase': 'unprepared', 'policy_digest': None}


def write_state(backend, mode, advertised, policy_digest=None, phase='stable'):
    value = {**initial_state(backend), 'mode': mode, 'advertised': advertised,
             'policy_digest': policy_digest, 'policy_source_digest': digest(nft_source(backend.cfg, mode == 'allow-primary')),
             'phase': phase, 'changed_utc': utc()}
    atomic_json(STATE / 'state.json', value, 0o644)
    return value


def local_checks(backend, state, require_advertised=True, ignore_pending=False):
    reasons = []
    if not ignore_pending and (STATE / 'pending.json').exists():
        reasons.append('reconciliation-or-transition-pending')
    if state.get('phase') != 'stable' or state.get('mode') not in ('closed', 'allow-primary'):
        reasons.append('not-stable-prepared-state')
    if require_advertised and not state.get('advertised'):
        reasons.append('health-withdrawn')
    if state.get('config_digest') != digest(backend.cfg):
        reasons.append('config-changed')
    if state.get('policy_source_digest') != digest(nft_source(backend.cfg, state.get('mode') == 'allow-primary')):
        reasons.append('policy-source-drift')
    try:
        reasons.extend(backend.topology_errors())
        if digest(backend.table()) != state.get('policy_digest'):
            reasons.append('owned-policy-drift')
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as exc:
        reasons.append('local-check-error:' + str(exc))
    return {'ready': not reasons, 'reasons': reasons, 'node': backend.cfg['role'],
            'time_utc': utc(), 'time_epoch': time.time(), 'state_digest': digest(state),
            'scope': 'local-structure-only-not-end-to-end-or-Azure-health'}


def private_directory(path):
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path, 0o700)
    return path


def event(directory, name, **details):
    record = {'event': name, 'utc': utc(), **details}
    fd = os.open(directory / 'events.jsonl', os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(fd, 'a') as stream:
        stream.write(json.dumps(record, sort_keys=True) + '\n')
        stream.flush()
        os.fsync(stream.fileno())
    return record


def snapshot(backend, destination=None):
    value = {'time_utc': utc(), 'time_epoch': time.time(), 'node': backend.cfg['role'],
             'config': backend.cfg, 'state': read_json(STATE / 'state.json', initial_state(backend)),
             'pending': read_json(STATE / 'pending.json'), 'observations': {}, 'errors': {}}
    for name, call in [('links', backend.links), ('addresses', backend.addresses), ('owned_nft_table', backend.table)]:
        try:
            value['observations'][name] = call()
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
            value['errors'][name] = str(exc)
    value['health'] = local_checks(backend, value['state'])
    value['completed_utc'] = utc()
    path = destination or private_directory(STATE / 'snapshots') / ('status-' + uuid.uuid4().hex + '.json')
    atomic_json(path, value)
    return {**value, 'snapshot_path': str(path)}


@contextlib.contextmanager
def exclusive_lock():
    RUNTIME.mkdir(parents=True, exist_ok=True, mode=0o755)
    os.chmod(RUNTIME, 0o755)
    with (RUNTIME / 'control.lock').open('a') as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RuntimeError('Another control/evidence operation holds the exclusive lock') from exc
        yield


def persist_withdrawn(backend, before, phase='pending'):
    state = {**before, 'advertised': False, 'phase': phase, 'changed_utc': utc()}
    atomic_json(STATE / 'state.json', state, 0o644)
    atomic_json(RUNTIME / 'health.json', {'ready': False, 'reasons': ['health-withdrawn', phase],
                'time_utc': utc(), 'time_epoch': time.time()}, 0o644)
    return state


def control(backend, action, seconds=30, confirmed=False, acknowledge_capture_required=False):
    if action == 'status':
        return snapshot(backend)
    if action != 'boot' and not confirmed:
        raise RuntimeError('Explicit --confirm-guest-change required after approval for this node/action')
    if os.geteuid() != 0:
        raise RuntimeError('Approved guest changes require root')
    if action == 'allow-primary' and not acknowledge_capture_required:
        raise RuntimeError('Use --acknowledge-capture-required: the public/private tuple union is not measured translation evidence')
    if action == 'withdraw-health' and not 5 <= seconds <= 120:
        raise ValueError('Single-node health withdrawal requires --seconds 5..120')
    STATE.mkdir(parents=True, exist_ok=True, mode=0o755)
    os.chmod(STATE, 0o755)
    with exclusive_lock():
        before = read_json(STATE / 'state.json', initial_state(backend))
        old_pending = read_json(STATE / 'pending.json')
        if action == 'boot' and before.get('mode') == 'restored' and not old_pending:
            return {'action': action, 'outcome': 'remains-restored-withdrawn', 'completed_utc': utc(), 'state': before}
        if old_pending and action not in ('recover', 'reconcile', 'boot', 'close', 'withdraw'):
            raise RuntimeError('Unresolved pending/uncertain transition; run reconcile before reopening or advertising')
        if action in ('allow-primary', 'advertise', 'withdraw-health'):
            checks = local_checks(backend, before, require_advertised=action == 'withdraw-health')
            if not checks['ready']:
                raise RuntimeError('Preflight failed: ' + ', '.join(checks['reasons']))
        attempt = private_directory(STATE / 'operations' / (action + '-' + uuid.uuid4().hex))
        pending = {'action': action, 'node': backend.cfg['role'], 'before': before,
                   'started_utc': utc(), 'phase': 'pending', 'attempt_directory': str(attempt),
                   'prior_pending': ({key: old_pending.get(key) for key in
                                      ('action', 'phase', 'attempt_directory', 'started_utc', 'failed_utc', 'error')}
                                     if old_pending else None)}
        atomic_json(STATE / 'pending.json', pending)
        pending_removal_started = False
        try:
            event(attempt, 'pending-persisted', action=action)
            persist_withdrawn(backend, before)
            snapshot(backend, attempt / 'before.json')
            if action in ('prepare', 'boot', 'recover', 'reconcile'):
                policy = backend.build_closed()
                after = write_state(backend, 'closed', False, policy)
            elif action == 'allow-primary':
                backend.assert_owned()
                policy = backend.apply_policy(True)
                after = write_state(backend, 'allow-primary', False, policy)
            elif action == 'close':
                backend.original()
                policy = backend.apply_policy(False)
                after = write_state(backend, 'closed', False, policy)
            elif action in ('advertise', 'withdraw'):
                after = write_state(backend, before['mode'], action == 'advertise', before.get('policy_digest'))
            elif action == 'withdraw-health':
                # A health-only experiment leaves nft table, counters and VXLAN links unchanged.
                event(attempt, 'health-withdrawn', seconds=seconds, scope='one-node-only')
                time.sleep(seconds)
                checks = local_checks(backend, before, require_advertised=False, ignore_pending=True)
                if not checks['ready']:
                    raise RuntimeError('Health restoration precheck failed: ' + ', '.join(checks['reasons']))
                after = write_state(backend, before['mode'], before['advertised'], before['policy_digest'])
            elif action == 'restore-original':
                backend.restore_original()
                after = write_state(backend, 'restored', False, phase='restored')
            else:
                raise ValueError('Unsupported action: ' + action)
            if action not in ('restore-original', 'withdraw'):
                checked = local_checks(backend, after, require_advertised=False, ignore_pending=True)
                if not checked['ready']:
                    raise RuntimeError('Post-transition verification failed: ' + ', '.join(checked['reasons']))
            # Boot closes after a crash, but never silently reconciles the interrupted operation.
            preserve = bool(old_pending and action in ('boot', 'close', 'withdraw'))
            if preserve:
                after = persist_withdrawn(backend, after, phase='uncertain')
                pending.update(phase='uncertain', safe_action_completed_utc=utc(),
                               reason='Prior interruption still requires explicit reconcile')
                atomic_json(STATE / 'pending.json', pending)
            event(attempt, 'completed', completed_utc=utc(), state=after,
                  outcome='safe-but-reconciliation-required' if preserve else 'verified-awaiting-finalization',
                  stage='before-pending-removal')
            result = snapshot(backend, attempt / 'after.json')
            response = {'action': action, 'outcome': 'reconciliation-required' if preserve else 'verified',
                        'completed_utc': utc(), 'state': after, 'evidence_directory': str(attempt),
                        'health': result['health'],
                        'health_observation': 'Before finalization; verify current status and /health separately'}
            if not preserve:
                # LAST fallible success step: no event, snapshot or new observation
                # follows removal. Unlink succeeding but directory fsync failing is
                # explicitly uncertain and triggers best-effort safe recovery below.
                pending_removal_started = True
                remove_record(STATE / 'pending.json')
            return response
        except BaseException as exc:
            # Once pending is durable, every later failure enters this path. Even
            # disk-full/fsync errors must not prevent the independent close attempt.
            # SIGKILL/power loss cannot run this handler: boot leaves reconciliation pending.
            recovery_errors = []
            try:
                failures = backend.emergency_close()
            except BaseException as close_error:
                failures = ['emergency-close-uncertain: ' + str(close_error)]
            try:
                persist_withdrawn(backend, {**before, 'mode': 'unknown' if failures else 'closed'}, phase='uncertain')
            except BaseException as state_error:
                recovery_errors.append('withdrawn-state-persistence: ' + str(state_error))
            pending.update(phase='uncertain', failed_utc=utc(), error_type=type(exc).__name__,
                           error=str(exc), emergency_close_errors=failures,
                           recovery_record_errors=recovery_errors,
                           pending_removal_started=pending_removal_started)
            marker_write_verified = False
            try:
                atomic_json(STATE / 'pending.json', pending)
                marker_write_verified = True
            except BaseException as pending_error:
                # If unlink already succeeded, the prior marker may be absent.
                # Arbitrary storage failure cannot guarantee record survival.
                recovery_errors.append('uncertain-marker-update: ' + str(pending_error))
            failure = {'completed_utc': utc(), 'error_type': type(exc).__name__,
                       'error': str(exc), 'emergency_close_errors': failures,
                       'recovery_record_errors': recovery_errors, 'reconciliation_required': True,
                       'pending_removal_started': pending_removal_started,
                       'uncertain_marker_write_verified': marker_write_verified}
            try:
                event(attempt, 'failed', **failure)
            except BaseException as event_error:
                recovery_errors.append('failure-event-persistence: ' + str(event_error))
            try:
                snapshot(backend, attempt / 'failure.json')
            except BaseException as snapshot_error:
                recovery_errors.append('failure-snapshot: ' + str(snapshot_error))
            # Record/report secondary storage failures without replacing the original
            # failure or falsely claiming recovery. After an unlink/fsync failure,
            # even a persistent reconciliation marker is only best-effort.
            if recovery_errors:
                try:
                    atomic_json(STATE / 'pending.json', pending)
                    failure['uncertain_marker_write_verified'] = True
                except BaseException:
                    pass
                with contextlib.suppress(BaseException):
                    print(json.dumps({'outcome': 'uncertain', **failure}), file=sys.stderr, flush=True)
            raise



def monitor(backend):
    RUNTIME.mkdir(parents=True, exist_ok=True, mode=0o755)
    while True:
        try:
            state = read_json(STATE / 'state.json', initial_state(backend))
            value = local_checks(backend, state)
        except (OSError, ValueError, TypeError) as exc:
            value = {'ready': False, 'reasons': ['monitor-error:' + str(exc)],
                     'time_epoch': time.time(), 'time_utc': utc()}
        atomic_json(RUNTIME / 'health.json', value, 0o644)
        time.sleep(2)


def health_snapshot(now=None):
    now = time.time() if now is None else now
    try:
        value = read_json(RUNTIME / 'health.json')
        state = read_json(STATE / 'state.json')
        if ((STATE / 'pending.json').exists() or not state or not state.get('advertised')
                or state.get('phase') != 'stable'):
            return 503, {'ready': False, 'reason': 'withdrawn-or-pending'}
        if not value or not 0 <= now - value['time_epoch'] <= 6:
            return 503, {'ready': False, 'reason': 'missing-or-stale-structural-monitor'}
        if value.get('state_digest') != digest(state):
            return 503, {'ready': False, 'reason': 'monitor-has-not-verified-current-state'}
        return (200 if value.get('ready') else 503), value
    except (OSError, ValueError, KeyError, TypeError):
        return 503, {'ready': False, 'reason': 'invalid-monitor-snapshot'}


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/health':
            self.send_error(404)
            return
        status, value = health_snapshot()
        body = (json.dumps(value) + '\n').encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


class HealthServer(ThreadingHTTPServer):
    daemon_threads = True

    def server_bind(self):
        # HTTPServer.server_bind calls getfqdn. This isolated listener needs no DNS.
        TCPServer.server_bind(self)
        self.server_name = 'azure-gwlb-lab'
        self.server_port = self.server_address[1]

    def get_request(self):
        sock, address = super().get_request()
        sock.settimeout(3)
        return sock, address


def capture_filters(backend):
    cfg = backend.cfg
    iface = backend.interface()
    # The remote source is deliberately NOT assumed to equal the GWLB frontend.
    outer = f'host {backend.ip} and udp and (port 10800 or port 10801)'
    # Unexpected inner tuples may be excluded here: decode the outer PCAP before
    # treating empty inner captures as absence of traffic. Never invent translation.
    inner = (f'ip and host {cfg["client_public_ip"]} and (host {cfg["consumer_public_ip"]} '
             f'or host {cfg["backend_ip"]}) and tcp and (port 8080 or port 8081)')
    return [(iface, outer), (EXTERNAL, inner), (INTERNAL, inner)]


def capture(backend, directory, seconds, packets):
    processes = []
    outcomes = []
    started = time.monotonic()
    try:
        for iface, expression in capture_filters(backend):
            path = directory / (iface + '.pcap')
            # Exclusive precreate prevents clobbering. tcpdump runs root without privilege switching.
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            os.close(fd)
            log = (directory / (iface + '.stderr')).open('x')
            args = ['tcpdump', '-n', '-p', '-U', '-s', '256', '-Z', 'root', '-i', iface,
                    '-c', str(packets), '-w', str(path), expression]
            try:
                process = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=log)
            except BaseException:
                log.close()
                raise
            processes.append((iface, process, log, args))
        remaining = max(0, seconds - (time.monotonic() - started))
        time.sleep(remaining)
    finally:
        for iface, process, log, args in processes:
            code = None
            cleanup_error = None
            timed_out = process.poll() is None
            try:
                if timed_out:
                    # The process may exit between poll and signal.
                    with contextlib.suppress(ProcessLookupError):
                        process.send_signal(signal.SIGINT)
                try:
                    code = process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    with contextlib.suppress(ProcessLookupError):
                        process.kill()
                    code = process.wait(timeout=3)
            except (OSError, subprocess.SubprocessError) as exc:
                cleanup_error = str(exc)
            finally:
                log.close()
            outcomes.append({'interface': iface, 'returncode': code, 'time_bound_reached': timed_out,
                             'cleanup_error': cleanup_error, 'command': args, 'completed_utc': utc()})
        atomic_json(directory / 'capture-outcomes.json', outcomes)
    if any(item['cleanup_error'] or item['returncode'] not in (0, -signal.SIGINT) for item in outcomes):
        raise RuntimeError('A bounded tcpdump failed; inspect private capture-outcomes and stderr')
    return outcomes


def evidence(backend, do_capture=False, seconds=10, packets=200, acknowledged=False):
    if do_capture and not acknowledged:
        raise ValueError('--acknowledge-sensitive-capture is required for local packet data collection')
    if not 1 <= seconds <= 60 or not 1 <= packets <= 1000:
        raise ValueError('Evidence bounds: seconds 1..60; packets 1..1000 per exact interface')
    directory = private_directory(STATE / 'evidence' / (utc().replace(':', '') + '-' + uuid.uuid4().hex))
    with exclusive_lock():
        event(directory, 'evidence-start', capture=do_capture)
        try:
            before = snapshot(backend, directory / 'before.json')
            if do_capture:
                checks = local_checks(backend, before['state'], require_advertised=False)
                if not checks['ready']:
                    raise RuntimeError('Capture requires prepared, verified owned topology: ' + ', '.join(checks['reasons']))
                capture(backend, directory, seconds, packets)
            snapshot(backend, directory / 'after.json')
            event(directory, 'evidence-completed', completed_utc=utc(), outcome='collected-not-a-datapath-pass')
        except BaseException as exc:
            event(directory, 'evidence-failed', completed_utc=utc(), error_type=type(exc).__name__, error=str(exc))
            raise
    return {'evidence_directory': str(directory), 'completed_utc': utc(),
            'outcome': 'collected-not-a-datapath-pass', 'capture': do_capture,
            'privacy': 'Local-only private files; no auto-upload. PCAP snaplen=256 may contain payload.'}


def install_interrupt_handlers():
    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)
    for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, interrupted)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', default=CONFIG)
    sub = parser.add_subparsers(dest='command', required=True)
    ctl = sub.add_parser('control')
    ctl.add_argument('action', choices=['boot', 'prepare', 'status', 'close', 'allow-primary',
                                      'advertise', 'withdraw', 'withdraw-health', 'recover', 'reconcile', 'restore-original'])
    ctl.add_argument('--seconds', type=int, default=30)
    ctl.add_argument('--confirm-guest-change', action='store_true')
    ctl.add_argument('--acknowledge-capture-required', action='store_true')
    sub.add_parser('monitor')
    sub.add_parser('health')
    ev = sub.add_parser('evidence')
    ev.add_argument('--capture', action='store_true')
    ev.add_argument('--seconds', type=int, default=10)
    ev.add_argument('--packets', type=int, default=200)
    ev.add_argument('--acknowledge-sensitive-capture', action='store_true')
    args = parser.parse_args()
    backend = Backend(read_json(args.config))
    install_interrupt_handlers()
    if args.command == 'health':
        HealthServer((backend.ip, 8008), HealthHandler).serve_forever()
        return
    if args.command == 'monitor':
        monitor(backend)
        return
    if args.command == 'evidence':
        result = evidence(backend, args.capture, args.seconds, args.packets, args.acknowledge_sensitive_capture)
    else:
        result = control(backend, args.action, args.seconds, args.confirm_guest_change, args.acknowledge_capture_required)
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({'outcome': 'error', 'error': str(error), 'completed_utc': utc()}), file=sys.stderr)
        sys.exit(1)
