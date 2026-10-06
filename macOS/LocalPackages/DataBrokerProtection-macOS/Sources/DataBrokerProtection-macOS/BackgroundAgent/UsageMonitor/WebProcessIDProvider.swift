//
//  WebProcessIDProvider.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Foundation
import WebKit

/// Finds the WebKit processes whose CPU and memory should be included in PIR measurements.
///
/// WebKit spreads its work over three kinds of process: one per web page, one for graphics, and one for networking. All
/// three belong to the agent's own process pool rather than to the browser, so all three count towards PIR.
struct WebProcessIDProvider {

    private static let webContentProcessInfoSelector = Selector(("_webContentProcessInfo"))
    private static let helperProcessInfoSelectors = [
        Selector(("_gpuProcessInfo")),
        Selector(("_networkingProcessInfo"))
    ]

    func currentProcessIDs() -> Set<pid_t>? {
        let collectPIDs: () -> Set<pid_t>? = {
            autoreleasepool {
                // Web content carries most of the cost, so without it there is no useful measurement. Graphics and
                // networking are additive, so their absence reduces the reported total rather than voiding it.
                guard var processIDs = Self.processIDs(reportedBy: Self.webContentProcessInfoSelector) else {
                    return nil
                }
                for selector in Self.helperProcessInfoSelectors {
                    processIDs.formUnion(Self.processIDs(reportedBy: selector) ?? [])
                }
                return processIDs
            }
        }

        return Thread.isMainThread
            ? collectPIDs()
            : DispatchQueue.main.sync(execute: collectPIDs)
    }

    /// Reads the process IDs WebKit reports for one kind of process, or `nil` if it cannot describe that kind.
    ///
    /// WebKit describes web content and networking as arrays but graphics as a single process, and reports nothing at
    /// all while no process of that kind is running, which is an empty result rather than a failure.
    private static func processIDs(reportedBy selector: Selector) -> Set<pid_t>? {
        guard WKProcessPool.responds(to: selector) else { return nil }
        guard let reportedInfo = WKProcessPool.perform(selector)?.takeUnretainedValue() else { return [] }

        let processInfoList: [NSObject]
        switch reportedInfo {
        case let reportedList as [NSObject]:
            processInfoList = reportedList
        case let reportedProcess as NSObject:
            processInfoList = [reportedProcess]
        default:
            return nil
        }

        return Set(processInfoList.compactMap(Self.processID))
    }

    private static func processID(of processInfo: NSObject) -> pid_t? {
        guard processInfo.responds(to: Selector(("pid"))),
              let pid = processInfo.value(forKey: "pid") as? pid_t,
              pid > 0 else {
            return nil
        }
        return pid
    }
}
