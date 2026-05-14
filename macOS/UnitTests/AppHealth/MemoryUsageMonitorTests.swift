//
//  MemoryUsageMonitorTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class MemoryUsageMonitorTests: XCTestCase {

    // MARK: - Thread Safety (regression tests for commit fixing use-after-free crash)

    func testWebContentMemory_pidProviderCalledOnMainThread_whenCalledFromBackground() {
        // The fix: _webContentProcessInfo must run on the main thread to avoid a
        // use-after-free crash in WebKit's AuxiliaryProcessProxy. When getWebContentProcessMemory
        // is called from a background thread it should dispatch the pid collection to main.
        var calledOnMainThread: Bool?
        let pidExp = expectation(description: "pidProvider called")
        let completionExp = expectation(description: "getWebContentProcessMemory returned")

        DispatchQueue.global().async {
            _ = MemoryUsageMonitor.getWebContentProcessMemory(
                pidProvider: {
                    calledOnMainThread = Thread.isMainThread
                    pidExp.fulfill()
                    return []
                }
            )
            completionExp.fulfill()
        }

        wait(for: [pidExp, completionExp], timeout: 2.0, enforceOrder: true)
        XCTAssertTrue(calledOnMainThread == true, "PID provider must be called on the main thread to avoid use-after-free in WebKit")
    }

    func testWebContentMemory_doesNotDeadlock_whenCalledFromMainThread() {
        // Regression: if the code always used DispatchQueue.main.sync it would deadlock
        // when the caller is already on the main thread. The Thread.isMainThread guard
        // must skip the sync dispatch in that case.
        var pidProviderCalled = false

        _ = MemoryUsageMonitor.getWebContentProcessMemory(
            pidProvider: {
                pidProviderCalled = true
                return []
            }
        )

        XCTAssertTrue(pidProviderCalled, "PID provider should be called directly without dispatch when already on the main thread")
    }

    // MARK: - Memory Aggregation

    func testWebContentMemory_sumsResidentMemoryAcrossAllPIDs() {
        let result = MemoryUsageMonitor.getWebContentProcessMemory(
            pidProvider: { [100, 200] },
            memoryProvider: { pid in
                switch pid {
                case 100: return 1_000
                case 200: return 2_000
                default: return nil
                }
            }
        )

        XCTAssertEqual(result?.totalBytes, 3_000)
        XCTAssertEqual(result?.processCount, 2)
    }

    func testWebContentMemory_returnsNil_whenPIDProviderReturnsNil() {
        let result = MemoryUsageMonitor.getWebContentProcessMemory(
            pidProvider: { nil }
        )

        XCTAssertNil(result)
    }

    func testWebContentMemory_excludesPIDsWhoseMemoryIsUnreadable() {
        // Simulates a process that terminated between collectPIDs() and proc_pidinfo():
        // its memoryProvider returns nil and it should not count toward the total.
        let result = MemoryUsageMonitor.getWebContentProcessMemory(
            pidProvider: { [100, 200] },
            memoryProvider: { pid in pid == 200 ? 2_000 : nil }
        )

        XCTAssertEqual(result?.totalBytes, 2_000)
        XCTAssertEqual(result?.processCount, 1)
    }

    func testWebContentMemory_returnsZero_whenPIDProviderReturnsEmptyArray() {
        let result = MemoryUsageMonitor.getWebContentProcessMemory(
            pidProvider: { [] },
            memoryProvider: { _ in nil }
        )

        XCTAssertEqual(result?.totalBytes, 0)
        XCTAssertEqual(result?.processCount, 0)
    }

    func testWebContentMemory_filtersOutNonPositivePIDs() {
        // The real collectPIDs already enforces pid > 0; this test ensures the aggregation
        // loop also enforces it so the invariant holds regardless of what pidProvider returns.
        let result = MemoryUsageMonitor.getWebContentProcessMemory(
            pidProvider: { [0, -1, 200] },
            memoryProvider: { _ in 1_000 }
        )

        XCTAssertEqual(result?.totalBytes, 1_000)
        XCTAssertEqual(result?.processCount, 1)
    }
}
