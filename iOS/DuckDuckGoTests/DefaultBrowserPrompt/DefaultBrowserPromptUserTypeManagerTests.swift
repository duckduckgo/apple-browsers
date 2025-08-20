//
//  DefaultBrowserPromptUserTypeManagerTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import struct Core.VariantIOS
import PersistenceTestingUtils
import SetDefaultBrowserCore
@testable import DuckDuckGo

@Suite("Default Browser Prompt - User Type Manager")
struct DefaultBrowserPromptUserTypeManagerTests {
    private var storeMock: MockDefaultBrowserPromptUserTypeStoring
    private var statisticsStoreMock: MockStatisticsStore
    private var sut: DefaultBrowserPromptUserTypeManager

    init() {
        storeMock = MockDefaultBrowserPromptUserTypeStoring()
        statisticsStoreMock = MockStatisticsStore()
        sut = DefaultBrowserPromptUserTypeManager(store: storeMock, statisticsStore: statisticsStoreMock)
    }

    @Test("Check If User Has Install Statistics Then Persist Existing User")
    func whenHasInstallStatisticsThenPersistExistingUser() {
        // GIVEN
        statisticsStoreMock.atb = "abcde"
        #expect(storeMock.capturedUserType == nil)

        // WHEN
        sut.persistUserType()

        // THEN
        #expect(storeMock.capturedUserType == .existing)
    }

    @Test("Check If User Variant Is RU Then Persist Returning User")
    func whenVariantIsRUThenPersistReturningUser() {
        // GIVEN
        statisticsStoreMock.atb = nil
        statisticsStoreMock.variant = VariantIOS.returningUser.name
        #expect(storeMock.capturedUserType == nil)

        // WHEN
        sut.persistUserType()

        // THEN
        #expect(storeMock.capturedUserType == .returning)
    }

    @Test("Check If User Has Neither Install Statistics Nor Variant Is RU Then Persist New User")
    func whenHasNeitherInstallStatisticsNorVariantIsRUThenPersistNewUser() {
        // GIVEN
        statisticsStoreMock.atb = nil
        statisticsStoreMock.variant = nil
        #expect(storeMock.capturedUserType == nil)

        // WHEN
        sut.persistUserType()

        // THEN
        #expect(storeMock.capturedUserType == .new)
    }

    @Test(
        "Check User Type Is Not Persisted When Value Is Already Persisted",
        arguments: [
            DefaultBrowserPromptUserType.existing,
            .returning,
            .new
        ]
    )
    func checkPersistUserTypeDoesNotSavesUserTypeWhenValueIsAlreadyPersisted(userType: DefaultBrowserPromptUserType) {
        // GIVEN
        storeMock.userTypeToReturn = userType
        #expect(!storeMock.didCallSaveUserType)
        #expect(storeMock.capturedUserType == nil)

        // WHEN
        sut.persistUserType()

        // THEN
        #expect(!storeMock.didCallSaveUserType)
        #expect(storeMock.capturedUserType == nil)
    }

    @Test(
        "Check Current User Type Is Returned",
        arguments: [
            DefaultBrowserPromptUserType.existing,
            .returning,
            .new,
            nil
        ]
    )
    func whenCurrentUserTypeIsRetrievedThenItIsReturned(userType: DefaultBrowserPromptUserType?) {
        // GIVEN
        storeMock.userTypeToReturn = userType

        // WHEN
        let result = sut.currentUserType()

        // THEN
        #expect(result == userType)
    }
}
