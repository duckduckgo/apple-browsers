#!/usr/bin/env python3
"""The same UI-test lifecycle is used by local schemes and portable CI artifacts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import time
import urllib.request


BUNDLE_IDS = {
    'review': 'com.duckduckgo.macos.browser.review',
    'review-appstore': 'com.duckduckgo.mobile.ios.review',
    'debug': 'com.duckduckgo.macos.browser.debug',
    'debug-appstore': 'com.duckduckgo.mobile.ios.debug',
}


def reset(bundle_id, home=None, defaults_tool='/usr/bin/defaults'):
    if bundle_id not in BUNDLE_IDS.values():
        raise ValueError('Refusing to reset a non-test app: ' + bundle_id)
    home = Path(home or Path.home())
    paths = [home / 'Library/Containers' / bundle_id / 'Data', home / 'Library/WebKit' / bundle_id]
    suffix = bundle_id.rsplit('.', 1)[1]
    namespace = bundle_id.rsplit('.', 1)[0]
    paths += list((home / 'Library/Group Containers').glob('*' + namespace + '.app-configuration.' + suffix))
    if namespace == 'com.duckduckgo.macos.browser':
        for container in (home / 'Library/Containers').glob('*' + namespace + '.network-protection*' + suffix):
            paths += [container / 'Data', home / 'Library/WebKit' / container.name]
    for path in paths:
        if path.is_symlink():
            raise ValueError('Refusing a symlinked state directory: ' + str(path))
        if path.resolve() != home.resolve() / path.relative_to(home):
            raise ValueError('Refusing a redirected state directory: ' + str(path))
    subprocess.run([defaults_tool, 'delete', bundle_id], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for path in paths:
        if path.exists():
            shutil.rmtree(path)
    subprocess.run([defaults_tool, 'write', bundle_id, 'moveToApplicationsFolderAlertSuppress', '-bool', 'true'], check=True)


def server_identity(pid):
    value = subprocess.run(['ps', '-p', str(pid), '-o', 'lstart=', '-o', 'comm='], stdout=subprocess.PIPE, text=True)
    return value.stdout.strip()


def stop_server(state):
    if not state.exists():
        return
    data = json.loads(state.read_text())
    if server_identity(data['pid']) == data['identity']:
        os.kill(data['pid'], signal.SIGTERM)
        for _ in range(40):
            if server_identity(data['pid']) != data['identity']:
                break
            time.sleep(.1)
        else:
            raise RuntimeError('Owned tests-server did not stop: ' + str(data['pid']))
    state.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['pre', 'post'])
    parser.add_argument('distribution', nargs='?', default='review', choices=BUNDLE_IDS)
    parser.add_argument('--reset-only', action='store_true')
    parser.add_argument('--bundle-id')
    parser.add_argument('--sync', action='store_true')
    args = parser.parse_args()
    products = Path(os.environ.get('BUILT_PRODUCTS_DIR', '.')).resolve()
    key = hashlib.sha256(str(products).encode()).hexdigest()[:16]
    state = Path(os.environ.get('UITEST_SERVER_STATE', '/tmp/ddg-ui-server-' + str(os.getuid()) + '-' + key + '.json'))
    if args.action == 'post':
        stop_server(state)
        return
    # Class setup invokes the reset after terminating the target app.
    if args.reset_only:
        bundle_id = args.bundle_id or BUNDLE_IDS[args.distribution]
        reset(bundle_id)
        if args.sync:
            subprocess.run(['/usr/bin/defaults', 'write', bundle_id, 'sync.environment', 'Development'], check=True)
        if 'UITEST_CLASS_RESET_MARKER' in os.environ:
            Path(os.environ['UITEST_CLASS_RESET_MARKER']).touch()
        return
    binary = products / 'tests-server'
    if not binary.is_file():
        raise ValueError('tests-server not found: ' + str(binary))
    stop_server(state)
    with socket.socket() as probe:
        if probe.connect_ex(('127.0.0.1', 8085)) == 0:
            raise RuntimeError('Port 8085 is owned by another process; no unrelated process was stopped')
    resources = Path(os.environ.get('UITEST_RESOURCES_DIR', os.environ.get('METAL_LIBRARY_OUTPUT_DIR', str(products))))
    resources.mkdir(parents=True, exist_ok=True)
    log_path = Path(os.environ.get('UITEST_SERVER_LOG', str(state.with_suffix('.log'))))
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open('ab') as log:
        server = subprocess.Popen([str(binary)], cwd=resources, stdin=subprocess.DEVNULL, stdout=log,
                                  stderr=subprocess.STDOUT, start_new_session=True)
    identity = server_identity(server.pid)
    if not identity:
        raise RuntimeError('tests-server exited before its identity was recorded')
    state.write_text(json.dumps({'pid': server.pid, 'identity': identity}))
    try:
        for _ in range(40):
            if server.poll() is not None:
                raise RuntimeError('tests-server exited; see ' + str(log_path))
            try:
                with urllib.request.urlopen('http://127.0.0.1:8085/', timeout=1):
                    bundle_id = BUNDLE_IDS[args.distribution]
                    subprocess.run(['/usr/bin/defaults', 'write', bundle_id, 'moveToApplicationsFolderAlertSuppress', '-bool', 'true'], check=True)
                    if args.sync:
                        subprocess.run(['/usr/bin/defaults', 'write', bundle_id, 'sync.environment', 'Development'], check=True)
                    return
            except OSError:
                time.sleep(.25)
        raise RuntimeError('tests-server did not become ready')
    except BaseException:
        stop_server(state)
        raise


if __name__ == '__main__':
    main()
