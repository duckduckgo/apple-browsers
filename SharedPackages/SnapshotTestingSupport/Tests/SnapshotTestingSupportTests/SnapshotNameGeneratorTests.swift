//
//  SnapshotNameGeneratorTests.swift
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
import Testing

@Suite("Snapshot Name Generator Tests")
struct SnapshotNameGeneratorTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func appearanceNamesAreStable() {
        #expect(SnapshotNameGenerator.name(for: .light) == "light")
        #expect(SnapshotNameGenerator.name(for: .dark) == "dark")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func deviceNamesAreIncludedWhenProvided() {
        #expect(
            SnapshotNameGenerator.name(for: .light, device: .iPadDefault) == "iPadDefault_light"
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func configurationUsesGeneratedNameWhenNoNameIsProvided() {
        let configuration = SnapshotImageConfiguration(
            appearance: .light,
            device: .iPhoneDefault
        )

        #expect(configuration.name == "iPhoneDefault_light")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func configurationUsesCustomNameWhenProvided() {
        let configuration = SnapshotImageConfiguration(appearance: .dark, name: "custom-dark")

        #expect(configuration.name == "custom-dark")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func previewNamesAreSanitizedAndPrepended() {
        #expect(
            SnapshotNameGenerator.name(forPreview: "Empty State", snapshotName: "iPadDefault_dark") == "Empty_State_iPadDefault_dark"
        )
    }
}
