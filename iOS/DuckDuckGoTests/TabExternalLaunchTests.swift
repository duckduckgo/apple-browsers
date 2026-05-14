//
//  TabExternalLaunchTests.swift
//  DuckDuckGo
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

import Testing
import Foundation
@testable import DuckDuckGo
@testable import Core

@Suite("Tab - External Launch Properties")
@MainActor
struct TabExternalLaunchTests {

    @Test("Validate new tab has both external launch flags set to false by default")
    func newTabHasDefaultFlagValues() throws {
        // GIVEN
        let tab = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))

        // THEN
        #expect(!tab.isExternalLaunch)
        #expect(!tab.shouldSuppressTrackerAnimationOnFirstLoad)
    }

    @Test("External launch flags are not persisted across encode/decode")
    func externalLaunchFlagsAreTransient() throws {
        // GIVEN
        let tab = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))
        tab.isExternalLaunch = true
        tab.shouldSuppressTrackerAnimationOnFirstLoad = true
        #expect(tab.isExternalLaunch)
        #expect(tab.shouldSuppressTrackerAnimationOnFirstLoad)

        // WHEN
        let data = try NSKeyedArchiver.archivedData(withRootObject: tab, requiringSecureCoding: false)
        let decodedTab = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? Tab

        // THEN
        #expect(decodedTab?.isExternalLaunch == false)
        #expect(decodedTab?.shouldSuppressTrackerAnimationOnFirstLoad == false)
    }

    @Test("Both flags can be set independently without affecting each other")
    func flagsAreIndependent() throws {
        // GIVEN
        let tab = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))

        // WHEN
        tab.isExternalLaunch = true

        // THEN
        #expect(tab.isExternalLaunch)
        #expect(!tab.shouldSuppressTrackerAnimationOnFirstLoad)

        // WHEN
        tab.shouldSuppressTrackerAnimationOnFirstLoad = true

        // THEN
        #expect(tab.isExternalLaunch)
        #expect(tab.shouldSuppressTrackerAnimationOnFirstLoad)

        // WHEN
        tab.isExternalLaunch = false

        // THEN
        #expect(!tab.isExternalLaunch)
        #expect(tab.shouldSuppressTrackerAnimationOnFirstLoad)
    }

}
