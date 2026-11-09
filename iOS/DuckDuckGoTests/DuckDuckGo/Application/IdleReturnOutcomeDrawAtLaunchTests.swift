//
//  IdleReturnOutcomeDrawAtLaunchTests.swift
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
@testable import DuckDuckGo

struct IdleReturnOutcomeDrawAtLaunchTests {

    private let ntp = IdleReturnOutcome.afterIdle(treatment: .ntp, timeAwayMs: 61_000)

    /// Defaults are the case that draws; each test changes one input.
    private func drawsAtLaunch(_ outcome: IdleReturnOutcome? = nil,
                               isFeatureOn: Bool = true,
                               hasLaunchAction: Bool = false,
                               isAppLockEnabled: Bool = false,
                               hasPageToReplace: Bool = true) -> Bool {
        (outcome ?? ntp).drawsNewTabPageAtLaunch(isFeatureOn: isFeatureOn,
                                                 hasLaunchAction: hasLaunchAction,
                                                 isAppLockEnabled: isAppLockEnabled,
                                                 hasPageToReplace: hasPageToReplace)
    }

    private func drawsOnForeground(_ outcome: IdleReturnOutcome? = nil,
                                   isFeatureOn: Bool = true,
                                   hasLaunchAction: Bool = false,
                                   isClearingTabs: Bool = false,
                                   isVoiceSessionActive: Bool = false,
                                   isAlertPresented: Bool = false,
                                   isTabSwitcherPresented: Bool = false,
                                   hasPageToReplace: Bool = true) -> Bool {
        (outcome ?? ntp).drawsNewTabPageOnForeground(isFeatureOn: isFeatureOn,
                                                     hasLaunchAction: hasLaunchAction,
                                                     isClearingTabs: isClearingTabs,
                                                     isVoiceSessionActive: isVoiceSessionActive,
                                                     hasPageToReplace: hasPageToReplace,
                                                     isAlertPresented: isAlertPresented,
                                                     isTabSwitcherPresented: isTabSwitcherPresented)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An after-idle New Tab Page replacing a restored page is drawn at launch", .timeLimit(.minutes(1)))
    func afterIdleNTPIsDrawnAtLaunch() {
        #expect(drawsAtLaunch())
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the feature off the New Tab Page is not drawn at launch", .timeLimit(.minutes(1)))
    func featureOffIsNotDrawnAtLaunch() {
        #expect(!drawsAtLaunch(isFeatureOn: false))
    }

    @available(iOS 16, macOS 13, *)
    @Test("When a launch action opened the app the New Tab Page is not drawn at launch", .timeLimit(.minutes(1)))
    func launchActionIsNotDrawnAtLaunch() {
        #expect(!drawsAtLaunch(hasLaunchAction: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("With App Lock on the New Tab Page is not drawn at launch", .timeLimit(.minutes(1)))
    func appLockIsNotDrawnAtLaunch() {
        #expect(!drawsAtLaunch(isAppLockEnabled: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("With no restored page to replace the New Tab Page is not drawn at launch", .timeLimit(.minutes(1)))
    func noPageToReplaceIsNotDrawnAtLaunch() {
        #expect(!drawsAtLaunch(hasPageToReplace: false))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Last-used-tab and ordinary returns are not drawn at launch", .timeLimit(.minutes(1)),
          arguments: [IdleReturnOutcome.afterIdle(treatment: .lut, timeAwayMs: 61_000), .ordinary(timeAwayMs: 5_000)])
    func otherOutcomesAreNotDrawnAtLaunch(outcome: IdleReturnOutcome) {
        #expect(!drawsAtLaunch(outcome))
    }

    // MARK: - Warm return

    @available(iOS 16, macOS 13, *)
    @Test("An after-idle New Tab Page replacing the previous page is drawn on foreground", .timeLimit(.minutes(1)))
    func afterIdleNTPIsDrawnOnForeground() {
        #expect(drawsOnForeground())
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the feature off the New Tab Page is not drawn on foreground", .timeLimit(.minutes(1)))
    func featureOffIsNotDrawnOnForeground() {
        #expect(!drawsOnForeground(isFeatureOn: false))
    }

    @available(iOS 16, macOS 13, *)
    @Test("When a launch action is waiting the New Tab Page is not drawn on foreground", .timeLimit(.minutes(1)))
    func launchActionIsNotDrawnOnForeground() {
        #expect(!drawsOnForeground(hasLaunchAction: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("While tabs are being cleared the New Tab Page is not drawn on foreground", .timeLimit(.minutes(1)))
    func clearingTabsIsNotDrawnOnForeground() {
        #expect(!drawsOnForeground(isClearingTabs: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("During a Duck.ai voice session the New Tab Page is not drawn on foreground", .timeLimit(.minutes(1)))
    func voiceSessionIsNotDrawnOnForeground() {
        #expect(!drawsOnForeground(isVoiceSessionActive: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("With an alert open the New Tab Page is not drawn on foreground", .timeLimit(.minutes(1)))
    func alertIsNotDrawnOnForeground() {
        #expect(!drawsOnForeground(isAlertPresented: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the tab switcher open the New Tab Page is not drawn on foreground", .timeLimit(.minutes(1)))
    func tabSwitcherIsNotDrawnOnForeground() {
        #expect(!drawsOnForeground(isTabSwitcherPresented: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("With no page to replace the New Tab Page is not drawn on foreground", .timeLimit(.minutes(1)))
    func noPageToReplaceIsNotDrawnOnForeground() {
        #expect(!drawsOnForeground(hasPageToReplace: false))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Last-used-tab and ordinary returns are not drawn on foreground", .timeLimit(.minutes(1)),
          arguments: [IdleReturnOutcome.afterIdle(treatment: .lut, timeAwayMs: 61_000), .ordinary(timeAwayMs: 5_000)])
    func otherOutcomesAreNotDrawnOnForeground(outcome: IdleReturnOutcome) {
        #expect(!drawsOnForeground(outcome))
    }

}
