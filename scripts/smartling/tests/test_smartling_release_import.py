#!/usr/bin/env python3

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / 'smartling_release_import.sh'
RELEASE_BRANCH = 'release/ios/0.1.0'
REFRESH_PREFIX = 'release/ios/0.1.0/current'
IMPORT_BRANCH = 'smartling/release-ios-0.1.0'
STRINGS_PATH = 'iOS/App/de.lproj/Localizable.strings'
ENGLISH_STRINGS_PATH = 'iOS/App/en.lproj/Localizable.strings'
EXPORTED_XLIFF = './iOS/scripts/assets/loc/en.xcloc/Localized Contents/en.xliff'
ENGLISH_STRINGSDICT = './iOS/DuckDuckGo/UserInterfaceResources/en.lproj/Localizable.stringsdict'

READY = {
    'outcome': 'ready', 'job_id': 'job-1', 'job_url': 'https://dashboard.smartling.com/app/projects/p/account-jobs/p:job-1',
    'job_status': 'COMPLETED', 'total_strings': 20,
    'strings_left': 0, 'incomplete_locales': [], 'locales': 2, 'reason': '',
}

GH_STUB = """#!/bin/bash
printf '%s\\n' "$*" >> "$STUB_DIR/gh.log"
while [ $# -gt 0 ]; do
	if [ "$1" = "--body-file" ]; then
		count=$(ls "$STUB_DIR" | grep -c '^body-' || true)
		cp "$2" "$STUB_DIR/body-$count.md"
	fi
	args+=("$1")
	shift
done
case "${args[0]} ${args[1]}" in
	"pr list")
		[ -s "$STUB_DIR/existing_pr" ] || exit 0
		read -r state url < "$STUB_DIR/existing_pr"
		if [[ " ${args[*]} " == *" --state open "* ]]; then
			[ "$state" = "OPEN" ] && echo "$url"
		else
			echo "$state $url"
		fi
		;;
	"pr create")
		[ ! -e "$STUB_DIR/pr_create_fails" ] || { echo "GraphQL: something went wrong" >&2; exit 1; }
		echo "https://github.com/duckduckgo/apple-browsers/pull/100"
		;;
esac
exit 0
"""

LOC_TOOL_STUB = """#!/bin/bash
printf '%s\\n' "$*" >> "$STUB_DIR/loc_tool.log"
case "$1" in
	refresh-files) exit "$(cat "$STUB_DIR/refresh_exit_code")" ;;
	download) [ ! -e "$STUB_DIR/download_fails" ] || exit 1 ;;
	release-status)
		while [ $# -gt 0 ]; do [ "$1" = "--result-file" ] && cp "$STUB_DIR/release_status.json" "$2"; shift; done
		;;
esac
"""

EXPORT_STUB = """#!/bin/bash
echo "export" >> "$STUB_DIR/loc_tool.log"
[ ! -e "$STUB_DIR/export_fails" ] || exit 0
mkdir -p "iOS/scripts/assets/loc/en.xcloc/Localized Contents"
echo '<xliff/>' > "iOS/scripts/assets/loc/en.xcloc/Localized Contents/en.xliff"
echo '"regenerated" = "Regenerated";' >> iOS/App/en.lproj/Localizable.strings
"""

XCBEAUTIFY_STUB = """#!/bin/bash
cat
"""

IMPORT_STUB = """#!/bin/bash
cp "$STUB_DIR/imported.strings" iOS/App/de.lproj/Localizable.strings
"""

INTEGRITY_STUB = """#!/bin/bash
echo "integrity $*" >> "$STUB_DIR/loc_tool.log"
exit "$(cat "$STUB_DIR/integrity_exit_code")"
"""


def write_executable(path: Path, content: str):
    path.write_text(content, encoding='utf-8')
    path.chmod(0o755)


def git(cwd: Path, *args: str) -> str:
    return subprocess.run(
        ['git', *args], cwd=cwd, check=True, capture_output=True, text=True
    ).stdout.strip()


def github_outputs(text: str) -> dict:
    """Parse a GITHUB_OUTPUT file, including multi-line values written as name<<DELIMITER."""
    outputs = {}
    lines = iter(text.splitlines())
    for line in lines:
        if '<<' in line and '=' not in line:
            name, delimiter = line.split('<<', 1)
            outputs[name] = '\n'.join(iter(lambda: next(lines), delimiter))
        elif '=' in line:
            name, value = line.split('=', 1)
            outputs[name] = value
    return outputs


