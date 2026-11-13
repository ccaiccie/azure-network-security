#!/usr/bin/env python3
"""Offline controller tests: temporary files and fakes, never guest/cloud actions.

These tests validate Python control flow and generated text, not FRR/nft syntax,
Linux packet behavior, Azure route programming, or actual failover readiness.
Every Backend operation that can touch a guest is overridden by FakeBackend.
Production methods are exercised explicitly only with their external boundaries
mocked. Global process/network guards fail if a test accidentally escapes them.
"""

import ast
import contextlib
import copy
import fcntl
import importlib.util
import io
import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import types
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("routeserver_controller", ROOT / "guest/controller.py")
controller = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(controller)


def config(role="nva1"):
    return {"role": role,
            "private_ip": {"nva1": "10.0.2.4", "nva2": "10.0.2.5", "remote": "10.30.1.20"}[role],
            "app_ip": "10.10.1.10", "remote_ip": "10.30.1.20",
            "destination_ip": "172.20.50.10", "rs_asn": 65515,
            "rs_peer_ips": ["10.0.1.8", "10.0.1.7"], "frr_version": "10.4.1"}


class FakeBackend(controller.Backend):
    """In-memory guest with a complete override of the production side effects."""

    def __init__(self, role="nva1"):
        super().__init__(config(role))
        self.calls = []
        self.opened = False
        self.exported = False
        self.disabled = set()
        self.sysctls = {"net.ipv4.ip_forward": 0, "net.netfilter.nf_conntrack_tcp_loose": 0}
        scopes = ["all", "default", "eth0"] + (["rs-gre1", "rs-gre2"] if self.remote else [f"rs-gre{self.n}"])
        for scope in scopes:
            for key in ("rp_filter", "accept_redirects", "send_redirects", "accept_source_route"):
                self.sysctls[f"net.ipv4.conf.{scope}.{key}"] = 2 if key == "rp_filter" else 0
        self.ready = True
        self.sessions = True
        self.reasons = ["mock-readiness-failed"]
        self.command_results = {}
        self.config_suffix = ""

    def run(self, args, check=True):
        self.calls.append(("run", list(args), check))
        key = tuple(args)
        if key not in self.command_results:
            raise AssertionError("Unconfigured fake command: " + repr(args))
        result = self.command_results[key]
        if isinstance(result, BaseException):
            raise result
        return subprocess.CompletedProcess(args, result[0], result[1], "")

    def interface(self):
        self.calls.append(("interface",))
        return "eth0"

    def table(self):
        self.calls.append(("table",))
        return {"nftables": [{"table": {"family": "inet", "name": self.table_name}},
                             {"mock_opened": self.opened}]}

    def apply_policy(self, opened):
        self.calls.append(("policy", opened))
        self.opened = opened

    def values(self):
        self.calls.append(("values",))
        return dict(self.sysctls)

    def set_values(self, values, persist=True):
        self.calls.append(("set-values", dict(values), persist))
        self.sysctls = dict(values)
        if persist:
            controller.SYSFILE.write_text("# fake only\n")

    def setup_underlay(self):
        self.calls.append(("underlay",))

    def strict_values(self, opened):
        self.calls.append(("strict", opened))
        self.sysctls = {key: (int(opened and not self.remote) if key == "net.ipv4.ip_forward"
                             else 2 if key.endswith(".rp_filter") else 0)
                        for key in self.sysctls}

    def frr(self, command):
        self.calls.append(("frr", command))
        if command == "show running-config":
            text = controller.frr_config(self.c)
            if self.exported:
                text = text.replace("route-map RS-EXPORT-CLOSED out", "route-map RS-EXPORT-OPEN out")
            return text + "".join(f" neighbor {peer} shutdown\n" for peer in sorted(self.disabled)) + self.config_suffix
        if command == "show version":
            return "FRRouting " + self.c["frr_version"]
        if command.startswith("clear bgp ipv4 unicast "):
            return ""
        raise AssertionError("Unexpected fake FRR command: " + command)

    def configure(self, commands):
        self.calls.append(("configure", list(commands)))

    def exports(self, enabled):
        self.calls.append(("exports", enabled))
        self.exported = enabled

    def shutdown(self, peer, disabled):
        self.calls.append(("shutdown", peer, disabled))
        if peer not in self.c["rs_peer_ips"]:
            raise RuntimeError("Peer not one of actual RS instances")
        self.disabled.add(peer) if disabled else self.disabled.discard(peer)

    def frr_base_check(self):
        self.calls.append(("frr-base-check",))
        return self.frr("show running-config")

    def verify_withdrawn(self):
        self.calls.append(("verify-withdrawn",))
        if self.exported:
            raise RuntimeError("Mock local peer exports remain open")
        return {"local_exports_verified_empty": True,
                "scope": "local-FRR-only-not-Azure-withdrawal-convergence"}

    def tunnel_check(self):
        self.calls.append(("tunnel-check",))

    def summary(self):
        self.calls.append(("summary",))
        return {"ipv4Unicast": {"peers": {peer: {"state": "Established" if self.sessions else "Idle"}
                                         for peer in self.c["rs_peer_ips"]}}}

    def sessions_ready(self):
        self.calls.append(("sessions-ready",))
        return self.sessions

    def checks(self, state, require_sessions=False):
        self.calls.append(("checks", copy.deepcopy(state), require_sessions))
        reasons = []
        if state.get("mode") != "open":
            reasons.append("forwarding-closed")
        if not self.ready:
            reasons.extend(self.reasons)
        if require_sessions and not self.sessions:
            reasons.append("both-RS-sessions-not-established")
        return {"ready": not reasons, "reasons": reasons, "utc": controller.utc()}


class SafeTestCase(unittest.TestCase):
    def setUp(self):
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        temporary = self.stack.enter_context(tempfile.TemporaryDirectory(prefix="rs-controller-unit-"))
        self.root = Path(temporary)
        for name, relative in (("STATE", "state"), ("RUNTIME", "run"),
                               ("FRRCONF", "etc/frr.conf"), ("SYSFILE", "etc/sysctl.conf")):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            self.stack.enter_context(patch.object(controller, name, target))
        self.stack.enter_context(patch.object(controller.os, "geteuid", return_value=0))
        self.stack.enter_context(patch.object(controller.os, "chown", side_effect=AssertionError("Host chown forbidden")))
        for name in ("run", "Popen", "call", "check_call", "check_output"):
            self.stack.enter_context(patch.object(subprocess, name, side_effect=AssertionError("External processes forbidden")))
        self.stack.enter_context(patch.object(os, "system", side_effect=AssertionError("External shell forbidden")))
        self.stack.enter_context(patch.object(socket, "socket", side_effect=AssertionError("Real sockets forbidden")))
        self.stack.enter_context(patch.object(socket, "create_connection", side_effect=AssertionError("Real networking forbidden")))
        self.stack.enter_context(patch.object(controller.http.client, "HTTPConnection", side_effect=AssertionError("Real HTTP forbidden")))
        self.sleep = self.stack.enter_context(patch.object(controller.time, "sleep"))
        self.stdout = self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.b = FakeBackend()

    def control(self, action, **kwargs):
        return controller.control(self.b, action, confirmed=True, **kwargs)

    def state(self):
        return controller.read_json(controller.STATE / "state.json")

    def ready_state(self, exports=True):
        self.b.opened = True
        self.b.exported = exports
        self.b.sysctls["net.ipv4.ip_forward"] = 1
        result = controller.write_state(self.b, "open", exports)
        self.b.calls.clear()
        return result

    def recovery(self, **changes):
        saved = {**self.ready_state(), "sysctls": self.b.values(),
                 "attempt_directory": str(controller.STATE / "experiments" / "pending"),
                 "action": "fail-forwarding", **changes}
        controller.atomic_json(controller.STATE / "recovery.json", saved)
        self.b.calls.clear()
        return saved

    def transition_marker(self, **changes):
        marker = {"node": self.b.role, "action": "advertise", "status": "uncertain",
                  "started_utc": controller.utc(), "error": "mock partial prior change", **changes}
        controller.atomic_json(controller.STATE / "transition.json", marker)
        return marker

    def events(self):
        paths = sorted(controller.STATE.glob("experiments/*/events.jsonl"))
        return [json.loads(line) for path in paths for line in path.read_text().splitlines()]

    def exports(self):
        return [call[1] for call in self.b.calls if call[0] == "exports"]


