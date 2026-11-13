#!/usr/bin/env python3
"""Fully mocked perimeter controller regression tests, with no guest or network I/O.

The real controller's state machine, ownership checks, file writes and command
construction run against a deliberately small in-memory kernel. This is NOT an
nft parser, kernel validation, Azure validation, or live forwarding/path proof.
Every subprocess and socket entry point is denied unless an individual test
supplies a fake. Public-looking addresses are inert strings only.
"""
import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("forced_controller_under_test", ROOT / "guest/controller.py")
controller = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(controller)
CONFIG = {
    "role": "perimeter", "private_ip": "10.30.1.4", "firewall_private_ip": "10.0.1.4",
    "app_ip": "10.20.1.10", "origin_public_ip": "20.42.0.10",
    "perimeter_public_ip": "20.50.0.20", "source_mode": "preserve",
}
GUARDS = []


def deny_external(*args, **kwargs):
    raise AssertionError("Controller tests forbid real subprocesses and all network I/O")


def setUpModule():
    targets = [(subprocess, "run"), (subprocess, "Popen"), (os, "system"), (os, "popen"),
               (socket, "socket"), (socket, "socketpair"), (socket, "create_connection"),
               (socket, "getaddrinfo"), (socket, "gethostbyname"), (socket, "gethostbyname_ex")]
    for name in ("posix_spawn", "posix_spawnp", "fork", "forkpty", "execv", "execve", "execvp", "execvpe"):
        if hasattr(os, name):
            targets.append((os, name))
    for obj, name in targets:
        guard = patch.object(obj, name, side_effect=deny_external)
        guard.start()
        GUARDS.append(guard)


def tearDownModule():
    for guard in reversed(GUARDS):
        guard.stop()
    GUARDS.clear()


class FakeKernel(controller.Backend):
    """Backend.run replacement; inherited policy/ownership logic stays real.

    Rulesets are represented as JSON with their complete generated source. No
    assertion here means the source was accepted by nft or an actual kernel.
    """
    def __init__(self, cfg=None):
        super().__init__(copy.deepcopy(cfg or CONFIG))
        self.address_rows = [{"ifname": "eth0", "addr_info": [{"local": self.cfg["private_ip"]}]}]
        self.sysctls = {"net.ipv4.ip_forward": 0, "net.netfilter.nf_conntrack_tcp_loose": 1}
        for scope in ("all", "default", "eth0"):
            for item in ("rp_filter", "accept_redirects", "send_redirects", "accept_source_route"):
                self.sysctls[f"net.ipv4.conf.{scope}.{item}"] = 1 if item != "rp_filter" else 2
        self.original_values = dict(self.sysctls)
        self.nft = None
        self.other_tables = [{"family": "ip", "name": "unrelated_existing_policy"}]
        self.commands = []
        self.policy_sources = []
        self.mutations = []
        self.fail = None
        self.ignore_sysctl = None

    def run(self, args, check=True):
        args = list(args)
        self.commands.append(args)
        if self.fail is not None:
            self.fail(args)
        stdout = ""
        if args == ["ip", "-j", "-4", "addr", "show"]:
            stdout = json.dumps(self.address_rows)
        elif args[:2] == ["sysctl", "-n"] and len(args) == 3:
            stdout = str(self.sysctls[args[2]]) + "\n"
        elif args[:2] == ["sysctl", "-w"] and len(args) == 3:
            key, value = args[2].split("=", 1)
            if key not in self.sysctls:
                raise AssertionError("Attempt to mutate a sysctl outside the owned set: " + key)
            self.mutations.append(("sysctl", key, int(value)))
            if key != self.ignore_sysctl:
                self.sysctls[key] = int(value)
            # Simulate the documented ip_forward reset of router/host defaults.
            if key == "net.ipv4.ip_forward":
                for name in self.sysctls:
                    if name.startswith("net.ipv4.conf."):
                        self.sysctls[name] = 1
        elif args == ["nft", "-j", "list", "tables"]:
            rows = [{"table": row} for row in copy.deepcopy(self.other_tables)]
            if self.nft is not None:
                rows.append({"table": {"family": "inet", "name": controller.TABLE}})
            stdout = json.dumps({"nftables": rows})
        elif args == ["nft", "-j", "list", "table", "inet", controller.TABLE]:
            if self.nft is None:
                raise RuntimeError("MOCK owned table does not exist")
            stdout = json.dumps(self.nft)
        elif args[:3] == ["nft", "-c", "-f"] and len(args) == 4:
            Path(args[3]).read_text()  # Read-only fake syntax check, never run nft.
        elif args[:2] == ["nft", "-f"] and len(args) == 3:
            source = Path(args[2]).read_text()
            self.policy_sources.append(source)
            self.mutations.append(("nft-policy", 'comment "allow-new-test-syn"' in source))
            comment = re.search(r'  comment "([^"]+)"', source).group(1)
            self.nft = {"nftables": [
                {"metainfo": {"version": "MOCK-NOT-KERNEL"}},
                {"table": {"family": "inet", "name": controller.TABLE, "comment": comment, "handle": 11}},
                {"rule": {"family": "inet", "table": controller.TABLE, "chain": "forward",
                          "handle": 21, "expr": [{"counter": {"packets": 0, "bytes": 0}}],
                          "mock_source_not_nft_json": source[source.index("table inet " + controller.TABLE + " {"): ]}},
            ]}
        elif args == ["nft", "delete", "table", "inet", controller.TABLE]:
            self.mutations.append(("nft-delete-owned",))
            self.nft = None
        elif args[:3] == ["ip", "-j", "route"] and len(args) == 5 and args[3] == "get":
            stdout = json.dumps([{"dst": args[4], "dev": "eth0", "mock_only": True}])
        elif args == ["conntrack", "-L", "-p", "tcp", "--orig-dst", self.cfg["origin_public_ip"], "-o", "extended"]:
            stdout = "MOCK retained connection record\n"
        else:
            raise AssertionError("Unmodeled command, prohibited in offline suite: " + repr(args))
        return subprocess.CompletedProcess(args, 0, stdout, "")

    @property
    def opened(self):
        return self.nft is not None and 'comment "allow-new-test-syn"' in self.nft["nftables"][2]["rule"]["mock_source_not_nft_json"]


