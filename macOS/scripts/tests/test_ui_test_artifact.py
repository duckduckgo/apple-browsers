#!/usr/bin/env python3
"""Portable test execution checks; never launch an app or touch real user defaults."""
import argparse
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import tarfile
import tempfile
import unittest
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[2] / 'UITests/Helpers/ui-tests'


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


artifact = load('artifact')
lifecycle = load('lifecycle')


class PortableTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.target = {'BlueprintName': 'UI Tests', 'ProductModuleName': 'UI_Tests',
                       'TestHostPath': '__TESTROOT__/Products/Review/UI Tests-Runner.app',
                       'TestBundlePath': '__TESTHOST__/Contents/PlugIns/UI Tests.xctest',
                       'TestHostBundleIdentifier': 'example.tests', 'IsUITestBundle': True,
                       'EnvironmentVariables': {'DYLD_INSERT_LIBRARIES': '/builder/diagnostics.dylib', 'CI': 'true'},
                       'UITargetAppEnvironmentVariables': {'DYLD_FRAMEWORK_PATH': '/builder/frameworks'}}
        self.metadata = {'app': 'DuckDuckGo Review.app', 'distribution': 'dmg', 'architectures': ['x86_64'],
                         'tests': {'UI Tests': ['First/testOne', 'First/testTwo', 'Second/testOne']}}
        (self.root / 'manifest.json').write_text(json.dumps(self.metadata))
        (self.root / 'Plans').mkdir()
        (self.root / 'Plans/UI Tests.xctestplan').write_text('{}')

    def test_runtime_honors_selected_developer_directory(self):
        developer = self.root / 'Xcode.app/Contents/Developer'
        (developer / 'usr/bin').mkdir(parents=True)
        (developer / 'usr/bin/xcodebuild').touch()
        with mock.patch.dict(os.environ, {'DEVELOPER_DIR': str(developer)}), mock.patch.object(artifact, 'output') as output:
            selected, environment = artifact.xcode(argparse.Namespace(xcode=None))
        self.assertEqual(selected, developer)
        self.assertEqual(environment['DEVELOPER_DIR'], str(developer))
        output.assert_not_called()

    def test_plan_selection_and_cli_filter_intersect(self):
        plan = {'testTargets': [{'target': {'name': 'UI Tests'}, 'selectedTests': ['First', 'Second/testOne()'],
                                'skippedTests': ['First/testTwo()']}]}
        self.assertEqual(artifact.selected_tests(self.metadata, self.target, plan, ['First']), ['First/testOne'])
        self.assertEqual(artifact.selected_tests(self.metadata, self.target, plan, ['Missing']), [])

    def test_relocated_run_has_no_builder_injection_and_uses_runtime_secrets(self):
        host = self.root / 'runner.app'
        plan = {'defaultOptions': {'performanceAntipatternCheckerEnabled': True, 'environmentVariableEntries': [{'key': 'CODE', 'value': '$(CODE)'}],
                                   'commandLineArgumentEntries': [{'argument': '-test', 'enabled': True}]}}
        with mock.patch.dict(os.environ, {'CODE': 'runtime-only'}):
            data = artifact.specification(self.root, self.target, host, None, self.root / 'Developer', ['First/testOne'], plan, 'internal')
        target = artifact.targets(data)[0]
        self.assertEqual(target['OnlyTestIdentifiers'], ['First/testOne'])
        self.assertEqual(target['TestHostPath'], str(host))
        self.assertEqual(target['EnvironmentVariables']['CODE'], 'runtime-only')
        self.assertEqual(target['EnvironmentVariables']['INTERNAL_USER_MODE'], 'true')
        self.assertNotIn('DYLD_INSERT_LIBRARIES', target['EnvironmentVariables'])
        self.assertEqual(target['UITargetAppEnvironmentVariables'], {})
        self.assertEqual(target['CommandLineArguments'], ['-test'])
        self.assertTrue(target['UITargetAppPerformanceAntipatternCheckerEnabled'])

    def test_old_xcode_specification_is_format_one(self):
        data = artifact.specification(self.root, self.target, self.root / 'runner.app', self.root / 'compat',
                                      self.root / 'Developer', ['First/testOne'], {}, 'production')
        self.assertEqual(data['__xctestrun_metadata__']['FormatVersion'], 1)
        self.assertEqual(artifact.targets(data)[0]['BlueprintName'], 'UI Tests')
        self.assertNotIn('DependentProductPaths', artifact.targets(data)[0])

    def test_ui_plan_does_not_inherit_producer_performance_diagnostics(self):
        self.target['UITargetAppPerformanceAntipatternCheckerEnabled'] = True
        for plan in ({}, {'defaultOptions': {'performanceAntipatternCheckerEnabled': False}}):
            data = artifact.specification(self.root, self.target, self.root / 'runner.app', None,
                                          self.root / 'Developer', ['First/testOne'], plan, 'production')
            self.assertFalse(artifact.targets(data)[0]['UITargetAppPerformanceAntipatternCheckerEnabled'])

    def test_legacy_methods_preserve_class_state(self):
        app = self.root / 'Products/Review' / self.metadata['app']
        app.mkdir(parents=True)
        artifact.write_plist(self.root / 'source.xctestrun', {'TestConfigurations': [{'TestTargets': [self.target]}]})
        host = self.root / 'runner.app'
        args = argparse.Namespace(root=self.root, environment_file=None, preflight_only=False, app=None, suite='ui', plan=None,
                                  only=[], result=self.root / 'Results', user_mode='production', timeout=3600)

        class PassingProcess:
            def __init__(self, command, **kwargs):
                spec = artifact.read_plist(Path(command[command.index('-xctestrun') + 1]))
                environment = artifact.targets(spec)[0]['EnvironmentVariables']
                Path(environment['UITEST_CLASS_RESET_MARKER']).touch()
                Path(command[command.index('-resultBundlePath') + 1]).mkdir()
                kwargs['stdout'].write('Executed 1 test, with 0 failures\n')

            def wait(self, **kwargs):
                return 0

        with mock.patch.object(artifact.platform, 'machine', return_value='x86_64'), \
             mock.patch.object(artifact, 'xcode', return_value=(self.root / 'Developer', {})), \
             mock.patch.object(artifact, 'legacy_host', return_value=(host, self.root / 'compat')), \
             mock.patch.object(artifact, 'execute'), mock.patch.object(artifact, 'stop_owned_runners'), mock.patch.object(artifact.subprocess, 'Popen', PassingProcess), \
             mock.patch('builtins.print'):
            self.assertEqual(artifact.execute_tests(args), 0)
        flags = [artifact.targets(artifact.read_plist(args.result / str(i) / 'run.xctestrun'))[0]
                 ['EnvironmentVariables']['UITEST_RESET_CLASS_STATE'] for i in (1, 2, 3)]
        self.assertEqual(flags, ['1', '0', '1'])

    def test_runner_cleanup_only_targets_this_artifact(self):
        host = self.root / 'Runner.app'
        executable = str(host / 'Contents/MacOS/Runner')
        with mock.patch.object(artifact, 'binary', return_value=Path(executable)), \
             mock.patch.object(artifact, 'output', side_effect=['123 ' + executable + '\n456 /other/Runner.app/Contents/MacOS/Runner', executable]), \
             mock.patch.object(artifact.os, 'kill') as kill:
            artifact.stop_owned_runners(host)
        kill.assert_called_once_with(123, artifact.signal.SIGTERM)

    def test_gui_launcher_quotes_arguments_and_removes_runtime_secrets(self):
        args = argparse.Namespace(root=self.root, environment_file=None, preflight_only=False, app=None,
                                  suite='ui', plan="a plan with ' quotes", only=['First/testOne'], result=self.root / 'GUI',
                                  gui=True, user_mode='production', timeout=300, xcode=None)
        def open_terminal(command):
            launcher = Path(command[-1])
            self.assertNotIn('runtime secret', launcher.read_text())
            self.assertEqual(os.stat(launcher.parent / 'environment.json').st_mode & 0o777, 0o600)
            self.assertEqual(__import__('subprocess').run(['bash', '-n', str(launcher)]).returncode, 0)
            (launcher.parent / 'exit-code').write_text('0')
        with mock.patch.dict(os.environ, {'CODE': 'runtime secret'}), \
             mock.patch.object(artifact, 'execute', side_effect=open_terminal), \
             mock.patch.object(artifact, 'require_noninteractive_automation'), mock.patch('builtins.print'):
            self.assertEqual(artifact.run(args), 0)
        self.assertFalse((args.result / 'environment.json').exists())

    def test_unattended_run_rejects_required_authentication(self):
        with mock.patch.object(artifact.Path, 'is_file', return_value=True), \
             mock.patch.object(artifact, 'output', return_value='This device requires user authentication to enable Automation Mode.'):
            with self.assertRaisesRegex(RuntimeError, 'UI Automation requires'):
                artifact.require_noninteractive_automation()

    def test_configured_automation_does_not_need_to_be_currently_active(self):
        with mock.patch.object(artifact.Path, 'is_file', return_value=True), \
             mock.patch.object(artifact, 'output', return_value='Automation Mode is disabled.\nThis device DOES NOT REQUIRE user authentication to enable Automation Mode.'):
            artifact.require_noninteractive_automation()

    def test_already_enabled_automation_does_not_request_reconfiguration(self):
        with mock.patch.object(artifact.Path, 'is_file', return_value=True), \
             mock.patch.object(artifact, 'output', return_value='Automation Mode is enabled.\nThis device requires user authentication to enable Automation Mode.'):
            artifact.require_noninteractive_automation()

    def test_download_rejects_plain_http_before_writing(self):
        with self.assertRaises(ValueError):
            artifact.download(argparse.Namespace(url='http://example.com/run.json', output=self.root / 'download'))
        self.assertFalse((self.root / 'download').exists())

    def test_extract_rejects_escape_and_external_link(self):
        for name, link in [('../outside', None), ('absolute-link', '/tmp/outside')]:
            archive = self.root / 'unsafe.tar'
            with tarfile.open(archive, 'w') as stream:
                entry = tarfile.TarInfo(name)
                if link:
                    entry.type = tarfile.SYMTYPE
                    entry.linkname = link
                stream.addfile(entry)
            with self.assertRaises(ValueError):
                artifact.extract(archive, self.root)
        self.assertFalse((self.root / 'outside').exists())

    def test_extract_preserves_framework_symlinks(self):
        archive = self.root / 'framework.tar'
        with tarfile.open(archive, 'w') as stream:
            entry = tarfile.TarInfo('F.framework/Versions/A/F')
            entry.size = 4
            stream.addfile(entry, io.BytesIO(b'test'))
            entry = tarfile.TarInfo('F.framework/F')
            entry.type = tarfile.SYMTYPE
            entry.linkname = 'Versions/A/F'
            stream.addfile(entry)
        artifact.extract(archive, self.root)
        self.assertTrue((self.root / 'F.framework/F').is_symlink())
        self.assertEqual((self.root / 'F.framework/F').read_bytes(), b'test')

    def test_reset_rejects_production_without_touching_defaults(self):
        with mock.patch.object(lifecycle.subprocess, 'run') as command:
            with self.assertRaises(ValueError):
                lifecycle.reset('com.duckduckgo.macos.browser', home=self.root)
        command.assert_not_called()

    def test_reset_only_deletes_selected_profile(self):
        review = lifecycle.BUNDLE_IDS['review']
        review_state = self.root / 'Library/Containers' / review / 'Data'
        debug_state = self.root / 'Library/Containers' / lifecycle.BUNDLE_IDS['debug'] / 'Data'
        for folder in (review_state, debug_state):
            folder.mkdir(parents=True)
            (folder / 'state').write_text('preserve other profiles')
        with mock.patch.object(lifecycle.subprocess, 'run'):
            lifecycle.reset(review, home=self.root)
        self.assertFalse(review_state.exists())
        self.assertTrue((debug_state / 'state').is_file())

    def test_reset_rejects_redirected_parent_before_touching_defaults(self):
        (self.root / 'outside').mkdir()
        (self.root / 'Library').symlink_to(self.root / 'outside')
        with mock.patch.object(lifecycle.subprocess, 'run') as command:
            with self.assertRaises(ValueError):
                lifecycle.reset(lifecycle.BUNDLE_IDS['review'], home=self.root)
        command.assert_not_called()

    def test_stop_does_not_kill_reused_pid(self):
        state = self.root / 'server.json'
        state.write_text(json.dumps({'pid': 123, 'identity': 'owned process'}))
        with mock.patch.object(lifecycle, 'server_identity', return_value='different process'), \
             mock.patch.object(lifecycle.os, 'kill') as kill:
            lifecycle.stop_server(state)
        kill.assert_not_called()
        self.assertFalse(state.exists())


if __name__ == '__main__':
    unittest.main()
