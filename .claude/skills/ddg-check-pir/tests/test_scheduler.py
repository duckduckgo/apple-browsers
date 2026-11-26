import argparse
from copy import deepcopy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pir
import scheduler


CUTOFF = '2026-11-20T12:00:00Z'
BROKER = 'example.test/path?key=value'
IDENTITY = dict(pid=42, started='Fri Nov 20 12:00:00 2026', executable='/tmp/Agent.app/Contents/MacOS/Agent')


def event(kind, second=1, error=None):
    value = dict(type=kind, date=f'2026-11-20T12:00:{second:02d}Z')
    return dict(value, error=dict(name=error, code=0, description='')) if error else value


def arguments(**kwargs):
    values = dict(platform='macos', scheduler_port=None, scheduler_since=CUTOFF,
                  scheduler_jobs=[[BROKER, '1']], scheduler_timeout=None)
    values.update(kwargs)
    return argparse.Namespace(**values)


class Context:
    def __init__(self):
        self.result, self.files, self.unverified_items = {}, {}, []

    def write(self, name, value):
        self.files[name] = deepcopy(value)

    def unverified(self, what, reason):
        self.unverified_items.append((what, reason))


class Client:
    def __init__(self, histories, *, state='idle', active=True, removed=False, broker=BROKER, missing=False):
        self.histories = histories
        self.state, self.active, self.removed, self.broker, self.missing = state, active, removed, broker, missing
        self.calls, self.sample = [], -1

    def request(self, method, path, timeout=None):
        self.calls.append((method, path, timeout))
        if path.startswith('/api/logs'):
            return [dict(message='native log line')]
        if path == '/api':
            self.sample += 1
            return dict(snapshot=dict(schedulerState=self.state,
                                       profileQueries=[dict(id=1, deprecated=not self.active)]))
        query = dict(profileQueryId=1, scan=dict(history=self.histories[min(self.sample, len(self.histories) - 1)]))
        return dict(url=self.broker, isRemoved=self.removed, profileQueries=[] if self.missing else [query])


