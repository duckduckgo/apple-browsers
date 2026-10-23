#!/usr/bin/env python3
"""Optional macOS 12 adapter. Never used by the native macOS 14+ CI path."""
import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import platform
import sys
import tempfile
import time

from artifact import binary, digest, execute, loader_environment, output, read_plist, selected_tests, targets, write_plist, xcode, SUITES


def sign_runner(host, entitlements):
    with tempfile.NamedTemporaryFile(suffix='.entitlements', dir=host.parent) as stream:
        stream.write(entitlements.encode())
        stream.flush()
        execute(['codesign', '-f', '-s', '-', '--deep', '--entitlements', stream.name, host])


def host(root, target, developer, env):
    original = root / target['TestHostPath'].replace('__TESTROOT__/', '')
    original_bundle = original / 'Contents/PlugIns' / (target['BlueprintName'] + '.xctest')
    metadata = json.loads((root / 'manifest.json').read_text())
    if not platform.mac_ver()[0].startswith('12.'):
        raise ValueError('The Monterey adapter is restricted to macOS 12')
    if platform.machine() not in metadata['architectures']:
        raise ValueError('The Monterey artifact does not contain this architecture')
    if metadata.get('os_major') != '14' or not metadata['xcode'].startswith('Xcode 16.2\n'):
        raise ValueError('Monterey requires the universal macOS 14 / Xcode 16.2 test artifact')
    if not output(['xcodebuild', '-version'], env=env).startswith('Xcode 13.4.1\n'):
        raise ValueError('Monterey requires installed Xcode 13.4.1')
    source = root / 'Scripts/monterey/XCTestCompat.swift'
    seal = original_bundle / 'Contents/_CodeSignature/CodeResources'
    entitlements = output(['codesign', '-d', '--entitlements', ':-', original]).rstrip('\0')
    if not entitlements:
        raise ValueError('The native test runner must supply its original code-signing entitlements')
    fingerprint = hashlib.sha256((output(['xcodebuild', '-version'], env=env) + platform.machine()
                                  + digest(binary(original_bundle)) + digest(seal) + digest(source) + entitlements).encode()).hexdigest()[:20]
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



def specification(data):
    allowed = ('BlueprintName', 'ProductModuleName', 'IsUITestBundle', 'IsXCTRunnerHostedTestBundle', 'TestHostPath',
               'TestHostBundleIdentifier', 'TestBundlePath', 'UITargetAppPath', 'UITargetAppBundleIdentifier',
               'OnlyTestIdentifiers', 'SkipTestIdentifiers', 'EnvironmentVariables', 'TestingEnvironmentVariables',
               'UITargetAppEnvironmentVariables', 'CommandLineArguments')
    return {data['BlueprintName']: {key: value for key, value in data.items() if key in allowed},
            '__xctestrun_metadata__': {'FormatVersion': 1}}


def run(args, execute_method):
    root = args.root.resolve()
    metadata = json.loads((root / 'manifest.json').read_text())
    developer, environment = xcode(args)
    target = next(t for t in targets(read_plist(root / 'source.xctestrun')) if t['BlueprintName'] == SUITES[args.suite])
    runner = host(root, target, developer, environment)
    if args.preflight_only:
        print(json.dumps({'monterey_adapter': True, 'app_launched': False}))
        return 0
    bundle = runner / 'Contents/PlugIns' / (target['BlueprintName'] + '.xctest')
    inventory = json.loads(output([sys.executable, root / 'Scripts/monterey/discover.py', binary(bundle),
                                   target['ProductModuleName']], env=loader_environment(root, runner, developer), timeout=60))
    default_plan = {'ui': 'UI Tests App Store Sandbox' if metadata['distribution'] == 'appstore' else 'UI Tests',
                    'performance': 'macOS Performance Tests', 'sync': 'Sync End-to-End UI Tests',
                    'sync-appstore': 'Sync End-to-End UI Tests App Store'}[args.suite]
    plan = json.loads((root / 'Plans' / ((args.plan or default_plan) + '.xctestplan')).read_text())
    selected = selected_tests(metadata, target, plan, args.only)
    configuration = next(t for t in plan['testTargets'] if t['target']['name'] == target['BlueprintName'])
    skipped = [value.removesuffix('()') for value in configuration.get('skippedTests', [])]
    def matches(identifier, selector):
        return identifier == selector or identifier.startswith(selector + '/') or fnmatch.fnmatchcase(identifier, selector)
    methods = [method for method in inventory if (not selected or any(matches(method, selector) for selector in selected))
               and not any(matches(method, selector) for selector in skipped)]
    if not methods:
        raise ValueError('No enabled Monterey methods match the selected plan/filter')
    results = args.result.resolve() if args.result else root / 'Results' / ('monterey-' + time.strftime('%Y%m%d-%H%M%S') + '-' + str(os.getpid()))
    results.mkdir(parents=True, exist_ok=False)
    previous = {key: os.environ.get(key) for key in ('UITEST_RESET_CLASS_STATE', 'UITEST_CLASS_RESET_MARKER')}
    failures = executed = skipped_count = 0
    try:
        for index, method in enumerate(methods):
            marker = results / ('class-reset-' + hashlib.sha256(method.split('/')[0].encode()).hexdigest()[:20])
            os.environ['UITEST_RESET_CLASS_STATE'] = '0' if marker.exists() else '1'
            os.environ['UITEST_CLASS_RESET_MARKER'] = str(marker)
            child = argparse.Namespace(**vars(args))
            child.only = [method]
            child.result = results / str(index + 1)
            child.timeout = min(args.timeout, 300)
            child._monterey_method = True
            failures += execute_method(child) != 0
            summary = json.loads((child.result / 'summary.json').read_text())
            executed += summary['executed']
            skipped_count += summary['skipped']
    finally:
        for key, value in previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
    passed = failures == 0 and executed > skipped_count
    (results / 'summary.json').write_text(json.dumps({'requested': len(methods), 'failed_methods': failures,
                                                     'executed': executed, 'skipped': skipped_count, 'passed': passed}, indent=2) + '\n')
    return 0 if passed else 1