class GateTests(SafeTestCase):
    def test_status_is_closed_without_mutation_or_root(self):
        with patch.object(controller.os, "geteuid", return_value=1000):
            result = controller.control(self.b, "status")
        self.assertEqual(result["state"], {"mode": "closed", "exports": False})
        self.assertFalse(result["recovery_available"])
        self.assertIn("does not acquire/check", result["note"])
        self.assertEqual(self.b.calls, [])

    def test_mutations_require_explicit_confirmation(self):
        for action in ("prepare", "advertise", "withdraw", "close", "recover", "restore-original", "reconcile",
                       "withdraw-for", "session-down-for", "fail-forwarding"):
            with self.subTest(action=action), self.assertRaisesRegex(RuntimeError, "confirm-guest-change"):
                controller.control(self.b, action)
        self.assertEqual(self.b.calls, [])

    def test_mutations_require_root(self):
        with patch.object(controller.os, "geteuid", return_value=1000):
            with self.assertRaisesRegex(RuntimeError, "require root"):
                self.control("prepare")
        self.assertEqual(self.b.calls, [])

    def test_boot_is_closed_and_renders_deny_all(self):
        with patch("pwd.getpwnam", return_value=types.SimpleNamespace(pw_uid=123)), patch(
            "grp.getgrnam", return_value=types.SimpleNamespace(gr_gid=456)
        ), patch.object(controller.os, "chown") as chown:
            result = controller.control(self.b, "boot")
        self.assertEqual(result, {"boot": "closed-export-deny-all"})
        self.assertEqual(self.b.calls, [("policy", False), ("underlay",), ("strict", False)])
        self.assertFalse(self.state()["exports"])
        self.assertEqual(self.state()["mode"], "closed")
        self.assertEqual(controller.FRRCONF.read_text(), controller.frr_config(self.b.c))
        self.assertEqual(controller.FRRCONF.stat().st_mode & 0o777, 0o640)
        chown.assert_called_once_with(controller.FRRCONF, 123, 456)

    def test_remote_boot_never_configures_bgp_or_opens_forwarding(self):
        self.b = FakeBackend("remote")
        self.control("boot")
        self.assertEqual(self.b.calls, [("policy", False), ("underlay",), ("strict", False)])
        self.assertFalse(controller.FRRCONF.exists())
        self.assertEqual(self.state()["mode"], "closed")
        with self.assertRaisesRegex(RuntimeError, "Remote role"):
            self.control("prepare")

    def test_prepare_withdraws_before_enabling_owned_forwarding(self):
        result = self.control("prepare")
        self.assertEqual(self.b.calls[:6], [("exports", False), ("policy", False), ("underlay",),
                                            ("strict", True), ("frr-base-check",), ("frr", "show running-config")])
        self.assertTrue(self.b.opened)
        self.assertEqual(result["mode"], "open")
        self.assertFalse(result["exports"])
        self.assertEqual(self.exports(), [False])
        self.assertFalse([c for c in self.b.calls if c[0] == "checks"][0][2])

    def test_prepare_readiness_failure_closes_data_and_keeps_export_closed(self):
        self.b.ready = False
        with self.assertRaisesRegex(RuntimeError, "Prepare failed closed"):
            self.control("prepare")
        self.assertFalse(self.b.opened)
        self.assertFalse(self.b.exported)
        self.assertEqual(self.state()["mode"], "uncertain")
        self.assertIsNone(self.state()["exports"])
        self.assertTrue((controller.STATE / "transition.json").exists())

    def test_advertise_refuses_closed_unprepared_state(self):
        with self.assertRaisesRegex(RuntimeError, "Cannot advertise.*forwarding-closed"):
            self.control("advertise")
        self.assertEqual(self.exports(), [])

    def test_advertise_requires_both_sessions_and_readiness(self):
        self.ready_state(exports=False)
        self.b.sessions = False
        with self.assertRaisesRegex(RuntimeError, "both-RS-sessions"):
            self.control("advertise")
        self.assertFalse(self.b.exported)
        self.b.sessions = True
        self.b.ready = False
        with self.assertRaisesRegex(RuntimeError, "mock-readiness-failed"):
            self.control("advertise")
        self.assertFalse(self.b.exported)

    def test_advertise_opens_only_after_checks(self):
        self.ready_state(exports=False)
        result = self.control("advertise")
        self.assertEqual(self.b.calls[0][0], "checks")
        self.assertTrue(self.b.calls[0][2])
        self.assertEqual(self.exports(), [True])
        self.assertTrue(result["exports"])

    def test_withdraw_keeps_forwarding_open(self):
        self.ready_state()
        result = self.control("withdraw")
        self.assertTrue(self.b.opened)
        self.assertFalse(result["exports"])
        self.assertEqual(result["mode"], "open")
        self.assertEqual(self.exports(), [False])
        self.assertFalse(any(c[0] == "policy" for c in self.b.calls))

    def test_close_withdraws_then_closes(self):
        self.ready_state()
        self.control("close")
        self.assertEqual(self.b.calls[:2], [("exports", False), ("policy", False)])
        self.assertEqual(self.state()["mode"], "closed")
        self.assertFalse(self.state()["exports"])

    def test_close_closes_data_even_when_bgp_withdrawal_raises(self):
        self.ready_state()
        with patch.object(self.b, "exports", side_effect=RuntimeError("mock FRR unavailable")):
            with self.assertRaisesRegex(RuntimeError, "FRR unavailable"):
                self.control("close")
        self.assertFalse(self.b.opened)

    def test_readonly_check_does_not_need_confirmation_or_root(self):
        with patch.object(controller.os, "geteuid", return_value=1000):
            result = controller.control(self.b, "check")
        self.assertFalse(result["ready"])
        self.assertEqual(len(self.b.calls), 1)
        self.assertEqual(self.b.calls[0][0], "checks")
        self.assertTrue(self.b.calls[0][2])


