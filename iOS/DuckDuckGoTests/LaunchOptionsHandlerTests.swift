//
//  LaunchOptionsHandlerTests.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import Core

final class LaunchOptionsHandlerTests {
    private static let suiteName = "testing_launchOptionsHandler"
    private var userDefaults: UserDefaults!

    func setUp() {
        userDefaults = UserDefaults(suiteName: Self.suiteName)
    }

    func tearDown() {
        userDefaults.removePersistentDomain(forName: Self.suiteName)
        userDefaults = nil
    }

    // MARK: - isOnboardingCompleted

    @Test("Developer completed status is overridden when onboarding is false in environment")
    func testShouldReturnStatusOverriddenDeveloperCompletedTrueWhenIsOnboardingCompletedAndEnvironmentsOnboardingIsFalse() {
        // GIVEN
        setUp()
        let environment = ["ONBOARDING": "false"]
        let sut = LaunchOptionsHandler(environment: environment, userDefaults: userDefaults)

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .overridden(.developer(completed: true)))
        tearDown()
    }

    @Test("Developer completed status is overridden when onboarding is true in environment")
    func testShouldReturnStatusOverriddenDeveloperCompletedFalseWhenIsOnboardingCompletedAndEnvironmentsOnboardingIsTrue() {
        // GIVEN
        setUp()
        let environment = ["ONBOARDING": "true"]
        let sut = LaunchOptionsHandler(environment: environment, userDefaults: userDefaults)

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .overridden(.developer(completed: false)))
        tearDown()
    }

    @Test("UI tests completed status is overridden when onboarding is completed in defaults")
    func testShouldReturnStatusOverriddenUITestsCompletedTrueWhenIsOnboardingCompletedAndDefaultsIsOnboardingCompletedIsTrue() {
        // GIVEN
        setUp()
        userDefaults.set("true", forKey: "isOnboardingCompleted")
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults)

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .overridden(.uiTests(completed: true)))
        tearDown()
    }

    @Test("UI tests completed status is overridden when onboarding is not completed in defaults")
    func testShouldReturnStatusOverriddenCompletedFalseWhenIsOnboardingCompletedAndDefaultsIsOnboardingCompletedIsFalse() {
        // GIVEN
        setUp()
        userDefaults.set("false", forKey: "isOnboardingCompleted")
        let sut = LaunchOptionsHandler(userDefaults: userDefaults)

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .overridden(.uiTests(completed: false)))
        tearDown()
    }

    @Test("Status is not overridden when defaults and environment are not defined")
    func testShouldReturnStatusNotOverriddenWhenIsOnboardingCompletedAndDefaultsAndEnvironmentAreNotDefined() {
        // GIVEN
        setUp()
        userDefaults.removeObject(forKey: "isOnboardingCompleted")
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults)

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .notOverridden)
        tearDown()
    }

    // MARK: - App Variant

    @Test("App variant is returned when defined in defaults")
    func testShouldReturnAppVariantWhenAppVariantIsCalledAndDefaultsContainsAppVariant() {
        // GIVEN
        setUp()
        userDefaults.set("mb", forKey: "currentAppVariant")
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults)

        // WHEN
        let result = sut.appVariantName

        // THEN
        #expect(result == "mb")
        tearDown()
    }

    @Test("Nil is returned when app variant is not defined in defaults")
    func testShouldReturnNilWhenAppVariantIsCalledAndDefaultsDoesNotContainsAppVariant() {
        // GIVEN
        setUp()
        userDefaults.removeObject(forKey: "currentAppVariant")
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults)

        // WHEN
        let result = sut.appVariantName

        // THEN
        #expect(result == nil)
        tearDown()
    }

    @Test("Nil is returned when app variant is 'null' in defaults")
    func testShouldReturnNilWhenAppVariantIsCalledAndDefaultsContainsNullStringAppVariant() {
        // GIVEN
        setUp()
        userDefaults.set("null", forKey: "currentAppVariant")
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults)

        // WHEN
        let result = sut.appVariantName

        // THEN
        #expect(result == nil)
        tearDown()
    }

    // MARK: - iPad 17.7.7 Issue

    @Test("Developer overridden completed status is returned when iPad and iOS 17.7.7")
    func testShouldReturnDeveloperOverriddenCompletedWhenIpadAndOSIs17_7_7() throws {
        // GIVEN
        setUp()
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults, isIpad: true, systemVersion: "17.7.7")

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .overridden(.developer(completed: true)))
        tearDown()
    }

    @Test("Developer overridden completed status is not returned when iPad and iOS is not 17.7.7")
    func testShouldNotReturnDeveloperOverriddenCompletedWhenIpadAndOSIsNot17_7_7() throws {
        // GIVEN
        setUp()
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults, isIpad: true, systemVersion: "17.7.6")

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .notOverridden)
        tearDown()
    }

    @Test("Developer overridden completed status is not returned when not iPad and iOS 17.7.7")
    func testShouldNotReturnDeveloperOverriddenCompletedWhenIsNotIpadAndOSIs17_7_7() {
        // GIVEN
        setUp()
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults, isIpad: false, systemVersion: "17.7.7")

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .notOverridden)
        tearDown()
    }
}
