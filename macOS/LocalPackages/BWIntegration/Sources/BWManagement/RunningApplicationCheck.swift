//
//  RunningApplicationCheck.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit
import Darwin
import Foundation

final class RunningApplicationCheck {

    static func isApplicationRunning(bundleId: String) -> Bool {
        // The proxy process this browser spawns is the Bitwarden app binary, so it
        // registers with the same bundle id. It must not count as "Bitwarden is
        // running", otherwise each spawned proxy satisfies the check for the next
        // spawn and the browser keeps relaunching proxies after Bitwarden quits.
        return NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == bundleId
                && !application.isTerminated
                && isProcessAlive(application.processIdentifier)
                && !isChildOfCurrentProcess(application.processIdentifier)
        }
    }

    // NSWorkspace can briefly list an already dead process with isTerminated
    // still false; such an entry must not count as a running application
    private static func isProcessAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    static func isChildOfCurrentProcess(_ pid: pid_t) -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else {
            // The process is already gone; treat the stale entry as not ours
            return false
        }

        return info.kp_eproc.e_ppid == getpid()
    }

}