class RecoveryTests(SafeTestCase):
    def test_all_bounded_actions_restore_exact_saved_state_without_sleeping(self):
        for action in ("withdraw-for", "session-down-for", "fail-forwarding"):
            with self.subTest(action=action):
                initial = self.ready_state()
                original_values = dict(self.b.sysctls)
                result = self.control(action, seconds=5, peer=self.b.c["rs_peer_ips"][0])
                self.assertEqual(result, {"restored_recorded_state": True})
                self.assertTrue(self.b.opened)
                self.assertTrue(self.b.exported)
                self.assertEqual(self.b.sysctls, original_values)
                self.assertEqual(self.b.disabled, set())
                self.assertEqual(self.state()["policy_digest"], initial["policy_digest"])
                self.assertEqual(self.state()["frr_digest"], initial["frr_digest"])
                self.assertFalse((controller.STATE / "recovery.json").exists())
                self.assertEqual(self.exports(), [False, True] if action == "withdraw-for" else [])
        self.assertEqual(self.sleep.call_count, 3)

    def test_failure_interval_keeps_bgp_exports_and_sessions_alive(self):
        self.ready_state()
        def during(seconds):
            self.assertEqual(seconds, 7)
            self.assertFalse(self.b.opened)
            self.assertTrue(self.b.exported)
            self.assertEqual(self.b.disabled, set())
            self.assertEqual(self.state()["mode"], "closed")
            self.assertTrue(self.state()["exports"])
            self.assertTrue((controller.STATE / "recovery.json").exists())
        self.sleep.side_effect = during
        self.control("fail-forwarding", seconds=7)
        self.assertEqual(self.exports(), [])

    def test_withdraw_interval_does_not_close_data_plane(self):
        self.ready_state()
        def during(_):
            self.assertTrue(self.b.opened)
            self.assertFalse(self.b.exported)
            self.assertEqual(self.b.disabled, set())
        self.sleep.side_effect = during
        self.control("withdraw-for", seconds=5)

    def test_session_action_only_disables_selected_actual_peer(self):
        self.ready_state()
        peer = self.b.c["rs_peer_ips"][1]
        def during(_):
            self.assertEqual(self.b.disabled, {peer})
            self.assertTrue(self.b.opened)
            self.assertTrue(self.b.exported)
            self.assertEqual(self.state()["disabled_peers"], [peer])
        self.sleep.side_effect = during
        self.control("session-down-for", seconds=5, peer=peer)
        self.assertEqual([c for c in self.b.calls if c[0] == "shutdown" and c[2]], [("shutdown", peer, True)])
        self.assertEqual(self.exports(), [])

    def test_peer_selection_rejects_guessed_other_and_missing_ips(self):
        self.ready_state()
        for peer in (None, "10.0.1.4", "10.0.2.4", "::1", "10.0.1.8; reboot"):
            with self.subTest(peer=peer), self.assertRaisesRegex(RuntimeError, "exact actual RS peer"):
                self.control("session-down-for", seconds=5, peer=peer)
        self.sleep.assert_not_called()
        self.assertFalse((controller.STATE / "recovery.json").exists())
        self.assertFalse(any(c[0] == "shutdown" for c in self.b.calls))

    def test_duration_bounds_rejected_before_experiment(self):
        self.ready_state()
        for seconds in (-1, 0, 4, 121, 10000):
            with self.subTest(seconds=seconds), self.assertRaisesRegex(RuntimeError, "Bounded interval"):
                self.control("fail-forwarding", seconds=seconds)
        self.assertEqual(self.b.calls, [])
        self.assertFalse((controller.STATE / "recovery.json").exists())

    def test_experiment_needs_advertised_open_state_and_both_sessions(self):
        self.ready_state(exports=False)
        with self.assertRaisesRegex(RuntimeError, "requires verified"):
            self.control("fail-forwarding", seconds=5)
        self.ready_state()
        self.b.sessions = False
        with self.assertRaisesRegex(RuntimeError, "requires verified"):
            self.control("fail-forwarding", seconds=5)
        self.sleep.assert_not_called()

    def test_interrupt_restores_state_then_propagates_exit(self):
        self.ready_state()
        self.sleep.side_effect = SystemExit(128 + signal.SIGTERM)
        with self.assertRaises(SystemExit) as caught:
            self.control("fail-forwarding", seconds=5)
        self.assertEqual(caught.exception.code, 143)
        self.assertTrue(self.b.opened)
        self.assertTrue(self.b.exported)
        self.assertFalse((controller.STATE / "recovery.json").exists())
        rows = self.events()
        self.assertEqual([r["event"] for r in rows], ["fail-forwarding-start", "fail-forwarding-restored"])
        self.assertEqual(rows[1]["interruption"], "SystemExit")

    def test_body_exception_restores_state_and_preserves_original_error(self):
        self.ready_state()
        self.sleep.side_effect = RuntimeError("mock experiment failure")
        with self.assertRaisesRegex(RuntimeError, "mock experiment failure"):
            self.control("withdraw-for", seconds=5)
        self.assertTrue(self.b.opened)
        self.assertTrue(self.b.exported)
        self.assertFalse((controller.STATE / "recovery.json").exists())
        self.assertEqual(self.events()[-1]["interruption"], "RuntimeError")

    def test_failed_restoration_readiness_withdraws_and_retains_marker(self):
        self.ready_state()
        self.sleep.side_effect = lambda _: setattr(self.b, "ready", False)
        with self.assertRaisesRegex(RuntimeError, "Restoration keeps exports withdrawn"):
            self.control("fail-forwarding", seconds=5)
        self.assertFalse(self.b.exported)
        self.assertFalse(self.state()["exports"])
        self.assertTrue((controller.STATE / "recovery.json").exists())
        self.assertEqual(self.events()[-1]["event"], "fail-forwarding-restore-failed")
        self.assertIn("mock-readiness-failed", self.events()[-1]["error"])

    def test_failure_events_have_parseable_ordered_utc_timestamps(self):
        self.ready_state()
        self.sleep.side_effect = lambda _: setattr(self.b, "ready", False)
        with self.assertRaises(RuntimeError):
            self.control("fail-forwarding", seconds=5)
        rows = self.events()
        stamps = [datetime.fromisoformat(row["utc"]) for row in rows]
        self.assertEqual(len(stamps), 2)
        self.assertTrue(all(stamp.utcoffset() == timezone.utc.utcoffset(stamp) for stamp in stamps))
        self.assertLessEqual(stamps[0], stamps[1])
        self.assertTrue(all(row["node"] == "nva1" for row in rows))

    def test_pending_recovery_blocks_reopening_baseline_change_and_overlap(self):
        self.recovery()
        for action in ("prepare", "advertise", "restore-original", "withdraw-for", "session-down-for", "fail-forwarding"):
            with self.subTest(action=action), self.assertRaisesRegex(RuntimeError, "Pending recovery"):
                self.control(action, seconds=5, peer=self.b.c["rs_peer_ips"][0])
        self.assertEqual(self.b.calls, [])

    def test_pending_recovery_still_allows_withdraw_and_emergency_close(self):
        self.recovery()
        self.control("withdraw")
        self.control("close")
        self.assertFalse(self.b.opened)
        self.assertFalse(self.b.exported)
        self.assertTrue((controller.STATE / "recovery.json").exists())

    def test_manual_recovery_withdraws_first_checks_and_reopens_last(self):
        self.recovery()
        self.b.opened = False
        result = self.control("recover")
        self.assertEqual(self.b.calls[0], ("exports", False))
        self.assertEqual(self.exports(), [False, True])
        index = [c[0] for c in self.b.calls].index("checks")
        self.assertTrue(any(c == ("exports", True) for c in self.b.calls[index + 1:]))
        self.assertFalse(self.b.calls[index][2])
        self.assertTrue(result["exports"])
        self.assertFalse((controller.STATE / "recovery.json").exists())
        self.assertEqual(self.events()[-1]["event"], "manual-recovered")

    def test_manual_recovery_failure_remains_withdrawn_and_pending(self):
        self.recovery()
        self.b.ready = False
        with self.assertRaisesRegex(RuntimeError, "Restoration keeps exports withdrawn"):
            self.control("recover")
        self.assertFalse(self.b.exported)
        self.assertTrue((controller.STATE / "recovery.json").exists())

    def test_early_restoration_failure_attempts_withdraw_and_close(self):
        self.ready_state()
        with patch.object(self.b, "setup_underlay", side_effect=RuntimeError("mock route restoration failed")):
            with self.assertRaisesRegex(RuntimeError, "mock route restoration failed"):
                self.control("fail-forwarding", seconds=5)
        self.assertEqual(self.exports(), [False])
        self.assertFalse(self.b.opened)
        self.assertFalse(self.b.exported)
        self.assertEqual(self.state()["mode"], "closed")
        self.assertFalse(self.state()["exports"])
        self.assertTrue((controller.STATE / "recovery.json").exists())
        self.assertEqual(self.events()[-1]["event"], "fail-forwarding-restore-failed")

    def test_each_restoration_stage_failure_runs_both_safety_actions(self):
        for method in ("setup_underlay", "set_values", "shutdown"):
            with self.subTest(method=method):
                saved = self.recovery()
                with patch.object(self.b, method, side_effect=RuntimeError("mock failed " + method)):
                    with self.assertRaisesRegex(RuntimeError, "mock failed " + method):
                        controller.restore(self.b, saved, live=True)
                self.assertFalse(self.b.exported)
                self.assertFalse(self.b.opened)
                self.assertIn(("exports", False), self.b.calls)
                self.assertIn(("policy", False), self.b.calls)
                self.assertTrue((controller.STATE / "recovery.json").exists())

    def test_failed_open_policy_restore_still_attempts_closed_policy(self):
        saved = self.recovery()
        apply_policy = self.b.apply_policy
        def policy(opened):
            if opened:
                raise RuntimeError("mock cannot reopen table")
            return apply_policy(opened)
        with patch.object(self.b, "apply_policy", side_effect=policy):
            with self.assertRaisesRegex(RuntimeError, "cannot reopen table"):
                controller.restore(self.b, saved, live=True)
        self.assertFalse(self.b.exported)
        self.assertFalse(self.b.opened)
        self.assertEqual(self.state()["mode"], "closed")

    def test_failed_safety_actions_record_uncertainty_without_claiming_closed(self):
        saved = self.recovery()
        with patch.object(self.b, "setup_underlay", side_effect=RuntimeError("mock route failure")), patch.object(
            self.b, "exports", side_effect=RuntimeError("mock FRR unavailable")
        ) as withdraw, patch.object(self.b, "apply_policy", side_effect=RuntimeError("mock nft unavailable")) as close:
            with self.assertRaisesRegex(RuntimeError, "mock route failure"):
                controller.restore(self.b, saved, live=True)
        withdraw.assert_called_once_with(False)
        close.assert_called_once_with(False)
        state = self.state()
        self.assertEqual(state["mode"], "uncertain")
        self.assertIsNone(state["exports"])
        self.assertEqual(state["recovery_safety_errors"], ["withdraw:mock FRR unavailable", "close:mock nft unavailable"])
        self.assertTrue((controller.STATE / "recovery.json").exists())

    def test_failed_withdraw_does_not_prevent_successful_emergency_data_close(self):
        saved = self.recovery()
        with patch.object(self.b, "setup_underlay", side_effect=RuntimeError("mock route failure")), patch.object(
            self.b, "exports", side_effect=RuntimeError("mock FRR unavailable")
        ):
            with self.assertRaises(RuntimeError):
                controller.restore(self.b, saved, live=True)
        self.assertFalse(self.b.opened)
        self.assertEqual(self.state()["mode"], "closed")
        self.assertIsNone(self.state()["exports"])
        self.assertTrue((controller.STATE / "recovery.json").exists())

    def test_recover_rejects_other_node_before_guest_actions(self):
        self.recovery(node="nva2")
        with self.assertRaisesRegex(RuntimeError, "matching pending recovery"):
            self.control("recover")
        self.assertEqual(self.b.calls, [])
        self.assertTrue((controller.STATE / "recovery.json").exists())

    def test_recover_without_marker_is_not_success(self):
        with self.assertRaisesRegex(RuntimeError, "No matching pending recovery"):
            self.control("recover")

    def test_live_restore_preserves_recorded_disabled_peer_and_sysctls(self):
        saved = self.recovery(disabled_peers=[self.b.c["rs_peer_ips"][0]])
        self.b.opened = False
        result = controller.restore(self.b, saved, live=True)
        self.assertEqual(self.b.disabled, set(saved["disabled_peers"]))
        self.assertEqual(self.b.sysctls, saved["sysctls"])
        self.assertEqual(result["disabled_peers"], saved["disabled_peers"])
        self.assertEqual(self.exports(), [])

    def test_held_lock_blocks_close_without_claiming_success(self):
        self.ready_state()
        controller.RUNTIME.mkdir(parents=True)
        with (controller.RUNTIME / "control.lock").open("a") as held:
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(BlockingIOError):
                self.control("close")
            self.assertEqual(self.b.calls, [])
            status = self.control("status")
            self.assertIn("does not acquire/check", status["note"])
            self.assertTrue(status["state"]["exports"])
        self.control("close")
        self.assertFalse(self.b.opened)

    def test_restore_original_is_scoped_and_removes_owned_persistence(self):
        self.ready_state()
        original = {key: 1 for key in self.b.sysctls}
        controller.atomic_json(controller.STATE / "original-sysctl.json", {"node": "nva1", "values": original})
        controller.SYSFILE.write_text("owned configuration")
        self.control("restore-original")
        self.assertEqual(self.b.calls[:3], [("exports", False), ("policy", False), ("set-values", original, False)])
        self.assertFalse(controller.SYSFILE.exists())
        self.assertEqual(self.state()["mode"], "closed")

    def test_restore_original_rejects_wrong_node(self):
        controller.atomic_json(controller.STATE / "original-sysctl.json", {"node": "nva2", "values": {}})
        with self.assertRaisesRegex(RuntimeError, "matching original"):
            self.control("restore-original")
        self.assertEqual(self.b.calls, [])
        self.assertFalse((controller.STATE / "transition.json").exists())


