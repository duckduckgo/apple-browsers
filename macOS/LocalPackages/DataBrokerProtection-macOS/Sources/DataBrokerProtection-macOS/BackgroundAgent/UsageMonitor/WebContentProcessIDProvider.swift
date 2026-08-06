//
//  WebContentProcessIDProvider.swift
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

/// Discovers the currently live WebContent processes used by PIR resource sampling.
struct WebContentProcessIDProvider {

    func currentProcessIDs() -> [pid_t]? {
        let processInfoSelector = Selector(("_webContentProcessInfo"))
        let pidSelector = Selector(("pid"))
        let collectPIDs: () -> [pid_t]? = {
            autoreleasepool {
                guard WKProcessPool.responds(to: processInfoSelector) else { return nil }
                guard let processInfoList = WKProcessPool.perform(processInfoSelector)?
                    .takeUnretainedValue() as? [NSObject] else {
                    return nil
                }
                return processInfoList.compactMap { processInfo in
                    guard processInfo.responds(to: pidSelector),
                          let pid = processInfo.value(forKey: "pid") as? pid_t,
                          pid > 0 else {
                        return nil
                    }
                    return pid
                }
            }
        }

        // WebKit owns these unretained proxy objects on the main thread. The monitor queue is never
        // synchronously awaited, so this main-queue hop cannot form a queue-to-main deadlock.
        return Thread.isMainThread
            ? collectPIDs()
            : DispatchQueue.main.sync(execute: collectPIDs)
    }
}
