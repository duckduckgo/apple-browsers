#!/usr/bin/env python3
"""Run a published app/test pair over an existing pinned SSH connection and fetch results."""
import argparse
import json
import os
from datetime import datetime
from pathlib import Path
import re
import shlex
import subprocess

REMOTE_SCRIPT = r'''set -euo pipefail
url=$1
work=$2
shift 2
console_user=$(stat -f '%Su' /dev/console)
if [[ "$console_user" != "$(id -un)" ]]; then
    echo "Log into an unlocked GUI session as $(id -un) before running UI tests." >&2
    exit 1
fi
mkdir -p "$work"
cd "$work"
umask 077
__RUNTIME_ENVIRONMENT__
trap 'rm -f runtime-environment.json' EXIT
curl --fail --location --silent --show-error "${url%/*}/run-ui-tests.py" -o runner.py
python3 runner.py download "$url" --output payload
python3 payload/ui-tests/Scripts/artifact.py run payload/ui-tests --environment-file runtime-environment.json "$@" 2>&1 | tee run.log
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ssh-config', type=Path, help='Pinned Virfield config or your configured Mac mini host')
    parser.add_argument('--results', type=Path, default=Path('remote-ui-results'))
    parser.add_argument('host', help='An SSH host alias with a verified host key')
    parser.add_argument('manifest', help='CI run-review.json URL')
    parser.add_argument('run_arguments', nargs=argparse.REMAINDER, help='Arguments forwarded to artifact.py run')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.@-]*', args.host):
        parser.error('Use a configured SSH host alias')
    if not args.manifest.startswith('https://'):
        parser.error('The CI manifest URL must use HTTPS')
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    remote = 'ddg-ui-tests/' + stamp
    options = ['-F', str(args.ssh_config.resolve())] if args.ssh_config else []
    command = shlex.join(['bash', '-s', '--', args.manifest, remote] + args.run_arguments)
    try:
        environment = json.dumps({key: os.environ[key] for key in ('CODE',) if key in os.environ})
        script = REMOTE_SCRIPT.replace('__RUNTIME_ENVIRONMENT__', 'printf %s ' + shlex.quote(environment) + ' > runtime-environment.json')
        result = subprocess.run(['ssh'] + options + [args.host, command], input=script, text=True)
        return_code = result.returncode
    finally:
        destination = args.results.resolve() / (args.host.replace('@', '-') + '-' + stamp)
        destination.mkdir(parents=True)
        copied = subprocess.run(['scp'] + options + ['-r', args.host + ':' + remote + '/payload/ui-tests/Results', args.host + ':' + remote + '/run.log', str(destination)])
        print('Local results: ' + str(destination), flush=True)
        print('Remote workspace: ' + args.host + ':~/' + remote, flush=True)
    return return_code or copied.returncode


if __name__ == '__main__':
    raise SystemExit(main())