class TransitionTests(SafeTestCase):
    def test_marker_is_durable_before_first_guest_mutation_and_cleared_on_success(self):
        self.ready_state()
        exports = self.b.exports
        observed = []
        def guarded(enabled):
            marker = controller.read_json(controller.STATE / "transition.json")
            self.assertEqual(marker["status"], "pending")
            self.assertEqual(marker["action"], "withdraw")
            self.assertEqual(marker["node"], "nva1")
            self.assertTrue(marker["last_recorded_intent"]["exports"])
            observed.append(marker)
            exports(enabled)
        with patch.object(self.b, "exports", side_effect=guarded):
            self.control("withdraw")
        self.assertEqual(len(observed), 1)
        self.assertFalse((controller.STATE / "transition.json").exists())

    def test_marker_write_failure_prevents_all_guest_mutation(self):
        self.ready_state()
        atomic_json = controller.atomic_json
        def write(path, value, *args, **kwargs):
            if Path(path).name == "transition.json":
                raise OSError("mock marker storage unavailable")
            return atomic_json(path, value, *args, **kwargs)
        with patch.object(controller, "atomic_json", side_effect=write):
            with self.assertRaisesRegex(OSError, "marker storage unavailable"):
                self.control("close")
        self.assertEqual(self.b.calls, [])
        self.assertTrue(self.b.opened)
        self.assertTrue(self.b.exported)

    def test_partial_peer_advertise_failure_attempts_withdraw_and_keeps_uncertainty(self):
        self.ready_state(exports=False)
        peers = {peer: False for peer in self.b.c["rs_peer_ips"]}
        calls = []
        def partial(enabled):
            calls.append(enabled)
            self.assertTrue((controller.STATE / "transition.json").exists())
            if enabled:
                peers[self.b.c["rs_peer_ips"][0]] = True
                self.b.exported = True
                raise RuntimeError("mock second peer export failure")
            for peer in peers:
                peers[peer] = False
            self.b.exported = False
        with patch.object(self.b, "exports", side_effect=partial):
            with self.assertRaisesRegex(RuntimeError, "second peer export failure"):
                self.control("advertise")
        self.assertEqual(calls, [True, False])
        self.assertFalse(any(peers.values()))
        self.assertFalse(self.b.opened)
        self.assertEqual(self.state()["mode"], "uncertain")
        self.assertIsNone(self.state()["exports"])
        marker = controller.read_json(controller.STATE / "transition.json")
        self.assertEqual(marker["status"], "uncertain")
        self.assertTrue(marker["withdraw_command_succeeded"])
        self.assertTrue(marker["close_command_succeeded"])
        self.assertIn("not observed", marker["note"])

    def test_partial_peer_failure_with_failed_safety_withdraw_never_claims_withdrawn(self):
        self.ready_state(exports=False)
        def partial(enabled):
            self.b.exported = True
            raise RuntimeError("mock partial open" if enabled else "mock withdrawal unavailable")
        with patch.object(self.b, "exports", side_effect=partial):
            with self.assertRaisesRegex(RuntimeError, "mock partial open"):
                self.control("advertise")
        self.assertTrue(self.b.exported)
        self.assertFalse(self.b.opened)
        self.assertIsNone(self.state()["exports"])
        marker = controller.read_json(controller.STATE / "transition.json")
        self.assertFalse(marker["withdraw_command_succeeded"])
        self.assertTrue(marker["close_command_succeeded"])
        self.assertEqual(marker["safety_errors"], ["withdraw:mock withdrawal unavailable"])

    def test_state_write_failure_after_mutation_keeps_marker_and_attempts_safety(self):
        self.ready_state(exports=False)
        with patch.object(controller, "write_state", side_effect=OSError("mock state persistence failed")):
            with self.assertRaisesRegex(OSError, "state persistence failed"):
                self.control("advertise")
        self.assertEqual(self.exports(), [True, False])
        self.assertFalse(self.b.opened)
        self.assertFalse(self.b.exported)
        self.assertTrue((controller.STATE / "transition.json").exists())
        self.assertEqual(self.state()["mode"], "uncertain")
        self.assertIsNone(self.state()["exports"])

    def test_ordinary_interrupt_keeps_marker_and_propagates_exit_after_safety(self):
        self.ready_state(exports=False)
        exports = self.b.exports
        def interrupted(enabled):
            if enabled:
                raise SystemExit(128 + signal.SIGINT)
            return exports(enabled)
        with patch.object(self.b, "exports", side_effect=interrupted):
            with self.assertRaises(SystemExit) as caught:
                self.control("advertise")
        self.assertEqual(caught.exception.code, 130)
        self.assertFalse(self.b.opened)
        self.assertFalse(self.b.exported)
        self.assertEqual(controller.read_json(controller.STATE / "transition.json")["status"], "uncertain")

    def test_ordinary_failure_marker_has_ordered_utc_event_times(self):
        self.ready_state(exports=False)
        with patch.object(controller, "write_state", side_effect=OSError("mock final state failure")):
            with self.assertRaises(OSError):
                self.control("advertise")
        marker = controller.read_json(controller.STATE / "transition.json")
        start = datetime.fromisoformat(marker["started_utc"])
        end = datetime.fromisoformat(marker["completed_utc"])
        self.assertEqual(start.utcoffset(), timezone.utc.utcoffset(start))
        self.assertEqual(end.utcoffset(), timezone.utc.utcoffset(end))
        self.assertLessEqual(start, end)

    def test_failure_to_update_marker_retains_original_pending_marker(self):
        self.ready_state(exports=False)
        atomic_json = controller.atomic_json
        marker_writes = []
        def write(path, value, *args, **kwargs):
            if Path(path).name == "transition.json":
                marker_writes.append(value)
                if len(marker_writes) > 1:
                    raise OSError("mock follow-on marker failure")
            return atomic_json(path, value, *args, **kwargs)
        with patch.object(controller, "atomic_json", side_effect=write), patch.object(
            controller, "write_state", side_effect=OSError("mock state write failure")
        ), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaisesRegex(OSError, "mock state write failure"):
                self.control("advertise")
        marker = controller.read_json(controller.STATE / "transition.json")
        self.assertEqual(marker["status"], "pending")
        self.assertEqual(marker["action"], "advertise")
        self.assertFalse(self.b.opened)
        self.assertFalse(self.b.exported)

    def test_pending_transition_blocks_reopening_experiments_and_recovery(self):
        self.ready_state()
        marker = self.transition_marker()
        for action in ("prepare", "advertise", "restore-original", "recover", "withdraw-for",
                       "session-down-for", "fail-forwarding"):
            with self.subTest(action=action), self.assertRaisesRegex(RuntimeError, "ordinary transition"):
                self.control(action, seconds=5, peer=self.b.c["rs_peer_ips"][0])
        self.assertEqual(self.b.calls, [])
        self.assertEqual(controller.read_json(controller.STATE / "transition.json"), marker)

    def test_successful_close_and_withdraw_do_not_clear_prior_uncertainty(self):
        self.ready_state()
        original = self.transition_marker()
        for action in ("withdraw", "close"):
            with self.subTest(action=action):
                self.control(action)
                marker = controller.read_json(controller.STATE / "transition.json")
                self.assertEqual(marker["status"], "needs-reconciliation")
                self.assertEqual(marker["previous_unresolved"], original)
                original = marker
        self.assertFalse(self.b.opened)
        self.assertFalse(self.b.exported)

    def test_foreign_transition_record_rejected_without_mutation_or_replacement(self):
        self.ready_state()
        marker = self.transition_marker(node="nva2")
        for action in ("withdraw", "close", "reconcile"):
            with self.subTest(action=action), self.assertRaisesRegex(RuntimeError, "another node"):
                self.control(action)
        self.assertEqual(self.b.calls, [])
        self.assertEqual(controller.read_json(controller.STATE / "transition.json"), marker)

    def test_status_labels_last_intent_and_reports_pending_marker_without_checking(self):
        self.ready_state()
        marker = self.transition_marker()
        result = self.control("status")
        self.assertEqual(result["transition"], marker)
        self.assertIn("last recorded intent", result["note"])
        self.assertIn("NOT observed", result["note"])
        self.assertEqual(self.b.calls, [])

    def test_readonly_check_fails_for_both_independent_pending_markers(self):
        self.recovery()
        self.transition_marker()
        result = self.control("check")
        self.assertFalse(result["ready"])
        self.assertIn("pending-transition.json", result["reasons"])
        self.assertIn("pending-recovery.json", result["reasons"])
        self.assertTrue((controller.STATE / "transition.json").exists())
        self.assertTrue((controller.STATE / "recovery.json").exists())

    def test_reconcile_withdraws_and_closes_before_verification_and_marker_removal(self):
        self.ready_state()
        self.transition_marker()
        verify = self.b.verify_withdrawn
        def checked():
            self.assertFalse(self.b.exported)
            self.assertFalse(self.b.opened)
            self.assertTrue((controller.STATE / "transition.json").exists())
            return verify()
        with patch.object(self.b, "verify_withdrawn", side_effect=checked):
            result = self.control("reconcile")
        self.assertEqual(self.b.calls[:3], [("exports", False), ("policy", False), ("verify-withdrawn",)])
        self.assertEqual(result["mode"], "closed")
        self.assertFalse(result["exports"])
        self.assertTrue(result["local_exports_verified_empty"])
        self.assertIn("not-Azure-withdrawal-convergence", result["scope"])
        self.assertFalse((controller.STATE / "transition.json").exists())

    def test_reconcile_preserves_independent_bounded_recovery_record_exactly(self):
        saved = self.recovery()
        self.transition_marker()
        self.control("reconcile")
        self.assertFalse((controller.STATE / "transition.json").exists())
        self.assertEqual(controller.read_json(controller.STATE / "recovery.json"), saved)
        with self.assertRaisesRegex(RuntimeError, "Pending recovery"):
            self.control("prepare")

    def test_reconcile_verification_failure_keeps_marker_and_uncertain_state(self):
        self.ready_state()
        original = self.transition_marker()
        with patch.object(self.b, "verify_withdrawn", side_effect=RuntimeError("mock peer advertisements still present")):
            with self.assertRaisesRegex(RuntimeError, "advertisements still present"):
                self.control("reconcile")
        marker = controller.read_json(controller.STATE / "transition.json")
        self.assertEqual(marker["status"], "uncertain")
        self.assertEqual(marker["previous_unresolved"], original)
        self.assertEqual(self.state()["mode"], "uncertain")
        self.assertIsNone(self.state()["exports"])
        self.assertFalse(self.b.opened)

    def test_reconcile_state_persistence_failure_does_not_clear_marker(self):
        self.ready_state()
        self.transition_marker()
        with patch.object(controller, "write_state", side_effect=OSError("mock reconciliation state write failure")):
            with self.assertRaisesRegex(OSError, "reconciliation state write failure"):
                self.control("reconcile")
        self.assertTrue((controller.STATE / "transition.json").exists())
        self.assertEqual(self.state()["mode"], "uncertain")

    def test_reconcile_marker_removal_failure_keeps_uncertain_marker(self):
        self.ready_state()
        self.transition_marker()
        unlink = Path.unlink
        def fail_marker(path, *args, **kwargs):
            if path == controller.STATE / "transition.json":
                raise OSError("mock marker removal failure")
            return unlink(path, *args, **kwargs)
        with patch.object(Path, "unlink", fail_marker):
            with self.assertRaisesRegex(OSError, "marker removal failure"):
                self.control("reconcile")
        self.assertEqual(controller.read_json(controller.STATE / "transition.json")["status"], "uncertain")
        self.assertEqual(self.state()["mode"], "uncertain")

    def test_reconcile_without_prior_marker_still_verifies_and_closes(self):
        self.ready_state()
        result = self.control("reconcile")
        self.assertTrue(result["local_exports_verified_empty"])
        self.assertFalse(self.b.opened)
        self.assertFalse(self.b.exported)
        self.assertFalse((controller.STATE / "transition.json").exists())