class SchedulerTests(unittest.TestCase):
    def run_observer(self, client, *, identity=None, timeout=.5):
        context = Context()
        clock = [0.0]
        def sleep(seconds):
            clock[0] += seconds
        scope = scheduler.parse_scope(arguments(scheduler_timeout=timeout))
        with patch.object(scheduler, '_identity', side_effect=identity or [IDENTITY] * 100), \
                patch.object(scheduler.time, 'monotonic', side_effect=lambda: clock[0]), \
                patch.object(scheduler.time, 'sleep', side_effect=sleep):
            outcome = scheduler.observe(context, client, scope)
        return outcome, context

    def test_scope_defaults_and_exact_pairs(self):
        scope = scheduler.parse_scope(arguments())
        self.assertEqual((scope.port, scope.timeout, scope.jobs), (8474, 600, (scheduler.Job(BROKER, 1),)))
        self.assertIsNotNone(scope.since.tzinfo)

    def test_invalid_scope(self):
        for changes in [dict(scheduler_jobs=[]), dict(scheduler_jobs=[[BROKER, '1'], [BROKER, '01']]),
                        dict(scheduler_jobs=[[BROKER, '0']]), dict(scheduler_jobs=[['', '1']]),
                        dict(scheduler_jobs=[[BROKER, True]]), dict(scheduler_jobs=[[BROKER, '1.5']]),
                        dict(scheduler_since='2026-11-20T12:00:00'), dict(scheduler_since='invalid'),
                        dict(scheduler_timeout=0), dict(scheduler_timeout=float('nan')),
                        dict(scheduler_timeout=float('inf')), dict(scheduler_timeout=3601),
                        dict(scheduler_port=0), dict(scheduler_port=True)]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                scheduler.parse_scope(arguments(**changes))

    def test_matches_and_no_match_both_complete_even_when_idle(self):
        for terminal in ('matchesFound', 'noMatchFound'):
            client = Client([[event('scanStarted'), event(terminal)]])
            outcome, context = self.run_observer(client)
            self.assertEqual(outcome['status'], 'pass')
            self.assertEqual(context.files['scheduler.json']['jobs'][0]['terminal'], terminal)
            self.assertEqual(context.result['scheduler']['identity'], IDENTITY)
            self.assertEqual(len(context.unverified_items), 4)
            self.assertEqual([call[0] for call in client.calls], ['GET', 'GET'])
            self.assertEqual(client.calls[1][1], '/api/brokers/example.test%2Fpath%3Fkey%3Dvalue')

    def test_pending_and_stale_and_orphaned_histories_do_not_pass(self):
        for history in ([], [event('scanStarted')], [event('noMatchFound')],
                        [event('scanStarted', 0), event('matchesFound', 1)],
                        [event('noMatchFound', 1), event('scanStarted', 1)],
                        [event('scanStarted', 1), event('matchesFound', 2), event('scanStarted', 3)]):
            with self.subTest(history=history):
                outcome, context = self.run_observer(Client([history]))
                self.assertEqual(outcome['status'], 'fail')
                self.assertEqual(context.result['scheduler']['jobs'][0]['status'], 'pending')

    def test_missing_inactive_and_alias_broker_are_not_completion(self):
        history = [[event('scanStarted'), event('noMatchFound')]]
        for options in (dict(missing=True), dict(active=False), dict(broker='alias')):
            with self.subTest(options=options):
                outcome, context = self.run_observer(Client(history, **options))
                self.assertEqual(outcome['status'], 'fail')
                self.assertEqual(context.result['scheduler']['jobs'][0]['status'], 'missing')

    def test_broker_removed_during_run_stops_waiting_without_passing(self):
        outcome, context = self.run_observer(Client([[]], removed=True), timeout=5)
        self.assertEqual(outcome['status'], 'inconclusive')
        self.assertEqual(context.files['scheduler.json']['polls'], 1)
        self.assertEqual(context.result['scheduler']['jobs'][0]['status'], 'removed')

    def test_removed_broker_does_not_block_other_jobs(self):
        class MixedClient(Client):
            def request(self, method, path, timeout):
                value = super().request(method, path, timeout)
                return dict(value, url='other', isRemoved=True) if path.endswith('other') else value
        context, clock = Context(), [0.0]
        scope = scheduler.parse_scope(arguments(scheduler_jobs=[[BROKER, '1'], ['other', '1']], scheduler_timeout=5))
        with patch.object(scheduler, '_identity', return_value=IDENTITY), \
                patch.object(scheduler.time, 'monotonic', side_effect=lambda: clock[0]), \
                patch.object(scheduler.time, 'sleep', side_effect=lambda seconds: clock.__setitem__(0, clock[0] + seconds)):
            outcome = scheduler.observe(context, MixedClient([[event('scanStarted'), event('noMatchFound')]]), scope)
        self.assertEqual(outcome['status'], 'pass')
        self.assertEqual([job['status'] for job in context.result['scheduler']['jobs']], ['pass', 'removed'])

    def test_broker_error_terminal_counts_as_completed_scan(self):
        for name in ('httpError', 'actionFailed'):
            with self.subTest(name=name):
                outcome, context = self.run_observer(Client([[event('scanStarted'), event('error', 2, name)]]))
                self.assertEqual(outcome['status'], 'pass')
                self.assertEqual(context.result['scheduler']['jobs'][0]['brokerError'], name)

    def test_non_broker_error_terminal_fails(self):
        for name in ('noActionFound', 'parsingErrorObjectFailed', 'captchaServiceError', None):
            with self.subTest(name=name):
                outcome, context = self.run_observer(Client([[event('scanStarted'), event('error', 2, name)]]))
                self.assertEqual(outcome['status'], 'fail')
                self.assertEqual(context.result['scheduler']['jobs'][0]['status'], 'fail')

    def test_timeout_and_network_terminals_are_transient_and_inconclusive(self):
        for name in ('Cancelled', 'jobTimeout', 'The network connection was lost.'):
            with self.subTest(name=name):
                outcome, context = self.run_observer(Client([[event('scanStarted'), event('error', 2, name)]]))
                self.assertEqual(outcome['status'], 'inconclusive')
                self.assertIn(BROKER, outcome['reason'])
                self.assertEqual(context.result['scheduler']['jobs'][0]['status'], 'transient')

    def test_a_failed_job_does_not_stop_observing_the_others(self):
        class MixedClient(Client):
            def request(self, method, path, timeout):
                value = super().request(method, path, timeout)
                if path.endswith('other'):
                    history = [event('scanStarted')] + ([event('noMatchFound', 3)] if self.sample >= 2 else [])
                    return dict(value, url='other', profileQueries=[dict(profileQueryId=1, scan=dict(history=history))])
                return value
        context, clock = Context(), [0.0]
        scope = scheduler.parse_scope(arguments(scheduler_jobs=[[BROKER, '1'], ['other', '1']], scheduler_timeout=30))
        with patch.object(scheduler, '_identity', return_value=IDENTITY), \
                patch.object(scheduler.time, 'monotonic', side_effect=lambda: clock[0]), \
                patch.object(scheduler.time, 'sleep', side_effect=lambda seconds: clock.__setitem__(0, clock[0] + seconds)):
            outcome = scheduler.observe(context, MixedClient([[event('scanStarted'), event('error', 2, 'noActionFound')]]), scope)
        self.assertEqual(outcome['status'], 'fail')
        self.assertIn(BROKER, outcome['reason'])
        self.assertEqual([job['status'] for job in context.result['scheduler']['jobs']], ['fail', 'pass'])
        self.assertEqual(context.files['scheduler.json']['polls'], 3)

    def test_retry_uses_latest_start_and_records_completed_polls(self):
        histories = [[event('scanStarted'), event('error', 2, 'httpError'), event('scanStarted', 3)],
                     [event('scanStarted'), event('error', 2, 'httpError'), event('scanStarted', 3), event('noMatchFound', 4)]]
        outcome, context = self.run_observer(Client(histories), timeout=5)
        self.assertEqual(outcome['status'], 'pass')
        self.assertEqual(context.files['scheduler.json']['polls'], 2)
        self.assertEqual(context.result['scheduler']['jobs'][0]['startedAt'], event('scanStarted', 3)['date'])

    def test_overlapping_scans_are_judged_by_the_last_terminal_event(self):
        started = [event('scanStarted', 1), event('scanStarted', 2), event('error', 2, 'Cancelled')]
        outcome, context = self.run_observer(Client([started, started + [event('error', 5, 'actionFailed')]]), timeout=5)
        self.assertEqual(outcome['status'], 'pass')
        self.assertEqual(context.result['scheduler']['jobs'][0]['brokerError'], 'actionFailed')
        self.assertEqual(context.files['scheduler.json']['polls'], 2)

    def test_ambiguous_history_does_not_pass(self):
        for history in ([event('scanStarted'), event('noMatchFound'), event('matchesFound')],
                        [event('scanStarted', 2), event('noMatchFound', 1)]):
            outcome, context = self.run_observer(Client([history]))
            self.assertEqual(outcome['status'], 'fail')
            self.assertEqual(context.result['scheduler']['jobs'][0]['status'], 'ambiguous')

    def test_standalone_and_listener_restart_reject(self):
        complete = [[event('scanStarted'), event('noMatchFound')]]
        with self.assertRaisesRegex(RuntimeError, 'production scheduler'):
            self.run_observer(Client(complete, state='standalone-debug'))
        for histories in (complete, [[]]):
            with self.assertRaisesRegex(RuntimeError, 'identity changed'):
                self.run_observer(Client(histories), identity=[IDENTITY, IDENTITY, dict(IDENTITY, pid=43)], timeout=5)

    def test_http_failure_is_inconclusive_setup_error(self):
        client = Client([[]])
        with patch.object(client, 'request', side_effect=Exception('private HTTP response')):
            with self.assertRaisesRegex(RuntimeError, '^scheduler HTTP read failed; see request evidence$'):
                self.run_observer(client)

    def test_read_failing_at_deadline_is_timeout(self):
        client, clock = Client([[]]), [0.0]
        def request(method, path, timeout):
            clock[0] += timeout
            raise TimeoutError
        with patch.object(client, 'request', side_effect=request):
            context, scope = Context(), scheduler.parse_scope(arguments(scheduler_timeout=.5))
            with patch.object(scheduler, '_identity', return_value=IDENTITY), \
                    patch.object(scheduler.time, 'monotonic', side_effect=lambda: clock[0]):
                outcome = scheduler.observe(context, client, scope)
        self.assertEqual(outcome, dict(status='fail', reason='expected scheduler scans did not complete before timeout'))

    def test_partial_scope_does_not_pass(self):
        context = Context()
        scope = scheduler.parse_scope(arguments(scheduler_jobs=[[BROKER, '1'], [BROKER, '2']], scheduler_timeout=.5))
        clock = [0.0]
        with patch.object(scheduler, '_identity', return_value=IDENTITY), \
                patch.object(scheduler.time, 'monotonic', side_effect=lambda: clock[0]), \
                patch.object(scheduler.time, 'sleep', side_effect=lambda seconds: clock.__setitem__(0, clock[0] + seconds)):
            outcome = scheduler.observe(context, Client([[event('scanStarted'), event('noMatchFound')]]), scope)
        self.assertEqual(outcome['status'], 'fail')
        self.assertEqual([job['status'] for job in context.result['scheduler']['jobs']], ['pass', 'missing'])

    def test_completion_after_deadline_fails(self):
        context = Context()
        scope = scheduler.parse_scope(arguments(scheduler_timeout=.5))
        with patch.object(scheduler, '_identity', return_value=IDENTITY), \
                patch.object(scheduler.time, 'monotonic', side_effect=[0, .1, .2, .6]):
            outcome = scheduler.observe(context, Client([[event('scanStarted'), event('noMatchFound')]]), scope)
        self.assertEqual(outcome['status'], 'fail')

    def test_identity_requires_unique_debug_agent_listener(self):
        completed = subprocess.CompletedProcess([], 0, '42\n', '')
        info = dict(CFBundleIdentifier=scheduler.runtime.BUNDLES['macos'], CFBundleExecutable='Agent')
        with patch.object(scheduler.subprocess, 'run', return_value=completed) as command, \
                patch.object(scheduler.runtime, '_process', return_value=IDENTITY), \
                patch.object(scheduler.runtime, '_info', return_value=info):
            deadline = time.monotonic() + 20
            self.assertEqual(scheduler._identity('macos', 8474, deadline)['pid'], 42)
            self.assertEqual(command.call_args.kwargs['timeout'], 5)
            for stdout in ('', '42\n43\n'):
                completed.stdout = stdout
                with self.assertRaises(RuntimeError):
                    scheduler._identity('macos', 8474, deadline)
            completed.stdout = '42\n'
            info['CFBundleIdentifier'] = 'com.duckduckgo.macos.DBP.backgroundAgent'
            with self.assertRaises(RuntimeError):
                scheduler._identity('macos', 8474, deadline)

    def test_ios_listener_requires_the_simulator_app_executable(self):
        completed = subprocess.CompletedProcess([], 0, '42\n', '')
        identity = dict(IDENTITY, executable='/tmp/DuckDuckGo.app/DuckDuckGo')
        info = dict(CFBundleIdentifier='com.duckduckgo.mobile.ios', CFBundleExecutable='DuckDuckGo',
                    DTPlatformName='iphonesimulator')
        with patch.object(scheduler.subprocess, 'run', return_value=completed), \
                patch.object(scheduler.runtime, '_process', return_value=identity), \
                patch.object(scheduler.runtime, '_info', return_value=info) as read_info:
            deadline = time.monotonic() + 20
            result = scheduler._identity('ios', 8474, deadline)
            self.assertEqual(result['pid'], 42)
            self.assertEqual(result['bundleId'], 'com.duckduckgo.mobile.ios')
            read_info.assert_called_once_with(Path(identity['executable']).resolve().parent, 'ios')
            with self.assertRaisesRegex(RuntimeError, 'requested macos'):
                scheduler._identity('macos', 8474, deadline)
            info['DTPlatformName'] = 'iphoneos'
            with self.assertRaisesRegex(RuntimeError, 'direct simulator listener'):
                scheduler._identity('ios', 8474, deadline)

    def test_scheduler_cli_records_read_only_observation_and_report(self):
        source = Client([[event('scanStarted'), event('noMatchFound', 2)]])
        expected_path = '/api/brokers/example.test%2Fpath%3Fkey%3Dvalue'
        calls = []

        class ServerHandler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                calls.append((self.command, self.path, self.headers.get('X-PIR-Debug-Instance')))
                if self.path not in ('/api', expected_path):
                    self.send_error(404)
                    return
                payload = json.dumps(source.request(self.command, self.path, 1)).encode()
                self.send_response(200)
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

        with ThreadingHTTPServer(('127.0.0.1', 0), ServerHandler) as server, tempfile.TemporaryDirectory() as evidence:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                for platform in ('macos', 'ios'):
                    with self.subTest(platform=platform):
                        calls.clear()
                        args = pir.parser().parse_args(['scheduler', 'observe', '--platform', platform, '--port', str(server.server_port),
                                                        '--job', BROKER, '1', '--since', CUTOFF, '--evidence-dir', evidence])
                        with patch.object(scheduler, '_identity', return_value=IDENTITY) as identity, \
                                patch.object(pir, 'read_token', side_effect=AssertionError('read credential')):
                            result = pir.execute(args, runtime_factory=lambda *a, **kw: self.fail('launched runtime'))
                        self.assertEqual(result['status'], 'pass', result)
                        self.assertEqual(result['cleanup'], {'mode': 'attached'})
                        self.assertEqual(calls, [('GET', '/api', None), ('GET', expected_path, None)])
                        self.assertEqual(identity.call_args.args[0], platform)
                        attempt = Path(result['evidence'])
                        observation = json.loads((attempt / 'scheduler.json').read_text())
                        self.assertEqual(observation['platform'], platform)
                        self.assertEqual(observation['jobs'][0]['terminal'], 'noMatchFound')
                        report = (attempt / 'report.md').read_text()
                        self.assertTrue(report.startswith('# PIR pass\n'))
                        self.assertIn(f'{BROKER} / query 1: noMatchFound', report)
                        manifest = json.loads((attempt / 'manifest.json').read_text())
                        self.assertIn('scheduler.json', manifest['files'])
                        self.assertIn('pir-http-0002.json', manifest['files'])
            finally:
                server.shutdown()
                thread.join()

    def test_ios_seed_observes_its_own_simulator_app_on_a_private_port(self):
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory) / 'profile.json'
            profile.write_text(json.dumps(dict(names=[dict(firstName='Test', lastName='Fixture')],
                                               addresses=[dict(city='Test City', state='CA')], phones=[], birthYear=1980)))
            args = pir.parser().parse_args(['scheduler', 'seed', '--platform', 'ios', '--device', 'ipad', '--keep',
                                            '--profile-file', str(profile), '--evidence-dir', directory,
                                            '--launch-profile', '{"onboardingCompleted": false}'])
            installed = '/Simulator/Devices/UDID/DuckDuckGo.app/DuckDuckGo'
            native = FakeSeedRuntime(process=dict(IDENTITY, executable=installed))
            client = Client([[event('scanStarted', 0), event('noMatchFound', 0)]])
            with patch.object(scheduler, '_identity', return_value=dict(IDENTITY, executable=installed)) as identity, \
                    patch.object(pir, 'Client', return_value=client) as make_client:
                result = pir.execute(args, runtime_factory=native.create)
            self.assertEqual(result['status'], 'pass', result)
            self.assertEqual(native.platform, 'ios')
            self.assertEqual(native.options, dict(device='ipad', keep=True, launch_profile=dict(onboardingCompleted=False)))
            self.assertEqual(result['launch']['launchProfile']['source'], dict(inline=dict(onboardingCompleted=False)))
            self.assertIn("--launch-profile '{\"onboardingCompleted\": false}'", result['rerun'])
            self.assertNotEqual(native.port, 8474)
            self.assertEqual(identity.call_args.args[:2], ('ios', native.port))
            self.assertEqual(make_client.call_args.args[1], native.port)
            self.assertEqual(result['scheduler']['platform'], 'ios')
            self.assertEqual(result['cleanup']['mode'], 'managed-simulator')
            self.assertTrue(native.stopped)

    def test_keep_is_limited_to_ios_seeding(self):
        for argv in (['scheduler', 'seed', '--platform', 'macos', '--profile-file', '/profile.json', '--keep'],
                     ['scheduler', 'observe', '--platform', 'ios', '--since', CUTOFF, '--job', BROKER, '1', '--keep']):
            with self.subTest(argv=argv), self.assertRaisesRegex(ValueError, '--keep applies only'):
                pir.execute(pir.parser().parse_args(argv), runtime_factory=lambda *a, **kw: self.fail('launched runtime'))

    def test_managed_modes_take_scope_from_the_owned_native_receipt(self):
        for mode in ('seed', 'reseed'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                profile = root / 'profile.json'
                profile.write_text(json.dumps(dict(names=[dict(firstName='Test', lastName='Fixture')],
                                                   addresses=[dict(city='Test City', state='CA')], phones=[], birthYear=1980)))
                args = pir.parser().parse_args(['scheduler', mode, '--platform', 'macos', '--profile-file', str(profile),
                                                '--evidence-dir', directory])
                native = FakeSeedRuntime()
                client = Client([[event('scanStarted', 0), event('noMatchFound', 0)]])
                with patch.object(scheduler, '_identity', return_value=IDENTITY), patch.object(pir, 'Client', return_value=client):
                    result = pir.execute(args, runtime_factory=native.create)
                self.assertEqual(result['status'], 'pass', result)
                self.assertEqual(json.loads((Path(result['evidence']) / 'pir-native-logs.json').read_text()),
                                 [dict(message='native log line')])
                self.assertEqual(native.launch_values, (mode, profile.read_text()))
                self.assertEqual(result['scheduler']['jobs'][0]['profileQueryId'], 1)
                self.assertTrue(all(method == 'GET' for method, *_ in client.calls))
                self.assertTrue(native.stopped)
                self.assertIn(f'scheduler {mode}', result['rerun'])
                self.assertNotIn('--job', result['rerun'])
                self.assertNotIn('--since', result['rerun'])

    def test_seed_brokers_reach_the_launch_report_and_rerun(self):
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory) / 'profile.json'
            profile.write_text(json.dumps(dict(names=[dict(firstName='Test', lastName='Fixture')],
                                               addresses=[dict(city='Test City', state='CA')], phones=[], birthYear=1980)))
            base = ['scheduler', 'seed', '--platform', 'macos', '--profile-file', str(profile), '--evidence-dir', directory]
            native = FakeSeedRuntime()
            client = Client([[event('scanStarted', 0), event('noMatchFound', 0)]])
            with patch.object(scheduler, '_identity', return_value=IDENTITY), patch.object(pir, 'Client', return_value=client):
                result = pir.execute(pir.parser().parse_args(base + ['--broker', 'a.com', '--broker', 'b.com']),
                                     runtime_factory=native.create)
            self.assertEqual(native.brokers, ('a.com', 'b.com'))
            self.assertEqual(result['schedulerBrokers'], ['a.com', 'b.com'])
            self.assertIn('--broker a.com --broker b.com', result['rerun'])
            for value, message in (('https://a.com', 'bare broker URL'), ('a.com/x', 'bare broker URL'), (' a.com', 'bare broker URL')):
                with self.subTest(value=value), self.assertRaisesRegex(ValueError, message):
                    pir.execute(pir.parser().parse_args(base + ['--broker', value]))
            with self.assertRaisesRegex(ValueError, 'unique'):
                pir.execute(pir.parser().parse_args(base + ['--broker', 'a.com', '--broker', 'a.com']))
            with self.assertRaisesRegex(ValueError, 'does not take a profile file or brokers'):
                pir.execute(pir.parser().parse_args(['scheduler', 'observe', '--platform', 'macos', '--since', CUTOFF,
                                                     '--job', BROKER, '1', '--broker', 'a.com']))
            unknown = FakeSeedRuntime(receipt_changes={'status': 'error', 'errorCode': 'unknownBroker',
                                                       'missingBrokers': {'missing.com': 'requiresSubscription'}})
            with patch.object(pir, 'Client', side_effect=AssertionError('contacted a listener')):
                result = pir.execute(pir.parser().parse_args(base + ['--broker', 'missing.com']), runtime_factory=unknown.create)
            self.assertEqual(result['status'], 'inconclusive')
            self.assertIn('missing.com (requiresSubscription)', result['reason'])

    def test_upgrade_refreshes_scans_now_and_observes_the_queued_jobs(self):
        later = '2099-01-01T00:00:01Z'
        class UpgradeClient(Client):
            def __init__(self):
                super().__init__([[dict(type='scanStarted', date=later), dict(type='noMatchFound', date=later)]], broker='example.test')
                self.posted = []
            def request(self, method, path, body=None, timeout=None):
                self.calls.append((method, path, timeout))
                if method == 'POST':
                    self.posted.append((path, body))
                    return dict(id='refresh' if path.endswith('refresh') else 'scans', status='pending')
                if path == '/api/debug/maintenance/refresh':
                    return dict(status='succeeded', result=[dict(url='beenverified.com', version='0.12.0', isRemoved=False, id=7)])
                if path == '/api/debug/maintenance/scans':
                    return dict(status='succeeded', result=dict(queued=[dict(brokerURL='example.test', profileQueryId=1)], notQueued=[]))
                return super().request(method, path, timeout)
        with tempfile.TemporaryDirectory() as directory:
            args = pir.parser().parse_args(['scheduler', 'upgrade', '--platform', 'macos', '--broker', 'example.test',
                                            '--evidence-dir', directory, '--scenario', 'An upgrade', '--step', 'upgrade'])
            native = FakeSeedRuntime()
            client = UpgradeClient()
            with patch.object(scheduler, '_identity', return_value=IDENTITY), patch.object(pir, 'Client', return_value=client), \
                    patch.object(scheduler.time, 'sleep'), patch.object(scheduler, 'listener_on', return_value=False):
                result = pir.execute(args, runtime_factory=native.create)
            self.assertEqual(result['status'], 'pass', result)
            occupied = FakeSeedRuntime()
            with patch.object(scheduler, 'listener_on', return_value=True):
                refused = pir.execute(args, runtime_factory=occupied.create)
            self.assertEqual(refused['status'], 'inconclusive')
            self.assertIn('launchctl bootout', refused['reason'])
            self.assertFalse(getattr(occupied, 'launched_existing', False))
            self.assertTrue(native.launched_existing)
            self.assertEqual(client.posted, [('/api/debug/broker-json/refresh', dict(resetDelivery=False)),
                                             ('/api/debug/scans/immediate', dict(brokers=['example.test']))])
            self.assertEqual(result['upgrade']['brokers'][0]['version'], '0.12.0')
            self.assertEqual(result['step'], 'upgrade')
            self.assertIn('--step upgrade', result['rerun'])
            self.assertTrue((Path(result['evidence']) / 'upgrade-scans.json').exists())
        for extra, message in ((['--platform', 'macos'], 'requires --broker'),
                               (['--platform', 'ios', '--broker', 'a.com'], '--simulator'),
                               (['--platform', 'macos', '--broker', 'a.com', '--simulator', 'X'], '--simulator'),
                               (['--platform', 'macos', '--broker', 'a.com', '--profile-file', '/p.json'], 'no profile')):
            with self.subTest(extra=extra), self.assertRaisesRegex(ValueError, message):
                pir.execute(pir.parser().parse_args(['scheduler', 'upgrade', *extra]))
        with self.assertRaisesRegex(ValueError, 'only to scheduler upgrade'):
            pir.execute(pir.parser().parse_args(['scheduler', 'seed', '--platform', 'macos', '--profile-file', '/p.json',
                                                 '--reset-delivery']))

    def test_failed_seed_receipt_prevents_observing_an_old_agent(self):
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory) / 'profile.json'
            profile.write_text(json.dumps(dict(names=[dict(firstName='Test', lastName='Fixture')],
                                               addresses=[dict(city='Test City', state='CA')], phones=[], birthYear=1980)))
            args = pir.parser().parse_args(['scheduler', 'seed', '--platform', 'macos', '--profile-file', str(profile),
                                            '--evidence-dir', directory])
            native = FakeSeedRuntime(receipt_changes={'status': 'error', 'errorCode': 'profileAlreadyExists'})
            with patch.object(pir, 'Client', side_effect=AssertionError('contacted an old listener')):
                result = pir.execute(args, runtime_factory=native.create)
            self.assertEqual(result['status'], 'inconclusive')
            self.assertIn('already has a profile', result['reason'])
            self.assertTrue(native.stopped)

    def test_seed_rejects_foreign_receipt_and_caller_supplied_scope(self):
        request = scheduler.SeedRequest('seed', Path('/profile.json'), 60)
        with self.assertRaisesRegex(RuntimeError, 'does not match'):
            scheduler.receipt_scope({'instanceID': 'different', 'mode': 'seed', 'status': 'ready'}, request, 'ours')
        args = pir.parser().parse_args(['scheduler', 'seed', '--platform', 'macos', '--profile-file', '/profile.json',
                                        '--since', CUTOFF, '--job', BROKER, '1'])
        with self.assertRaisesRegex(ValueError, 'automatically'):
            pir.execute(args)


class FakeSeedRuntime:
    def __init__(self, receipt_changes=None, process=None):
        self.receipt_changes = receipt_changes or {}
        self.process = process
        self.stopped = False

    def create(self, platform, evidence, instance, port, **options):
        self.platform, self.evidence, self.instance, self.port, self.options = platform, evidence, instance, port, options
        return self

    def launch_scheduler(self, mode, profile_json, brokers=()):
        self.launch_values = (mode, profile_json)
        self.brokers = brokers
        return dict(product=dict(executable=IDENTITY['executable']), process=self.process)

    def launch_existing(self, simulator=None):
        self.launched_existing = True
        return dict(product=dict(executable=IDENTITY['executable']), process=self.process)

    def scheduler_receipt(self):
        receipt = dict(instanceID=self.instance, mode=self.launch_values[0], status='ready', since=CUTOFF,
                       jobs=[dict(brokerURL=BROKER, profileQueryId=1)])
        receipt.update(self.receipt_changes)
        (self.evidence / 'scheduler-launch.json').write_text(json.dumps(receipt))
        return receipt

    def stop(self):
        self.stopped = True
        return dict(stopped=True)


if __name__ == '__main__':
    unittest.main()
