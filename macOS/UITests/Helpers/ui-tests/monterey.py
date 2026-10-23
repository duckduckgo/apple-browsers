#!/usr/bin/env python3
"""Run native Xcode 16.2 test products on macOS 12 using installed Xcode 13.4.1 only."""
import argparse
import copy
from contextlib import contextmanager
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

HERE = Path(__file__).resolve().parent
REVIEW_IDS = {'com.duckduckgo.macos.browser.review': 'review',
              'com.duckduckgo.mobile.ios.review': 'review-appstore'}


def execute(command, **kwargs):
    return subprocess.run([str(part) for part in command], check=True, **kwargs)


def output(command, **kwargs):
    return execute(command, stdout=subprocess.PIPE, text=True, **kwargs).stdout.strip()


def read_plist(path):
    return plistlib.loads(path.read_bytes())


def write_plist(path, value):
    path.write_bytes(plistlib.dumps(value))


def binary(bundle):
    return bundle / 'Contents/MacOS' / read_plist(bundle / 'Contents/Info.plist')['CFBundleExecutable']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def targets(data):
    if 'TestConfigurations' in data:
        return [target for config in data['TestConfigurations'] if config.get('IsEnabled', True)
                for target in config['TestTargets']]
    return [value for key, value in data.items() if not key.startswith('__')
            and isinstance(value, dict) and value.get('IsUITestBundle')]


def loader_environment(root, runner, developer):
    sdk = developer / 'Platforms/MacOSX.platform/Developer'
    frameworks = [runner.parent, runner / 'Contents/Frameworks', root / 'Review', sdk / 'Library/Frameworks']
    environment = {key: value for key, value in os.environ.items() if not key.startswith('DYLD_')}
    return dict(environment, DEVELOPER_DIR=str(developer), DYLD_FRAMEWORK_PATH=':'.join(map(str, frameworks)),
                DYLD_LIBRARY_PATH=str(sdk / 'usr/lib') + ':' + str(root / 'Review'))


def sign_runner(host, entitlements):
    with tempfile.NamedTemporaryFile(suffix='.entitlements', dir=host.parent) as stream:
        values = plistlib.loads(entitlements.encode())
        values['com.apple.security.app-sandbox'] = False
        stream.write(plistlib.dumps(values))
        stream.flush()
        execute(['codesign', '-f', '-s', '-', '--deep', '--entitlements', stream.name, host])


