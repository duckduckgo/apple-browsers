#!/usr/bin/env python3
"""Exercise the real notarization shell function without signing or contacting Apple."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class NotarizationTests(unittest.TestCase):
    def run_notarization(self, status, submit_exit=0):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        work = root / 'release with spaces'
        work.mkdir()
        tools = root / 'bin'
        tools.mkdir()
        (tools / 'ditto').write_text('#!/bin/bash\nexit 0\n')
        (tools / 'xcrun').write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
if sys.argv[2] == 'submit':
    print(json.dumps({'id': 'test-submission', 'status': os.environ['NOTARY_STATUS']}))
    sys.exit(int(os.environ['SUBMIT_EXIT']))
if sys.argv[2] == 'log':
    pathlib.Path(sys.argv[-1]).write_text(json.dumps({'issues': [{'message': 'rejection details'}]}))
else:
    sys.exit(99)
''')
        for path in tools.iterdir():
            path.chmod(0o755)
        source = (Path(__file__).resolve().parents[1] / 'archive.sh').read_text()
        function = 'notarize() {' + source.split('notarize() {', 1)[1].split('\n}\n', 1)[0] + '\n}\n'
        environment = dict(os.environ, PATH=str(tools) + ':' + os.environ['PATH'], workdir=str(work),
                           app_path=str(work / 'Review.app'), CI='true', APPLE_API_KEY_PATH='fake-key',
                           APPLE_API_KEY_ID='fake-id', APPLE_API_KEY_ISSUER='fake-issuer',
                           NOTARY_STATUS=status, SUBMIT_EXIT=str(submit_exit))
        result = subprocess.run(['/bin/bash', '-c', 'set -e\ndie() { echo "$*" >&2; exit 1; }\n' + function
                                 + '\nnotarize\ntouch "$workdir/would-staple"'],
                                env=environment, text=True, capture_output=True)
        return result, work

    def test_invalid_submission_cannot_reach_stapling_and_preserves_apple_log(self):
        result, work = self.run_notarization('Invalid')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((work / 'would-staple').exists())
        self.assertEqual(json.loads((work / 'notarization.json').read_text())['status'], 'Invalid')
        self.assertIn('rejection details', (work / 'notarization-log.json').read_text())

    def test_accepted_submission_can_reach_stapling(self):
        result, work = self.run_notarization('Accepted')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((work / 'would-staple').exists())
        self.assertFalse((work / 'notarization-log.json').exists())

    def test_command_failure_cannot_reach_stapling(self):
        result, work = self.run_notarization('Accepted', submit_exit=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((work / 'would-staple').exists())


if __name__ == '__main__':
    unittest.main()
