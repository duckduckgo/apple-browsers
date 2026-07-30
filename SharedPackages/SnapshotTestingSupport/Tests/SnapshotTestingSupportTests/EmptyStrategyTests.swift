//
//  EmptyStrategyTests.swift
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

import SnapshotTestingSupport
import SwiftUI
import Testing

@MainActor
@Suite("Empty Strategy Tests")
struct EmptyStrategyTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func directAssertionWithEmptyCustomStrategyRecordsIssue() {
        withKnownIssue("An empty strategy must record an issue instead of silently passing.") {
            assertImageSnapshot(
                matching: Text("snapshot"),
                strategy: .custom([]),
                size: .intrinsicContentSize
            )
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func previewBackedAssertionWithEmptyCustomStrategyRecordsIssue() {
        let previews = PreviewSnapshots<Int>(
            configurations: [.init(name: "Default", state: 0)],
            configure: { _ in Text("snapshot") }
        )

        withKnownIssue("An empty strategy must record an issue instead of silently passing.") {
            assertImageSnapshots(
                previews,
                strategy: .custom([]),
                size: .intrinsicContentSize
            )
        }
    }
}
