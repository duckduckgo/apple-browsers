//
//  UpdatePromptAttributionTests.swift
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

import AppUpdaterShared
import Foundation
@_spi(Testing) import Persistence
import Testing

@Suite("Update prompt attribution")
struct UpdatePromptAttributionTests {

    private let settings: any ThrowingKeyedStoring<UpdateControllerSettings> = InMemoryThrowingKeyValueStore().throwingKeyedStoring()
    private let clickDate = Date(timeIntervalSince1970: 1_000_000)

    private func attribution(at date: Date) -> UpdatePromptAttribution {
        UpdatePromptAttribution(settings: settings, now: { date })
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reports the clicked surface within the window", .timeLimit(.minutes(1)),
          arguments: zip(UpdatePromptSurface.allCases, ["menu-item", "menu-row", "menu-card", "toolbar-button"]))
    func reportsClickedSurface(surface: UpdatePromptSurface, expectedValue: String) {
        attribution(at: clickDate).recordClick(on: surface)

        #expect(attribution(at: clickDate.addingTimeInterval(UpdatePromptAttribution.window)).consumePromptSurface() == expectedValue)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reports the most recent click", .timeLimit(.minutes(1)))
    func reportsMostRecentClick() {
        attribution(at: clickDate).recordClick(on: .menuRow)
        attribution(at: clickDate.addingTimeInterval(60)).recordClick(on: .toolbarButton)

        #expect(attribution(at: clickDate.addingTimeInterval(120)).consumePromptSurface() == "toolbar-button")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reports none without a click, or once the window has passed", .timeLimit(.minutes(1)))
    func reportsNone() {
        #expect(attribution(at: clickDate).consumePromptSurface() == "none")

        attribution(at: clickDate).recordClick(on: .menuCard)
        #expect(attribution(at: clickDate.addingTimeInterval(UpdatePromptAttribution.window + 1)).consumePromptSurface() == "none")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Forgets the click once it's reported", .timeLimit(.minutes(1)))
    func forgetsClickOnceReported() {
        attribution(at: clickDate).recordClick(on: .menuCard)

        #expect(attribution(at: clickDate).consumePromptSurface() == "menu-card")
        #expect(attribution(at: clickDate).consumePromptSurface() == "none")
    }
}