class RenderingTests(SafeTestCase):
    def test_frr_exact_prefix_control_policy_and_versioned_path_preference(self):
        primary = controller.frr_config(config())
        backup = controller.frr_config(config("nva2"))
        for text in (primary, backup):
            self.assertEqual(text.count("  network 172.20.50.0/24\n"), 1)
            self.assertIn("ip prefix-list RS-EXACT seq 10 permit 172.20.50.0/24\n", text)
            self.assertIn("ip prefix-list RS-IN-DENY seq 10 deny 0.0.0.0/0 le 32\n", text)
            for required in ("bgp no-rib", "bgp network import-check", "no bgp graceful-restart",
                             "route-map RS-EXPORT-CLOSED deny 10", "route-map RS-EXPORT-OPEN deny 100"):
                self.assertIn(required, text)
            for forbidden in ("redistribute ", "default-originate", "aggregate-address", "--no_zebra"):
                self.assertNotIn(forbidden, text)
        self.assertNotIn("set as-path", primary)
        self.assertEqual(backup.count(" set as-path prepend 65010 65010\n"), 1)
        # Ordinary eBGP adds the third ASN; no runtime observed-path claim here.
        self.assertNotIn("set as-path prepend 65010 65010 65010", backup)

    def test_frr_peers_are_sorted_actual_ips_and_export_closed(self):
        text = controller.frr_config(config())
        self.assertLess(text.index("neighbor 10.0.1.7 remote-as"), text.index("neighbor 10.0.1.8 remote-as"))
        for peer in config()["rs_peer_ips"]:
            for line in (f"neighbor {peer} remote-as 65515", f"neighbor {peer} ebgp-multihop 255",
                         f"neighbor {peer} update-source 10.0.2.4", f"neighbor {peer} timers 60 180",
                         f"neighbor {peer} prefix-list RS-IN-DENY in",
                         f"neighbor {peer} route-map RS-EXPORT-CLOSED out",
                         f"neighbor {peer} maximum-prefix 20 force", f"neighbor {peer} maximum-prefix-out 1"):
                self.assertIn(line, text)
        self.assertNotIn("route-map RS-EXPORT-OPEN out", text)

    def test_nft_open_filter_uses_original_source_and_reverse_restored_tuple(self):
        text = controller.nft_source(config(), True)
        forwarding = text.split(" chain forward", 1)[1].split(" chain postrouting", 1)[0]
        self.assertIn('oifname "rs-gre1" ip saddr 10.10.1.10 ip daddr 172.20.50.10 tcp dport 8080', forwarding)
        self.assertIn('ct state new tcp flags & (fin | syn | rst | ack) == syn counter accept', forwarding)
        self.assertIn('iifname "rs-gre1" ip saddr 172.20.50.10 ip daddr 10.10.1.10 tcp sport 8080 ct state established', forwarding)
        self.assertNotIn("10.255.1.1", forwarding)
        self.assertNotIn("ct state related,established accept", forwarding)
        self.assertNotIn("ct state established accept", forwarding)
        self.assertIn("tcp option maxseg size set 1360", forwarding)

    def test_nft_snat_is_per_node_exact_original_flow_only(self):
        for role, n in (("nva1", 1), ("nva2", 2)):
            text = controller.nft_source(config(role), True)
            snat = [line.strip() for line in text.splitlines() if "snat ip" in line]
            self.assertEqual(snat, [f'oifname "rs-gre{n}" ip saddr 10.10.1.10 ip daddr 172.20.50.10 tcp dport 8080 counter snat ip to 10.255.{n}.1 comment "scoped-overlay-snat"'])
            self.assertNotIn("dnat", text)
            self.assertNotIn("masquerade", text)

    def test_closed_policy_has_no_forward_accept_but_preserves_control(self):
        text = controller.nft_source(config(), False)
        forward = text.split(" chain forward", 1)[1].split(" chain postrouting", 1)[0]
        self.assertNotIn("accept", forward)
        self.assertIn("policy drop", forward)
        self.assertIn('comment "deny-alternate-8081"', forward)
        self.assertIn("tcp dport 179 accept", text)
        self.assertIn("ip protocol gre accept", text)

    def test_8081_named_deny_precedes_every_forward_allow(self):
        text = controller.nft_source(config(), True)
        self.assertLess(text.index('comment "deny-alternate-8081"'), text.index('comment "allow-new-syn-8080"'))
        self.assertIn('counter drop comment "drop-other-forward"', text)

    def test_remote_input_is_exact_per_overlay_and_has_no_forward_allow_or_snat(self):
        text = controller.nft_source(config("remote"), True)
        for n in (1, 2):
            self.assertIn(f'ip saddr 10.0.2.{n + 3} ip daddr 10.30.1.20 ip protocol gre accept', text)
            self.assertIn(f'iifname "rs-gre{n}" ip saddr 10.255.{n}.1 ip daddr 172.20.50.10 tcp dport {{ 8080, 8081 }} accept', text)
        self.assertNotIn("snat", text)
        self.assertNotIn("accept", text.split(" chain forward", 1)[1])

    def test_nva_decapsulated_input_allows_only_scoped_readiness_replies(self):
        for role, n in (("nva1", 1), ("nva2", 2)):
            for opened in (False, True):
                with self.subTest(role=role, opened=opened):
                    text = controller.nft_source(config(role), opened)
                    incoming = text.split(" chain input", 1)[1].split(" chain forward", 1)[0]
                    allowed = f'iifname "rs-gre{n}" ip saddr 172.20.50.10 ip daddr 10.255.{n}.1 tcp sport {{ 8080, 8081 }} ct state established accept comment "local-tunnel-readiness-reply"'
                    denied = f'iifname "rs-gre{n}" counter drop comment "deny-other-decapsulated-input"'
                    self.assertIn(allowed, incoming)
                    self.assertLess(incoming.index(allowed), incoming.index(denied))
                    self.assertLess(incoming.index(denied), incoming.index("ip protocol gre accept"))
                    self.assertLess(incoming.index(denied), incoming.index("tcp dport 179 accept"))
                    self.assertNotIn("tcp dport 22 accept", incoming)
                    self.assertEqual(len([line for line in incoming.splitlines() if f'iifname "rs-gre{n}"' in line and "accept" in line]), 1)

    def test_remote_decapsulated_input_deny_precedes_outer_gre_and_host_allows(self):
        text = controller.nft_source(config("remote"), False)
        incoming = text.split(" chain input", 1)[1].split(" chain forward", 1)[0]
        denied = 'iifname { "rs-gre1", "rs-gre2" } counter drop comment "deny-other-decapsulated-input"'
        self.assertIn(denied, incoming)
        for n in (1, 2):
            allowed = f'iifname "rs-gre{n}" ip saddr 10.255.{n}.1 ip daddr 172.20.50.10 tcp dport {{ 8080, 8081 }} accept'
            outer = f'ip saddr 10.0.2.{n + 3} ip daddr 10.30.1.20 ip protocol gre accept'
            self.assertLess(incoming.index(allowed), incoming.index(denied))
            self.assertLess(incoming.index(denied), incoming.index(outer))
        self.assertLess(incoming.index(denied), incoming.index('iifname "lo"'))
        self.assertNotIn("tcp dport 22 accept", incoming)

    def test_controller_never_flushes_or_syncs_conntrack_or_global_rules(self):
        source = (ROOT / "guest/controller.py").read_text()
        for forbidden in ("conntrack -F", "conntrackd", "flush ruleset", "flush table", "nft flush",
                          "conntrack --flush", "ct state established,related accept"):
            self.assertNotIn(forbidden, source)
        self.ready_state()
        self.control("fail-forwarding", seconds=5)
        self.assertFalse(any(c[0] == "run" for c in self.b.calls))