def host(root, target, developer, env):
    original = root / target['TestHostPath'].replace('__TESTROOT__/', '')
    original_bundle = original / 'Contents/PlugIns' / (target['BlueprintName'] + '.xctest')
    if not platform.mac_ver()[0].startswith('12.'):
        raise ValueError('The Monterey adapter is restricted to macOS 12')
    if platform.machine() not in output(['lipo', '-archs', binary(original_bundle)]).split():
        raise ValueError('The Monterey artifact does not contain this architecture')
    if read_plist(original_bundle / 'Contents/Info.plist').get('DTXcodeBuild') != '16C5032a':
        raise ValueError('Monterey requires the universal macOS 14 / Xcode 16.2 test artifact')
    if not output(['xcodebuild', '-version'], env=env).startswith('Xcode 13.4.1\n'):
        raise ValueError('Monterey requires installed Xcode 13.4.1')
    source = HERE / 'monterey/XCTestCompat.swift'
    seal = original_bundle / 'Contents/_CodeSignature/CodeResources'
    entitlements = output(['codesign', '-d', '--entitlements', ':-', original]).rstrip('\0')
    if not entitlements:
        raise ValueError('The native test runner must supply its original code-signing entitlements')
    fingerprint = hashlib.sha256((output(['xcodebuild', '-version'], env=env) + platform.machine()
                                  + digest(binary(original_bundle)) + digest(seal) + digest(source) + digest(Path(__file__)) + entitlements).encode()).hexdigest()[:20]
    final = root / 'Compatibility' / fingerprint
    if (final / 'ready').is_file():
        return final / 'Legacy-Runner.app'
    final.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.preparing-', dir=final.parent))
    sdk = developer / 'Platforms/MacOSX.platform/Developer'
    framework = stage / 'XCTestCompat.framework'
    (framework / 'Versions/A').mkdir(parents=True)
    compat_binary = framework / 'Versions/A/XCTestCompat'
    execute(['xcrun', 'swiftc', '-target', platform.machine() + '-apple-macos12.0', '-module-name', 'XCUIAutomation', '-emit-library',
             '-F', sdk / 'Library/Frameworks', '-I', sdk / 'usr/lib', '-L', sdk / 'usr/lib',
             '-Xlinker', '-reexport_framework', '-Xlinker', 'XCTest', '-Xlinker', '-reexport-lXCTestSwiftSupport',
             '-Xlinker', '-install_name', '-Xlinker', '@rpath/XCTestCompat.framework/Versions/A/XCTestCompat', source, '-o', compat_binary], env=env)
    (framework / 'Versions/Current').symlink_to('A')
    (framework / 'XCTestCompat').symlink_to('Versions/Current/XCTestCompat')
    execute(['codesign', '-f', '-s', '-', compat_binary])
    host = stage / 'Legacy-Runner.app'
    execute(['ditto', sdk / 'Library/Xcode/Agents/XCTRunner.app', host])
    runner = host / 'Contents/MacOS/XCTRunner'
    if len(output(['lipo', '-archs', runner]).split()) > 1:
        execute(['lipo', runner, '-thin', platform.machine(), '-output', str(runner) + '.thin'])
        os.replace(str(runner) + '.thin', runner)
    info = read_plist(host / 'Contents/Info.plist')
    info.update(CFBundleExecutable='XCTRunner', CFBundleName='Legacy-Runner', CFBundleIdentifier=target['TestHostBundleIdentifier'])
    write_plist(host / 'Contents/Info.plist', info)
    (host / 'Contents/PlugIns').mkdir(exist_ok=True)
    bundle = host / 'Contents/PlugIns' / original_bundle.name
    execute(['ditto', original_bundle, bundle])
    compat = '@rpath/XCTestCompat.framework/Versions/A/XCTestCompat'
    bundle_binary = binary(bundle)
    if len(output(['lipo', '-archs', bundle_binary]).split()) > 1:
        execute(['lipo', bundle_binary, '-thin', platform.machine(), '-output', str(bundle_binary) + '.thin'])
        os.replace(str(bundle_binary) + '.thin', bundle_binary)
    execute(['install_name_tool', '-change', '@rpath/XCTest.framework/Versions/A/XCTest', compat,
             '-change', '@rpath/libXCTestSwiftSupport.dylib', compat, binary(bundle)])
    sign_runner(host, entitlements)
    # Fail on missing symbols before any application state is touched.
    execute([sys.executable, '-c', 'import ctypes,os,sys; ctypes.CDLL(sys.argv[1], mode=os.RTLD_NOW)', binary(bundle)],
            env=loader_environment(root, host, developer))
    (stage / 'ready').touch()
    stage.rename(final)
    return final / 'Legacy-Runner.app'


def select_methods(inventory, target, plan, requested):
    config = next((item for item in plan['testTargets'] if item['target']['name'] == target['BlueprintName']), None)
    if config is None:
        raise ValueError('The selected plan does not include target ' + target['BlueprintName'])
    if not config.get('enabled', True):
        raise ValueError('The selected test target is disabled in the plan')
    def matches(method, selector):
        selector = selector.removesuffix('()')
        return method == selector or method.startswith(selector + '/') or fnmatch.fnmatchcase(method, selector)
    selected, skipped = config.get('selectedTests', []), config.get('skippedTests', [])
    methods = [method for method in inventory
               if (not selected or any(matches(method, value) for value in selected))
               and (not requested or any(matches(method, value) for value in requested))
               and not any(matches(method, value) for value in skipped)]
    if not methods:
        raise ValueError('No enabled tests match the plan and filter')
    return methods


