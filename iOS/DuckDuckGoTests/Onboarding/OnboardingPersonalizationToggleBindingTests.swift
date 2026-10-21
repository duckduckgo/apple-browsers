//
//  OnboardingPersonalizationToggleBindingTests.swift
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

import Foundation
import SwiftUI
import Onboarding
import Testing
@testable import DuckDuckGo

@Suite("Onboarding - Personalization Toggle Binding")
struct OnboardingPersonalizationToggleBindingTests {

    typealias MockManager = MockOnboardingPersonalizationManager
    typealias ItemType = OnboardingPersonalizationContent.Item.ItemType

    // Each toggle row's binding must read and write exactly this manager property
    static let wiring: [(item: ItemType, keyPath: ReferenceWritableKeyPath<MockManager, Bool>)] = [
        (.recentlyVisitedSites, \.isRecentlyVisitedSitesEnabled),
        (.safeSearch, \.isSafeSearchEnabled),
        (.searchAssist, \.isSearchAssistEnabled),
        (.aiGeneratedImages, \.areAIGeneratedImagesHidden),
        (.youTubeAdBlocking, \.isYouTubeAdBlockingEnabled),
        (.rejectOptionalCookies, \.isCookiePopUpProtectionEnabled),
        (.acceptOtherCookies, \.isPopUpsWithoutOptOutsEnabled)
    ]

    @Test("Check Each toggle binding's reads its own manager setting", arguments: Self.wiring)
    func getReadsItsOwnSetting(item: ItemType, keyPath: ReferenceWritableKeyPath<MockManager, Bool>) {
        // GIVEN
        let manager = MockManager()
        manager[keyPath: keyPath] = true

        // WHEN
        let value = item.uiBindingTo(manager: manager).wrappedValue

        // THEN
        #expect(value)
    }

    @Test("Check Each toggle binding's writes only its own manager setting", arguments: Self.wiring)
    func setWritesOnlyItsOwnSetting(item: ItemType, keyPath: ReferenceWritableKeyPath<MockManager, Bool>) {
        // GIVEN
        let manager = MockManager()

        // WHEN
        item.uiBindingTo(manager: manager).wrappedValue = true

        // THEN
        #expect(manager[keyPath: keyPath])
    }
}
