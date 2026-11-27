//
//  NewTabPageKeyboardPolicyTests.swift
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

import Core
import Foundation
import Testing
@testable import DuckDuckGo

struct NewTabPageKeyboardPolicyTests {

    @available(iOS 16, macOS 13, *)
    @Test(
        "App open follows New Tab on a New Tab Page, and App Launch elsewhere",
        .timeLimit(.minutes(1)),
        arguments: [false, true]
    )
    func whenAppOpensThenKeyboardFollowsTheSettingsTable(onNewTab: Bool) {
        let onAppLaunch = !onNewTab
        let policy = NewTabPageKeyboardPolicy(onNewTab: onNewTab, onAppLaunch: onAppLaunch)

        #expect(policy.showsKeyboardOnAppOpen(onNewTabPage: true) == onNewTab)
        #expect(policy.showsKeyboardOnAppOpen(onNewTabPage: false) == onAppLaunch)
    }

    @available(iOS 16, macOS 13, *)
    @Test(
        "App open is a cold start or a return after more than 20 seconds in the background",
        .timeLimit(.minutes(1)),
        arguments: [
            (nil, true),
            (21, true),
            (20, false)
        ] as [(TimeInterval?, Bool)]
    )
    func whenReturningAfterTimeInBackgroundThenItIsAnAppOpenOnlyPastTheThreshold(secondsInBackground: TimeInterval?, isAppOpen: Bool) {
        let now = Date()
        let lastBackgroundDate = secondsInBackground.map { now.addingTimeInterval(-$0) }

        #expect(NewTabPageKeyboardPolicy.isAppOpen(lastBackgroundDate: lastBackgroundDate, now: now) == isAppOpen)
    }

    struct FocusesOnReturnCase: Sendable {
        let name: String
        let secondsInBackground: TimeInterval?
        let hasCompletedAuthentication: Bool
        let drewIdleReturnPage: Bool
        let focuses: Bool
    }

    @available(iOS 16, macOS 13, *)
    @Test(
        "A return focuses when it is an app open or drew the idle return page",
        .timeLimit(.minutes(1)),
        arguments: [
            FocusesOnReturnCase(name: "long return", secondsInBackground: 60, hasCompletedAuthentication: true, drewIdleReturnPage: false, focuses: true),
            FocusesOnReturnCase(name: "short return", secondsInBackground: 5, hasCompletedAuthentication: true, drewIdleReturnPage: false, focuses: false),
            FocusesOnReturnCase(name: "short return that drew the idle page", secondsInBackground: 5, hasCompletedAuthentication: true, drewIdleReturnPage: true, focuses: true),
            FocusesOnReturnCase(name: "short return before App Lock was unlocked", secondsInBackground: 5, hasCompletedAuthentication: false, drewIdleReturnPage: false, focuses: true),
            FocusesOnReturnCase(name: "no recorded background date", secondsInBackground: nil, hasCompletedAuthentication: true, drewIdleReturnPage: false, focuses: true)
        ]
    )
    func whenReturningThenFocusFollowsAppOpenOrIdleReturnPage(testCase: FocusesOnReturnCase) {
        let now = Date()
        let lastBackgroundDate = testCase.secondsInBackground.map { now.addingTimeInterval(-$0) }

        let focuses = NewTabPageKeyboardPolicy.focusesOnReturn(lastBackgroundDate: lastBackgroundDate,
                                                               hasCompletedAuthentication: testCase.hasCompletedAuthentication,
                                                               drewIdleReturnPage: testCase.drewIdleReturnPage,
                                                               now: now)

        #expect(focuses == testCase.focuses, "\(testCase.name)")
    }

    struct AfterFireCase: Sendable {
        let onNewTab: Bool
        let onDuckAITab: Bool
        let stillOnboarding: Bool
        let showsKeyboard: Bool
    }