@unittest.skipUnless(shutil.which('jq') and shutil.which('git'), 'needs git and jq')
class ReleaseImportScriptTests(unittest.TestCase):

    def setUp(self):
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)
        root = Path(temp_dir.name)
        self.stub_dir = root / 'stubs'
        self.repo = root / 'repo'
        self.origin = root / 'origin.git'
        self.stub_dir.mkdir()
        write_executable(self.stub_dir / 'gh', GH_STUB)
        write_executable(self.stub_dir / 'xcbeautify', XCBEAUTIFY_STUB)

        git(root, 'init', '-q', '--bare', str(self.origin))
        git(root, 'init', '-q', '-b', RELEASE_BRANCH, str(self.repo))
        smartling_dir = self.repo / 'scripts' / 'smartling'
        smartling_dir.mkdir(parents=True)
        shutil.copy(SCRIPT_PATH, smartling_dir / SCRIPT_PATH.name)
        write_executable(smartling_dir / 'loc_tool.sh', LOC_TOOL_STUB)
        write_executable(smartling_dir / 'smartling_import.sh', IMPORT_STUB)
        write_executable(smartling_dir / 'check_translation_integrity.py', INTEGRITY_STUB)
        (self.repo / 'iOS' / 'scripts').mkdir(parents=True)
        write_executable(self.repo / 'iOS' / 'scripts' / 'loc_export.sh', EXPORT_STUB)
        (self.repo / 'iOS' / '.gitignore').write_text('scripts/assets\n', encoding='utf-8')
        (self.repo / ENGLISH_STRINGSDICT).parent.mkdir(parents=True)
        (self.repo / ENGLISH_STRINGSDICT).write_text('<plist/>\n', encoding='utf-8')
        (self.repo / 'iOS' / 'App' / 'en.lproj').mkdir(parents=True)
        (self.repo / ENGLISH_STRINGS_PATH).write_text('"a" = "A";\n', encoding='utf-8')
        (self.repo / 'iOS' / 'App' / 'de.lproj').mkdir(parents=True)
        (self.repo / STRINGS_PATH).write_text('"a" = "A";\n"b" = "B";\n', encoding='utf-8')
        (self.repo / 'iOS' / 'App' / 'de.lproj' / 'Localizable.stringsdict').write_text('<plist/>\n', encoding='utf-8')
        (self.repo / 'iOS' / 'App' / 'Localizable.xcstrings').write_text('{}\n', encoding='utf-8')
        git(self.repo, 'add', '-A')
        git(self.repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-q', '-m', 'Release')
        git(self.repo, 'remote', 'add', 'origin', str(self.origin))
        git(self.repo, 'push', '-q', 'origin', 'HEAD')

    def run_import(self, *args, existing_pr='', imported='"a" = "A";\n"b" = "B";\n"c" = "C";\n',
                   integrity_passes=True, release_status=None, refresh_passes=True, expected_exit_code=0):
        (self.stub_dir / 'existing_pr').write_text(existing_pr, encoding='utf-8')
        (self.stub_dir / 'release_status.json').write_text(json.dumps(release_status or READY), encoding='utf-8')
        (self.stub_dir / 'refresh_exit_code').write_text('0' if refresh_passes else '1', encoding='utf-8')
        (self.stub_dir / 'loc_tool.log').write_text('', encoding='utf-8')
        (self.stub_dir / 'imported.strings').write_text(imported, encoding='utf-8')
        (self.stub_dir / 'integrity_exit_code').write_text('0' if integrity_passes else '1', encoding='utf-8')
        output_file = self.stub_dir / 'github_output'
        output_file.write_text('', encoding='utf-8')
        git(self.repo, 'checkout', '-q', RELEASE_BRANCH)
        env = {
            **os.environ,
            'PATH': f"{self.stub_dir}{os.pathsep}{os.environ['PATH']}",
            'STUB_DIR': str(self.stub_dir),
            'GITHUB_OUTPUT': str(output_file),
            'RUNNER_TEMP': str(self.stub_dir),
            'SMARTLING_PROJECT_ID': 'project-123',
        }
        env.pop('GITHUB_STEP_SUMMARY', None)
        env.pop('GITHUB_RUN_ID', None)
        result = subprocess.run(
            ['./scripts/smartling/smartling_release_import.sh', 'iOS', '--release-branch', RELEASE_BRANCH, *args],
            cwd=self.repo, env=env, capture_output=True, text=True, check=False
        )
        self.assertEqual(result.returncode, expected_exit_code, result.stdout + result.stderr)
        return github_outputs(output_file.read_text(encoding='utf-8'))

    def tool_calls(self):
        return (self.stub_dir / 'loc_tool.log').read_text(encoding='utf-8').splitlines()

    def gh_calls(self):
        log = self.stub_dir / 'gh.log'
        return log.read_text(encoding='utf-8').splitlines() if log.exists() else []

    def body(self, index):
        return (self.stub_dir / f'body-{index}.md').read_text(encoding='utf-8')

    def testWhenAPullRequestExistsThenNothingIsImported(self):
        outputs = self.run_import(existing_pr='MERGED https://github.com/duckduckgo/apple-browsers/pull/1')

        self.assertEqual(outputs['outcome'], 'skipped_existing_pr')
        self.assertEqual(outputs['pr_url'], 'https://github.com/duckduckgo/apple-browsers/pull/1')
        self.assertFalse(any(call.startswith('pr create') for call in self.gh_calls()))

    def testWhenTranslationsAreReadyThenAPullRequestIsOpened(self):
        outputs = self.run_import()

        self.assertEqual(outputs['outcome'], 'pr_opened')
        self.assertEqual(outputs['job_url'], READY['job_url'])
        self.assertIn(f"[Release iOS 0.1.0]({READY['job_url']})", self.body(0))
        self.assertIn('Integrity check: passed', self.body(0))
        self.assertEqual(git(self.repo, 'show', '--name-only', '--format=', IMPORT_BRANCH), STRINGS_PATH)

    def testWhenReimportFollowsAMergedPullRequestThenANewOneIsOpened(self):
        outputs = self.run_import('--reimport', existing_pr='MERGED https://github.com/duckduckgo/apple-browsers/pull/1')

        self.assertEqual(outputs['outcome'], 'pr_opened')
        self.assertEqual(outputs['pr_url'], 'https://github.com/duckduckgo/apple-browsers/pull/100')

    def testWhenReimportUpdatesAnOpenPullRequestThenItsDescriptionShowsTheNewIntegrityResult(self):
        first = self.run_import()
        self.assertEqual(first['outcome'], 'pr_opened')
        self.assertIn('Integrity check: passed', self.body(0))

        second = self.run_import(
            '--reimport',
            existing_pr=f"OPEN {first['pr_url']}",
            imported='"a" = "A";\n',
            integrity_passes=False
        )

        self.assertEqual(second['outcome'], 'pr_updated')
        self.assertEqual(second['integrity'], 'issues_found')
        self.assertIn(f"pr edit {first['pr_url']} --body-file", '\n'.join(self.gh_calls()))
        self.assertEqual(sum(call.startswith('pr create') for call in self.gh_calls()), 1)
        updated_body = self.body(1)
        self.assertIn('found deleted or much shorter translations', updated_body)
        self.assertNotIn('Integrity check: passed', updated_body)
        self.assertEqual(
            git(self.repo, '--git-dir', str(self.origin), 'show', f'{IMPORT_BRANCH}:{STRINGS_PATH}'),
            '"a" = "A";'
        )

    def testWhenImportingThenTheReleaseFilesAreRefreshedFromTheExportBeforeTheStatusIsRead(self):
        outputs = self.run_import()

        self.assertEqual(outputs['outcome'], 'pr_opened')
        calls = self.tool_calls()
        self.assertEqual([call.split(' ')[0] for call in calls[:3]], ['export', 'refresh-files', 'release-status'])
        self.assertEqual(
            calls[1],
            f'refresh-files --file-uri-prefix {REFRESH_PREFIX} --files {EXPORTED_XLIFF} {ENGLISH_STRINGSDICT}'
        )
        self.assertIn(f'--file-uris {REFRESH_PREFIX}/en.xliff {REFRESH_PREFIX}/Localizable.stringsdict', calls[2])
        self.assertTrue(any(call.startswith('integrity') for call in calls))

    def testWhenTheExportChangesTrackedFilesThenOnlyTheImportedTranslationsAreCommitted(self):
        outputs = self.run_import()

        self.assertEqual(outputs['outcome'], 'pr_opened')
        self.assertEqual(git(self.repo, 'show', '--name-only', '--format=', IMPORT_BRANCH), STRINGS_PATH)
        self.assertEqual((self.repo / ENGLISH_STRINGS_PATH).read_text(encoding='utf-8'), '"a" = "A";\n')

    def testWhenTheRefreshFailsThenItIsAStatusErrorAndNothingIsImported(self):
        outputs = self.run_import(refresh_passes=False, expected_exit_code=1)

        self.assertEqual(outputs['outcome'], 'status_error')
        self.assertIn('Could not refresh', outputs['reason'])
        self.assertFalse(any(call.startswith('release-status') for call in self.tool_calls()))

    def testWhenTheExportProducesNoXliffThenItIsAnErrorAndNothingIsRefreshed(self):
        stale_xliff = self.repo / EXPORTED_XLIFF
        stale_xliff.parent.mkdir(parents=True)
        stale_xliff.write_text('<xliff/>', encoding='utf-8')
        (self.stub_dir / 'export_fails').touch()

        outputs = self.run_import(expected_exit_code=1)

        self.assertEqual(outputs['outcome'], 'error')
        self.assertIn('did not produce', outputs['reason'])
        self.assertEqual(self.tool_calls(), ['export'])

    def testWhenTheWorkingTreeHasChangesThenNothingIsExported(self):
        (self.repo / STRINGS_PATH).write_text('"local" = "Local";\n', encoding='utf-8')

        outputs = self.run_import(expected_exit_code=1)

        self.assertEqual(outputs['outcome'], 'error')
        self.assertEqual(self.tool_calls(), [])
        self.assertEqual((self.repo / STRINGS_PATH).read_text(encoding='utf-8'), '"local" = "Local";\n')

    def testWhenNotReadyThenTheJobsAwaitingAuthorizationAreReported(self):
        outputs = self.run_import(release_status={
            **READY, 'outcome': 'not_ready', 'strings_left': 120, 'incomplete_locales': ['de-DE'],
            'strings_awaiting_authorization': 96,
            'jobs_awaiting_authorization': ['keyChange (created 2025-04-04): https://j/1', 'pau/feature: https://j/2'],
        })

        self.assertEqual(outputs['outcome'], 'not_ready')
        self.assertEqual(outputs['strings_awaiting_authorization'], '96')
        self.assertEqual(
            outputs['jobs_awaiting_authorization'],
            '- keyChange (created 2025-04-04): https://j/1\n- pau/feature: https://j/2'
        )
        self.assertEqual(outputs['integrity'], '')

    def testWhenTheDownloadFailsThenTheOutcomeIsAnError(self):
        (self.stub_dir / 'download_fails').touch()

        outputs = self.run_import(expected_exit_code=1)

        self.assertEqual(outputs['outcome'], 'error')
        self.assertIn('loc_tool.sh download', outputs['reason'])
        self.assertFalse(any(call.startswith('pr create') for call in self.gh_calls()))

    def testWhenOpeningThePullRequestFailsThenTheOutcomeIsAnError(self):
        (self.stub_dir / 'pr_create_fails').touch()

        outputs = self.run_import(expected_exit_code=1)

        self.assertEqual(outputs['outcome'], 'error')
        self.assertIn('Failed at line', outputs['reason'])
        self.assertEqual(outputs['integrity'], 'passed')

    def testWhenThePullRequestIsOpenedThenItsDescriptionLinksOnlyTheTechDesign(self):
        self.run_import()

        self.assertNotIn('Task/Issue URL', self.body(0))
        self.assertIn('Tech Design URL', self.body(0))

    def testWhenReimportFindsNothingNewThenTheSupersededOpenPullRequestIsClosed(self):
        first = self.run_import(imported='"a" = "A";\n"b" = "B2";\n')
        self.assertEqual(first['outcome'], 'pr_opened')

        second = self.run_import('--reimport', existing_pr=f"OPEN {first['pr_url']}", imported='"a" = "A";\n"b" = "B";\n')

        self.assertEqual(second['outcome'], 'pr_closed')
        self.assertEqual(second['pr_url'], first['pr_url'])
        calls = self.gh_calls()
        self.assertTrue(any(call.startswith(f"pr close {first['pr_url']} --comment") for call in calls))
        self.assertEqual(sum(call.startswith('pr create') for call in calls), 1)
        self.assertFalse(any(call.startswith('pr edit') for call in calls))

    def testWhenADryRunReimportFindsNothingNewThenTheOpenPullRequestIsLeftAlone(self):
        outputs = self.run_import(
            '--reimport', '--dry-run',
            existing_pr='OPEN https://github.com/duckduckgo/apple-browsers/pull/100',
            imported='"a" = "A";\n"b" = "B";\n'
        )

        self.assertEqual(outputs['outcome'], 'no_changes')
        self.assertIn('would be closed', outputs['reason'])
        self.assertFalse(any(call.startswith('pr close') for call in self.gh_calls()))

    def testWhenReimportAfterAMergedPullRequestFindsNothingNewThenNothingIsClosed(self):
        outputs = self.run_import(
            '--reimport',
            existing_pr='MERGED https://github.com/duckduckgo/apple-browsers/pull/1',
            imported='"a" = "A";\n"b" = "B";\n'
        )

        self.assertEqual(outputs['outcome'], 'no_changes')
        self.assertFalse(any(call.startswith('pr close') for call in self.gh_calls()))


if __name__ == '__main__':
    unittest.main()
