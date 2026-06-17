//
//  SnapshotImageStrategyTests.swift
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
import XCTest

final class SnapshotImageStrategyTests: XCTestCase {

    func testMacOSAllAppearancesExpandsToLightAndDark() {
        let configurations = SnapshotImageStrategy.allAppearances.configurations(
            for: .macOS,
            size: .intrinsicContentSize
        )

        XCTAssertEqual(configurations.map(\.appearance), [.light, .dark])
        XCTAssertEqual(configurations.map(\.name), ["light", "dark"])
    }

    func testIOSAllAppearancesDefaultsToIntrinsicLightAndDark() {
        let configurations = SnapshotImageStrategy.allAppearances.configurations(
            for: .iOS,
            size: .intrinsicContentSize
        )

        XCTAssertEqual(configurations.map(\.appearance), [.light, .dark])
        XCTAssertEqual(configurations.map(\.name), ["light", "dark"])
        XCTAssertEqual(configurations.map(\.device), [nil, nil])
    }

    func testIOSAllAppearancesExpandsToPhoneAndPadForScreenSnapshots() {
        let configurations = SnapshotImageStrategy.allAppearances.configurations(for: .iOS, size: .screen)

        XCTAssertEqual(
            configurations.map(\.name),
            [
                "iPhoneDefault_light",
                "iPhoneDefault_dark",
                "iPadDefault_light",
                "iPadDefault_dark"
            ]
        )
    }

    func testIOSAllAppearancesExpandsToPhoneAndPadForSheetSnapshots() {
        let configurations = SnapshotImageStrategy.allAppearances.configurations(for: .iOS, size: .sheet)

        XCTAssertEqual(
            configurations.map(\.name),
            [
                "iPhoneDefault_light",
                "iPhoneDefault_dark",
                "iPadDefault_light",
                "iPadDefault_dark"
            ]
        )
    }

    func testMacOSSingleAppearanceExpandsToOneConfiguration() {
        let configurations = SnapshotImageStrategy.single(.dark).configurations(
            for: .macOS,
            size: .intrinsicContentSize
        )

        XCTAssertEqual(configurations, [SnapshotImageConfiguration(appearance: .dark)])
    }

    func testIOSSingleAppearanceDefaultsToIntrinsic() {
        let configurations = SnapshotImageStrategy.single(.dark).configurations(
            for: .iOS,
            size: .intrinsicContentSize
        )

        XCTAssertEqual(configurations, [SnapshotImageConfiguration(appearance: .dark)])
    }

    func testIOSSingleAppearanceExpandsToPhoneAndPadForScreenSnapshots() {
        let configurations = SnapshotImageStrategy.single(.dark).configurations(for: .iOS, size: .screen)

        XCTAssertEqual(
            configurations.map(\.name),
            [
                "iPhoneDefault_dark",
                "iPadDefault_dark"
            ]
        )
    }

    func testCustomConfigurationsArePreserved() {
        let custom = [
            SnapshotImageConfiguration(
                appearance: .light,
                name: "compact-light",
                size: CGSize(width: 320, height: 480)
            )
        ]

        XCTAssertEqual(
            SnapshotImageStrategy.custom(custom).configurations(for: .iOS, size: .intrinsicContentSize),
            custom
        )
    }
}
