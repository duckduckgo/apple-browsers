//
//  AIChatBonusFactsProviderTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

@Suite("AIChatBonus - Facts Provider Tests")
final class AIChatBonusFactsProviderTests {
    private static let installDate = Date(timeIntervalSince1970: 1_792_036_890) // Oct 15
    private static let installWindowDays = 7

    private var installDate: Date? = AIChatBonusFactsProviderTests.installDate
    private var isReinstallingUser = false
    private var isAIChatEnabled = true
    private var now = AIChatBonusFactsProviderTests.installDate

    private func makeSUT(installWindowDays: Int = AIChatBonusFactsProviderTests.installWindowDays) -> AIChatBonusFactsProvider {
        AIChatBonusFactsProvider(
            installDateProvider: { [unowned self] in installDate },
            isReinstallingUserProvider: { [unowned self] in isReinstallingUser },
            isAIChatEnabledProvider: { [unowned self] in isAIChatEnabled },
            installWindowDays: installWindowDays,
            now: { [unowned self] in now }
        )
    }

    private func advance(days: Int) {
        now = Calendar.current.date(byAdding: .day, value: days, to: now)!
    }

    // MARK: - isNewInstall

    @Test("Check a first install on its install day is a new install")
    func firstInstallOnInstallDayIsNew() {
        // WHEN
        let sut = makeSUT()

        // THEN
        #expect(sut.isNewInstall)
    }

    @Test("Check a first install on the last day of the window is a new install")
    func firstInstallOnTheLastDayOfTheWindowIsNew() {
        // GIVEN
        advance(days: Self.installWindowDays - 1)

        // WHEN
        let sut = makeSUT()

        // THEN
        #expect(sut.isNewInstall)
    }

    @Test("Check a first install is no longer new once the window has passed")
    func firstInstallAfterTheWindowIsNotNew() {
        // GIVEN
        advance(days: Self.installWindowDays)

        // WHEN
        let sut = makeSUT()

        // THEN
        #expect(!sut.isNewInstall)
    }

    @Test("Check the install window can be changed")
    func installWindowCanBeChanged() {
        // GIVEN
        let sut = makeSUT(installWindowDays: 3)
        advance(days: 2)

        // WHEN
        let isNewOnTheLastDay = sut.isNewInstall

        // THEN
        #expect(isNewOnTheLastDay)

        // WHEN
        advance(days: 1)
        let isNewAfterTheWindow = sut.isNewInstall

        // THEN
        #expect(!isNewAfterTheWindow)
    }

    @Test("Check a reinstall isn't a new install")
    func reinstallIsNotNew() {
        // GIVEN
        isReinstallingUser = true

        // WHEN
        let sut = makeSUT()

        // THEN
        #expect(!sut.isNewInstall)
    }

    @Test("Check an install without an install date isn't a new install")
    func installWithoutInstallDateIsNotNew() {
        // GIVEN
        installDate = nil

        // WHEN
        let sut = makeSUT()

        // THEN
        #expect(!sut.isNewInstall)
    }

    // MARK: - isAIChatEnabled

    @Test("Check Duck.ai enabled follows the setting", arguments: [true, false])
    func aiChatEnabledFollowsTheSetting(isEnabled: Bool) {
        // GIVEN
        isAIChatEnabled = isEnabled

        // WHEN
        let sut = makeSUT()

        // THEN
        #expect(sut.isAIChatEnabled == isEnabled)
    }
}
