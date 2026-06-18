//
//  PreviewSnapshotsTests.swift
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
import XCTest

final class PreviewSnapshotsTests: XCTestCase {

    func testPreviewCollectionKeepsConfigurationsAndBuildsViews() {
        let previews = PreviewSnapshots(
            configurations: [
                .init(name: "Enabled", state: "enabled"),
                .init(name: "Disabled", state: "disabled", scope: .previews),
                .init(name: "Snapshots Only", state: "snapshots", scope: .snapshots)
            ],
            configure: { Text($0) }
        )

        XCTAssertEqual(previews.configurations.map(\.name), ["Enabled", "Disabled", "Snapshots Only"])
        XCTAssertEqual(previews.previewConfigurations.map(\.name), ["Enabled", "Disabled"])
        XCTAssertEqual(previews.snapshotConfigurations.map(\.name), ["Enabled", "Snapshots Only"])
        _ = previews.configure("enabled")
    }

    func testStatesInitializerUsesNamedStateNames() {
        let previews = PreviewSnapshots(
            states: [
                NamedState(name: "First", value: 1),
                NamedState(name: "Second", value: 2)
            ],
            configure: { Text(String($0.value)) }
        )

        XCTAssertEqual(previews.configurations.map(\.name), ["First", "Second"])
    }

    func testStatesInitializerUsesNameKeyPath() {
        let previews = PreviewSnapshots(
            states: [
                KeyPathNamedState(title: "Alpha"),
                KeyPathNamedState(title: "Beta")
            ],
            name: \.title,
            configure: { Text($0.title) }
        )

        XCTAssertEqual(previews.configurations.map(\.name), ["Alpha", "Beta"])
    }
}

private struct NamedState: NamedPreviewState {
    let name: String
    let value: Int
}

private struct KeyPathNamedState {
    let title: String
}
