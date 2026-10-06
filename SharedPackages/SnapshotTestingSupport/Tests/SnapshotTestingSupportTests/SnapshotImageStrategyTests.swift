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
import Testing

@Suite("Snapshot Image Strategy Tests")
struct SnapshotImageStrategyTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func macOSAllAppearancesExpandsToLightAndDark() {
        let configurations = SnapshotImageStrategy.allAppearances.configurations(
            for: .macOS,
            size: .intrinsicContentSize
        )

        #expect(configurations.map(\.appearance) == [.light, .dark])
        #expect(configurations.map(\.name) == ["light", "dark"])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func iOSAllAppearancesDefaultsToIntrinsicLightAndDark() {
        let configurations = SnapshotImageStrategy.allAppearances.configurations(
            for: .iOS,
            size: .intrinsicContentSize
        )

        #expect(configurations.map(\.appearance) == [.light, .dark])
        #expect(configurations.map(\.name) == ["light", "dark"])
        #expect(configurations.map(\.device) == [nil, nil])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func iOSAllAppearancesExpandsToPhoneAndPadForScreenSnapshots() {
        let configurations = SnapshotImageStrategy.allAppearances.configurations(for: .iOS, size: .screen)

        #expect(
            configurations.map(\.name) == [
                "iPhoneDefault_light",
                "iPhoneDefault_dark",
                "iPadDefault_light",
                "iPadDefault_dark"
            ]
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func iOSAllAppearancesExpandsToPhoneAndPadForSheetSnapshots() {
        let configurations = SnapshotImageStrategy.allAppearances.configurations(for: .iOS, size: .sheet)

        #expect(
            configurations.map(\.name) == [
                "iPhoneDefault_light",
                "iPhoneDefault_dark",
                "iPadDefault_light",
                "iPadDefault_dark"
            ]
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func macOSSingleAppearanceExpandsToOneConfiguration() {
        let configurations = SnapshotImageStrategy.single(.dark).configurations(
            for: .macOS,
            size: .intrinsicContentSize
        )

        #expect(configurations == [SnapshotImageConfiguration(appearance: .dark)])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func iOSSingleAppearanceDefaultsToIntrinsic() {
        let configurations = SnapshotImageStrategy.single(.dark).configurations(
            for: .iOS,
            size: .intrinsicContentSize
        )

        #expect(configurations == [SnapshotImageConfiguration(appearance: .dark)])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func iOSSingleAppearanceExpandsToPhoneAndPadForScreenSnapshots() {
        let configurations = SnapshotImageStrategy.single(.dark).configurations(for: .iOS, size: .screen)

        #expect(
            configurations.map(\.name) == [
                "iPhoneDefault_dark",
                "iPadDefault_dark"
            ]
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func customConfigurationsArePreserved() {
        let custom = [
            SnapshotImageConfiguration(
                appearance: .light,
                name: "compact-light",
                size: CGSize(width: 320, height: 480)
            )
        ]

        #expect(
            SnapshotImageStrategy.custom(custom).configurations(for: .iOS, size: .intrinsicContentSize) == custom
        )
    }
}
