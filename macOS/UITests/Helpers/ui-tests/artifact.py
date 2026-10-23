#!/usr/bin/env python3
"""Package native Xcode test products once per environment and run them without rebuilding."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request

HERE = Path(__file__).resolve().parent
SUITES = {'ui': 'UI Tests', 'performance': 'Performance Tests', 'sync': 'SyncE2EUITests', 'sync-appstore': 'SyncE2EUITests App Store'}


def execute(command, **kwargs):
    return subprocess.run([str(part) for part in command], check=True, **kwargs)


def output(command, **kwargs):
    return execute(command, stdout=subprocess.PIPE, text=True, **kwargs).stdout.strip()


def read_plist(path):
    with open(path, 'rb') as stream:
        return plistlib.load(stream)


def write_plist(path, data):
    with open(path, 'wb') as stream:
        plistlib.dump(data, stream)


def binary(bundle):
    return bundle / 'Contents/MacOS' / read_plist(bundle / 'Contents/Info.plist')['CFBundleExecutable']


def digest(path):
    value = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def xcode(args):
    developer = args.xcode.resolve() / 'Contents/Developer' if args.xcode else Path(os.environ.get('DEVELOPER_DIR') or output(['xcode-select', '-p']))
    if not (developer / 'usr/bin/xcodebuild').is_file():
        raise ValueError('Install a compatible full Xcode, or pass --xcode /Applications/Xcode.app')
    environment = {key: value for key, value in os.environ.items() if not key.startswith('DYLD_')}
    return developer, dict(environment, DEVELOPER_DIR=str(developer))


def targets(data):
    if 'TestConfigurations' not in data:
        return [target for key, target in data.items() if not key.startswith('__') and isinstance(target, dict)]
    return [target for config in data['TestConfigurations'] if config.get('IsEnabled', True) for target in config['TestTargets']]


def loader_environment(root, host, developer):
    sdk = developer / 'Platforms/MacOSX.platform/Developer'
    frameworks = [host / 'Contents/Frameworks', sdk / 'Library/Frameworks', sdk / 'Library/PrivateFrameworks',
                  root / 'Products/Review', root / 'Products/Review/PackageFrameworks']
    if platform.mac_ver()[0].startswith('12.'):
        frameworks.insert(0, host.parent)
    environment = {key: value for key, value in os.environ.items() if not key.startswith('DYLD_')}
    return dict(environment, DYLD_FRAMEWORK_PATH=':'.join(map(str, frameworks)),
                DYLD_LIBRARY_PATH=str(sdk / 'usr/lib') + ':' + str(root / 'Products/Review'))


def pack(args):
    args.developer = args.developer or Path(os.environ.get('DEVELOPER_DIR') or output(['xcode-select', '-p']))
    products = args.products.resolve()
    sources = list(products.glob('macOS UI Test Artifacts*.xctestrun'))
    sources = [p for p in sources if ('App Store' in p.name) == (args.distribution == 'appstore')]
    if len(sources) != 1:
        raise ValueError('Expected exactly one artifact-production xctestrun; found ' + str(sources))
    data = read_plist(sources[0])
    apps = list((products / 'Review').glob('DuckDuckGo*.app'))
    if len(apps) != 1:
        raise ValueError('Expected exactly one exported DuckDuckGo application; found ' + str(apps))
    app = apps[0]
    app_name = app.name
    app_info = read_plist(app / 'Contents/Info.plist')
    first = targets(data)[0]
    first_runner = Path(first['TestHostPath'].replace('__TESTROOT__', str(products)))
    architectures = output(['lipo', '-archs', binary(first_runner / 'Contents/PlugIns' / (first['BlueprintName'] + '.xctest'))]).split()
    with tempfile.TemporaryDirectory(prefix='ddg-test-artifact-') as temporary:
        root = Path(temporary) / 'ui-tests'
        destination = root / 'Products/Review'
        destination.mkdir(parents=True)
        for target in targets(data):
            host = Path(target['TestHostPath'].replace('__TESTROOT__', str(products)))
            execute(['ditto', host, destination / host.name])
            packaged_host = destination / host.name
            target['TestHostPath'] = '__TESTROOT__/Products/Review/' + host.name
            target['UITargetAppPath'] = str(app)
            target['UITargetAppBundleIdentifier'] = app_info['CFBundleIdentifier']
            bundle = packaged_host / 'Contents/PlugIns' / (target['BlueprintName'] + '.xctest')
            test_architectures = output(['lipo', '-archs', binary(bundle)]).split()
            for architecture in architectures:
                if architecture not in test_architectures:
                    raise ValueError('Test bundle must contain architecture ' + architecture)
        for pattern in ('*.bundle', '*.framework', '*.dylib', 'tests-server'):
            for dependency in (products / 'Review').glob(pattern):
                execute(['ditto', dependency, destination / dependency.name])
        server = destination / 'tests-server'
        if not server.is_file():
            raise ValueError('The producer did not build tests-server')
        server_architectures = output(['lipo', '-archs', server]).split()
        for architecture in architectures:
            if architecture not in server_architectures:
                raise ValueError('tests-server must contain architecture ' + architecture)
        shutil.copytree(HERE, root / 'Scripts', ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        plans = root / 'Plans'
        plans.mkdir()
        for folder in (HERE.parents[2] / 'UITests', HERE.parents[2] / 'PerformanceTests', HERE.parents[2] / 'SyncE2EUITests'):
            for plan in folder.glob('*.xctestplan'):
                shutil.copy2(plan, plans / plan.name)
        for target in targets(data):
            target['UITargetAppPath'] = '__TESTROOT__/Products/Review/' + app_name
        write_plist(root / 'source.xctestrun', data)
        metadata = {'format': 1, 'git_sha': output(['git', 'rev-parse', 'HEAD']),
                    'distribution': args.distribution, 'app': app_name, 'bundle_id': app_info['CFBundleIdentifier'],
                    'app_version': app_info['CFBundleShortVersionString'], 'app_build': app_info['CFBundleVersion'],
                    'xcode': output(['xcodebuild', '-version']), 'os_major': platform.mac_ver()[0].split('.')[0],
                    'architectures': architectures, 'targets': [target['BlueprintName'] for target in targets(data)]}
        (root / 'manifest.json').write_text(json.dumps(metadata, indent=2) + '\n')
        args.output.parent.mkdir(parents=True, exist_ok=True)
        execute(['tar', '-czf', args.output.resolve(), '-C', root.parent, root.name])
    print(args.output)


def extract(archive, destination):
    destination = destination.resolve()
    with tarfile.open(archive) as stream:
        for item in stream.getmembers():
            path = destination / item.name
            if os.path.commonpath([str(destination), str(path.resolve())]) != str(destination):
                raise ValueError('Unsafe archive path: ' + item.name)
            if item.issym() or item.islnk():
                link = path.parent / item.linkname if item.issym() else destination / item.linkname
                if os.path.commonpath([str(destination), str(link.resolve())]) != str(destination):
                    raise ValueError('Unsafe archive link: ' + item.name)
            if not (item.isfile() or item.isdir() or item.issym() or item.islnk()):
                raise ValueError('Unexpected archive entry: ' + item.name)
    execute(['tar', '-xf', archive, '-C', destination])


def download(args):
    if not args.url.startswith('https://'):
        raise ValueError('Run manifest must use HTTPS')
    with urllib.request.urlopen(args.url) as response:
        descriptor = json.load(response)
    args.output.mkdir(parents=True, exist_ok=False)
    for key in ('tests', 'app'):
        item = descriptor[key]
        if not item['url'].startswith('https://'):
            raise ValueError('Artifacts must use HTTPS')
        path = args.output / (key + '.tar')
        with urllib.request.urlopen(item['url']) as response, path.open('wb') as destination:
            shutil.copyfileobj(response, destination)
        if digest(path) != item['sha256']:
            raise ValueError('Artifact checksum mismatch: ' + key)
        extract(path, args.output)
    root = args.output / 'ui-tests'
    metadata = json.loads((root / 'manifest.json').read_text())
    if metadata['git_sha'] != descriptor['git_sha']:
        raise ValueError('App/test revision mismatch')
    apps = list(args.output.glob('*.app'))
    if len(apps) != 1:
        raise ValueError('Expected one downloaded app')
    execute(['ditto', apps[0], root / 'Products/Review' / metadata['app']])
    print(root)


def native_host(root, target, developer, env):
    if platform.mac_ver()[0].startswith('12.'):
        import monterey
        return monterey.host(root, target, developer, env)
    metadata = json.loads((root / 'manifest.json').read_text())
    if metadata.get('os_major') != platform.mac_ver()[0].split('.')[0]:
        raise ValueError('Use a test artifact built on this macOS major version; cross-OS XCTest adaptation is not supported')
    if metadata.get('xcode') != output(['xcodebuild', '-version'], env=env):
        raise ValueError('Use the same Xcode version and build that produced this test artifact')
    return root / target['TestHostPath'].replace('__TESTROOT__/', '')


def selected_tests(metadata, target, plan, only):
    config = next((item for item in plan.get('testTargets', []) if item['target']['name'] == target['BlueprintName']), None)
    if config is None or not config.get('enabled', True):
        raise ValueError('Selected suite is not enabled in this test plan')
    normalize = lambda value: value.removesuffix('()')
    selected = [normalize(value) for value in config.get('selectedTests', [])]
    only = [normalize(value) for value in only]
    if not selected or not only:
        return only or selected
    result = set()
    for requested in only:
        for allowed in selected:
            if requested == allowed or requested.startswith(allowed + '/'):
                result.add(requested)
            elif allowed.startswith(requested + '/'):
                result.add(allowed)
    if not result:
        raise ValueError('The requested tests are outside the selected test plan')
    return sorted(result)


def specification(root, target, host, developer, identifiers, plan, mode):
    def relocate(value):
        if isinstance(value, dict):
            return {key: relocate(item) for key, item in value.items()}
        if isinstance(value, list):
            return [relocate(item) for item in value]
        if isinstance(value, str):
            return value.replace('__TESTROOT__/Review', str(root / 'Products/Review')).replace('__DERIVEDDATA__', str(root / 'RuntimeData'))
        return value
    data = relocate(copy.deepcopy(target))
    app = root / 'Products/Review' / json.loads((root / 'manifest.json').read_text())['app']
    data['TestHostPath'] = str(host)
    data['TestBundlePath'] = '__TESTHOST__/Contents/PlugIns/' + target['BlueprintName'] + '.xctest'
    data['UITargetAppPath'] = str(app)
    # TEST_TARGET_NAME= avoids rebuilding the app, but marks it as supplied by
    # the tests. Restore the normal target-app configuration for this paired app.
    data['UseUITargetAppProvidedByTests'] = False
    data['DependentProductPaths'] = [str(host), str(host / 'Contents/PlugIns' / (target['BlueprintName'] + '.xctest')), str(app)]
    if identifiers:
        data['OnlyTestIdentifiers'] = identifiers
    else:
        data.pop('OnlyTestIdentifiers', None)
    config = next(item for item in plan['testTargets'] if item['target']['name'] == target['BlueprintName'])
    data['SkipTestIdentifiers'] = [value.removesuffix('()') for value in config.get('skippedTests', [])]
    # Artifacts contain no source/build machine paths, sanitizers or injected builder libraries.
    data['TestingEnvironmentVariables'] = {}
    env = loader_environment(root, host, developer)
    for key in ('DYLD_FRAMEWORK_PATH', 'DYLD_LIBRARY_PATH'):
        data['TestingEnvironmentVariables'][key] = env[key]
    environment = {k: v for k, v in data.get('EnvironmentVariables', {}).items() if not k.startswith(('DYLD_', '__', 'PERFC_', 'IDE_', 'SQLITE_'))}
    for item in plan.get('defaultOptions', {}).get('environmentVariableEntries', []):
        if item.get('enabled', True):
            value = item['value']
            environment[item['key']] = os.environ.get(item['key'], '') if '$(' in value else value
    environment.update(INTERNAL_USER_MODE='true' if mode == 'internal' else 'false', UITEST_APP_PATH=str(app),
                       UITEST_LIFECYCLE_SCRIPT=str(root / 'Scripts/pre-run.sh'))
    for key in ('CODE', 'UITEST_KEYCHAIN_PATH', 'UITEST_RESET_CLASS_STATE', 'UITEST_CLASS_RESET_MARKER'):
        if key in os.environ:
            environment[key] = os.environ[key]
    data['EnvironmentVariables'] = environment
    data['CommandLineArguments'] = [item['argument'] for item in plan.get('defaultOptions', {}).get('commandLineArgumentEntries', []) if item.get('enabled', True)]
    # Producer Xcode defaults must not enable app diagnostics for a different consumer test plan.
    data['UITargetAppPerformanceAntipatternCheckerEnabled'] = bool(plan.get('defaultOptions', {}).get('performanceAntipatternCheckerEnabled', False))
    data['UITargetAppMainThreadCheckerEnabled'] = bool(plan.get('defaultOptions', {}).get('mainThreadCheckerEnabled', True))
    data['UITargetAppEnvironmentVariables'] = {k: v for k, v in target.get('UITargetAppEnvironmentVariables', {}).items() if not k.startswith(('DYLD_', '__'))}
    if platform.mac_ver()[0].startswith('12.'):
        import monterey
        return monterey.specification(data)
    source = read_plist(root / 'source.xctestrun')
    if 'TestConfigurations' not in source:
        return {data['BlueprintName']: data, '__xctestrun_metadata__': source['__xctestrun_metadata__']}
    return {'TestConfigurations': [{'Name': 'Native', 'IsEnabled': True, 'TestTargets': [data]}],
            '__xctestrun_metadata__': source['__xctestrun_metadata__']}


def stop_process(process):
    if process.poll() is not None:
        return
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()


def stop_owned_app(host):
    expected = str(binary(host))
    rows = output(['ps', '-axo', 'pid=,comm=']).splitlines()
    for row in rows:
        parts = row.strip().split(None, 1)
        if len(parts) != 2 or parts[1] != expected:
            continue
        pid = int(parts[0])
        try:
            # Recheck the exact executable after enumeration; never target a runner by its generic name.
            if output(['ps', '-p', str(pid), '-o', 'comm=']) == expected:
                os.kill(pid, signal.SIGTERM)
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    status = subprocess.run(['ps', '-p', str(pid), '-o', 'comm='], stdout=subprocess.PIPE, text=True)
                    if status.returncode or status.stdout.strip() != expected:
                        break
                    time.sleep(.1)
                else:
                    if output(['ps', '-p', str(pid), '-o', 'comm=']) == expected:
                        os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, subprocess.CalledProcessError):
            pass


def execution_summary(log, code, result, expected, retrying=False, allow_all_skipped=False, env=None):
    counts = re.findall(r'Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?', log)
    count, skipped, failed = tuple(int(v or 0) for v in counts[-1]) if counts else (0, 0, 0)
    # XCTest and our observer both report each skip, sometimes with different
    # module qualification. Count methods, not duplicated log messages.
    skipped_cases = {re.sub(r'^-\[(?:\w+\.)+', '-[', case)
                     for case in re.findall(r"Test Case '([^']+)' skipped(?: |\()", log)}
    skipped = max(max((int(item[1] or 0) for item in counts), default=0), len(skipped_cases))
    successful = failed == 0
    if retrying and result.is_dir():
        # xcodebuild can exit zero after a class setup exception. The result bundle
        # records the final outcome, including native retries, without observer counts.
        report = json.loads(output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', result, '--compact'], env=env))
        count, skipped, failed = report['totalTestCount'], report['skippedTests'], report['failedTests']
        successful = report['result'] == 'Passed' and failed == 0
    passed = code == 0 and count >= expected and (count > skipped or allow_all_skipped) and successful and result.is_dir()
    return dict(exit_code=code, executed=count, skipped=skipped, failed=failed, passed=passed)


def execute_tests(args):
    if platform.mac_ver()[0].startswith('12.') and not getattr(args, '_monterey_method', False):
        import monterey
        return monterey.run(args, execute_tests)
    if args.environment_file:
        os.environ.update(json.loads(args.environment_file.read_text()))
    root = args.root.resolve()
    metadata = json.loads((root / 'manifest.json').read_text())
    if platform.machine() not in metadata['architectures']:
        raise ValueError('Artifact does not contain ' + platform.machine())
    if args.app:
        destination = root / 'Products/Review' / metadata['app']
        if destination.exists():
            raise ValueError('App already installed in artifact; use a fresh extraction')
        execute(['ditto', args.app.resolve(), destination])
    app = root / 'Products/Review' / metadata['app']
    if not app.is_dir() and not args.preflight_only:
        raise ValueError('Install the matching notarized app with --app /path/to/app')
    if not args.preflight_only and 'bundle_id' in metadata:
        app_info = read_plist(app / 'Contents/Info.plist')
        for key, field in (('bundle_id', 'CFBundleIdentifier'), ('app_version', 'CFBundleShortVersionString'), ('app_build', 'CFBundleVersion')):
            if key in metadata and app_info.get(field) != metadata[key]:
                raise ValueError('App/test artifact mismatch: ' + key)
    developer, env = xcode(args)
    target = next(t for t in targets(read_plist(root / 'source.xctestrun')) if t['BlueprintName'] == SUITES[args.suite])
    host = native_host(root, target, developer, env)
    if args.preflight_only:
        print(json.dumps({'suite': args.suite, 'target': target['BlueprintName'],
                          'native_environment_matches': True, 'app_launched': False}))
        return 0
    default_plan = {'ui': 'UI Tests App Store Sandbox' if metadata['distribution'] == 'appstore' else 'UI Tests',
                    'performance': 'macOS Performance Tests', 'sync': 'Sync End-to-End UI Tests', 'sync-appstore': 'Sync End-to-End UI Tests App Store'}[args.suite]
    plan_path = root / 'Plans' / ((args.plan or default_plan) + '.xctestplan')
    if not plan_path.is_file():
        raise ValueError('Test plan not found: ' + str(plan_path))
    plan = json.loads(plan_path.read_text())
    identifiers = selected_tests(metadata, target, plan, args.only)
    results = args.result.resolve() if args.result else root / 'Results' / (time.strftime('%Y%m%d-%H%M%S') + '-' + str(os.getpid()))
    results.mkdir(parents=True, exist_ok=False)
    batches = [identifiers]
    failures = 0
    executed = skipped = 0
    for index, batch in enumerate(batches):
        directory = results / str(index + 1)
        directory.mkdir()
        spec = directory / 'run.xctestrun'
        specification_data = specification(root, target, host, developer, batch, plan, args.user_mode)
        write_plist(spec, specification_data)
        resources = host / 'Contents/PlugIns' / (target['BlueprintName'] + '.xctest') / 'Contents/Resources'
        lifecycle_env = dict(env, BUILT_PRODUCTS_DIR=str(root / 'Products/Review'), UITEST_RESOURCES_DIR=str(resources),
                             UITEST_SERVER_STATE=str(directory / 'server.json'), UITEST_SERVER_LOG=str(directory / 'server.log'))
        pre_arguments = ['--sync'] if args.suite.startswith('sync') else []
        execute(['bash', root / 'Scripts/pre-run.sh', 'review-appstore' if metadata['distribution'] == 'appstore' else 'review'] + pre_arguments, env=lifecycle_env)
        code = 1
        try:
            command = ['xcodebuild', 'test-without-building', '-xctestrun', str(spec), '-destination', 'platform=macOS,arch=' + platform.machine(),
                       '-resultBundlePath', str(directory / 'tests.xcresult')]
            if not getattr(args, '_monterey_method', False):
                command += ['-test-iterations', '2', '-retry-tests-on-failure', '-test-repetition-relaunch-enabled', 'YES']
            with (directory / 'xcodebuild.log').open('w') as log:
                process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    code = process.wait(timeout=args.timeout)
                except subprocess.TimeoutExpired:
                    stop_process(process)
                    code = 124
                except BaseException:
                    stop_process(process)
                    raise
        finally:
            try:
                try:
                    if 'UITEST_KEYCHAIN_PATH' in os.environ or getattr(args, '_monterey_method', False):
                        stop_owned_app(app)
                finally:
                    stop_owned_app(host)
            finally:
                execute(['bash', root / 'Scripts/post-run.sh'], env=lifecycle_env)
        log = (directory / 'xcodebuild.log').read_text(errors='replace')
        print(log, end='', flush=True)
        summary = dict(tests=batch, **execution_summary(log, code, directory / 'tests.xcresult', 1,
                                                      retrying=not getattr(args, '_monterey_method', False),
                                                      allow_all_skipped=getattr(args, '_monterey_method', False), env=env))
        executed += summary['executed']
        skipped += summary['skipped']
        failures += not summary['passed']
        (directory / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps(summary), flush=True)
    passed = failures == 0 and (executed > skipped or getattr(args, '_monterey_method', False))
    (results / 'summary.json').write_text(json.dumps({'filters': identifiers, 'failed_batches': failures,
                                                     'executed': executed, 'skipped': skipped, 'passed': passed}, indent=2) + '\n')
    return 0 if passed else 1


def require_noninteractive_automation():
    tool = Path('/usr/bin/automationmodetool')
    if tool.is_file():
        status = output([tool])
        if 'requires user authentication' in status and 'Automation Mode is enabled.' not in status:
            raise RuntimeError('UI Automation requires interactive authentication. Provision the dedicated test Mac with '
                               'automationmodetool enable-automationmode-without-authentication before unattended runs.')


def run(args):
    if not args.preflight_only:
        require_noninteractive_automation()
    if args.environment_file:
        os.environ.update(json.loads(args.environment_file.read_text()))
    if not args.gui or args.preflight_only:
        return execute_tests(args)
    # Terminal launches into the unlocked console session. Forward concrete arguments, not shell environment assumptions.
    root = args.root.resolve()
    result = args.result.resolve() if args.result else root / 'Results' / (time.strftime('%Y%m%d-%H%M%S') + '-gui-' + str(os.getpid()))
    result.mkdir(parents=True, exist_ok=False)
    command = [sys.executable, str(root / 'Scripts/artifact.py'), 'run', str(root), '--suite', args.suite,
               '--user-mode', args.user_mode, '--result', str(result / 'native'), '--timeout', str(args.timeout)]
    if args.xcode:
        command += ['--xcode', str(args.xcode.resolve())]
    if args.app:
        command += ['--app', str(args.app.resolve())]
    if args.plan:
        command += ['--plan', args.plan]
    for identifier in args.only:
        command += ['--only', identifier]
    runtime_environment = result / 'environment.json'
    runtime_environment.write_text(json.dumps({key: os.environ[key] for key in ('CODE',) if key in os.environ}))
    runtime_environment.chmod(0o600)
    command += ['--environment-file', str(runtime_environment)]
    launcher = result / ('ui-tests-' + str(os.getpid()) + '.command')
    launcher.write_text('#!/bin/bash\n'
                        + "child=\ntrap 'if [[ -n \"$child\" ]]; then kill -TERM \"$child\" 2>/dev/null || true; wait \"$child\" 2>/dev/null || true; fi; exit 143' TERM INT\n"
                        + 'echo $$ > ' + shlex.quote(str(result / 'launcher.pid')) + '\n'
                        + shlex.join(command) + ' > ' + shlex.quote(str(result / 'console.log')) + ' 2>&1 &\n'
                        + 'child=$!\nwait "$child"\nstatus=$?\necho "$status" > ' + shlex.quote(str(result / 'exit-code')) + '\n')
    launcher.chmod(0o755)
    try:
        execute(['open', '-a', 'Terminal', launcher])
        started = time.monotonic()
        while not (result / 'exit-code').exists():
            pid_path = result / 'launcher.pid'
            if pid_path.exists():
                os.kill(int(pid_path.read_text()), 0)
            elif time.monotonic() - started > 60:
                raise TimeoutError('Terminal did not start the command; inspect ' + str(result))
            time.sleep(1)
        print(result)
        return int((result / 'exit-code').read_text())
    finally:
        if not (result / 'exit-code').exists() and (result / 'launcher.pid').exists():
            try:
                os.kill(int((result / 'launcher.pid').read_text()), signal.SIGTERM)
            except ProcessLookupError:
                pass
        runtime_environment.unlink()


def main():
    def interrupted(signum, _frame):
        raise InterruptedError('Interrupted by signal ' + str(signum))
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    pack_parser = sub.add_parser('pack')
    pack_parser.add_argument('--products', type=Path, required=True)
    pack_parser.add_argument('--distribution', choices=['dmg', 'appstore'], required=True)
    pack_parser.add_argument('--output', type=Path, required=True)
    pack_parser.add_argument('--developer', type=Path, default=None)
    download_parser = sub.add_parser('download')
    download_parser.add_argument('url')
    download_parser.add_argument('--output', type=Path, required=True)
    run_parser = sub.add_parser('run')
    run_parser.add_argument('root', type=Path)
    run_parser.add_argument('--app', type=Path)
    run_parser.add_argument('--suite', choices=SUITES, default='ui')
    run_parser.add_argument('--plan')
    run_parser.add_argument('--only', action='append', default=[])
    run_parser.add_argument('--xcode', type=Path)
    run_parser.add_argument('--gui', action='store_true')
    run_parser.add_argument('--preflight-only', action='store_true', help='Verify native OS/architecture/Xcode metadata without app launch/reset')
    run_parser.add_argument('--environment-file', type=Path, help=argparse.SUPPRESS)
    run_parser.add_argument('--user-mode', choices=['production', 'internal'], default='production')
    run_parser.add_argument('--result', type=Path)
    run_parser.add_argument('--timeout', type=int, default=3600)
    args = parser.parse_args()
    if args.command == 'pack':
        pack(args)
        return 0
    if args.command == 'download':
        download(args)
        return 0
    return run(args)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