class BackendUnitTests(SafeTestCase):
    def test_backend_has_no_unoverridden_guest_boundaries(self):
        expected = {name for name, value in vars(controller.Backend).items() if callable(value) and name != "__init__"}
        self.assertTrue(expected <= set(vars(FakeBackend)), expected - set(vars(FakeBackend)))

    def test_exports_changes_both_peers_and_soft_refreshes_both(self):
        # Simulate the local running text after the requested configuration.
        self.b.exported = True
        controller.Backend.exports(self.b, True)
        self.assertEqual(self.b.calls[0], ("configure", ["address-family ipv4 unicast",
                         "neighbor 10.0.1.7 route-map RS-EXPORT-OPEN out", "neighbor 10.0.1.8 route-map RS-EXPORT-OPEN out"]))
        self.assertEqual({c[1] for c in self.b.calls if c[0] == "frr" and c[1].startswith("clear ")},
                         {f"clear bgp ipv4 unicast {p} soft out" for p in self.b.c["rs_peer_ips"]})
        self.assertEqual(self.b.calls[-1], ("frr", "show running-config"))

    def test_exports_rejects_silent_partial_peer_changes_in_both_directions(self):
        for enabled in (True, False):
            for peer in self.b.c["rs_peer_ips"]:
                self.b.exported = enabled
                frr = self.b.frr
                expected, old = ("OPEN", "CLOSED") if enabled else ("CLOSED", "OPEN")
                def partial(command):
                    return frr(command).replace(f"neighbor {peer} route-map RS-EXPORT-{expected} out",
                                                f"neighbor {peer} route-map RS-EXPORT-{old} out")
                with self.subTest(enabled=enabled, peer=peer), patch.object(self.b, "frr", side_effect=partial):
                    with self.assertRaisesRegex(RuntimeError, "outcome may be partial"):
                        controller.Backend.exports(self.b, enabled)

    def test_exports_rejects_missing_filter_even_when_commands_succeed(self):
        self.b.exported = True
        frr = self.b.frr
        peer = self.b.c["rs_peer_ips"][0]
        def missing(command):
            return frr(command).replace(f"  neighbor {peer} route-map RS-EXPORT-OPEN out\n", "")
        with patch.object(self.b, "frr", side_effect=missing):
            with self.assertRaisesRegex(RuntimeError, "not observed locally"):
                controller.Backend.exports(self.b, True)

    def test_shutdown_validates_peer_before_configure(self):
        with self.assertRaisesRegex(RuntimeError, "actual RS instances"):
            controller.Backend.shutdown(self.b, "10.0.1.4", True)
        self.assertEqual(self.b.calls, [])
        controller.Backend.shutdown(self.b, "10.0.1.7", True)
        controller.Backend.shutdown(self.b, "10.0.1.7", False)
        self.assertEqual(self.b.calls, [("configure", ["neighbor 10.0.1.7 shutdown"]),
                                       ("configure", ["no neighbor 10.0.1.7 shutdown"])])

    def test_strict_values_capture_original_once_and_forwarding_first(self):
        original = {key: 1 for key in self.b.sysctls}
        self.b.sysctls = original.copy()
        controller.Backend.strict_values(self.b, True)
        saved = controller.read_json(controller.STATE / "original-sysctl.json")
        self.assertEqual(saved, {"node": "nva1", "values": original})
        self.assertEqual(self.b.sysctls["net.ipv4.ip_forward"], 1)
        self.assertEqual(self.b.sysctls["net.netfilter.nf_conntrack_tcp_loose"], 0)
        for key, value in self.b.sysctls.items():
            if key not in ("net.ipv4.ip_forward", "net.netfilter.nf_conntrack_tcp_loose"):
                self.assertEqual(value, 2 if key.endswith(".rp_filter") else 0)
        controller.Backend.strict_values(self.b, False)
        self.assertEqual(controller.read_json(controller.STATE / "original-sysctl.json"), saved)

    def test_set_values_writes_ip_forward_before_hardening_then_verifies(self):
        desired = {"net.ipv4.conf.all.rp_filter": 2, "net.netfilter.nf_conntrack_tcp_loose": 0,
                   "net.ipv4.ip_forward": 1, "net.ipv4.conf.eth0.accept_redirects": 0}
        commands = []
        def run(args, check=True):
            commands.append(args)
            return subprocess.CompletedProcess(args, 0, "", "")
        with patch.object(self.b, "run", side_effect=run), patch.object(self.b, "values", return_value=desired):
            controller.Backend.set_values(self.b, desired)
        self.assertEqual(commands[0], ["sysctl", "-w", "net.ipv4.ip_forward=1"])
        self.assertEqual(commands[1:], [["sysctl", "-w", f"{key}={desired[key]}"] for key in desired if key != "net.ipv4.ip_forward"])
        persisted = controller.SYSFILE.read_text().splitlines()[1:]
        self.assertEqual(persisted, [command[-1] for command in commands])

    def test_set_values_does_not_persist_failed_verification(self):
        with patch.object(self.b, "run", return_value=subprocess.CompletedProcess([], 0, "", "")), patch.object(
            self.b, "values", return_value={"net.ipv4.ip_forward": 0}
        ):
            with self.assertRaisesRegex(RuntimeError, "verification failed"):
                controller.Backend.set_values(self.b, {"net.ipv4.ip_forward": 1})
        self.assertFalse(controller.SYSFILE.exists())

    def test_values_reads_only_owned_scopes(self):
        calls = []
        def run(args, check=True):
            calls.append(args)
            return subprocess.CompletedProcess(args, 0, "0\n", "")
        with patch.object(self.b, "run", side_effect=run):
            values = controller.Backend.values(self.b)
        self.assertEqual(set(values), set(self.b.sysctls))
        self.assertTrue(all(args[:2] == ["sysctl", "-n"] for args in calls))
        self.assertFalse(any("rs-gre2" in args[-1] for args in calls))

    def test_owned_policy_apply_checks_then_replaces_only_its_table(self):
        calls = []
        texts = []
        def run(args, check=True):
            calls.append(args)
            if args[:2] in (["nft", "-c"], ["nft", "-f"]):
                texts.append(Path(args[-1]).read_text())
            return subprocess.CompletedProcess(args, 0, "", "")
        with patch.object(self.b, "run", side_effect=run):
            controller.Backend.apply_policy(self.b, True)
        self.assertEqual(calls[0], ["nft", "list", "table", "inet", "rs_nva"])
        self.assertEqual(calls[1][:3], ["nft", "-c", "-f"])
        self.assertEqual(calls[2][:2], ["nft", "-f"])
        self.assertEqual(texts[0], texts[1])
        self.assertTrue(texts[0].startswith("delete table inet rs_nva\n"))
        self.assertFalse(Path(calls[-1][-1]).exists())

    def test_frr_baseline_accepts_both_rendered_nodes(self):
        for role in ("nva1", "nva2"):
            with self.subTest(role=role):
                backend = FakeBackend(role)
                self.assertEqual(controller.Backend.frr_base_check(backend), controller.frr_config(backend.c))

    def test_frr_baseline_rejects_unsafe_routes_neighbors_and_route_map_bodies(self):
        unsafe = ("redistribute connected", "default-originate", "aggregate-address 172.20.0.0/16",
                  "network 0.0.0.0/0", "neighbor 10.0.1.9 remote-as 65515",
                  "ip prefix-list OTHER seq 1 permit 0.0.0.0/0 le 32", "route-map EXTRA permit 10",
                  "set ip next-hop 10.0.2.5", "call UNSAFE", "on-match next")
        for line in unsafe:
            with self.subTest(line=line):
                self.b.config_suffix = line + "\n"
                with self.assertRaises(RuntimeError):
                    controller.Backend.frr_base_check(self.b)

    def test_frr_exact_approved_version_is_required(self):
        real = self.b.frr
        with patch.object(self.b, "frr", side_effect=lambda cmd: "FRRouting 10.4.2" if cmd == "show version" else real(cmd)):
            with self.assertRaisesRegex(RuntimeError, "exact approved"):
                controller.Backend.frr_base_check(self.b)

    def test_frr_import_check_enabled_default_can_be_omitted_from_runtime_render(self):
        frr = self.b.frr
        def rendered(command):
            return frr(command).replace(" bgp network import-check\n", "")
        with patch.object(self.b, "frr", side_effect=rendered):
            text = controller.Backend.frr_base_check(self.b)
        self.assertNotIn("bgp network import-check", text)

    def test_frr_explicitly_disabled_import_check_is_rejected(self):
        frr = self.b.frr
        def rendered(command):
            return frr(command).replace(" bgp network import-check\n", " no bgp network import-check\n")
        with patch.object(self.b, "frr", side_effect=rendered):
            with self.assertRaisesRegex(RuntimeError, "import check disabled"):
                controller.Backend.frr_base_check(self.b)

    def test_frr_missing_required_norib_or_exact_prefix_is_rejected(self):
        frr = self.b.frr
        for required in (" bgp no-rib\n", "  network 172.20.50.0/24\n",
                         "ip prefix-list RS-EXACT seq 10 permit 172.20.50.0/24\n",
                         "frr defaults traditional\n"):
            with self.subTest(required=required), patch.object(self.b, "frr", side_effect=lambda command: frr(command).replace(required, "")):
                with self.assertRaisesRegex(RuntimeError, "baseline configuration"):
                    controller.Backend.frr_base_check(self.b)

    def test_sessions_need_both_actual_instances(self):
        for peers in ({"10.0.1.7": {"state": "Established"}},
                      {"10.0.1.7": {"state": "Established"}, "10.0.1.8": {"state": "Idle"}}):
            with patch.object(self.b, "summary", return_value={"ipv4Unicast": {"peers": peers}}):
                self.assertFalse(controller.Backend.sessions_ready(self.b))
        self.assertTrue(controller.Backend.sessions_ready(self.b))

    def test_verify_withdrawn_checks_each_actual_peer_and_limits_observation_scope(self):
        frr = self.b.frr
        commands = []
        def reply(command):
            commands.append(command)
            if command.endswith("advertised-routes json"):
                return json.dumps({"advertisedRoutes": {}, "totalPrefixCounter": 0})
            return frr(command)
        with patch.object(self.b, "frr", side_effect=reply):
            result = controller.Backend.verify_withdrawn(self.b)
        self.assertTrue(result["local_exports_verified_empty"])
        self.assertIn("not-Azure-withdrawal-convergence", result["scope"])
        for peer in self.b.c["rs_peer_ips"]:
            self.assertIn(f"show bgp ipv4 unicast neighbors {peer} advertised-routes json", commands)

    def test_verify_withdrawn_rejects_either_peer_open_or_missing_closed_filter(self):
        frr = self.b.frr
        for peer in self.b.c["rs_peer_ips"]:
            for replacement in ("", f"  neighbor {peer} route-map RS-EXPORT-OPEN out\n"):
                def reply(command):
                    if command.endswith("advertised-routes json"):
                        return json.dumps({"advertisedRoutes": {}, "totalPrefixCounter": 0})
                    return frr(command).replace(f"  neighbor {peer} route-map RS-EXPORT-CLOSED out\n", replacement)
                with self.subTest(peer=peer, replacement=replacement), patch.object(self.b, "frr", side_effect=reply):
                    with self.assertRaisesRegex(RuntimeError, "export policies"):
                        controller.Backend.verify_withdrawn(self.b)

    def test_verify_withdrawn_rejects_nonempty_or_unknown_advertisement_reports(self):
        frr = self.b.frr
        reports = ({"advertisedRoutes": {"172.20.50.0/24": {}}, "totalPrefixCounter": 1},
                   {"advertisedRoutes": {}, "totalPrefixCounter": 1},
                   {"advertisedRoutes": {}}, {"totalPrefixCounter": 0},
                   {"advertisedRoutes": [], "totalPrefixCounter": 0}, [], None)
        for peer in self.b.c["rs_peer_ips"]:
            for report in reports:
                def reply(command):
                    if command.endswith("advertised-routes json"):
                        row = report if f"neighbors {peer} " in command else {"advertisedRoutes": {}, "totalPrefixCounter": 0}
                        return json.dumps(row)
                    return frr(command)
                with self.subTest(peer=peer, report=report), patch.object(self.b, "frr", side_effect=reply):
                    with self.assertRaisesRegex(RuntimeError, "not confirmed empty"):
                        controller.Backend.verify_withdrawn(self.b)

    def test_tunnel_checks_both_fixtures_from_node_specific_overlay(self):
        for role, n in (("nva1", 1), ("nva2", 2)):
            backend = FakeBackend(role)
            def run(args, check=True):
                destination = args[-1]
                route = {"dev": f"rs-gre{n}", "gateway": f"10.255.{n}.2"} if destination == controller.D else {"dev": "eth0", "gateway": "10.0.2.1"}
                return subprocess.CompletedProcess(args, 0, json.dumps([route]), "")
            made = []
            class FakeHTTP:
                def __init__(self, host, port, timeout, source_address):
                    self.host, self.port, self.source = host, port, source_address
                    self.closed = False
                    made.append(self)
                def request(self, method, path, headers):
                    self.method, self.path, self.case = method, path, headers["X-Lab-Case-ID"]
                def getresponse(self):
                    row = {"fixture": "azure-routeserver-origin-v1", "case_id": self.case,
                           "server_ip": controller.D, "server_port": self.port,
                           "peer_ip": f"10.255.{n}.1"}
                    return types.SimpleNamespace(status=200, read=lambda limit: json.dumps(row).encode())
                def close(self):
                    self.closed = True
            with patch.object(backend, "run", side_effect=run), patch.object(controller.http.client, "HTTPConnection", FakeHTTP):
                controller.Backend.tunnel_check(backend)
            self.assertEqual([conn.port for conn in made], [8080, 8081])
            self.assertTrue(all(conn.source == (f"10.255.{n}.1", 0) and conn.closed for conn in made))
            self.assertTrue(all(conn.host == controller.D and conn.path == "/probe" for conn in made))

    def test_recursive_destination_route_fails_before_fixture_network(self):
        with patch.object(self.b, "run", return_value=subprocess.CompletedProcess([], 0, json.dumps([{"dev": "eth0", "gateway": "10.0.2.1"}]), "")):
            with self.assertRaisesRegex(RuntimeError, "exact intended GRE"):
                controller.Backend.tunnel_check(self.b)

    def test_checks_detects_each_owned_readiness_drift(self):
        state = self.ready_state()
        cases = [("mode", "closed", "forwarding-closed"),
                 ("policy_digest", "changed", "owned-policy-drift"),
                 ("frr_digest", "changed", "FRR-runtime-config-drift")]
        for key, value, reason in cases:
            with self.subTest(key=key):
                result = controller.Backend.checks(self.b, {**state, key: value}, True)
                self.assertFalse(result["ready"])
                self.assertIn(reason, result["reasons"])
        for key, value, reason in (("net.ipv4.ip_forward", 0, "forwarding-or-strict-conntrack-drift"),
                                  ("net.netfilter.nf_conntrack_tcp_loose", 1, "forwarding-or-strict-conntrack-drift"),
                                  ("net.ipv4.conf.eth0.rp_filter", 1, "owned-hardening-drift"),
                                  ("net.ipv4.conf.all.accept_redirects", 1, "owned-hardening-drift")):
            before = self.b.sysctls[key]
            self.b.sysctls[key] = value
            with self.subTest(key=key):
                self.assertIn(reason, controller.Backend.checks(self.b, state)["reasons"])
            self.b.sysctls[key] = before

    def test_checks_tunnel_failure_and_session_gate_are_honest_local_scope(self):
        state = self.ready_state()
        self.b.sessions = False
        self.assertTrue(controller.Backend.checks(self.b, state, False)["ready"])
        result = controller.Backend.checks(self.b, state, True)
        self.assertIn("both-RS-sessions-not-established", result["reasons"])
        self.assertIn("not-Azure-route-or-client-proof", result["scope"])
        with patch.object(self.b, "tunnel_check", side_effect=TimeoutError("mock fixture timeout")):
            self.assertIn("mock fixture timeout", controller.Backend.checks(self.b, state)["reasons"])

    def test_digest_ignores_nft_handles_indexes_and_counter_values(self):
        before = {"nftables": [{"metainfo": {"version": "one"}}, {"rule": {"handle": 4, "index": 1,
                            "expr": [{"counter": {"packets": 2, "bytes": 100}}, {"accept": None}]}}]}
        after = copy.deepcopy(before)
        after["nftables"][0]["metainfo"]["version"] = "two"
        rule = after["nftables"][1]["rule"]
        rule.update(handle=8, index=9)
        rule["expr"][0]["counter"] = {"packets": 999, "bytes": 8000}
        self.assertEqual(controller.digest(before), controller.digest(after))
        rule["expr"][1] = {"drop": None}
        self.assertNotEqual(controller.digest(before), controller.digest(after))


