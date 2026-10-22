#!/usr/bin/env python3
"""Check the isolated Monterey boundary without launching apps or altering a real test bundle."""
import argparse
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[2] / 'UITests/Helpers/ui-tests'
sys.path.insert(0, str(SCRIPTS))
import artifact
import monterey


class MontereyTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.target = {'BlueprintName': 'UI Tests', 'ProductModuleName': 'UI_Tests',
                       'TestHostPath': '__TESTROOT__/Products/Review/UI Tests-Runner.app'}
        self.metadata = {'app': 'Review.app', 'distribution': 'dmg', 'os_major': '14',
                         'xcode': 'Xcode 16.2\nBuild version 16C5032a', 'architectures': ['arm64', 'x86_64']}
        (self.root / 'manifest.json').write_text(json.dumps(self.metadata))
        artifact.write_plist(self.root / 'source.xctestrun', {'TestConfigurations': [{'TestTargets': [self.target]}],
                                                           '__xctestrun_metadata__': {'FormatVersion': 2}})
        (self.root / 'Plans').mkdir()
        (self.root / 'Plans/UI Tests.xctestplan').write_text(json.dumps({'testTargets': [{'target': {'name': 'UI Tests'}}]}))

    def test_native_sonoma_never_calls_the_adapter(self):
        with mock.patch.object(artifact.platform, 'mac_ver', return_value=('14.8.9', (), 'arm64')), \
             mock.patch.object(artifact, 'output', return_value=self.metadata['xcode']), \
             mock.patch.object(monterey, 'host', side_effect=AssertionError('Adapter must not run')):
            self.assertEqual(artifact.native_host(self.root, self.target, self.root / 'Developer', {}),
                             self.root / 'Products/Review/UI Tests-Runner.app')

    def test_adapter_rejects_other_os_and_unqualified_producers_before_mutation(self):
        for os_version, producer in (('14.8.9', self.metadata['xcode']), ('12.7.6', 'Xcode 27.0\nBuild version 27A1')):
            metadata = dict(self.metadata, xcode=producer)
            (self.root / 'manifest.json').write_text(json.dumps(metadata))
            with self.subTest(os=os_version, producer=producer), \
                 mock.patch.object(monterey.platform, 'mac_ver', return_value=(os_version, (), 'arm64')), \
                 mock.patch.object(monterey, 'execute') as execute:
                with self.assertRaises(ValueError):
                    monterey.host(self.root, self.target, self.root / 'Developer', {})
                execute.assert_not_called()
        self.assertFalse((self.root / 'Compatibility').exists())

    def test_monterey_spec_keeps_filters_but_removes_modern_runtime_options(self):
        data = dict(self.target, OnlyTestIdentifiers=['First/testOne'], SkipTestIdentifiers=['First/testTwo'],
                    UITargetAppPerformanceAntipatternCheckerEnabled=True)
        result = monterey.specification(data)
        self.assertEqual(result['__xctestrun_metadata__']['FormatVersion'], 1)
        target = artifact.targets(result)[0]
        self.assertEqual(target['OnlyTestIdentifiers'], ['First/testOne'])
        self.assertEqual(target['SkipTestIdentifiers'], ['First/testTwo'])
        self.assertNotIn('UITargetAppPerformanceAntipatternCheckerEnabled', target)

    def test_methods_preserve_class_state_and_all_skipped_is_not_success(self):
        args = argparse.Namespace(root=self.root, suite='ui', plan=None, only=[], result=None,
                                  timeout=3600, xcode=None, preflight_only=False)
        for all_skipped in (False, True):
            args.result = self.root / str(all_skipped)
            flags = []

            def method(child):
                flags.append(os.environ['UITEST_RESET_CLASS_STATE'])
                self.assertEqual(child.timeout, 300)
                self.assertTrue(child._monterey_method)
                Path(os.environ['UITEST_CLASS_RESET_MARKER']).touch()
                child.result.mkdir()
                (child.result / 'summary.json').write_text(json.dumps({'executed': 1, 'skipped': int(all_skipped)}))
                return 0

            previous = {key: os.environ.get(key) for key in ('UITEST_RESET_CLASS_STATE', 'UITEST_CLASS_RESET_MARKER')}
            with mock.patch.object(monterey, 'host', return_value=self.root / 'Legacy-Runner.app'), \
                 mock.patch.object(monterey, 'xcode', return_value=(self.root / 'Developer', {})), \
                 mock.patch.object(monterey, 'binary', return_value=self.root / 'bundle'), \
                 mock.patch.object(monterey, 'output', return_value=json.dumps(['First/testOne', 'First/testTwo', 'Second/testOne'])):
                self.assertEqual(monterey.run(args, method), 1 if all_skipped else 0)
            self.assertEqual(flags, ['1', '0', '1'])
            self.assertEqual(previous, {key: os.environ.get(key) for key in previous})


if __name__ == '__main__':
    unittest.main()