    @Test(
        "After Fire New Tab decides, except on a Duck.ai tab or during onboarding",
        .timeLimit(.minutes(1)),
        arguments: [
            AfterFireCase(onNewTab: true, onDuckAITab: false, stillOnboarding: false, showsKeyboard: true),
            AfterFireCase(onNewTab: true, onDuckAITab: false, stillOnboarding: true, showsKeyboard: false),
            AfterFireCase(onNewTab: true, onDuckAITab: true, stillOnboarding: false, showsKeyboard: false),
            AfterFireCase(onNewTab: true, onDuckAITab: true, stillOnboarding: true, showsKeyboard: false),
            AfterFireCase(onNewTab: false, onDuckAITab: false, stillOnboarding: false, showsKeyboard: false),
            AfterFireCase(onNewTab: false, onDuckAITab: false, stillOnboarding: true, showsKeyboard: false),
            AfterFireCase(onNewTab: false, onDuckAITab: true, stillOnboarding: false, showsKeyboard: false),
            AfterFireCase(onNewTab: false, onDuckAITab: true, stillOnboarding: true, showsKeyboard: false)
        ],
        [false, true]
    )
    @available(iOS 16, macOS 13, *)
    func whenFireLandsOnNewTabPageThenKeyboardFollowsTheAfterFireTable(_ testCase: AfterFireCase, onAppLaunch: Bool) {
        // App Launch plays no part after Fire, so every row must hold with it on and off.
        let policy = NewTabPageKeyboardPolicy(onNewTab: testCase.onNewTab, onAppLaunch: onAppLaunch)

        let showsKeyboard = policy.showsKeyboardAfterFire(
            onDuckAITab: testCase.onDuckAITab,
            stillOnboarding: testCase.stillOnboarding)

        #expect(showsKeyboard == testCase.showsKeyboard)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Swiping back restores only the focus remembered before leaving the page", .timeLimit(.minutes(1)),
          arguments: [false, true])
    func whenSwipingBackThenOnlyPreviouslyFocusedPageRestoresFocus(isInputFocused: Bool) throws {
        let policy = NewTabPageKeyboardPolicy(onNewTab: true, onAppLaunch: false)
        let newTab = Tab(fireTab: false)
        let otherNewTab = Tab(fireTab: false)
        let url = try #require(URL(string: "https://example.com"))
        let website = Tab(link: Link(title: nil, url: url), fireTab: false)

        policy.rememberInputFocusForTabSwitch(on: newTab, isInputFocused: isInputFocused)
        // The tab switcher's programmatic dismissal is separate from the captured user focus.
        policy.rememberInputFocusForTabSwitch(on: website, isInputFocused: false)

        #expect(policy.shouldRestoreInputFocusOnTabSwipe(on: website) == false)
        #expect(policy.shouldRestoreInputFocusOnTabSwipe(on: otherNewTab) == false)
        #expect(policy.shouldRestoreInputFocusOnTabSwipe(on: newTab) == isInputFocused)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A dismissal clears the focus remembered on the next departure", .timeLimit(.minutes(1)))
    func whenLeavingPageWithDismissedInputThenPreviousFocusIsCleared() {
        let policy = NewTabPageKeyboardPolicy(onNewTab: true, onAppLaunch: false)
        let tab = Tab(fireTab: false)
        policy.rememberInputFocusForTabSwitch(on: tab, isInputFocused: true)
        #expect(policy.shouldRestoreInputFocusOnTabSwipe(on: tab))

        // An inactive unified-input session has no first responder, even while its editor exists.
        policy.rememberInputFocusForTabSwitch(on: tab, isInputFocused: false)

        #expect(tab.wasInputFocusedBeforeTabSwitch == false)
        #expect(policy.shouldRestoreInputFocusOnTabSwipe(on: tab) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Swiping back preserves input focus regardless of the keyboard settings", .timeLimit(.minutes(1)),
          arguments: [false, true], [false, true])
    func whenSwipingBackThenInputFocusIsRestoredRegardlessOfKeyboardSettings(onNewTab: Bool, onAppLaunch: Bool) {
        let policy = NewTabPageKeyboardPolicy(onNewTab: onNewTab, onAppLaunch: onAppLaunch)
        let tab = Tab(fireTab: false)
        policy.rememberInputFocusForTabSwitch(on: tab, isInputFocused: true)

        #expect(policy.shouldRestoreInputFocusOnTabSwipe(on: tab))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Navigation clears remembered focus so another New Tab page does not inherit it", .timeLimit(.minutes(1)))
    func whenTabNavigatesThenRememberedInputFocusIsCleared() throws {
        let policy = NewTabPageKeyboardPolicy(onNewTab: true, onAppLaunch: false)
        let tab = Tab(fireTab: false)
        policy.rememberInputFocusForTabSwitch(on: tab, isInputFocused: true)
        let url = try #require(URL(string: "https://example.com"))

        tab.link = Link(title: nil, url: url)
        #expect(tab.wasInputFocusedBeforeTabSwitch == false)
        tab.link = nil

        #expect(policy.shouldRestoreInputFocusOnTabSwipe(on: tab) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cold restoration does not restore the previous editing focus", .timeLimit(.minutes(1)))
    func whenTabIsArchivedThenRememberedInputFocusIsNotPersisted() throws {
        let policy = NewTabPageKeyboardPolicy(onNewTab: true, onAppLaunch: false)
        let tab = Tab(fireTab: false)
        policy.rememberInputFocusForTabSwitch(on: tab, isInputFocused: true)

        let data = try NSKeyedArchiver.archivedData(withRootObject: tab, requiringSecureCoding: false)
        let restoredTab = try #require(NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? Tab)

        #expect(restoredTab.wasInputFocusedBeforeTabSwitch == false)
        #expect(policy.shouldRestoreInputFocusOnTabSwipe(on: restoredTab) == false)
    }

    struct FocusedLayoutBeforeAppOpenCase: Sendable {
        let name: String
        let onNewTab: Bool
        let hasInlineInput: Bool
        let isHeldForOnboarding: Bool
        let isBlockedByDialog: Bool
        let isAutoClearEnabled: Bool
        let hasLaunchAction: Bool
        let presentsFocused: Bool
    }

    @available(iOS 16, macOS 13, *)
    @Test(
        "The focused layout is drawn first only when focus is certain at app open",
        .timeLimit(.minutes(1)),
        arguments: [
            FocusedLayoutBeforeAppOpenCase(name: "everything allows focus", onNewTab: true, hasInlineInput: true, isHeldForOnboarding: false,
                                           isBlockedByDialog: false, isAutoClearEnabled: false, hasLaunchAction: false, presentsFocused: true),
            FocusedLayoutBeforeAppOpenCase(name: "New Tab keyboard setting off", onNewTab: false, hasInlineInput: true, isHeldForOnboarding: false,
                                           isBlockedByDialog: false, isAutoClearEnabled: false, hasLaunchAction: false, presentsFocused: false),
            FocusedLayoutBeforeAppOpenCase(name: "classic page has no inline input", onNewTab: true, hasInlineInput: false, isHeldForOnboarding: false,
                                           isBlockedByDialog: false, isAutoClearEnabled: false, hasLaunchAction: false, presentsFocused: false),
            FocusedLayoutBeforeAppOpenCase(name: "onboarding holds the keyboard", onNewTab: true, hasInlineInput: true, isHeldForOnboarding: true,
                                           isBlockedByDialog: false, isAutoClearEnabled: false, hasLaunchAction: false, presentsFocused: false),
            FocusedLayoutBeforeAppOpenCase(name: "a dialog blocks the keyboard", onNewTab: true, hasInlineInput: true, isHeldForOnboarding: false,
                                           isBlockedByDialog: true, isAutoClearEnabled: false, hasLaunchAction: false, presentsFocused: false),
            FocusedLayoutBeforeAppOpenCase(name: "automatic clearing re-attaches the page", onNewTab: true, hasInlineInput: true, isHeldForOnboarding: false,
                                           isBlockedByDialog: false, isAutoClearEnabled: true, hasLaunchAction: false, presentsFocused: false),
            FocusedLayoutBeforeAppOpenCase(name: "a launch action may replace the page", onNewTab: true, hasInlineInput: true, isHeldForOnboarding: false,
                                           isBlockedByDialog: false, isAutoClearEnabled: false, hasLaunchAction: true, presentsFocused: false)
        ]
    )
    func whenDecidingFocusedLayoutBeforeAppOpenThenOnlyCertainFocusDrawsIt(testCase: FocusedLayoutBeforeAppOpenCase) {
        let policy = NewTabPageKeyboardPolicy(onNewTab: testCase.onNewTab, onAppLaunch: false)

        let presentsFocused = policy.presentsFocusedLayoutBeforeAppOpen(hasInlineInput: testCase.hasInlineInput,
                                                                        isHeldForOnboarding: testCase.isHeldForOnboarding,
                                                                        isBlockedByDialog: testCase.isBlockedByDialog,
                                                                        isAutoClearEnabled: testCase.isAutoClearEnabled,
                                                                        hasLaunchAction: testCase.hasLaunchAction)

        #expect(presentsFocused == testCase.presentsFocused, "\(testCase.name)")
    }

}
