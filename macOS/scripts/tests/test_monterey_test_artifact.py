#!/usr/bin/env python3
"""Exercise the optional legacy boundary without UI, profile resets or real test execution."""
import argparse
from contextlib import nullcontext, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[2] / 'UITests/Helpers/ui-tests'
spec = importlib.util.spec_from_file_location('monterey', SCRIPTS / 'monterey.py')
monterey = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monterey)


class MontereyTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.products = self.root / 'Products'
        self.products.mkdir()
        self.target = {'BlueprintName': 'UI Tests', 'ProductModuleName': 'UI_Tests', 'IsUITestBundle': True,
                       'TestHostPath': '__TESTROOT__/Review/UI Tests-Runner.app',
                       'TestHostBundleIdentifier': 'example.tests'}
        monterey.write_plist(self.products / 'tests.xctestrun', {
            'TestConfigurations': [{'TestTargets': [self.target]}], '__xctestrun_metadata__': {'FormatVersion': 2}})

    def test_native_os_rejected_before_any_commands_or_changes(self):
        with mock.patch.object(monterey.platform, 'mac_ver', return_value=('14.8.9', (), 'arm64')), \
             mock.patch.object(monterey, 'execute') as execute, \
             self.assertRaisesRegex(ValueError, 'macOS 12 only'):
            monterey.run(argparse.Namespace())
        execute.assert_not_called()

    def test_unqualified_compiler_rejected_before_runner_preparation(self):
        bundle = self.products / 'Review/UI Tests-Runner.app/Contents/PlugIns/UI Tests.xctest'
        (bundle / 'Contents').mkdir(parents=True)
        monterey.write_plist(bundle / 'Contents/Info.plist', {'CFBundleExecutable': 'Tests', 'DTXcodeBuild': '27A1'})
        with mock.patch.object(monterey.platform, 'mac_ver', return_value=('12.7.6', (), 'arm64')), \
             mock.patch.object(monterey.platform, 'machine', return_value='arm64'), \
             mock.patch.object(monterey, 'output', return_value='arm64 x86_64'), \
             mock.patch.object(monterey, 'execute') as execute, \
             self.assertRaisesRegex(ValueError, 'Xcode 16.2'):
            monterey.host(self.products, self.target, self.root / 'Developer', {})
        execute.assert_not_called()
        self.assertFalse((self.products / 'Compatibility').exists())

    def test_plan_filters_intersect_without_running_skipped_methods(self):
        plan = {'testTargets': [{'target': {'name': 'UI Tests'}, 'selectedTests': ['First'],
                                 'skippedTests': ['First/testTwo()']}]}
        inventory = ['First/testOne', 'First/testTwo', 'Second/testOne']
        self.assertEqual(monterey.select_methods(inventory, self.target, plan, ['First']), ['First/testOne'])
        with self.assertRaises(ValueError):
            monterey.select_methods(inventory, self.target, plan, ['Second'])

    def test_zero_exit_setup_failure_and_missing_results_fail(self):
        self.assertFalse(monterey.result_summary({}, 0)['passed'])
        report = {'metrics': {'testsCount': {'_value': '0'}, 'testsFailedCount': {'_value': '1'}}}
        self.assertFalse(monterey.result_summary(report, 0)['passed'])
        report = {'metrics': {'testsCount': {'_value': '1'}},
                  'issues': {'testFailureSummaries': {'_values': [{'message': 'class setup failed'}]}}}
        self.assertFalse(monterey.result_summary(report, 0)['passed'])
        report = {'metrics': {'testsCount': {'_value': '1'}}}
        self.assertTrue(monterey.result_summary(report, 0)['passed'])
        self.assertFalse(monterey.result_summary(report, 65)['passed'])

    def test_only_legacy_copy_changes_its_sandbox_entitlement(self):
        runner = self.root / 'Legacy-Runner.app'
        executable = runner / 'Contents/MacOS/Runner'
        executable.parent.mkdir(parents=True)
        shutil.copyfile('/usr/bin/true', executable)
        executable.chmod(0o755)
        monterey.write_plist(runner / 'Contents/Info.plist', {
            'CFBundleIdentifier': 'example.runner', 'CFBundleExecutable': 'Runner'})
        source = plistlib.dumps({'com.apple.security.app-sandbox': True,
                                'com.apple.security.network.client': True}).decode()
        monterey.sign_runner(runner, source)
        actual = plistlib.loads(monterey.output(['codesign', '-d', '--entitlements', ':-', runner]).rstrip('\0').encode())
        self.assertFalse(actual['com.apple.security.app-sandbox'])
        self.assertTrue(actual['com.apple.security.network.client'])
        self.assertTrue(plistlib.loads(source.encode())['com.apple.security.app-sandbox'])

    def test_class_state_preserved_and_entirely_skipped_run_fails(self):
        app = self.root / 'Review.app'
        (app / 'Contents').mkdir(parents=True)
        monterey.write_plist(app / 'Contents/Info.plist', {'CFBundleIdentifier': 'com.duckduckgo.macos.browser.review'})
        plan = self.root / 'plan.json'
        plan.write_text(json.dumps({'testTargets': [{'target': {'name': 'UI Tests'}}]}))
        for all_skipped in (False, True):
            with self.subTest(all_skipped=all_skipped):
                args = argparse.Namespace(products=self.products, target='UI Tests', xcode=None, app=app,
                                          preflight_only=False, plan=plan, only=[], user_mode='internal',
                                          result=self.root / str(all_skipped), timeout=300)
                flags = []
                def output(command, **_kwargs):
                    if command[:2] == ['xcode-select', '-p']:
                        return str(self.root / 'Developer')
                    if command[0] in ('stat', 'id'):
                        return 'test-user'
                    return json.dumps(['First/testOne', 'First/testTwo', 'Second/testOne'])
                def method(spec, _runner, _args, _environment, _result):
                    environment = spec['UI Tests']['EnvironmentVariables']
                    self.assertEqual(environment['INTERNAL_USER_MODE'], 'true')
                    flags.append(environment['UITEST_RESET_CLASS_STATE'])
                    return dict(executed=1, skipped=int(all_skipped), failed=0, passed=True)
                with mock.patch.object(monterey.platform, 'mac_ver', return_value=('12.7.6', (), 'arm64')), \
                     mock.patch.object(monterey, 'host', return_value=self.root / 'Legacy-Runner.app'), \
                     mock.patch.object(monterey, 'binary', return_value=self.root / 'binary'), \
                     mock.patch.object(monterey, 'output', side_effect=output), \
                     mock.patch.object(monterey, 'test_server', return_value=nullcontext()), \
                     mock.patch.object(monterey, 'stop_app'), \
                     mock.patch.object(monterey, 'execute') as execute, \
                     mock.patch.object(monterey, 'execute_method', side_effect=method), redirect_stdout(io.StringIO()):
                    self.assertEqual(monterey.run(args), int(all_skipped))
                self.assertEqual(flags, ['1', '0', '1'])
                self.assertEqual(sum(call.args[0][0] == 'bash' for call in execute.call_args_list), 2)
                self.assertEqual(json.loads((args.result / 'summary.json').read_text())['class_resets'], 2)


if __name__ == '__main__':
    unittest.main()
