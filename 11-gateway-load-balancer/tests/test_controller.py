"""Entirely mocked OS/network commands. Never run ip/nft/sysctl/tcpdump here.
These tests establish controller logic only, not Linux nft syntax or Azure behavior.
"""
import copy
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('gwlb_controller', Path(__file__).resolve().parents[1] / 'guest/controller.py')
c = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(c)
# Public addresses are synthetic in-memory fixtures only. No packets are sent.
CFG = {'role': 'nva1', 'private_ip': '10.0.1.4', 'gwlb_frontend_ip': '10.0.2.10',
       'client_public_ip': '8.8.8.8', 'consumer_public_ip': '1.1.1.1', 'backend_ip': '10.20.1.20',
       'underlay_mtu': 1550, 'inner_mtu': 1500}


class FakeBackend(c.Backend):
    def __init__(self, cfg=None):
        super().__init__(cfg or CFG)
        self.link_data = {'eth0': {'ifname': 'eth0', 'ifindex': 2, 'address': '00:11:22:33:44:55', 'mtu': 1500, 'flags': ['UP']},
                          'other-br': {'ifname': 'other-br', 'ifindex': 3, 'mtu': 1500, 'flags': ['UP'], 'linkinfo': {'info_kind': 'bridge'}}}
        self.addr_data = {'eth0': [{'family': 'inet', 'local': self.ip}], 'other-br': []}
        self.nft = None
        self.unrelated = {'name': 'keep-this-table', 'rules': ['unrelated']}
        self.commands = []
        self.mutations = []
        self.fail = None
        self.on_mutation = None
        self.fail_consumed = False

    def run(self, args, check=True):
        args = list(args)
        self.commands.append(args)
        mutable = (args[:3] in (['ip', 'link', 'add'], ['ip', 'link', 'set'], ['ip', 'link', 'delete'])
                   or args[:2] == ['nft', '-f'] or args[:2] == ['nft', 'delete'])
        if mutable:
            self.mutations.append(args)
            if self.on_mutation:
                self.on_mutation(args)
            if self.fail and self.fail(args) and not self.fail_consumed:
                self.fail_consumed = True
                raise RuntimeError('Injected command failure')
        data = ''
        if args == ['ip', '-j', '-d', 'link', 'show']:
            data = json.dumps(list(self.link_data.values()))
        elif args == ['ip', '-j', 'address', 'show']:
            data = json.dumps([{'ifname': name, 'addr_info': addresses} for name, addresses in self.addr_data.items()])
        elif args == ['nft', '-j', 'list', 'tables']:
            data = json.dumps({'nftables': [] if self.nft is None else [{'table': {'family': 'bridge', 'name': c.TABLE}}]})
        elif args == ['nft', '-j', 'list', 'table', 'bridge', c.TABLE]:
            if self.nft is None:
                raise RuntimeError('No such mock table')
            data = json.dumps(self.nft)
        elif args[:2] == ['nft', '-c']:
            assert args[2] == '-f'
            assert Path(args[3]).exists()
        elif args[:2] == ['nft', '-f']:
            source = Path(args[2]).read_text()
            self.nft = {'nftables': [{'table': {'name': c.TABLE, 'family': 'bridge', 'comment': c.owner(self.cfg)}},
                                     {'mock_program': '\n'.join(line for line in source.splitlines() if not line.startswith('delete table ')), 'counter': {'packets': 0, 'bytes': 0}}]}
        elif args == ['nft', 'delete', 'table', 'bridge', c.TABLE]:
            self.nft = None
        elif args[:3] == ['ip', 'link', 'add']:
            name = args[args.index('name') + 1]
            assert name not in self.link_data
            kind = args[args.index('type') + 1]
            row = {'ifname': name, 'ifindex': max(x['ifindex'] for x in self.link_data.values()) + 1,
                   'mtu': 1500, 'flags': [], 'ifalias': args[args.index('alias') + 1], 'linkinfo': {'info_kind': kind}}
            if kind == 'vxlan':
                row['linkinfo']['info_data'] = {'id': int(args[args.index('id') + 1]),
                    'local': args[args.index('local') + 1], 'remote': args[args.index('remote') + 1],
                    'port': int(args[args.index('dstport') + 1]), 'link': args[args.index('dev') + 1], 'learning': False}
            self.link_data[name] = row
            self.addr_data[name] = []
        elif args[:3] == ['ip', 'link', 'delete']:
            name = args[4]
            del self.link_data[name]
            del self.addr_data[name]
        elif args[:3] == ['ip', 'link', 'set']:
            name = args[4]
            row = self.link_data[name]
            if args[5] == 'mtu':
                row['mtu'] = int(args[6])
            elif args[5] == 'master':
                row['master'] = args[6]
            elif args[5] == 'addrgenmode':
                row['addrgenmode'] = args[6]
            elif args[5] == 'up':
                row['flags'] = ['UP']
            elif args[5] == 'down':
                row['flags'] = []
            else:
                raise AssertionError('Unmodeled set command: ' + repr(args))
        else:
            raise AssertionError('Unexpected mock command: ' + repr(args))
        return subprocess.CompletedProcess(args, 0, data, '')


class ControllerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        self.patches = [patch.object(c, 'STATE', root / 'state'), patch.object(c, 'RUNTIME', root / 'run'),
                        patch.object(c.os, 'geteuid', return_value=0),
                        patch.object(c.subprocess, 'run', side_effect=AssertionError('Real subprocess forbidden')),
                        patch.object(c.subprocess, 'Popen', side_effect=AssertionError('Real capture forbidden'))]
        for item in self.patches:
            item.start()
        c.STATE.mkdir()
        c.RUNTIME.mkdir()
        self.b = FakeBackend()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.temp.cleanup()

    def ctl(self, action, **kwargs):
        return c.control(self.b, action, confirmed=True, **kwargs)

    def prepared(self, advertise=False, opened=False):
        self.ctl('prepare')
        if opened:
            self.ctl('allow-primary', acknowledge_capture_required=True)
        if advertise:
            self.ctl('advertise')

    def state(self):
        return c.read_json(c.STATE / 'state.json')

    def test_config_rejects_unknown_missing_nonpublic_ipv6_and_topology(self):
        invalid = [{key: x} for key in ('client_public_ip', 'consumer_public_ip')
                   for x in ('192.0.2.1', '10.1.2.3', '127.0.0.1', '224.1.1.1', '100.64.0.1',
                             '::1', '8.8.8.8/32', '192.0.0.9', '192.0.0.10', '192.88.99.1', '240.0.0.1')]
        invalid += [{'consumer_public_ip': CFG['client_public_ip']}, {'private_ip': '10.0.1.5'}, {'underlay_mtu': 1500}, {'backend_ip': '10.20.1.21'}, {'extra': 1}]
        for change in invalid:
            with self.subTest(change=change), self.assertRaises(ValueError):
                c.validate_config({**CFG, **change})
        cfg = dict(CFG); del cfg['consumer_public_ip']
        with self.assertRaises(ValueError):
            c.validate_config(cfg)
        self.assertEqual(c.validate_config({**CFG, 'role': 'nva2', 'private_ip': '10.0.1.5'})['role'], 'nva2')

    def test_stateless_bridge_policy_is_scoped_and_closed_by_default(self):
        closed = c.nft_source(CFG)
        opened = c.nft_source(CFG, True)
        self.assertIn('table bridge azure_gwlb_lab', closed)
        self.assertNotIn('counter accept', closed)
        self.assertEqual(opened.count('counter accept'), 2)
        for forbidden in ('ct state', 'masquerade', 'snat ', 'dnat ', 'table inet', 'flush ruleset'):
            self.assertNotIn(forbidden, opened)
        self.assertIn('deny-primary-8080-forward', closed)
        self.assertIn('deny-primary-8080-reverse', closed)
        self.assertNotIn('deny-primary-8080-forward', opened)
        self.assertIn('deny-alternate-8081-forward', opened)
        self.assertIn('deny-alternate-8081-reverse', opened)
        self.assertIn('deny-owned-default-including-ipv6-and-non-ip', closed)
        self.assertIn('iifname "gwlb-ext" oifname "gwlb-int" ether type ip ip saddr 8.8.8.8 ip daddr { 1.1.1.1, 10.20.1.20 }', opened)
        self.assertIn('iifname "gwlb-int" oifname "gwlb-ext" ether type ip ip saddr { 1.1.1.1, 10.20.1.20 } ip daddr 8.8.8.8', opened)
        self.assertEqual(closed.count('policy accept;'), 3)
        self.assertNotIn('policy drop;', closed)  # Unrelated bridge traffic is untouched.

    def test_prepare_persists_pending_before_mutation_closed_withdrawn(self):
        def check(_args):
            self.assertTrue((c.STATE / 'pending.json').exists())
            self.assertFalse(self.state()['advertised'])
        self.b.on_mutation = check
        result = self.ctl('prepare')
        self.assertEqual(result['outcome'], 'verified')
        self.assertEqual(self.state()['mode'], 'closed')
        self.assertFalse(self.state()['advertised'])
        self.assertFalse((c.STATE / 'pending.json').exists())
        self.assertEqual(self.b.topology_errors(), [])
        self.assertEqual(self.b.link_data['eth0']['mtu'], 1550)
        self.assertNotIn('master', self.b.link_data['eth0'])
        self.assertEqual(self.b.unrelated, {'name': 'keep-this-table', 'rules': ['unrelated']})
        self.assertNotIn('sysctl', ' '.join(' '.join(x) for x in self.b.commands))
        self.assertTrue(all('ifalias' in self.b.link_data[x] for x in c.DEVICES))
        first_up = next(i for i, cmd in enumerate(self.b.mutations) if cmd[-1] == 'up')
        nft_load = next(i for i, cmd in enumerate(self.b.mutations) if cmd[:2] == ['nft', '-f'])
        self.assertLess(nft_load, first_up)

    def test_closed_can_advertise_health_without_opening(self):
        self.prepared(advertise=True)
        check = c.local_checks(self.b, self.state())
        self.assertTrue(check['ready'], check)
        self.assertEqual(self.state()['mode'], 'closed')
        c.atomic_json(c.RUNTIME / 'health.json', check, 0o644)
        self.assertEqual(c.health_snapshot()[0], 200)

    def test_explicit_confirmation_and_tuple_ack_required(self):
        with self.assertRaisesRegex(RuntimeError, 'confirm-guest-change'):
            c.control(self.b, 'prepare')
        self.prepared()
        with self.assertRaisesRegex(RuntimeError, 'acknowledge-capture-required'):
            self.ctl('allow-primary')
        self.ctl('allow-primary', acknowledge_capture_required=True)
        self.assertFalse(self.state()['advertised'])
        self.assertEqual(self.state()['mode'], 'allow-primary')
        self.ctl('advertise')
        self.assertTrue(self.state()['advertised'])
        self.ctl('close')
        self.assertEqual(self.state()['mode'], 'closed')
        self.assertFalse(self.state()['advertised'])

    def test_reboot_never_restores_open_or_advertised(self):
        self.prepared(advertise=True, opened=True)
        self.ctl('boot')
        self.assertEqual(self.state()['mode'], 'closed')
        self.assertFalse(self.state()['advertised'])
        self.assertNotIn('counter accept', json.dumps(self.b.nft))

    def test_crash_marker_survives_boot_and_requires_reconciliation(self):
        self.prepared(advertise=True, opened=True)
        c.atomic_json(c.STATE / 'pending.json', {'phase': 'pending', 'action': 'interrupted'})
        result = self.ctl('boot')
        self.assertEqual(result['outcome'], 'reconciliation-required')
        self.assertEqual(self.state()['mode'], 'closed')
        self.assertFalse(self.state()['advertised'])
        with self.assertRaisesRegex(RuntimeError, 'Unresolved'):
            self.ctl('advertise')
        self.ctl('reconcile')
        self.assertFalse((c.STATE / 'pending.json').exists())
        self.assertEqual(self.state()['mode'], 'closed')
        self.assertFalse(self.state()['advertised'])

    def test_partial_prepare_failure_keeps_uncertainty_and_closes(self):
        self.b.fail = lambda args: args[:3] == ['ip', 'link', 'add'] and c.INTERNAL in args
        with self.assertRaisesRegex(RuntimeError, 'Injected'):
            self.ctl('prepare')
        pending = c.read_json(c.STATE / 'pending.json')
        self.assertEqual(pending['phase'], 'uncertain')
        self.assertFalse(self.state()['advertised'])
        self.assertNotIn('counter accept', json.dumps(self.b.nft))
        self.assertNotIn('UP', self.b.link_data[c.EXTERNAL]['flags'])
        self.assertTrue((Path(pending['attempt_directory']) / 'failure.json').exists())
        with self.assertRaisesRegex(RuntimeError, 'Unresolved'):
            self.ctl('allow-primary', acknowledge_capture_required=True)
        self.ctl('recover')
        self.assertEqual(self.b.topology_errors(), [])
        self.assertEqual(self.state()['mode'], 'closed')

    def test_failed_open_recloses_with_pending_before_any_mutation(self):
        self.prepared()
        self.b.fail = lambda args: args[:2] == ['nft', '-f']
        with self.assertRaises(RuntimeError):
            self.ctl('allow-primary', acknowledge_capture_required=True)
        self.assertEqual(self.state()['phase'], 'uncertain')
        self.assertNotIn('counter accept', json.dumps(self.b.nft))

    def test_unowned_collision_is_never_adopted_or_mutated(self):
        self.b.link_data[c.BRIDGE] = {'ifname': c.BRIDGE, 'ifindex': 10, 'mtu': 1500, 'flags': []}
        before = copy.deepcopy(self.b.link_data)
        with self.assertRaisesRegex(RuntimeError, 'refusing adoption'):
            self.ctl('prepare')
        self.assertEqual(before, self.b.link_data)
        self.assertEqual(self.b.mutations, [])
        self.assertIsNone(self.b.nft)

    def test_table_collision_not_replaced(self):
        self.b.nft = {'nftables': [{'table': {'name': c.TABLE, 'family': 'bridge', 'comment': 'foreign'}}]}
        before = copy.deepcopy(self.b.nft)
        with self.assertRaises(RuntimeError):
            self.ctl('prepare')
        self.assertEqual(before, self.b.nft)
        self.assertEqual(self.b.mutations, [])

    def test_wrong_tunnel_policy_addresses_mtu_and_membership_fail_health(self):
        self.prepared(advertise=True)
        original_links = copy.deepcopy(self.b.link_data)
        cases = [lambda: self.b.link_data[c.EXTERNAL]['linkinfo']['info_data'].update(id=999),
                 lambda: self.b.link_data[c.INTERNAL].update(mtu=1400),
                 lambda: self.b.link_data['other-br'].update(master=c.BRIDGE),
                 lambda: self.b.link_data[c.BRIDGE].update(ifalias='foreign'),
                 lambda: self.b.link_data[c.INTERNAL].update(flags=[])]
        for change in cases:
            self.b.link_data = copy.deepcopy(original_links)
            change()
            self.assertFalse(c.local_checks(self.b, self.state())['ready'])
        self.b.link_data = original_links
        self.b.addr_data[c.EXTERNAL] = [{'family': 'inet6', 'local': 'fe80::1'}]
        self.assertFalse(c.local_checks(self.b, self.state())['ready'])
        self.b.addr_data[c.EXTERNAL] = []
        self.b.nft['nftables'].append({'unexpected': 'rule'})
        self.assertIn('owned-policy-drift', c.local_checks(self.b, self.state())['reasons'])

    def test_counter_and_handle_changes_do_not_break_policy_digest(self):
        self.prepared(advertise=True)
        self.b.nft['nftables'][1]['counter'] = {'packets': 900, 'bytes': 8000}
        self.b.nft['nftables'][1]['handle'] = 77
        self.assertTrue(c.local_checks(self.b, self.state())['ready'])

    def test_withdraw_health_is_bounded_and_does_not_touch_dataplane(self):
        self.prepared(advertise=True, opened=True)
        count = len(self.b.mutations)
        before = copy.deepcopy(self.b.nft)
        def during_sleep(seconds):
            self.assertEqual(seconds, 5)
            self.assertFalse(self.state()['advertised'])
            self.assertTrue((c.STATE / 'pending.json').exists())
            self.assertEqual(c.health_snapshot()[0], 503)
        with patch.object(c.time, 'sleep', side_effect=during_sleep):
            self.ctl('withdraw-health', seconds=5)
        self.assertEqual(before, self.b.nft)
        self.assertEqual(count, len(self.b.mutations))
        self.assertTrue(self.state()['advertised'])
        self.assertEqual(self.state()['mode'], 'allow-primary')
        for seconds in (0, 4, 121):
            with self.assertRaises(ValueError):
                self.ctl('withdraw-health', seconds=seconds)

    def test_interrupted_withdrawal_does_not_claim_recovery(self):
        self.prepared(advertise=True, opened=True)
        with patch.object(c.time, 'sleep', side_effect=SystemExit(128 + signal.SIGHUP)):
            with self.assertRaises(SystemExit):
                self.ctl('withdraw-health', seconds=5)
        self.assertEqual(self.state()['phase'], 'uncertain')
        self.assertFalse(self.state()['advertised'])
        pending = c.read_json(c.STATE / 'pending.json')
        self.assertEqual(pending['error_type'], 'SystemExit')
        events = (Path(pending['attempt_directory']) / 'events.jsonl').read_text()
        self.assertIn('"event": "failed"', events)
        self.assertNotIn('"event": "completed"', events)

    def test_failed_restore_checks_remain_pending(self):
        self.prepared(advertise=True)
        def drift(_seconds):
            self.b.link_data[c.INTERNAL]['mtu'] = 1400
        with patch.object(c.time, 'sleep', side_effect=drift), self.assertRaisesRegex(RuntimeError, 'restoration precheck'):
            self.ctl('withdraw-health', seconds=5)
        self.assertFalse(self.state()['advertised'])
        self.assertTrue((c.STATE / 'pending.json').exists())

    def test_lock_contention_rejects_without_mutation(self):
        with c.exclusive_lock(), self.assertRaisesRegex(RuntimeError, 'exclusive lock'):
            self.ctl('prepare')
        self.assertEqual(self.b.mutations, [])

    def test_health_stale_or_pending_or_withdrawn_never_200(self):
        self.prepared(advertise=True)
        check = c.local_checks(self.b, self.state())
        c.atomic_json(c.RUNTIME / 'health.json', check)
        self.assertEqual(c.health_snapshot(now=check['time_epoch'] + 7)[0], 503)
        self.assertEqual(c.health_snapshot(now=check['time_epoch'] - 1)[0], 503)
        c.atomic_json(c.STATE / 'pending.json', {'phase': 'pending'})
        self.assertEqual(c.health_snapshot()[0], 503)

    def test_restore_original_only_owned_devices_table_and_underlay_mtu(self):
        unrelated = copy.deepcopy(self.b.link_data['other-br'])
        self.prepared(advertise=True, opened=True)
        self.ctl('restore-original')
        self.assertEqual(self.b.link_data['eth0']['mtu'], 1500)
        self.assertEqual(self.b.link_data['other-br'], unrelated)
        self.assertTrue(all(x not in self.b.link_data for x in c.DEVICES))
        self.assertIsNone(self.b.nft)
        self.assertEqual(self.state()['mode'], 'restored')
        count = len(self.b.mutations)
        self.assertEqual(self.ctl('boot')['outcome'], 'remains-restored-withdrawn')
        self.assertEqual(count, len(self.b.mutations))

    def test_restore_does_not_overwrite_foreign_mtu_change(self):
        self.prepared()
        self.b.link_data['eth0']['mtu'] = 1400
        with self.assertRaisesRegex(RuntimeError, 'MTU changed outside'):
            self.ctl('restore-original')
        self.assertEqual(self.b.link_data['eth0']['mtu'], 1400)

    def test_status_and_evidence_are_unique_fresh_and_private(self):
        self.prepared()
        first = self.ctl('status')
        second = self.ctl('status')
        self.assertNotEqual(first['snapshot_path'], second['snapshot_path'])
        self.assertIn('completed_utc', first)
        self.assertEqual(os.stat(first['snapshot_path']).st_mode & 0o777, 0o600)
        first = c.evidence(self.b)
        second = c.evidence(self.b)
        self.assertNotEqual(first['evidence_directory'], second['evidence_directory'])
        self.assertEqual(os.stat(first['evidence_directory']).st_mode & 0o777, 0o700)
        self.assertIn('not-a-datapath-pass', first['outcome'])

    def test_capture_targets_are_exact_and_payload_ack_required(self):
        filters = c.capture_filters(self.b)
        self.assertEqual([x[0] for x in filters], ['eth0', c.EXTERNAL, c.INTERNAL])
        self.assertIn('host 10.0.1.4', filters[0][1])
        self.assertNotIn('host 10.0.2.10', filters[0][1])
        self.assertIn('host 8.8.8.8', filters[1][1])
        with self.assertRaisesRegex(ValueError, 'sensitive-capture'):
            c.evidence(self.b, do_capture=True)
        for seconds, packets in [(61, 1), (1, 1001), (0, 1)]:
            with self.assertRaises(ValueError):
                c.evidence(self.b, seconds=seconds, packets=packets)

    def test_signal_handlers_include_hangup_interrupt_terminate(self):
        calls = []
        with patch.object(c.signal, 'signal', side_effect=lambda sig, fn: calls.append((sig, fn))):
            c.install_interrupt_handlers()
        self.assertEqual([x[0] for x in calls], [signal.SIGHUP, signal.SIGINT, signal.SIGTERM])
        for sig, handler in calls:
            with self.assertRaises(SystemExit) as caught:
                handler(sig, None)
            self.assertEqual(caught.exception.code, 128 + sig)

    def test_health_rejects_a_fresh_snapshot_for_a_different_state(self):
        self.prepared(advertise=True)
        check = c.local_checks(self.b, self.state())
        c.atomic_json(c.RUNTIME / 'health.json', check)
        changed = {**self.state(), 'changed_utc': 'new-transition'}
        c.atomic_json(c.STATE / 'state.json', changed)
        self.assertEqual(c.health_snapshot()[0], 503)

    def test_administratively_up_without_carrier_is_unhealthy(self):
        self.prepared(advertise=True)
        self.b.link_data['eth0']['flags'] = ['UP', 'NO-CARRIER']
        self.assertFalse(c.local_checks(self.b, self.state())['ready'])
        self.b.link_data['eth0']['flags'] = ['UP']
        self.b.link_data[c.EXTERNAL]['operstate'] = 'LOWERLAYERDOWN'
        self.assertFalse(c.local_checks(self.b, self.state())['ready'])

    def test_capture_mocked_processes_are_bounded_and_nonclobbering(self):
        class Process:
            def __init__(self):
                self.signals = []; self.waits = []; self.killed = False
            def poll(self):
                return None
            def send_signal(self, sig):
                self.signals.append(sig)
            def wait(self, timeout):
                self.waits.append(timeout)
                return 0
            def kill(self):
                self.killed = True
        self.prepared()
        processes = [Process(), Process(), Process()]
        with patch.object(c.subprocess, 'Popen', side_effect=processes) as popen, patch.object(c.time, 'sleep'):
            result = c.evidence(self.b, do_capture=True, seconds=1, packets=2, acknowledged=True)
        directory = Path(result['evidence_directory'])
        self.assertEqual(popen.call_count, 3)
        for process in processes:
            self.assertEqual(process.signals, [signal.SIGINT])
            self.assertEqual(process.waits, [3])
        for args, _kwargs in popen.call_args_list:
            command = args[0]
            self.assertNotIn('any', command)
            self.assertEqual(command[command.index('-c') + 1], '2')
            self.assertEqual(command[command.index('-s') + 1], '256')
        self.assertEqual(len(list(directory.glob('*.pcap'))), 3)
        outcomes = c.read_json(directory / 'capture-outcomes.json')
        self.assertTrue(all(item['returncode'] == 0 for item in outcomes))
        with self.assertRaises(FileExistsError):
            c.capture(self.b, directory, 1, 2)

    def test_capture_spawn_failure_still_reaps_previous_process(self):
        from unittest.mock import Mock
        self.prepared()
        process = Mock()
        process.poll.return_value = None
        process.wait.return_value = 0
        directory = c.private_directory(c.STATE / 'capture-test')
        with patch.object(c.subprocess, 'Popen', side_effect=[process, OSError('spawn failed')]):
            with self.assertRaisesRegex(OSError, 'spawn failed'):
                c.capture(self.b, directory, 1, 2)
        process.send_signal.assert_called_once_with(signal.SIGINT)
        process.wait.assert_called_once_with(timeout=3)
        self.assertTrue((directory / 'capture-outcomes.json').exists())

    def test_capture_stubborn_process_is_killed_with_bounded_waits(self):
        from unittest.mock import Mock
        self.prepared()
        processes = [Mock() for _ in range(3)]
        for process in processes:
            process.poll.return_value = None
            process.wait.side_effect = [subprocess.TimeoutExpired('tcpdump', 3), -signal.SIGKILL]
        directory = c.private_directory(c.STATE / 'capture-test')
        with patch.object(c.subprocess, 'Popen', side_effect=processes), patch.object(c.time, 'sleep'):
            with self.assertRaisesRegex(RuntimeError, 'tcpdump failed'):
                c.capture(self.b, directory, 1, 2)
        for process in processes:
            process.kill.assert_called_once()
            self.assertEqual(process.wait.call_count, 2)
        self.assertEqual(len(c.read_json(directory / 'capture-outcomes.json')), 3)

    def test_capture_exit_signal_race_still_cleans_all_processes(self):
        from unittest.mock import Mock
        self.prepared()
        processes = [Mock() for _ in range(3)]
        for process in processes:
            process.poll.return_value = None
            process.send_signal.side_effect = ProcessLookupError('already exited')
            process.wait.return_value = 0
        directory = c.private_directory(c.STATE / 'capture-test')
        with patch.object(c.subprocess, 'Popen', side_effect=processes), patch.object(c.time, 'sleep'):
            self.assertEqual(len(c.capture(self.b, directory, 1, 2)), 3)

    def test_control_failure_when_emergency_policy_fails_reports_uncertainty(self):
        self.prepared()
        original = self.b.apply_policy
        def broken(opened):
            raise RuntimeError('nft unavailable')
        self.b.apply_policy = broken
        with self.assertRaisesRegex(RuntimeError, 'nft unavailable'):
            self.ctl('allow-primary', acknowledge_capture_required=True)
        pending = c.read_json(c.STATE / 'pending.json')
        self.assertTrue(pending['emergency_close_errors'])
        self.assertFalse(self.state()['advertised'])
        self.assertTrue(all('UP' not in self.b.link_data[name]['flags'] for name in c.PORTS))
        self.b.apply_policy = original
        self.ctl('reconcile')
        self.assertEqual(self.b.topology_errors(), [])

    def test_state_write_failure_after_nft_mutation_recloses(self):
        self.prepared()
        real_atomic = c.atomic_json
        failed = []
        def injected(path, value, *args, **kwargs):
            if Path(path).name == 'state.json' and value.get('mode') == 'allow-primary' and value.get('phase') == 'stable' and not failed:
                failed.append(True)
                self.assertIn('counter accept', json.dumps(self.b.nft))
                raise OSError('post-policy state fsync failed')
            return real_atomic(path, value, *args, **kwargs)
        with patch.object(c, 'atomic_json', side_effect=injected), self.assertRaisesRegex(OSError, 'post-policy state fsync'):
            self.ctl('allow-primary', acknowledge_capture_required=True)
        self.assertNotIn('counter accept', json.dumps(self.b.nft))
        pending = c.read_json(c.STATE / 'pending.json')
        self.assertEqual(pending['phase'], 'uncertain')
        self.assertEqual(pending['error'], 'post-policy state fsync failed')
        self.assertFalse(self.state()['advertised'])
        self.assertEqual(c.health_snapshot()[0], 503)

    def test_event_failure_before_withdrawal_still_closes_prior_allow(self):
        self.prepared(advertise=True, opened=True)
        real_event = c.event
        failed = []
        def injected(*args, **kwargs):
            if not failed:
                failed.append(True)
                raise OSError('event fsync failed')
            return real_event(*args, **kwargs)
        with patch.object(c, 'event', side_effect=injected), self.assertRaisesRegex(OSError, 'event fsync failed'):
            self.ctl('withdraw-health', seconds=5)
        self.assertNotIn('counter accept', json.dumps(self.b.nft))
        self.assertFalse(self.state()['advertised'])
        self.assertEqual(c.read_json(c.STATE / 'pending.json')['phase'], 'uncertain')

    def test_persistent_state_write_failure_preserves_original_error_and_pending(self):
        from io import StringIO
        self.prepared(advertise=True, opened=True)
        real_atomic = c.atomic_json
        def injected(path, value, *args, **kwargs):
            if Path(path).name == 'state.json':
                raise OSError('persistent state storage failure')
            return real_atomic(path, value, *args, **kwargs)
        stderr = StringIO()
        with patch.object(c, 'atomic_json', side_effect=injected), patch.object(c.sys, 'stderr', stderr):
            with self.assertRaisesRegex(OSError, 'persistent state storage failure'):
                self.ctl('close')
        self.assertNotIn('counter accept', json.dumps(self.b.nft))
        pending = c.read_json(c.STATE / 'pending.json')
        self.assertEqual(pending['error'], 'persistent state storage failure')
        self.assertTrue(pending['recovery_record_errors'])
        # State could not be updated, but a durable pending gate blocks old healthy publication.
        self.assertEqual(c.health_snapshot()[0], 503)
        self.assertIn('uncertain', stderr.getvalue())

    def test_event_and_emergency_failures_cannot_mask_original_exception(self):
        from io import StringIO
        self.prepared(advertise=True, opened=True)
        with patch.object(c, 'event', side_effect=OSError('original event error')), \
                patch.object(self.b, 'emergency_close', side_effect=RuntimeError('secondary close error')), \
                patch.object(c.sys, 'stderr', StringIO()):
            with self.assertRaisesRegex(OSError, 'original event error'):
                self.ctl('withdraw')
        pending = c.read_json(c.STATE / 'pending.json')
        self.assertEqual(pending['error'], 'original event error')
        self.assertIn('secondary close error', pending['emergency_close_errors'][0])
        self.assertEqual(self.state()['mode'], 'unknown')
        self.assertFalse(self.state()['advertised'])
        self.assertEqual(c.health_snapshot()[0], 503)

    def test_health_server_bind_does_not_resolve_dns(self):
        server = object.__new__(c.HealthServer)
        server.server_address = (CFG['private_ip'], 8008)
        with patch.object(c.TCPServer, 'server_bind') as bind, \
                patch('socket.getfqdn', side_effect=AssertionError('DNS forbidden')):
            server.server_bind()
        bind.assert_called_once_with(server)
        self.assertEqual(server.server_name, 'azure-gwlb-lab')
        self.assertEqual(server.server_port, 8008)

    def test_health_handler_only_serves_exact_health_path(self):
        from io import BytesIO
        from unittest.mock import Mock
        handler = object.__new__(c.HealthHandler)
        handler.send_error = Mock()
        handler.send_response = Mock()
        handler.send_header = Mock()
        handler.end_headers = Mock()
        handler.wfile = BytesIO()
        for path in ('/', '/healthz', '/health?x=1'):
            handler.path = path
            handler.do_GET()
        self.assertEqual(handler.send_error.call_count, 3)
        handler.path = '/health'
        with patch.object(c, 'health_snapshot', return_value=(503, {'ready': False})):
            handler.do_GET()
        handler.send_response.assert_called_once_with(503)
        self.assertIn(b'false', handler.wfile.getvalue())

    def test_completed_event_failure_keeps_pending_until_recovery(self):
        self.prepared(advertise=True, opened=True)
        real_event = c.event
        def injected(directory, name, **details):
            if name == 'completed':
                self.assertTrue((c.STATE / 'pending.json').exists())
                raise OSError('completed event fsync failed')
            return real_event(directory, name, **details)
        with patch.object(c, 'event', side_effect=injected), self.assertRaisesRegex(OSError, 'completed event fsync'):
            self.ctl('withdraw')
        pending = c.read_json(c.STATE / 'pending.json')
        self.assertEqual(pending['phase'], 'uncertain')
        self.assertFalse(pending['pending_removal_started'])
        self.assertFalse(self.state()['advertised'])
        self.assertNotIn('counter accept', json.dumps(self.b.nft))

    def test_final_snapshot_failure_keeps_pending_until_recovery(self):
        self.prepared(advertise=True, opened=True)
        real_snapshot = c.snapshot
        def injected(backend, destination=None):
            if destination and Path(destination).name == 'after.json':
                self.assertTrue((c.STATE / 'pending.json').exists())
                raise OSError('final snapshot fsync failed')
            return real_snapshot(backend, destination)
        with patch.object(c, 'snapshot', side_effect=injected), self.assertRaisesRegex(OSError, 'final snapshot fsync'):
            self.ctl('withdraw')
        pending = c.read_json(c.STATE / 'pending.json')
        self.assertEqual(pending['phase'], 'uncertain')
        self.assertFalse(pending['pending_removal_started'])
        self.assertFalse(self.state()['advertised'])
        self.assertNotIn('counter accept', json.dumps(self.b.nft))
        events = (Path(pending['attempt_directory']) / 'events.jsonl').read_text()
        self.assertIn('verified-awaiting-finalization', events)
        self.assertIn('"event": "failed"', events)

    def test_pending_removal_fsync_failure_is_uncertain_and_reconciled_closed(self):
        self.prepared(advertise=True, opened=True)
        real_sync = c.sync_directory
        failed = []
        def injected(path):
            if Path(path) == c.STATE and not (c.STATE / 'pending.json').exists() and not failed:
                failed.append(True)
                raise OSError('pending removal directory fsync failed')
            return real_sync(path)
        with patch.object(c, 'sync_directory', side_effect=injected), self.assertRaisesRegex(OSError, 'removal directory fsync'):
            self.ctl('withdraw')
        self.assertTrue(failed)
        pending = c.read_json(c.STATE / 'pending.json')
        self.assertTrue(pending['pending_removal_started'])
        self.assertEqual(pending['phase'], 'uncertain')
        self.assertFalse(self.state()['advertised'])
        self.assertNotIn('counter accept', json.dumps(self.b.nft))
        self.assertEqual(c.health_snapshot()[0], 503)
        self.ctl('reconcile')
        self.assertFalse((c.STATE / 'pending.json').exists())
        self.assertEqual(self.state()['mode'], 'closed')

    def test_removal_then_failed_marker_rewrite_reports_no_survival_guarantee(self):
        from io import StringIO
        self.prepared(advertise=True, opened=True)
        real_atomic = c.atomic_json
        removal_started = []
        def injected_remove(path):
            Path(path).unlink()
            removal_started.append(True)
            raise OSError('unlink succeeded but fsync failed')
        def injected_atomic(path, value, *args, **kwargs):
            if removal_started and Path(path).name == 'pending.json':
                raise OSError('marker rewrite storage failure')
            return real_atomic(path, value, *args, **kwargs)
        stderr = StringIO()
        with patch.object(c, 'remove_record', side_effect=injected_remove), \
                patch.object(c, 'atomic_json', side_effect=injected_atomic), patch.object(c.sys, 'stderr', stderr):
            with self.assertRaisesRegex(OSError, 'unlink succeeded but fsync failed'):
                self.ctl('withdraw')
        self.assertFalse((c.STATE / 'pending.json').exists())
        self.assertEqual(self.state()['phase'], 'uncertain')
        self.assertFalse(self.state()['advertised'])
        self.assertNotIn('counter accept', json.dumps(self.b.nft))
        self.assertEqual(c.health_snapshot()[0], 503)
        failure = json.loads(stderr.getvalue())
        self.assertTrue(failure['pending_removal_started'])
        self.assertFalse(failure['uncertain_marker_write_verified'])
        self.assertTrue(failure['recovery_record_errors'])

    def test_success_snapshot_is_explicitly_before_finalization(self):
        result = self.ctl('prepare')
        self.assertIn('Before finalization', result['health_observation'])
        snap = c.read_json(Path(result['evidence_directory']) / 'after.json')
        self.assertIsNotNone(snap['pending'])
        self.assertFalse(snap['health']['ready'])
        self.assertFalse((c.STATE / 'pending.json').exists())
        self.assertEqual(result['outcome'], 'verified')


if __name__ == '__main__':
    unittest.main()
