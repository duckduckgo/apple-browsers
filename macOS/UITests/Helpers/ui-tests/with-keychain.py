#!/usr/bin/env python3
"""Run UI tests with a disposable keychain, restoring the account's original selection."""
import argparse
import json
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import sys
import tempfile
import time
import uuid
import plistlib


def security(action, *arguments, capture=False):
    result = subprocess.run(['security', action, *map(str, arguments)], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    if result.returncode:
        # Never include arguments: create/unlock commands contain a private password.
        raise RuntimeError('Test keychain operation failed: ' + action)
    return shlex.split(result.stdout) if capture else None


def gui_request(path):
    request = json.loads(path.read_text())
    status = {'exit_code': 1}
    try:
        status['previous'] = {'default': security('default-keychain', '-d', 'user', capture=True),
                              'search': security('list-keychains', '-d', 'user', capture=True)}
        if request.get('password_file'):
            security('unlock-keychain', '-p', Path(request['password_file']).read_text(), request['keychain'])
        security('default-keychain', '-d', 'user', '-s', *request['default'])
        security('list-keychains', '-d', 'user', '-s', *request['search'])
        status['exit_code'] = 0
    except Exception as error:
        status['error'] = str(error)
    temporary = path.with_name('status.next')
    temporary.write_text(json.dumps(status) + '\n')
    os.replace(temporary, path.with_name('status.json'))
    return status['exit_code']


def configure_gui(directory, selection, keychain=None, password_file=None):
    directory.mkdir(mode=0o700)
    request = directory / 'request.json'
    request.write_text(json.dumps(dict(selection, keychain=str(keychain) if keychain else None,
                                       password_file=str(password_file) if password_file else None)) + '\n')
    label = 'com.duckduckgo.uitests.keychain-' + uuid.uuid4().hex
    service = 'gui/' + str(os.getuid()) + '/' + label
    plist = directory / 'agent.plist'
    plist.write_bytes(plistlib.dumps({'Label': label, 'RunAtLoad': True,
                                     'ProgramArguments': [sys.executable, str(Path(__file__).resolve()), '--gui-request', str(request)],
                                     'StandardOutPath': str(directory / 'agent.log'), 'StandardErrorPath': str(directory / 'agent.log')}))
    subprocess.run(['launchctl', 'bootstrap', 'gui/' + str(os.getuid()), str(plist)], check=True, timeout=30)
    try:
        deadline = time.monotonic() + 30
        status = directory / 'status.json'
        while not status.exists() and time.monotonic() < deadline:
            time.sleep(.1)
        if not status.exists() or json.loads(status.read_text())['exit_code']:
            raise RuntimeError('Could not configure the disposable keychain in the GUI session; see ' + str(directory))
    finally:
        subprocess.run(['launchctl', 'bootout', service], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--result', type=Path, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('Provide the artifact.py run command after --')
    result = args.result.resolve()
    result.mkdir(mode=0o700, parents=True, exist_ok=False)
    original_default = security('default-keychain', '-d', 'user', capture=True)
    original_search = security('list-keychains', '-d', 'user', capture=True)
    (result / 'previous.json').write_text(json.dumps({'default': original_default, 'search': original_search}, indent=2) + '\n')
    keychain = Path.home() / 'Library/Keychains' / ('ddg-ui-' + uuid.uuid4().hex + '.keychain')
    # Keep the secret outside the result tree, including if SSH is interrupted
    # before cleanup and the remote launcher fetches failure diagnostics.
    descriptor, password_path = tempfile.mkstemp(prefix='ddg-ui-keychain-')
    password_file = Path(password_path)
    password = secrets.token_urlsafe(32)
    with os.fdopen(descriptor, 'w') as stream:
        stream.write(password)
    created = False
    code = 1
    try:
        security('create-keychain', '-p', password, keychain)
        created = True
        security('unlock-keychain', '-p', password, keychain)
        security('set-keychain-settings', keychain)
        configure_gui(result / 'gui-setup', {'default': [str(keychain)], 'search': [str(keychain)]}, keychain, password_file)
        security('default-keychain', '-d', 'user', '-s', keychain)
        security('list-keychains', '-d', 'user', '-s', keychain)
        environment = dict(os.environ, UITEST_KEYCHAIN_PATH=str(keychain))
        code = subprocess.call(command, env=environment)
    finally:
        restored = False
        try:
            try:
                status = result / 'gui-setup/status.json'
                if status.exists() and 'previous' in json.loads(status.read_text()):
                    configure_gui(result / 'gui-restore', json.loads(status.read_text())['previous'])
            finally:
                try:
                    security('default-keychain', '-d', 'user', '-s', *original_default)
                finally:
                    security('list-keychains', '-d', 'user', '-s', *original_search)
            restored = True
        finally:
            try:
                if created and restored:
                    security('delete-keychain', keychain)
            finally:
                password_file.unlink()
    (result / 'summary.json').write_text(json.dumps({'exit_code': code, 'original_selection_restored': True}, indent=2) + '\n')
    return code


if __name__ == '__main__':
    raise SystemExit(gui_request(Path(sys.argv[2])) if sys.argv[1:2] == ['--gui-request'] else main())