def specification(target, runner, app, products, developer, method, mode, first):
    # Xcode 13 consumes format 1 and its installed XCTest, never a packaged modern runtime.
    keys = ('BlueprintName', 'ProductModuleName', 'IsUITestBundle', 'IsXCTRunnerHostedTestBundle',
            'TestHostBundleIdentifier', 'UITargetAppCommandLineArguments', 'UITargetAppEnvironmentVariables')
    data = {key: copy.deepcopy(target[key]) for key in keys if key in target}
    data.update(TestHostPath=str(runner), TestBundlePath='__TESTHOST__/Contents/PlugIns/' + target['BlueprintName'] + '.xctest',
                UITargetAppPath=str(app), UITargetAppBundleIdentifier=read_plist(app / 'Contents/Info.plist')['CFBundleIdentifier'],
                OnlyTestIdentifiers=[method])
    environment = {key: value for key, value in target.get('EnvironmentVariables', {}).items()
                   if not key.startswith(('DYLD_', '__', 'PERFC_', 'IDE_', 'SQLITE_'))}
    environment.update(INTERNAL_USER_MODE='true' if mode == 'internal' else 'false',
                       UITEST_APP_PATH=str(app), UITEST_RESET_CLASS_STATE='1' if first else '0')
    if 'CODE' in os.environ:
        environment['CODE'] = os.environ['CODE']
    data['EnvironmentVariables'] = environment
    runtime = loader_environment(products, runner, developer)
    data['TestingEnvironmentVariables'] = {key: runtime[key] for key in ('DYLD_FRAMEWORK_PATH', 'DYLD_LIBRARY_PATH')}
    data['UITargetAppEnvironmentVariables'] = {
        key: value for key, value in data.get('UITargetAppEnvironmentVariables', {}).items()
        if not key.startswith(('DYLD_', '__'))}
    return {target['BlueprintName']: data, '__xctestrun_metadata__': {'FormatVersion': 1}}


def result_summary(report, code):
    metrics = report.get('metrics', {})
    number = lambda key: int(metrics.get(key, {}).get('_value', 0))
    count, skipped, failed = number('testsCount'), number('testsSkippedCount'), number('testsFailedCount')
    issues = report.get('issues', {}).get('testFailureSummaries', {}).get('_values', [])
    failed = max(failed, len(issues))
    return dict(exit_code=code, executed=count, skipped=skipped, failed=failed,
                passed=code == 0 and count > 0 and failed == 0)


def stop_process(process):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()


def stop_app(app):
    executable = str(binary(app))
    for row in output(['ps', '-axo', 'pid=,comm=']).splitlines():
        parts = row.strip().split(None, 1)
        if len(parts) == 2 and parts[1] == executable:
            pid = int(parts[0])
            current = subprocess.run(['ps', '-p', str(pid), '-o', 'comm='], stdout=subprocess.PIPE, text=True)
            if current.returncode == 0 and current.stdout.strip() == executable:
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass


@contextmanager
def test_server(products, result):
    server = products / 'Review/tests-server'
    if not server.is_file():
        raise ValueError('The artifact does not contain tests-server')
    with socket.socket() as probe:
        if probe.connect_ex(('127.0.0.1', 8085)) == 0:
            raise RuntimeError('Port 8085 is occupied; no existing process was stopped')
    with (result / 'tests-server.log').open('w') as log:
        process = subprocess.Popen([str(server)], cwd=server.parent, stdin=subprocess.DEVNULL,
                                   stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            for _ in range(40):
                if process.poll() is not None:
                    raise RuntimeError('tests-server exited before readiness')
                try:
                    with urllib.request.urlopen('http://127.0.0.1:8085/', timeout=1):
                        break
                except OSError:
                    time.sleep(.25)
            else:
                raise RuntimeError('tests-server did not become ready')
            yield
        finally:
            stop_process(process)


def execute_method(spec, runner, args, environment, result):
    result.mkdir()
    write_plist(result / 'tests.xctestrun', spec)
    command = ['xcodebuild', 'test-without-building', '-xctestrun', str(result / 'tests.xctestrun'),
               '-destination', 'platform=macOS', '-parallel-testing-enabled', 'NO',
               '-resultBundlePath', str(result / 'tests.xcresult')]
    with (result / 'xcodebuild.log').open('w') as log:
        process = subprocess.Popen(command, env=environment, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            code = process.wait(timeout=min(args.timeout, 300))
        except subprocess.TimeoutExpired:
            stop_process(process)
            code = 124
        except BaseException:
            stop_process(process)
            raise
        finally:
            stop_app(args.app)
            stop_app(runner)
    report = {}
    if (result / 'tests.xcresult').is_dir():
        try:
            report = json.loads(output(['xcrun', 'xcresulttool', 'get', '--path', result / 'tests.xcresult',
                                        '--format', 'json'], env=environment))
        except (subprocess.CalledProcessError, ValueError):
            pass
    summary = result_summary(report, code)
    (result / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    return summary


def run(args):
    if not platform.mac_ver()[0].startswith('12.'):
        raise ValueError('Use the existing native workflow on macOS 14+; this command is macOS 12 only')
    products = args.products.resolve()
    sources = list(products.glob('*.xctestrun'))
    if len(sources) != 1:
        raise ValueError('Expected exactly one producer xctestrun in Build/Products')
    target = next((item for item in targets(read_plist(sources[0])) if item['BlueprintName'] == args.target), None)
    if target is None:
        raise ValueError('The artifact does not contain target ' + args.target)
    developer = args.xcode.resolve() / 'Contents/Developer' if args.xcode else Path(output(['xcode-select', '-p']))
    environment = dict(os.environ, DEVELOPER_DIR=str(developer))
    runner = host(products, target, developer, environment)
    if args.preflight_only:
        print(json.dumps({'loader_passed': True, 'app_launched': False}))
        return 0
    if args.app is None:
        raise ValueError('--app must identify the notarized Review application')
    args.app = args.app.resolve()
    bundle_id = read_plist(args.app / 'Contents/Info.plist')['CFBundleIdentifier']
    if bundle_id not in REVIEW_IDS:
        raise ValueError('Refusing to reset or launch a non-Review app')
    if output(['stat', '-f', '%Su', '/dev/console']) != output(['id', '-un']):
        raise RuntimeError('Use the logged-in, unlocked GUI account with UI Automation already configured')
    plan_path = args.plan or HERE.parents[1] / ('UI Tests App Store Sandbox.xctestplan'
                                               if REVIEW_IDS[bundle_id] == 'review-appstore' else 'UI Tests.xctestplan')
    plan = json.loads(plan_path.read_text())
    bundle = runner / 'Contents/PlugIns' / (target['BlueprintName'] + '.xctest')
    inventory = json.loads(output([sys.executable, HERE / 'monterey/discover.py', binary(bundle),
                                   target['ProductModuleName']], env=loader_environment(products, runner, developer), timeout=60))
    methods = select_methods(inventory, target, plan, args.only)
    clean_script = HERE.parents[2] / 'clean-app.sh'
    if not clean_script.is_file():
        raise ValueError('Keep the existing macOS/clean-app.sh beside the test helpers')
    result = args.result.resolve()
    result.mkdir(parents=True, exist_ok=False, mode=0o700)
    summaries, prepared = [], set()
    with test_server(products, result):
        for index, method in enumerate(methods):
            test_class = method.split('/')[0]
            first = test_class not in prepared
            if first:
                stop_app(args.app)
                execute(['bash', clean_script, REVIEW_IDS[bundle_id]])
                execute(['defaults', 'write', bundle_id, 'moveToApplicationsFolderAlertSuppress', '-bool', 'true'])
            spec = specification(target, runner, args.app, products, developer, method, args.user_mode, first)
            summary = execute_method(spec, runner, args, environment, result / str(index + 1))
            if summary['executed'] > 0:
                prepared.add(test_class)
            summaries.append(dict(summary, method=method))
            print(json.dumps(summaries[-1]), flush=True)
    executed = sum(item['executed'] for item in summaries)
    skipped = sum(item['skipped'] for item in summaries)
    summary = dict(requested=len(methods), executed=executed, skipped=skipped,
                   class_resets=len(prepared), failed_methods=sum(not item['passed'] for item in summaries),
                   passed=bool(summaries) and all(item['passed'] for item in summaries) and executed > skipped)
    (result / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    return 0 if summary['passed'] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--products', type=Path, required=True, help='Extracted native Build/Products directory')
    parser.add_argument('--app', type=Path, help='Notarized Review application; required for execution')
    parser.add_argument('--target', default='UI Tests')
    parser.add_argument('--plan', type=Path)
    parser.add_argument('--only', action='append', default=[])
    parser.add_argument('--user-mode', choices=['production', 'internal'], default='production')
    parser.add_argument('--xcode', type=Path)
    parser.add_argument('--result', type=Path, required=True)
    parser.add_argument('--timeout', type=int, default=300)
    parser.add_argument('--preflight-only', action='store_true')
    return run(parser.parse_args())


if __name__ == '__main__':
    sys.exit(main())
