//
//  XCUIApplication+AllocationStats.swift
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

extension XCUIApplication {

    /// Our Temporary Stats URL is in `/tmp` for simplicity reasons, as `FileManager.default.temporaryDirectory` will always
    /// point to a different location due to the macOS Sandbox restrictions.
    ///
    var memoryStatsURL: URL {
        URL(fileURLWithPath: "/tmp/" + bundleID! + "-allocations.json")
    }

    func cleanExportMemoryStats() {
        deleteMemoryStats()
        exportMemoryStats()
    }

    private func exportMemoryStats() {
        typeKey("m", modifierFlags: [.control, .command, .shift, .option])
    }

    private func deleteMemoryStats() {
        try? FileManager.default.removeItem(at: memoryStatsURL)
    }
}
