//
//  SyncSetupViewV2Tests.swift
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

import CoreGraphics
import SnapshotTestingSupport
import Testing
@testable import SyncUI_macOS

@MainActor
@Suite("Sync Setup View V2 Tests", .disabled("Snapshot testing is opt-in until the sync automations land"))
final class SyncSetupViewV2Tests {

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testSyncSetupViewV2Snapshots() {
        assertImageSnapshots(
            SyncSetupViewV2_Previews.snapshots,
            size: .intrinsicContentSize
        )
    }
}