class ConfigurationTests(SafeTestCase):
    def test_all_fixed_role_addresses_validate(self):
        for role in ("nva1", "nva2", "remote"):
            c = config(role)
            self.assertEqual(controller.validate_config(c), c)

    def test_fixed_addresses_cannot_be_changed(self):
        for key in ("private_ip", "app_ip", "remote_ip", "destination_ip"):
            with self.subTest(key=key), self.assertRaises((AssertionError, ValueError)):
                controller.validate_config({**config(), key: "127.0.0.1"})

    def test_peer_ip_validation_rejects_duplicates_out_of_subnet_v6_and_non_ip(self):
        for peers in (["10.0.1.7"], ["10.0.1.7", "10.0.1.7"], ["10.0.1.7", "10.0.1.64"],
                      ["10.0.1.7", "2001:db8::1"], ["10.0.1.7", "example.com"],
                      ["10.0.1.7", "10.0.1.8; reboot"]):
            with self.subTest(peers=peers), self.assertRaises((AssertionError, ValueError)):
                controller.validate_config({**config(), "rs_peer_ips": peers})

    def test_local_asn_cannot_equal_actual_route_server_asn(self):
        for asn in (65010, 0, -1, 4294967296, "65515"):
            with self.subTest(asn=asn), self.assertRaises((AssertionError, ValueError)):
                controller.validate_config({**config(), "rs_asn": asn})

    def test_boolean_asn_is_not_an_integer_configuration_value(self):
        for asn in (True, False):
            with self.subTest(asn=asn), self.assertRaises(ValueError):
                controller.validate_config({**config(), "rs_asn": asn})

    def test_integer_encoded_peer_addresses_are_rejected(self):
        # ipaddress accepts integer IPv4 encodings; the FRR renderer needs strings.
        for peers in ([167772423, 167772424], ["10.0.1.7", 167772424]):
            with self.subTest(peers=peers), self.assertRaises(ValueError):
                controller.validate_config({**config(), "rs_peer_ips": peers})

    def test_configuration_validation_survives_python_optimization(self):
        # Compile only this pure validation function in-process. No child Python,
        # shell, guest operation, or network activity is invoked.
        tree = ast.parse((ROOT / "guest/controller.py").read_text())
        function = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "validate_config")
        module = ast.Module(body=[function], type_ignores=[])
        namespace = dict(vars(controller))
        exec(compile(module, "<optimized-configuration-unit-test>", "exec", optimize=2), namespace)
        validate = namespace["validate_config"]
        for changes in ({"role": "app"}, {"private_ip": "127.0.0.1"}, {"rs_asn": True},
                        {"rs_peer_ips": [167772423, 167772424]}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validate({**config(), **changes})
        self.assertEqual(validate(config()), config())

    def test_only_approved_frr_release_shape_is_allowed(self):
        for version in ("9.1", "10.3.1", "10.5", "10.4.1.2", "10.4; reboot"):
            with self.subTest(version=version), self.assertRaises((AssertionError, ValueError)):
                controller.validate_config({**config(), "frr_version": version})

    def test_signal_handlers_use_bounded_finally_exit_and_do_not_swallow_signal(self):
        handlers = {}
        with patch.object(controller.signal, "signal", side_effect=lambda sig, fn: handlers.setdefault(sig, fn)):
            controller.handlers()
        self.assertEqual(set(handlers), {signal.SIGHUP, signal.SIGINT, signal.SIGTERM})
        for sig, fn in handlers.items():
            with self.subTest(sig=sig), self.assertRaises(SystemExit) as caught:
                fn(sig, None)
            self.assertEqual(caught.exception.code, 128 + sig)


if __name__ == "__main__":
    unittest.main(verbosity=2)
