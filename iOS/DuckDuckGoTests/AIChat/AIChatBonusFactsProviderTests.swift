//
//  AIChatBonusFactsProviderTests.swift
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
import Testing
import AIChat
import FoundationExtensions
@testable import Core
@testable import DuckDuckGo

@Suite("AIChatBonus - Facts Provider Tests")
struct AIChatBonusFactsProviderTests {
    private static let installDate = Date(timeIntervalSince1970: 1_792_036_890) // Oct 15
    private static let installWindowDays = 7

    private let statisticsStore = MockStatisticsStore()
    private let aiChatSettings = MockAIChatSettingsProvider()
    private let timeTraveller = TimeTraveller(date: Self.installDate)

    private func makeSUT(installWindowDays: Int = Self.installWindowDays) -> AIChatBonusFactsProvider {
        AIChatBonusFactsProvider(
            statisticsStore: statisticsStore,
            aiChatSettings: aiChatSettings,
            installWindowDays: installWindowDays,
            now: { timeTraveller.getDate() }
        )
    }

    // MARK: - isNewInstall

    @Test("Check a first install on its install day is a new install")
    func firstInstallOnInstallDayIsNew() {
        // GIVEN
        statisticsStore.installDate = Self.installDate

        // WHEN
        let sut = makeSUT()

        // THEN
        #expect(sut.isNewInstall)
    }

    @Test("Check a first install on the last day of the window is a new install")
    func firstInstallOnTheLastDayOfTheWindowIsNew() {
        // GIVEN
        statisticsStore.installDate = Self.installDate
        timeTraveller.advanceBy(.days(Self.installWindowDays - 1))

        // WHEN
        let sut = makeSUT()

        // THEN
        #expect(sut.isNewInstall)
    }

    @Test("Check a first install is no longer new once the window has passed")
    func firstInstallAfterTheWindowIsNotNew() {
        // GIVEN
        statisticsStore.installDate = Self.installDate
        timeTraveller.advanceBy(.days(Self.installWindowDays))

        // WHEN
        let sut = makeSUT()

        // THEN
        #expect(!sut.isNewInstall)
    }

    @Test("Check the install window can be changed")
    func installWindowCanBeChanged() {
        // GIVEN
        statisticsStore.installDate = Self.installDate
        let sut = makeSUT(installWindowDays: 3)
        timeTraveller.advanceBy(.days(2))

        // WHEN
        let isNewOnTheLastDay = sut.isNewInstall

        // THEN
        #expect(isNewOnTheLastDay)

        // WHEN
        timeTraveller.advanceBy(.days(1))
        let isNewAfterTheWindow = sut.isNewInstall

        // THEN
        #expect(!isNewAfterTheWindow)
    }

    @Test("Check a returning user isn't a new install")
    func returningUserIsNotNew() {
        // GIVEN
        statisticsStore.installDate = Self.installDate
        statisticsStore.variant = VariantIOS.returningUser.name

        // WHEN
        let sut = makeSUT()

        // THEN
        #expect(!sut.isNewInstall)
    }

    @Test("Check an install without an install date isn't a new install")
    func installWithoutInstallDateIsNotNew() {
        // GIVEN
        statisticsStore.installDate = nil

        // WHEN
        let sut = makeSUT()

        // THEN
        #expect(!sut.isNewInstall)
    }

    // MARK: - isAIChatEnabled

    @Test("Check Duck.ai enabled follows the setting", arguments: [true, false])
    func aiChatEnabledFollowsTheSetting(isEnabled: Bool) {
        // GIVEN
        aiChatSettings.isAIChatEnabled = isEnabled

        // WHEN
        let sut = makeSUT()

        // THEN
        #expect(sut.isAIChatEnabled == isEnabled)
    }
}
