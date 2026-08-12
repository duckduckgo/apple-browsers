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

/// Finds the WebContent processes whose CPU and memory should be included in PIR measurements.
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

        // WebKit owns the returned process-info objects and expects them to be accessed on the main thread. It is safe
        // to wait for the main queue here because the main queue never waits synchronously for the monitor queue.
        return Thread.isMainThread
            ? collectPIDs()
            : DispatchQueue.main.sync(execute: collectPIDs)
    }
}