class ControllerCase(unittest.TestCase):
    def setUp(self):
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        temp = self.stack.enter_context(tempfile.TemporaryDirectory(prefix=".controller-mock-", dir=ROOT / "tests"))
        self.root = Path(temp)
        self.state = self.root / "state"
        self.runtime = self.root / "run"
        self.kernel_temp = self.root / "kernel-command-files"
        self.kernel_temp.mkdir()
        self.stack.enter_context(patch.object(controller, "STATE", self.state))
        self.stack.enter_context(patch.object(controller, "RUNTIME", self.runtime))
        self.stack.enter_context(patch.object(tempfile, "tempdir", str(self.kernel_temp)))
        self.stack.enter_context(patch.object(controller.os, "geteuid", return_value=0))
        self.sleep = self.stack.enter_context(patch.object(controller.time, "sleep", side_effect=AssertionError("Unexpected sleep in offline test")))
        self.stderr = self.stack.enter_context(contextlib.redirect_stderr(io.StringIO()))
        self.backend = FakeKernel()

    def control(self, action, **kwargs):
        return controller.control(self.backend, action, confirmed=True, **kwargs)

    def prepare(self):
        return self.control("prepare")

    def open(self):
        self.prepare()
        return self.control("allow-test", acknowledged=True)

    def saved(self, name="state.json"):
        return controller.read_json(self.state / name)

    def uncertain(self, error_type=None):
        state = self.saved()
        pending = self.saved("pending.json")
        self.assertEqual(state["phase"], "uncertain")
        self.assertIn(state["mode"], ("closed", "unknown"))
        self.assertEqual(pending["phase"], "uncertain")
        if error_type:
            self.assertEqual(pending["error_type"], error_type)
        self.assertFalse(self.backend.check(state)["ready"])
        return pending

    def seed_pending(self):
        record = {"action": "allow-test", "phase": "pending", "test_marker": "interrupted"}
        controller.atomic_json(self.state / "pending.json", record)
        return record

    def event_rows(self, directory):
        return [json.loads(line) for line in (Path(directory) / "events.jsonl").read_text().splitlines()]


