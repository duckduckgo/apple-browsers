#!/usr/bin/env python3
"""Build once, package once, run the same macOS UI tests without project/package resolution."""
import argparse
import copy
import fnmatch
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


def minimum_os(path, architecture=None):
    commands = output(['otool', '-arch', architecture or platform.machine(), '-l', path])
    versions = []
    for command in re.split(r'Load command \d+\n', commands):
        if re.search(r'cmd LC_BUILD_VERSION\b', command):
            versions += re.findall(r'^\s*minos (\S+)', command, re.MULTILINE)
        elif re.search(r'cmd LC_VERSION_MIN_MACOSX\b', command):
            versions += re.findall(r'^\s*version (\S+)', command, re.MULTILINE)
    return max((tuple(map(int, value.split('.'))) for value in versions), default=(0,))


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


def loader_environment(root, host, developer, legacy=None):
    frameworks = [root / 'Runtime/Frameworks', root / 'Runtime/PrivateFrameworks', host / 'Contents/Frameworks', root / 'Products/Review', root / 'Products/Review/PackageFrameworks']
    sdk = developer / 'Platforms/MacOSX.platform/Developer'
    if legacy:
        frameworks = [legacy, sdk / 'Library/Frameworks', sdk / 'Library/PrivateFrameworks', root / 'Products/Review', root / 'Products/Review/PackageFrameworks']
    environment = {key: value for key, value in os.environ.items() if not key.startswith('DYLD_')}
    return dict(environment, DYLD_FRAMEWORK_PATH=':'.join(map(str, frameworks)),
                DYLD_LIBRARY_PATH=(str(sdk / 'usr/lib') if legacy else str(root / 'Runtime/lib')) + ':' + str(root / 'Products/Review'))


