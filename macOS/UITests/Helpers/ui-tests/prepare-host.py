#!/usr/bin/env python3
"""Qualify the console's UI Automation using its installed Xcode and an isolated probe app."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import time

from artifact import execution_summary, output, require_noninteractive_automation, stop_owned_app, stop_process, xcode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--xcode', type=Path)
    parser.add_argument('--result', type=Path, required=True)
    parser.add_argument('--timeout', type=int, default=300)
    args = parser.parse_args()
    if output(['stat', '-f', '%Su', '/dev/console']) != output(['id', '-un']):
        raise RuntimeError('Log into an unlocked GUI session as the SSH user before qualifying UI Automation.')
    require_noninteractive_automation()
    developer, environment = xcode(args)
    result = args.result.resolve()
    result.mkdir(parents=True, exist_ok=False)
    project = result / 'project'
    shutil.copytree(Path(__file__).resolve().parent / 'HostReadiness', project)
    command = ['xcodebuild', 'test', '-project', str(project / 'Gate.xcodeproj'), '-scheme', 'Gate',
               '-derivedDataPath', str(result / 'DerivedData'), '-destination', 'platform=macOS',
               '-only-testing:GateTests/GateTests/testCanLaunchAndInspectApplication',
               '-resultBundlePath', str(result / 'probe.xcresult')]
    started = time.monotonic()
    with (result / 'xcodebuild.log').open('w') as log:
        process = subprocess.Popen(command, env=environment, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            stop_process(process)
            code = 124
        except BaseException:
            stop_process(process)
            raise
        finally:
            for name in ('GateApp.app', 'GateTests-Runner.app'):
                app = result / 'DerivedData/Build/Products/Debug' / name
                if (app / 'Contents/Info.plist').is_file():
                    stop_owned_app(app)
    summary = execution_summary((result / 'xcodebuild.log').read_text(errors='replace'), code, result / 'probe.xcresult', 1)
    summary.update(developer=str(developer), seconds=round(time.monotonic() - started, 2),
                   probe='native app launch, click and accessibility value', app_profile_reset=False)
    (result / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary), flush=True)
    print('UI Automation qualification results: ' + str(result), flush=True)
    return 0 if summary['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