class ConfigPolicyTests(ControllerCase):
    def test_config_exact_fields_fixed_identity_and_mode(self):
        self.assertEqual(controller.validate_config(CONFIG), CONFIG)
        for key, value in (("role", "app"), ("private_ip", "10.30.1.5"), ("app_ip", "10.20.1.11"),
                           ("source_mode", "any"), ("firewall_private_ip", "10.0.1.3"),
                           ("firewall_private_ip", "10.0.1.63"), ("firewall_private_ip", "10.0.2.4"),
                           ("perimeter_public_ip", CONFIG["origin_public_ip"])):
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                controller.validate_config({**CONFIG, key: value})
        for config in ({**CONFIG, "extra": True}, {key: value for key, value in CONFIG.items() if key != "role"}, []):
            with self.subTest(config=config), self.assertRaises(ValueError):
                controller.validate_config(config)

    def test_global_ipv4_only_no_dns_or_documentation_addresses(self):
        for value in ("", "example.com", "127.0.0.1", "10.2.3.4", "0.0.0.0", "100.64.0.1", "169.254.1.1",
                      "192.0.2.1", "198.51.100.1", "203.0.113.1", "198.18.0.1", "192.0.0.8", "192.88.99.1",
                      "224.0.0.1", "240.0.0.1", "255.255.255.255", "::1", "2001:4860::1", "20.42.0.10/32"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                controller.public_ip(value)
        self.assertEqual(controller.public_ip(CONFIG["origin_public_ip"]), CONFIG["origin_public_ip"])

    def test_source_modes_exact_app_or_firewall_subnet(self):
        for mode, prefix in (("preserve", "10.20.1.10/32"), ("firewall_private", "10.0.1.0/26")):
            config = {**CONFIG, "source_mode": mode}
            self.assertEqual(controller.source_prefix(config), prefix)
            source = controller.nft_source(config, "eth0", True)
            self.assertIn("ip saddr " + prefix + " ip daddr " + CONFIG["origin_public_ip"], source)
            self.assertNotIn("ip saddr 0.0.0.0/0", source)
            self.assertNotIn("10.0.0.0/8", source)

    def test_closed_policy_is_drop_with_no_allow_or_snat(self):
        source = controller.nft_source(CONFIG, "eth0", False)
        self.assertIn("type filter hook forward priority 0; policy drop;", source)
        self.assertIn('counter drop comment "deny-other-forward"', source)
        self.assertIn('comment "deny-closed-test-forward"', source)
        self.assertIn('comment "deny-closed-test-return"', source)
        self.assertNotIn("counter accept", source)
        self.assertNotIn("snat ip", source)
        self.assertNotIn("masquerade", source)

    def test_open_policy_snat_is_only_exact_D_test_ports_to_E_never_P(self):
        for mode, prefix in (("preserve", "10.20.1.10/32"), ("firewall_private", "10.0.1.0/26")):
            source = controller.nft_source({**CONFIG, "source_mode": mode}, "eth0", True)
            nat = [line.strip() for line in source.splitlines() if "snat" in line]
            self.assertEqual(nat, [f'oifname "eth0" ip saddr {prefix} ip daddr 20.42.0.10 tcp dport {{ 8080, 8081 }} counter snat ip to 10.30.1.4 comment "snat-only-owned-test-to-E"'])
            self.assertNotIn(CONFIG["perimeter_public_ip"], source)
            self.assertNotIn("masquerade", source)
            accepts = [line for line in source.splitlines() if "counter accept" in line]
            self.assertEqual(len(accepts), 3)
            self.assertTrue(all('iifname "eth0" oifname "eth0"' in line for line in accepts))
            self.assertTrue(all("{ 8080, 8081 }" in line for line in accepts))
            self.assertTrue(any("ct state new tcp flags & (fin | syn | rst | ack) == syn" in line for line in accepts))
            self.assertEqual(sum("ct state established" in line for line in accepts), 2)
            self.assertNotIn("related", source)

    def test_8082_denied_both_directions_before_allow_rules_in_both_modes(self):
        for mode in ("preserve", "firewall_private"):
            for opened in (False, True):
                source = controller.nft_source({**CONFIG, "source_mode": mode}, "eth0", opened)
                lines = [line for line in source.splitlines() if "8082" in line]
                self.assertEqual(len(lines), 2)
                self.assertTrue(all("counter drop" in line for line in lines))
                self.assertTrue(any("tcp dport 8082" in line for line in lines))
                self.assertTrue(any("tcp sport 8082" in line for line in lines))
                if opened:
                    self.assertLess(source.index("deny-perimeter-8082-reverse"), source.index("allow-new-test-syn"))

    def test_interface_injection_and_loopback_identity_rejected(self):
        for name in ("", "eth0;evil", 'eth0"', "a" * 16, "eth0.2", "eth0\n"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                controller.nft_source(CONFIG, name, True)
        for rows in ([], [{"ifname": "lo", "addr_info": [{"local": CONFIG["private_ip"]}]}],
                     self.backend.address_rows * 2):
            self.backend.address_rows = rows
            with self.assertRaisesRegex(RuntimeError, "NIC"):
                self.backend.interface()

    def test_digest_ignores_handles_and_counters_but_not_policy(self):
        self.prepare()
        original = self.backend.table()
        changed = copy.deepcopy(original)
        changed["nftables"][0]["metainfo"]["version"] = "different"
        changed["nftables"][1]["table"]["handle"] = 900
        changed["nftables"][2]["rule"]["index"] = 50
        changed["nftables"][2]["rule"]["expr"][0]["counter"] = {"packets": 1000, "bytes": 90000}
        self.assertEqual(controller.digest(original), controller.digest(changed))
        changed["nftables"][2]["rule"]["mock_source_not_nft_json"] += "different policy"
        self.assertNotEqual(controller.digest(original), controller.digest(changed))


class OwnershipBackendTests(ControllerCase):
    def test_prepare_captures_original_once_and_installs_closed_before_forwarding(self):
        result = self.prepare()
        self.assertEqual(result["state"]["mode"], "closed")
        self.assertFalse(self.backend.opened)
        self.assertEqual(self.saved("original.json")["values"], self.backend.original_values)
        self.assertEqual(self.backend.mutations[0], ("nft-policy", False))
        self.assertEqual(self.backend.mutations[1], ("sysctl", "net.ipv4.ip_forward", 1))
        self.assertEqual(self.backend.sysctls, self.backend.desired_values())
        self.assertEqual(len(self.backend.sysctls), 14)
        self.assertTrue(all(value == 0 for key, value in self.backend.sysctls.items() if key != "net.ipv4.ip_forward"))
        self.assertIsNone(self.saved("pending.json"))
        self.assertTrue(self.backend.check(self.saved())["ready"])
        original_bytes = (self.state / "original.json").read_bytes()
        self.prepare()
        self.assertEqual((self.state / "original.json").read_bytes(), original_bytes)

    def test_sysctl_forwarding_first_then_owned_defaults_and_verified(self):
        self.backend.set_values(self.backend.original_values)
        writes = [command for command in self.backend.commands if command[:2] == ["sysctl", "-w"]]
        self.assertEqual(writes[0], ["sysctl", "-w", "net.ipv4.ip_forward=0"])
        self.assertEqual(self.backend.sysctls, self.backend.original_values)
        self.backend.ignore_sysctl = "net.netfilter.nf_conntrack_tcp_loose"
        with self.assertRaisesRegex(RuntimeError, "verification failed"):
            self.backend.set_values({**self.backend.original_values, "net.netfilter.nf_conntrack_tcp_loose": 0})

    def test_preexisting_forwarding_not_enrolled(self):
        self.backend.sysctls["net.ipv4.ip_forward"] = 1
        with self.assertRaisesRegex(RuntimeError, "forwarding disabled"):
            self.backend.enroll()
        self.assertIsNone(self.saved("original.json"))
        self.assertFalse(self.backend.mutations)

    def test_foreign_table_collision_never_replaced(self):
        self.backend.nft = {"nftables": [{"table": {"family": "inet", "name": controller.TABLE, "comment": "somebody-else"}}]}
        original = copy.deepcopy(self.backend.nft)
        with self.assertRaisesRegex(RuntimeError, "collides"):
            self.backend.enroll()
        self.assertEqual(self.backend.nft, original)
        self.assertFalse(self.backend.mutations)

    def test_owned_table_without_original_record_not_adopted(self):
        self.prepare()
        (self.state / "original.json").unlink()
        before = copy.deepcopy(self.backend.nft)
        self.backend.mutations.clear()
        with self.assertRaisesRegex(RuntimeError, "without original"):
            self.backend.enroll()
        self.assertEqual(self.backend.nft, before)
        self.assertFalse(self.backend.mutations)

    def test_missing_changed_config_or_changed_interface_refuses_original(self):
        with self.assertRaisesRegex(RuntimeError, "ownership record"):
            self.backend.original()
        self.prepare()
        original = self.saved("original.json")
        for changed in ({**original, "interface": "eth1"},
                        {**original, "config": {**CONFIG, "source_mode": "firewall_private"}}):
            controller.atomic_json(self.state / "original.json", changed)
            with self.assertRaisesRegex(RuntimeError, "ownership record"):
                self.backend.original()

    def test_policy_replacement_uses_checked_single_owned_transaction(self):
        self.prepare()
        self.backend.commands.clear()
        other = copy.deepcopy(self.backend.other_tables)
        self.backend.apply_policy(True)
        apply_commands = [command for command in self.backend.commands if command[0] == "nft" and "-f" in command]
        self.assertEqual(len(apply_commands), 2)
        self.assertEqual(apply_commands[0][:3], ["nft", "-c", "-f"])
        self.assertEqual(apply_commands[1][:2], ["nft", "-f"])
        self.assertEqual(apply_commands[0][-1], apply_commands[1][-1])
        self.assertFalse(Path(apply_commands[0][-1]).exists())
        self.assertTrue(self.backend.policy_sources[-1].startswith("delete table inet azure_forced_lab\n"))
        self.assertNotIn("flush ruleset", self.backend.policy_sources[-1])
        self.assertEqual(self.backend.other_tables, other)

    def test_failed_fake_syntax_check_never_applies_or_leaves_temp_file(self):
        self.prepare()
        before = copy.deepcopy(self.backend.nft)
        self.backend.mutations.clear()
        def fail(args):
            if args[:3] == ["nft", "-c", "-f"]:
                raise RuntimeError("MOCK syntax failure")
        self.backend.fail = fail
        with self.assertRaisesRegex(RuntimeError, "MOCK syntax"):
            self.backend.apply_policy(True)
        self.assertEqual(self.backend.nft, before)
        self.assertFalse(self.backend.mutations)
        self.assertEqual(list(self.kernel_temp.iterdir()), [])

    def test_restore_removes_only_owned_table_restores_all_original_sysctls(self):
        self.prepare()
        other = copy.deepcopy(self.backend.other_tables)
        result = self.control("restore-original", acknowledged=True)
        self.assertEqual(result["state"]["mode"], "restored")
        self.assertIsNone(self.backend.nft)
        self.assertEqual(self.backend.sysctls, self.backend.original_values)
        self.assertEqual(self.backend.other_tables, other)
        self.assertEqual(self.backend.mutations[-1], ("nft-delete-owned",))
        self.assertIsNotNone(self.saved("original.json"))
        self.assertFalse(self.backend.check(self.saved())["ready"])

    def test_emergency_close_without_original_record_refuses_all_mutation(self):
        self.backend.sysctls["net.ipv4.ip_forward"] = 1
        before = dict(self.backend.sysctls)
        errors = self.backend.emergency_close()
        self.assertTrue(errors)
        self.assertEqual(self.backend.sysctls, before)
        self.assertFalse(self.backend.mutations)

    def test_emergency_close_with_mismatched_original_refuses_all_mutation(self):
        self.open()
        original = self.saved("original.json")
        for changed in ({**original, "interface": "eth1"},
                        {**original, "config": {**CONFIG, "source_mode": "firewall_private"}}):
            with self.subTest(changed=changed):
                controller.atomic_json(self.state / "original.json", changed)
                before = copy.deepcopy(self.backend.nft)
                values = dict(self.backend.sysctls)
                self.backend.mutations.clear()
                errors = self.backend.emergency_close()
                self.assertTrue(errors)
                self.assertEqual(self.backend.nft, before)
                self.assertEqual(self.backend.sysctls, values)
                self.assertFalse(self.backend.mutations)

    def test_control_prepare_rejects_foreign_policy_without_sysctl_fallback_mutation(self):
        self.backend.nft = {"nftables": [{"table": {"family": "inet", "name": controller.TABLE, "comment": "somebody-else"}}]}
        self.backend.sysctls["net.ipv4.ip_forward"] = 1
        original = copy.deepcopy(self.backend.nft)
        values = dict(self.backend.sysctls)
        with self.assertRaisesRegex(RuntimeError, "collides"):
            self.prepare()
        self.assertEqual(self.backend.nft, original)
        self.assertEqual(self.backend.sysctls, values)
        self.assertFalse(self.backend.mutations)
        self.assertIsNone(self.saved("original.json"))
        self.assertEqual(self.saved()["mode"], "unknown")
        self.assertTrue(self.saved("pending.json")["closure_errors"])

    def test_control_prepare_rejects_preexisting_forwarding_without_mutation(self):
        self.backend.sysctls["net.ipv4.ip_forward"] = 1
        values = dict(self.backend.sysctls)
        with self.assertRaisesRegex(RuntimeError, "forwarding disabled"):
            self.prepare()
        self.assertEqual(self.backend.sysctls, values)
        self.assertFalse(self.backend.mutations)
        self.assertIsNone(self.saved("original.json"))
        self.assertEqual(self.saved()["mode"], "unknown")

    def test_emergency_close_fallback_disables_forwarding_but_reports_uncertainty(self):
        self.open()
        with patch.object(self.backend, "apply_policy", side_effect=RuntimeError("MOCK table failure")):
            errors = self.backend.emergency_close()
        self.assertIn("MOCK table failure", errors[0])
        self.assertEqual(self.backend.sysctls["net.ipv4.ip_forward"], 0)
        self.assertTrue(self.backend.opened)  # Table outcome cannot be claimed closed.

    def test_emergency_fallback_failure_reports_both_errors(self):
        self.prepare()
        def fail(args):
            if args[:2] == ["sysctl", "-w"]:
                raise RuntimeError("MOCK sysctl failure")
        self.backend.fail = fail
        with patch.object(self.backend, "apply_policy", side_effect=RuntimeError("MOCK table failure")):
            errors = self.backend.emergency_close()
        self.assertEqual(len(errors), 2)
        self.assertIn("forwarding-off fallback", errors[1])


class ControlStateTests(ControllerCase):
    def test_every_guest_change_requires_confirmation_except_boot(self):
        for action in ("prepare", "allow-test", "close", "reconcile", "recover", "restore-original", "fail-forwarding"):
            with self.subTest(action=action), self.assertRaisesRegex(RuntimeError, "confirm-guest-change"):
                controller.control(self.backend, action)
        self.assertFalse(self.backend.commands)
        self.assertFalse(self.state.exists())
        result = controller.control(self.backend, "boot")
        self.assertEqual(result["state"]["mode"], "closed")

    def test_scope_acknowledgment_needed_before_open_or_restore(self):
        self.prepare()
        for action in ("allow-test", "restore-original"):
            with self.subTest(action=action), self.assertRaisesRegex(RuntimeError, "acknowledge-reviewed-scope"):
                self.control(action)
        self.assertFalse(self.backend.opened)
        self.assertIsNone(self.saved("pending.json"))

    def test_root_required_before_mutation(self):
        with patch.object(controller.os, "geteuid", return_value=1000):
            with self.assertRaisesRegex(RuntimeError, "requires root"):
                self.prepare()
        self.assertFalse(self.backend.commands)
        self.assertFalse(self.state.exists())

    def test_status_read_only_does_not_require_confirmation_or_root(self):
        self.prepare()
        state_bytes = (self.state / "state.json").read_bytes()
        self.backend.mutations.clear()
        with patch.object(controller.os, "geteuid", return_value=1000):
            result = controller.control(self.backend, "status")
        self.assertTrue(result["readiness"]["ready"])
        self.assertEqual((self.state / "state.json").read_bytes(), state_bytes)
        self.assertFalse(self.backend.mutations)
        self.assertIn("not Azure", result["readiness"]["scope"])

    def test_open_and_close_persist_real_state_and_scoped_evidence(self):
        self.prepare()
        result = self.control("allow-test", acknowledged=True)
        self.assertTrue(self.backend.opened)
        self.assertEqual(self.saved()["mode"], "allow-test")
        self.assertEqual(self.saved()["policy_digest"], controller.digest(self.backend.table()))
        rows = self.event_rows(result["evidence_directory"])
        self.assertEqual([row["event"] for row in rows], ["pending-persisted", "verified-before-finalization"])
        evidence = Path(result["evidence_directory"])
        before = json.loads((evidence / "before.json").read_text())
        after = json.loads((evidence / "after-before-finalization.json").read_text())
        self.assertEqual(before["state"]["phase"], "pending")
        self.assertFalse(after["readiness"]["ready"])  # Marker still exists at snapshot time.
        self.assertEqual(result["outcome"], "verified-before-current-status-check")
        self.assertNotIn("success", result["outcome"].lower())
        closed = self.control("close")
        self.assertFalse(self.backend.opened)
        self.assertEqual(closed["state"]["mode"], "closed")
        self.assertNotEqual(result["evidence_directory"], closed["evidence_directory"])

    def test_both_modes_complete_prepare_open_close_with_unchanged_original(self):
        self.backend = FakeKernel({**CONFIG, "source_mode": "firewall_private"})
        self.open()
        self.assertTrue(self.backend.opened)
        self.assertIn("10.0.1.0/26", self.backend.policy_sources[-1])
        self.assertEqual(self.saved("original.json")["config"]["source_mode"], "firewall_private")
        self.control("close")
        self.assertFalse(self.backend.opened)

    def test_unknown_action_and_unprepared_open_do_not_mutate(self):
        with self.assertRaises(ValueError):
            self.control("flush-everything")
        with self.assertRaisesRegex(RuntimeError, "Preflight"):
            self.control("allow-test", acknowledged=True)
        self.assertFalse(self.backend.mutations)
        self.assertIsNone(self.saved("pending.json"))

    def test_policy_and_sysctl_drift_both_block_open_preflight(self):
        self.prepare()
        self.backend.nft["nftables"][2]["rule"]["mock_source_not_nft_json"] += " drift"
        self.backend.sysctls["net.ipv4.conf.eth0.rp_filter"] = 2
        check = self.backend.check(self.saved())
        self.assertIn("owned-policy-drift", check["reasons"])
        self.assertIn("owned-sysctl-drift", check["reasons"])
        self.backend.mutations.clear()
        with self.assertRaisesRegex(RuntimeError, "Preflight"):
            self.control("allow-test", acknowledged=True)
        self.assertFalse(self.backend.mutations)

    def test_pending_blocks_reopening_prepare_restore_and_failure(self):
        self.prepare()
        self.seed_pending()
        for action in ("allow-test", "prepare", "restore-original", "fail-forwarding"):
            with self.subTest(action=action), self.assertRaisesRegex(RuntimeError, "reconciliation"):
                self.control(action, acknowledged=True)
        self.assertEqual(self.saved("pending.json")["test_marker"], "interrupted")

    def test_close_with_prior_pending_stays_uncertain_until_reconcile(self):
        self.open()
        self.seed_pending()
        result = self.control("close")
        self.assertEqual(result["outcome"], "reconciliation-required")
        self.assertFalse(self.backend.opened)
        self.assertEqual(self.saved()["phase"], "uncertain")
        self.assertEqual(self.saved("pending.json")["phase"], "uncertain")
        self.assertFalse(self.backend.check(self.saved())["ready"])
        self.control("reconcile")
        self.assertEqual(self.saved()["mode"], "closed")
        self.assertEqual(self.saved()["phase"], "stable")
        self.assertIsNone(self.saved("pending.json"))
        self.assertTrue(self.backend.check(self.saved())["ready"])

    def test_boot_with_pending_closes_but_does_not_clear_prior_uncertainty(self):
        self.open()
        self.seed_pending()
        result = controller.control(self.backend, "boot")
        self.assertEqual(result["outcome"], "reconciliation-required")
        self.assertFalse(self.backend.opened)
        self.assertTrue(self.saved("pending.json")["prior_pending"])
        self.control("recover")
        self.assertIsNone(self.saved("pending.json"))
        self.assertEqual(self.saved()["mode"], "closed")

    def test_restored_boot_never_reenables_forwarding_or_recreates_table(self):
        self.prepare()
        self.control("restore-original", acknowledged=True)
        self.backend.commands.clear()
        self.backend.mutations.clear()
        result = controller.control(self.backend, "boot")
        self.assertEqual(result["outcome"], "remains-restored")
        self.assertFalse(self.backend.commands)
        self.assertFalse(self.backend.mutations)
        self.assertIsNone(self.backend.nft)

    def test_restore_requires_closed_and_failure_requires_open_baseline(self):
        self.prepare()
        with self.assertRaisesRegex(RuntimeError, "open baseline"):
            self.control("fail-forwarding", seconds=5)
        self.control("allow-test", acknowledged=True)
        with self.assertRaisesRegex(RuntimeError, "Close before"):
            self.control("restore-original", acknowledged=True)

    def test_bounds_rejected_without_sleep_or_state_change(self):
        for seconds in (-1, 0, 4, 121, 100000):
            with self.subTest(seconds=seconds), self.assertRaisesRegex(ValueError, "5..120"):
                self.control("fail-forwarding", seconds=seconds)
        self.assertFalse(self.backend.commands)
        self.sleep.assert_not_called()

    def test_bounded_forwarding_failure_restores_previous_open_after_sleep(self):
        self.open()
        expected = self.saved()["policy_digest"]
        self.backend.mutations.clear()
        def while_closed(seconds):
            self.assertEqual(seconds, 5)
            self.assertFalse(self.backend.opened)
            self.assertEqual(self.saved()["mode"], "closed")
            self.assertIsNotNone(self.saved("pending.json"))
            self.assertEqual(self.backend.sysctls["net.ipv4.ip_forward"], 1)
        self.sleep.side_effect = while_closed
        result = self.control("fail-forwarding", seconds=5)
        self.sleep.assert_called_once_with(5)
        self.assertEqual(self.backend.mutations, [("nft-policy", False), ("nft-policy", True)])
        self.assertTrue(self.backend.opened)
        self.assertEqual(self.saved()["policy_digest"], expected)
        self.assertIsNone(self.saved("pending.json"))
        rows = self.event_rows(result["evidence_directory"])
        self.assertEqual([row["event"] for row in rows], ["pending-persisted", "forwarding-closed", "prior-open-policy-restored", "verified-before-finalization"])
        self.assertIn("not a crash", rows[1]["conntrack"])
        self.assertIn("no seamless-flow claim", rows[2]["warning"])
        self.assertFalse(any(command[0] == "conntrack" for command in self.backend.commands))

    def test_upper_failure_bound_is_not_extended_by_controller(self):
        self.open()
        self.sleep.side_effect = None
        self.control("fail-forwarding", seconds=120)
        self.sleep.assert_called_once_with(120)
        self.assertTrue(self.backend.opened)

    def test_failure_interval_drift_prevents_restoration_and_closes_uncertain(self):
        self.open()
        def drift(_seconds):
            self.backend.sysctls["net.ipv4.conf.eth0.accept_redirects"] = 1
        self.sleep.side_effect = drift
        with self.assertRaisesRegex(RuntimeError, "Restoration precheck"):
            self.control("fail-forwarding", seconds=5)
        self.assertFalse(self.backend.opened)
        self.uncertain("RuntimeError")

    def test_handled_hup_int_term_close_and_preserve_uncertain_marker(self):
        self.open()
        handlers = {}
        with patch.object(controller.signal, "signal", side_effect=lambda number, handler: handlers.__setitem__(number, handler)):
            controller.install_interrupt_handlers()
        self.assertEqual(set(handlers), {signal.SIGHUP, signal.SIGINT, signal.SIGTERM})
        for signum in handlers:
            with self.subTest(signum=signum):
                self.control("reconcile")
                self.control("allow-test", acknowledged=True)
                self.sleep.side_effect = lambda seconds, sig=signum: handlers[sig](sig, None)
                with self.assertRaises(SystemExit) as caught:
                    self.control("fail-forwarding", seconds=5)
                self.assertEqual(caught.exception.code, 128 + signum)
                self.assertFalse(self.backend.opened)
                self.uncertain("SystemExit")

    def test_keyboard_interrupt_also_uses_fail_closed_path(self):
        self.open()
        self.sleep.side_effect = KeyboardInterrupt("MOCK interrupted sleep")
        with self.assertRaises(KeyboardInterrupt):
            self.control("fail-forwarding", seconds=5)
        self.assertFalse(self.backend.opened)
        self.uncertain("KeyboardInterrupt")

    def test_lock_excludes_control_and_evidence_without_mutation(self):
        self.prepare()
        self.backend.mutations.clear()
        with controller.exclusive_lock():
            for operation in (lambda: self.control("close"), lambda: controller.evidence(self.backend)):
                with self.assertRaisesRegex(RuntimeError, "exclusive lock"):
                    operation()
        self.assertFalse(self.backend.mutations)
        self.control("close")  # Closing the file releases the lock after the context.
        self.assertEqual(self.saved()["mode"], "closed")

    def test_private_state_and_evidence_permissions(self):
        result = self.prepare()
        for file in self.state.rglob("*"):
            if file.is_file():
                self.assertEqual(file.stat().st_mode & 0o777, 0o600, str(file))
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o700)
        self.assertEqual(Path(result["evidence_directory"]).stat().st_mode & 0o777, 0o700)


class FailurePersistenceTests(ControllerCase):
    def test_pending_creation_failure_occurs_before_any_guest_mutation(self):
        self.prepare()
        self.backend.mutations.clear()
        real = controller.atomic_json
        def fail(path, value):
            if Path(path).name == "pending.json":
                raise OSError("MOCK pending creation disk failure")
            return real(path, value)
        with patch.object(controller, "atomic_json", side_effect=fail):
            with self.assertRaisesRegex(OSError, "pending creation"):
                self.control("allow-test", acknowledged=True)
        self.assertFalse(self.backend.mutations)
        self.assertFalse(self.backend.opened)
        self.assertEqual(self.saved()["mode"], "closed")

    def test_event_failure_before_open_attempt_closes_and_marks_uncertain(self):
        self.prepare()
        real = controller.event
        def fail(path, name, **details):
            if name == "pending-persisted":
                raise OSError("MOCK initial event disk failure")
            return real(path, name, **details)
        with patch.object(controller, "event", side_effect=fail):
            with self.assertRaisesRegex(OSError, "initial event"):
                self.control("allow-test", acknowledged=True)
        self.assertFalse(self.backend.opened)
        self.uncertain("OSError")

    def test_state_write_failure_after_open_does_not_leave_open(self):
        self.prepare()
        real = controller.write_state
        def fail(mode, policy=None, phase="stable"):
            if mode == "allow-test" and phase == "stable":
                self.assertTrue(self.backend.opened)
                raise OSError("MOCK open-state disk failure")
            return real(mode, policy, phase)
        with patch.object(controller, "write_state", side_effect=fail):
            with self.assertRaisesRegex(OSError, "open-state"):
                self.control("allow-test", acknowledged=True)
        self.assertFalse(self.backend.opened)
        self.uncertain("OSError")

    def test_event_failure_after_reopen_returns_to_closed_not_success(self):
        self.open()
        self.sleep.side_effect = None
        real = controller.event
        def fail(path, name, **details):
            if name == "prior-open-policy-restored":
                self.assertTrue(self.backend.opened)
                raise OSError("MOCK restored-event disk failure")
            return real(path, name, **details)
        with patch.object(controller, "event", side_effect=fail):
            with self.assertRaisesRegex(OSError, "restored-event"):
                self.control("fail-forwarding", seconds=5)
        self.assertFalse(self.backend.opened)
        self.uncertain("OSError")

    def test_after_snapshot_failure_closes_before_pending_removal(self):
        self.prepare()
        real = controller.snapshot
        def fail(backend, destination=None):
            if destination and Path(destination).name == "after-before-finalization.json":
                raise OSError("MOCK final snapshot disk failure")
            return real(backend, destination)
        with patch.object(controller, "snapshot", side_effect=fail):
            with self.assertRaisesRegex(OSError, "final snapshot"):
                self.control("allow-test", acknowledged=True)
        pending = self.uncertain("OSError")
        self.assertFalse(pending["removal_started"])
        self.assertFalse(self.backend.opened)

    def test_post_action_verification_failure_closes_and_keeps_marker(self):
        self.prepare()
        real = self.backend.check
        def check(state, ignore_pending=False):
            if state["mode"] == "allow-test" and ignore_pending:
                return {"ready": False, "reasons": ["MOCK verification drift"]}
            return real(state, ignore_pending)
        with patch.object(self.backend, "check", side_effect=check):
            with self.assertRaisesRegex(RuntimeError, "Post-action verification"):
                self.control("allow-test", acknowledged=True)
        self.assertFalse(self.backend.opened)
        self.uncertain("RuntimeError")

    def test_marker_unlink_failure_rewrites_uncertain_record(self):
        self.prepare()
        with patch.object(controller, "remove_record", side_effect=OSError("MOCK unlink failure")):
            with self.assertRaisesRegex(OSError, "unlink failure"):
                self.control("allow-test", acknowledged=True)
        pending = self.uncertain("OSError")
        self.assertTrue(pending["removal_started"])
        self.assertFalse(self.backend.opened)

    def test_unlink_then_fsync_failure_recreates_uncertain_marker(self):
        self.prepare()
        def remove_then_fail(path):
            path.unlink()
            raise OSError("MOCK parent fsync failure after unlink")
        with patch.object(controller, "remove_record", side_effect=remove_then_fail):
            with self.assertRaisesRegex(OSError, "after unlink"):
                self.control("allow-test", acknowledged=True)
        pending = self.uncertain("OSError")
        self.assertTrue(pending["removal_started"])
        self.assertTrue(json.loads(self.stderr.getvalue().splitlines()[-1])["marker_write_verified"])

    def test_finalization_marker_rewrite_failure_is_not_all_clear(self):
        self.prepare()
        real = controller.atomic_json
        def atomic(path, value):
            if Path(path).name == "pending.json" and value.get("phase") == "uncertain":
                raise OSError("MOCK marker rewrite failure")
            return real(path, value)
        def remove_then_fail(path):
            path.unlink()
            raise OSError("MOCK fsync after unlink")
        with patch.object(controller, "atomic_json", side_effect=atomic), patch.object(controller, "remove_record", side_effect=remove_then_fail):
            with self.assertRaisesRegex(OSError, "fsync after unlink"):
                self.control("close")
        self.assertIsNone(self.saved("pending.json"))
        self.assertEqual(self.saved()["phase"], "uncertain")
        self.assertFalse(self.backend.check(self.saved())["ready"])
        report = json.loads(self.stderr.getvalue().splitlines()[-1])
        self.assertFalse(report["marker_write_verified"])
        self.assertIn("no all-clear", report["note"])
        self.assertTrue(any("pending write" in value for value in report["recovery_errors"]))

    def test_finalization_cannot_look_ready_if_all_recovery_writes_fail(self):
        self.prepare()
        real_atomic = controller.atomic_json
        real_state = controller.write_state
        def atomic(path, value):
            if Path(path).name == "pending.json" and value.get("phase") == "uncertain":
                raise OSError("MOCK marker rewrite unavailable")
            return real_atomic(path, value)
        def state(mode, policy=None, phase="stable"):
            if phase == "uncertain":
                raise OSError("MOCK uncertain state unavailable")
            return real_state(mode, policy, phase)
        def remove_then_fail(path):
            path.unlink()
            raise OSError("MOCK finalization fsync failed after unlink")
        with patch.object(controller, "atomic_json", side_effect=atomic), patch.object(
            controller, "write_state", side_effect=state
        ), patch.object(controller, "remove_record", side_effect=remove_then_fail):
            with self.assertRaisesRegex(OSError, "finalization fsync"):
                self.control("close")
        self.assertIsNone(self.saved("pending.json"))
        self.assertFalse(self.backend.opened)
        report = json.loads(self.stderr.getvalue().splitlines()[-1])
        self.assertFalse(report["marker_write_verified"])
        self.assertFalse(self.backend.check(self.saved())["ready"],
                         "Durable state must remain non-ready if unlink succeeded but all recovery writes failed")

    def test_post_unlink_stable_write_and_all_recovery_failures_leave_nonready_state(self):
        self.prepare()
        real_atomic = controller.atomic_json
        real_state = controller.write_state
        removal_finished = False
        real_remove = controller.remove_record
        def remove(path):
            nonlocal removal_finished
            real_remove(path)
            removal_finished = True
        def atomic(path, value):
            if Path(path).name == "pending.json" and value.get("phase") == "uncertain":
                raise OSError("MOCK marker rewrite unavailable")
            return real_atomic(path, value)
        def state(mode, policy=None, phase="stable"):
            if removal_finished:
                raise OSError("MOCK all state writes unavailable after removal")
            return real_state(mode, policy, phase)
        with patch.object(controller, "atomic_json", side_effect=atomic), patch.object(
            controller, "write_state", side_effect=state
        ), patch.object(controller, "remove_record", side_effect=remove):
            with self.assertRaisesRegex(OSError, "after removal"):
                self.control("close")
        self.assertIsNone(self.saved("pending.json"))
        self.assertFalse(self.backend.opened)
        self.assertEqual(self.saved()["phase"], "finalizing")
        self.assertFalse(self.backend.check(self.saved())["ready"])

    def test_final_stable_rename_then_fsync_failure_never_returns_success(self):
        # Multiple records are not an atomic transaction. If *all* recovery writes
        # fail after the final state rename, stale-looking files may survive.
        # The call must still raise and emit explicit uncertainty, never success.
        self.prepare()
        real_atomic = controller.atomic_json
        removal_finished = False
        real_remove = controller.remove_record
        def remove(path):
            nonlocal removal_finished
            real_remove(path)
            removal_finished = True
        def atomic(path, value):
            if removal_finished:
                if Path(path).name == "pending.json" or value.get("phase") == "uncertain":
                    raise OSError("MOCK recovery storage unavailable")
                if Path(path).name == "state.json" and value.get("phase") == "stable":
                    real_atomic(path, value)
                    raise OSError("MOCK final state fsync failure after rename")
            return real_atomic(path, value)
        with patch.object(controller, "atomic_json", side_effect=atomic), patch.object(controller, "remove_record", side_effect=remove):
            with self.assertRaisesRegex(OSError, "final state fsync"):
                self.control("close")
        self.assertFalse(self.backend.opened)
        self.assertIsNone(self.saved("pending.json"))
        report = json.loads(self.stderr.getvalue().splitlines()[-1])
        self.assertEqual(report["outcome"], "uncertain")
        self.assertFalse(report["marker_write_verified"])
        self.assertIn("no all-clear", report["note"])
        self.assertTrue(any("state write:" in value for value in report["recovery_errors"]))
        self.assertTrue(any("pending write:" in value for value in report["recovery_errors"]))

    def test_nonstable_phase_alone_blocks_readiness_and_reopening(self):
        self.prepare()
        previous = self.saved()
        for phase in ("pending", "finalizing", "uncertain", "unknown", None):
            with self.subTest(phase=phase):
                controller.atomic_json(self.state / "state.json", {**previous, "phase": phase})
                self.assertFalse(self.backend.check(self.saved())["ready"])
                with self.assertRaisesRegex(RuntimeError, "Preflight"):
                    self.control("allow-test", acknowledged=True)

    def test_failed_emergency_close_sets_unknown_not_closed(self):
        self.prepare()
        with patch.object(controller, "event", side_effect=OSError("MOCK event failure")), patch.object(
            self.backend, "emergency_close", return_value=["MOCK closure not verified"]
        ):
            with self.assertRaisesRegex(OSError, "event failure"):
                self.control("allow-test", acknowledged=True)
        pending = self.uncertain("OSError")
        self.assertEqual(self.saved()["mode"], "unknown")
        self.assertEqual(pending["closure_errors"], ["MOCK closure not verified"])

    def test_exception_from_emergency_close_does_not_hide_original_error(self):
        self.prepare()
        with patch.object(controller, "event", side_effect=OSError("MOCK original failure")), patch.object(
            self.backend, "emergency_close", side_effect=RuntimeError("MOCK closure exception")
        ):
            with self.assertRaisesRegex(OSError, "original failure"):
                self.control("close")
        self.assertEqual(self.saved()["mode"], "unknown")
        self.assertIn("closure exception", self.saved("pending.json")["closure_errors"][0])

    def test_secondary_state_event_snapshot_failures_reported_and_reraise_primary(self):
        self.prepare()
        real_state = controller.write_state
        def write_state(mode, policy=None, phase="stable"):
            if phase == "uncertain":
                raise OSError("MOCK recovery state failure")
            return real_state(mode, policy, phase)
        real_snapshot = controller.snapshot
        def snapshot(backend, destination=None):
            if destination and Path(destination).name == "failure.json":
                raise OSError("MOCK recovery snapshot failure")
            return real_snapshot(backend, destination)
        with patch.object(controller, "write_state", side_effect=write_state), patch.object(
            controller, "event", side_effect=OSError("MOCK event failure")
        ), patch.object(controller, "snapshot", side_effect=snapshot):
            with self.assertRaisesRegex(OSError, "event failure"):
                self.control("allow-test", acknowledged=True)
        self.assertFalse(self.backend.opened)
        report = json.loads(self.stderr.getvalue().splitlines()[-1])
        self.assertTrue(report["marker_write_verified"])
        self.assertTrue(any("state write:" in value for value in report["recovery_errors"]))
        self.assertTrue(any("event write:" in value for value in report["recovery_errors"]))
        self.assertTrue(any("snapshot write:" in value for value in report["recovery_errors"]))
        self.assertFalse(self.backend.check(self.saved())["ready"])


class EvidenceTests(ControllerCase):
    def test_capture_filter_exact_D_all_test_ports_without_expected_source(self):
        expected = "host 20.42.0.10 and tcp and (port 8080 or port 8081 or port 8082)"
        for mode in ("preserve", "firewall_private"):
            backend = FakeKernel({**CONFIG, "source_mode": mode})
            self.assertEqual(controller.capture_filter(backend), expected)
            self.assertNotIn("10.20.1.10", controller.capture_filter(backend))
            self.assertNotIn("10.0.1.0/26", controller.capture_filter(backend))

    def test_capture_bounds_ack_and_root_checked_before_io(self):
        for seconds, packets in ((0, 200), (61, 200), (1, 0), (1, 1001)):
            with self.subTest(seconds=seconds, packets=packets), self.assertRaises(ValueError):
                controller.evidence(self.backend, seconds=seconds, packets=packets)
        with self.assertRaisesRegex(RuntimeError, "acknowledge-sensitive-capture"):
            controller.evidence(self.backend, do_capture=True)
        with patch.object(controller.os, "geteuid", return_value=1000):
            with self.assertRaisesRegex(RuntimeError, "root evidence"):
                controller.evidence(self.backend)
        self.assertFalse(self.backend.commands)
        self.assertFalse(self.state.exists())

    def test_read_only_evidence_queries_only_exact_routes_and_conntrack(self):
        self.prepare()
        self.backend.commands.clear()
        self.backend.mutations.clear()
        before = (self.state / "state.json").read_bytes()
        result = controller.evidence(self.backend)
        self.assertEqual(result["outcome"], "NEEDS_REVIEW")
        out = Path(result["evidence_directory"])
        records = json.loads((out / "read-results.json").read_text())
        self.assertEqual(set(records), {"route-to-D", "route-to-A", "route-to-F", "test-conntrack"})
        route_commands = [command for command in self.backend.commands if command[:3] == ["ip", "-j", "route"]]
        self.assertEqual(route_commands, [["ip", "-j", "route", "get", CONFIG[field]] for field in ("origin_public_ip", "app_ip", "firewall_private_ip")])
        conntrack = [command for command in self.backend.commands if command[0] == "conntrack"]
        self.assertEqual(conntrack, [["conntrack", "-L", "-p", "tcp", "--orig-dst", CONFIG["origin_public_ip"], "-o", "extended"]])
        self.assertFalse(self.backend.mutations)
        self.assertEqual((self.state / "state.json").read_bytes(), before)
        self.assertFalse(json.loads((out / "capture-result.json").read_text())["capture_requested"])
        self.assertFalse((out / "perimeter.pcap").exists())

    def test_mock_capture_has_narrow_filter_private_output_and_dual_bounds(self):
        self.prepare()
        process = Mock()
        process.wait.return_value = 0
        process.poll.return_value = 0
        def popen(args, stdout, stderr):
            Path(args[args.index("-w") + 1]).write_bytes(b"MOCK-PCAP-NOT-PACKET-DATA")
            return process
        with patch.object(controller.subprocess, "Popen", side_effect=popen) as start:
            result = controller.evidence(self.backend, do_capture=True, seconds=7, packets=23, acknowledged=True)
        args = start.call_args.args[0]
        self.assertEqual(args[:9], ["tcpdump", "-n", "-U", "-i", "eth0", "-s", "256", "-c", "23"])
        self.assertEqual(args[-1], controller.capture_filter(self.backend))
        process.wait.assert_called_once_with(timeout=7)
        process.kill.assert_not_called()
        out = Path(result["evidence_directory"])
        self.assertEqual((out / "perimeter.pcap").stat().st_mode & 0o777, 0o600)
        outcome = json.loads((out / "capture-result.json").read_text())
        self.assertEqual((outcome["seconds_limit"], outcome["packet_limit"], outcome["snaplen"]), (7, 23, 256))
        self.assertIn("may contain payload", outcome["scope"])

    def test_mock_capture_timeout_sends_interrupt_then_reaps(self):
        self.prepare()
        process = Mock()
        process.wait.side_effect = [subprocess.TimeoutExpired("MOCK tcpdump", 1), 0]
        process.poll.return_value = 0
        with patch.object(controller.subprocess, "Popen", return_value=process):
            result = controller.evidence(self.backend, True, 1, 1, True)
        process.send_signal.assert_called_once_with(signal.SIGINT)
        self.assertEqual([call.kwargs for call in process.wait.call_args_list], [{"timeout": 1}, {"timeout": 3}])
        process.kill.assert_not_called()
        outcome = json.loads((Path(result["evidence_directory"]) / "capture-result.json").read_text())
        self.assertTrue(outcome["bounded_stop"])

    def test_mock_capture_ignored_interrupt_is_killed_and_reaped(self):
        self.prepare()
        process = Mock()
        process.wait.side_effect = [subprocess.TimeoutExpired("MOCK tcpdump", 1), subprocess.TimeoutExpired("MOCK tcpdump", 3), 0]
        process.poll.return_value = None
        with patch.object(controller.subprocess, "Popen", return_value=process):
            with self.assertRaises(subprocess.TimeoutExpired):
                controller.evidence(self.backend, True, 1, 1, True)
        process.kill.assert_called_once()
        self.assertEqual(process.wait.call_count, 3)
        self.assertEqual(self.saved()["mode"], "closed")
        out = next((self.state / "evidence").iterdir())
        outcome = json.loads((out / "capture-result.json").read_text())
        self.assertEqual(outcome["error_type"], "TimeoutExpired")
        self.assertIn("completed_utc", outcome)
        self.assertTrue((out / "after.json").is_file())

    def test_read_evidence_command_failure_is_recorded_not_hidden(self):
        self.prepare()
        def fail(args):
            if args[0] == "conntrack":
                raise RuntimeError("MOCK conntrack read failure")
        self.backend.fail = fail
        result = controller.evidence(self.backend)
        records = json.loads((Path(result["evidence_directory"]) / "read-results.json").read_text())
        self.assertIn("MOCK conntrack read failure", records["test-conntrack"]["error"])
        self.assertEqual(result["outcome"], "NEEDS_REVIEW")

    def test_retained_read_results_are_bounded_and_mark_truncation(self):
        self.prepare()
        real = self.backend.run
        def run(args, check=True):
            if args[0] == "conntrack":
                return subprocess.CompletedProcess(args, 7, "x" * 70000, "y" * 10000)
            return real(args, check)
        with patch.object(self.backend, "run", side_effect=run):
            result = controller.evidence(self.backend)
        records = json.loads((Path(result["evidence_directory"]) / "read-results.json").read_text())
        row = records["test-conntrack"]
        self.assertEqual(row["exit"], 7)
        self.assertEqual(len(row["stdout"]), 65536)
        self.assertEqual(len(row["stderr"]), 8192)
        self.assertTrue(row["retained_stdout_truncated"])
        self.assertTrue(row["retained_stderr_truncated"])
        self.assertFalse(records["route-to-D"]["retained_stdout_truncated"])

    def test_capture_start_failure_still_persists_error_and_after_snapshot(self):
        self.prepare()
        with patch.object(controller.subprocess, "Popen", side_effect=OSError("MOCK tcpdump unavailable")):
            with self.assertRaisesRegex(OSError, "tcpdump unavailable"):
                controller.evidence(self.backend, True, 1, 1, True)
        out = next((self.state / "evidence").iterdir())
        outcome = json.loads((out / "capture-result.json").read_text())
        self.assertEqual(outcome["error_type"], "OSError")
        self.assertIn("tcpdump unavailable", outcome["error"])
        self.assertIn("completed_utc", outcome)
        self.assertTrue((out / "after.json").is_file())
        self.assertFalse((out / "perimeter.pcap").exists())

    def test_global_test_guards_forbid_commands_and_all_sockets(self):
        with self.assertRaisesRegex(AssertionError, "forbid"):
            subprocess.run(["true"])
        with self.assertRaisesRegex(AssertionError, "forbid"):
            subprocess.Popen(["true"])
        with self.assertRaisesRegex(AssertionError, "forbid"):
            socket.socket()
        with self.assertRaisesRegex(AssertionError, "forbid"):
            socket.getaddrinfo("example.com", 80)


if __name__ == "__main__":
    unittest.main(verbosity=2)