def pack(args):
    args.developer = args.developer or Path(os.environ.get('DEVELOPER_DIR') or output(['xcode-select', '-p']))
    products = args.products.resolve()
    sources = list(products.glob('macOS UI Test Artifacts*.xctestrun'))
    sources = [p for p in sources if ('App Store' in p.name) == (args.distribution == 'appstore')]
    if len(sources) != 1:
        raise ValueError('Expected exactly one artifact-production xctestrun; found ' + str(sources))
    data = read_plist(sources[0])
    app_name = 'DuckDuckGo App Store Review.app' if args.distribution == 'appstore' else 'DuckDuckGo Review.app'
    app = products / 'Review' / app_name
    app_info = read_plist(app / 'Contents/Info.plist')
    architectures = output(['lipo', '-archs', binary(app)]).split()
    with tempfile.TemporaryDirectory(prefix='ddg-test-artifact-') as temporary:
        root = Path(temporary) / 'ui-tests'
        destination = root / 'Products/Review'
        destination.mkdir(parents=True)
        sdk = args.developer / 'Platforms/MacOSX.platform/Developer'
        for folder in ('Frameworks', 'PrivateFrameworks'):
            execute(['ditto', sdk / 'Library' / folder, root / 'Runtime' / folder])
        (root / 'Runtime/lib').mkdir()
        for library in (sdk / 'usr/lib').glob('*.dylib'):
            execute(['ditto', library, root / 'Runtime/lib' / library.name])
        test_inventory = {}
        for target in targets(data):
            host = Path(target['TestHostPath'].replace('__TESTROOT__', str(products)))
            execute(['ditto', host, destination / host.name])
            packaged_host = destination / host.name
            for cache in packaged_host.rglob('__pycache__'):
                shutil.rmtree(cache)
            execute(['codesign', '-f', '-s', '-', '--deep', packaged_host])
            target['TestHostPath'] = '__TESTROOT__/Products/Review/' + host.name
            target['UITargetAppPath'] = '__TESTROOT__/Products/Review/' + app_name
            bundle = packaged_host / 'Contents/PlugIns' / (target['BlueprintName'] + '.xctest')
            env = loader_environment(root, packaged_host, args.developer)
            test_inventory[target['BlueprintName']] = json.loads(output([sys.executable, HERE / 'discover.py', binary(bundle), target['ProductModuleName']], env=env))
            test_architectures = output(['lipo', '-archs', binary(bundle)]).split()
            for architecture in architectures:
                if architecture not in test_architectures or minimum_os(binary(bundle), architecture) > (12, 3, 0):
                    raise ValueError('Test bundle must support macOS 12.3 and architecture ' + architecture)
        for pattern in ('*.bundle', '*.framework', '*.dylib', 'tests-server'):
            for dependency in (products / 'Review').glob(pattern):
                execute(['ditto', dependency, destination / dependency.name])
        server = destination / 'tests-server'
        if not server.is_file():
            raise ValueError('The producer did not build tests-server')
        server_architectures = output(['lipo', '-archs', server]).split()
        for architecture in architectures:
            if architecture not in server_architectures or minimum_os(server, architecture) > (12, 3, 0):
                raise ValueError('tests-server must support macOS 12.3 and architecture ' + architecture)
        shutil.copytree(HERE, root / 'Scripts', ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        plans = root / 'Plans'
        plans.mkdir()
        for folder in (HERE.parents[2] / 'UITests', HERE.parents[2] / 'PerformanceTests', HERE.parents[2] / 'SyncE2EUITests'):
            for plan in folder.glob('*.xctestplan'):
                shutil.copy2(plan, plans / plan.name)
        write_plist(root / 'source.xctestrun', data)
        metadata = {'format': 1, 'git_sha': output(['git', 'rev-parse', 'HEAD']),
                    'distribution': args.distribution, 'app': app_name, 'bundle_id': app_info['CFBundleIdentifier'],
                    'app_version': app_info['CFBundleShortVersionString'], 'app_build': app_info['CFBundleVersion'],
                    'xcode': output(['xcodebuild', '-version']),
                    'architectures': architectures, 'tests': test_inventory}
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


def legacy_host(root, target, developer, env):
    original = root / target['TestHostPath'].replace('__TESTROOT__/', '')
    original_bundle = original / 'Contents/PlugIns' / (target['BlueprintName'] + '.xctest')
    if minimum_os(binary(original)) <= tuple(map(int, platform.mac_ver()[0].split('.'))):
        return original, None
    source = root / 'Scripts/XCTestCompat.swift'
    fingerprint = hashlib.sha256((output(['xcodebuild', '-version'], env=env) + platform.machine() + digest(binary(original_bundle)) + digest(source)).encode()).hexdigest()[:20]
    final = root / 'Compatibility' / fingerprint
    if (final / 'ready').is_file():
        return final / 'Legacy-Runner.app', final
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
    execute(['codesign', '-f', '-s', '-', '--deep', host])
    # Fail on missing symbols before any application state is touched.
    execute([sys.executable, '-c', 'import ctypes,os,sys; ctypes.CDLL(sys.argv[1], mode=os.RTLD_NOW)', binary(bundle)],
            env=loader_environment(root, host, developer, stage))
    (stage / 'ready').touch()
    stage.rename(final)
    return final / 'Legacy-Runner.app', final


def selected_tests(metadata, target, plan, only):
    cases = metadata['tests'][target['BlueprintName']]
    config = next((item for item in plan.get('testTargets', []) if item['target']['name'] == target['BlueprintName']), {})
    selected = config.get('selectedTests', [])
    skipped = config.get('skippedTests', [])
    def matches(identifier, pattern):
        pattern = pattern.removesuffix('()') if hasattr(pattern, 'removesuffix') else re.sub(r'\(\)$', '', pattern)
        return identifier == pattern or identifier.startswith(pattern + '/') or fnmatch.fnmatchcase(identifier, pattern)
    return [test for test in cases if (not selected or any(matches(test, p) for p in selected))
            and not any(matches(test, p) for p in skipped) and (not only or any(matches(test, p) for p in only))]


def specification(root, target, host, legacy, developer, identifiers, plan, mode):
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
    data['DependentProductPaths'] = [str(host), str(host / 'Contents/PlugIns' / (target['BlueprintName'] + '.xctest')), str(app)]
    data['OnlyTestIdentifiers'] = identifiers
    data.pop('SkipTestIdentifiers', None)
    # Artifacts contain no source/build machine paths, sanitizers or injected builder libraries.
    data['TestingEnvironmentVariables'] = {}
    env = loader_environment(root, host, developer, legacy)
    for key in ('DYLD_FRAMEWORK_PATH', 'DYLD_LIBRARY_PATH'):
        data['TestingEnvironmentVariables'][key] = env[key]
    environment = {k: v for k, v in data.get('EnvironmentVariables', {}).items() if not k.startswith(('DYLD_', '__', 'PERFC_', 'IDE_', 'SQLITE_'))}
    for item in plan.get('defaultOptions', {}).get('environmentVariableEntries', []):
        if item.get('enabled', True):
            value = item['value']
            environment[item['key']] = os.environ.get(item['key'], '') if '$(' in value else value
    environment.update(INTERNAL_USER_MODE='true' if mode == 'internal' else 'false', UITEST_APP_PATH=str(app),
                       UITEST_LIFECYCLE_SCRIPT=str(root / 'Scripts/pre-run.sh'))
    if 'CODE' in os.environ:
        environment['CODE'] = os.environ['CODE']
    data['EnvironmentVariables'] = environment
    data['CommandLineArguments'] = [item['argument'] for item in plan.get('defaultOptions', {}).get('commandLineArgumentEntries', []) if item.get('enabled', True)]
    # Producer Xcode defaults must not enable app diagnostics for a different consumer test plan.
    data['UITargetAppPerformanceAntipatternCheckerEnabled'] = bool(plan.get('defaultOptions', {}).get('performanceAntipatternCheckerEnabled', False))
    data['UITargetAppEnvironmentVariables'] = {k: v for k, v in target.get('UITargetAppEnvironmentVariables', {}).items() if not k.startswith(('DYLD_', '__'))}
    if legacy:
        allowed = ('BlueprintName', 'ProductModuleName', 'IsUITestBundle', 'IsXCTRunnerHostedTestBundle', 'TestHostPath',
                   'TestHostBundleIdentifier', 'TestBundlePath', 'UITargetAppPath', 'OnlyTestIdentifiers', 'EnvironmentVariables',
                   'TestingEnvironmentVariables', 'UITargetAppEnvironmentVariables', 'CommandLineArguments')
        data = {k: v for k, v in data.items() if k in allowed}
        return {data['BlueprintName']: data, '__xctestrun_metadata__': {'FormatVersion': 1}}
    return {'TestConfigurations': [{'Name': 'Portable', 'IsEnabled': True, 'TestTargets': [data]}], '__xctestrun_metadata__': {'FormatVersion': 2}}


def stop_process(process):
    if process.poll() is not None:
        return
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()


def stop_owned_runners(host):
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
        except (ProcessLookupError, subprocess.CalledProcessError):
            pass


def execute_tests(args):
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
    host, legacy = legacy_host(root, target, developer, env)
    if args.preflight_only:
        bundle = host / 'Contents/PlugIns' / (target['BlueprintName'] + '.xctest')
        inventory = json.loads(output([sys.executable, root / 'Scripts/discover.py', binary(bundle), target['ProductModuleName']],
                                      env=loader_environment(root, host, developer, legacy)))
        if inventory != metadata['tests'][target['BlueprintName']]:
            raise ValueError('Runtime test inventory differs from the builder inventory')
        print(json.dumps({'suite': args.suite, 'tests': len(inventory), 'legacy': bool(legacy), 'app_launched': False}))
        return 0
    default_plan = {'ui': 'UI Tests App Store Sandbox' if metadata['distribution'] == 'appstore' else 'UI Tests',
                    'performance': 'macOS Performance Tests', 'sync': 'Sync End-to-End UI Tests', 'sync-appstore': 'Sync End-to-End UI Tests App Store'}[args.suite]
    plan_path = root / 'Plans' / ((args.plan or default_plan) + '.xctestplan')
    if not plan_path.is_file():
        raise ValueError('Test plan not found: ' + str(plan_path))
    plan = json.loads(plan_path.read_text())
    identifiers = selected_tests(metadata, target, plan, args.only)
    if not identifiers:
        raise ValueError('No enabled tests match this plan/filter')
    results = args.result.resolve() if args.result else root / 'Results' / (time.strftime('%Y%m%d-%H%M%S') + '-' + str(os.getpid()))
    results.mkdir(parents=True, exist_ok=False)
    batches = [[test] for test in identifiers] if legacy else [identifiers]
    failures = 0
    for index, batch in enumerate(batches):
        directory = results / str(index + 1)
        directory.mkdir()
        spec = directory / 'run.xctestrun'
        specification_data = specification(root, target, host, legacy, developer, batch, plan, args.user_mode)
        runtime_target = targets(specification_data)[0]
        test_class = batch[0].split('/')[0]
        runtime_target['EnvironmentVariables']['UITEST_RESET_CLASS_STATE'] = '1'
        if legacy:
            marker = results / ('class-reset-' + hashlib.sha256(test_class.encode()).hexdigest()[:20])
            runtime_target['EnvironmentVariables']['UITEST_RESET_CLASS_STATE'] = '0' if marker.exists() else '1'
            runtime_target['EnvironmentVariables']['UITEST_CLASS_RESET_MARKER'] = str(marker)
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
            if not legacy:
                command += ['-test-iterations', '2', '-retry-tests-on-failure', '-test-repetition-relaunch-enabled', 'YES']
            with (directory / 'xcodebuild.log').open('w') as log:
                process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    code = process.wait(timeout=min(args.timeout, 300) if legacy else args.timeout)
                except subprocess.TimeoutExpired:
                    stop_process(process)
                    code = 124
                except BaseException:
                    stop_process(process)
                    raise
        finally:
            try:
                stop_owned_runners(host)
            finally:
                execute(['bash', root / 'Scripts/post-run.sh'], env=lifecycle_env)
        log = (directory / 'xcodebuild.log').read_text(errors='replace')
        print(log, end='', flush=True)
        counts = re.findall(r'Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?', log)
        count, skipped, failed = tuple(int(v or 0) for v in counts[-1]) if counts else (0, 0, 0)
        skipped = max(skipped, len(re.findall(r'Test Case .* skipped(?: |\()', log)))
        count = max((int(item[0]) for item in counts), default=0)
        passed = code == 0 and count >= len(batch) and count > skipped and failed == 0 and (directory / 'tests.xcresult').is_dir()
        failures += not passed
        summary = dict(tests=batch, exit_code=code, executed=count, skipped=skipped, failed=failed, passed=passed)
        (directory / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps(summary), flush=True)
    (results / 'summary.json').write_text(json.dumps({'requested': len(identifiers), 'failed_batches': failures}, indent=2) + '\n')
    return 1 if failures else 0


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
    run_parser.add_argument('--preflight-only', action='store_true', help='Verify bundle loading and inventory without app launch/reset')
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
    except (ValueError, OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
