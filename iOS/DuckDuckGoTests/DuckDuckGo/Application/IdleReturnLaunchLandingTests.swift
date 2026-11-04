//
//  IdleReturnLaunchLandingTests.swift
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

struct IdleReturnLaunchLandingTests {

    private let ntp = IdleReturnOutcome.afterIdle(treatment: .ntp, timeAwayMs: 61_000)

    /// Defaults are the case that draws; each test changes one input.
    private func draws(_ outcome: IdleReturnOutcome? = nil,
                       isFeatureOn: Bool = true,
                       isBackgroundLaunch: Bool = false,
                       hasLaunchAction: Bool = false,
                       isAppLockEnabled: Bool = false,
                       hasPageToReplace: Bool = true) -> Bool {
        (outcome ?? ntp).drawsNewTabPageAtLaunch(isFeatureOn: isFeatureOn,
                                                 isBackgroundLaunch: isBackgroundLaunch,
                                                 hasLaunchAction: hasLaunchAction,
                                                 isAppLockEnabled: isAppLockEnabled,
                                                 hasPageToReplace: hasPageToReplace)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An after-idle New Tab Page replacing a restored page is drawn at launch", .timeLimit(.minutes(1)))
    func afterIdleNTPIsDrawnAtLaunch() {
        #expect(draws())
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the feature off the New Tab Page is not drawn at launch", .timeLimit(.minutes(1)))
    func featureOffIsNotDrawnAtLaunch() {
        #expect(!draws(isFeatureOn: false))
    }

    @available(iOS 16, macOS 13, *)
    @Test("On a background launch the New Tab Page is not drawn at launch", .timeLimit(.minutes(1)))
    func backgroundLaunchIsNotDrawnAtLaunch() {
        #expect(!draws(isBackgroundLaunch: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("When a launch action opened the app the New Tab Page is not drawn at launch", .timeLimit(.minutes(1)))
    func launchActionIsNotDrawnAtLaunch() {
        #expect(!draws(hasLaunchAction: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("With App Lock on the New Tab Page is not drawn at launch", .timeLimit(.minutes(1)))
    func appLockIsNotDrawnAtLaunch() {
        #expect(!draws(isAppLockEnabled: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("With no restored page to replace the New Tab Page is not drawn at launch", .timeLimit(.minutes(1)))
    func noPageToReplaceIsNotDrawnAtLaunch() {
        #expect(!draws(hasPageToReplace: false))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Last-used-tab and ordinary returns are not drawn at launch", .timeLimit(.minutes(1)),
          arguments: [IdleReturnOutcome.afterIdle(treatment: .lut, timeAwayMs: 61_000), .ordinary(timeAwayMs: 5_000)])
    func otherOutcomesAreNotDrawnAtLaunch(outcome: IdleReturnOutcome) {
        #expect(!draws(outcome))
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test("A drawn New Tab Page is taken once", .timeLimit(.minutes(1)))
    func drawnNewTabPageIsTakenOnce() {
        let landing = IdleReturnLaunchLanding(drewNewTabPage: true)
        #expect(landing.takeDrawnNewTabPage())
        #expect(!landing.takeDrawnNewTabPage())
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test("Nothing is taken when the launch didn't draw the New Tab Page", .timeLimit(.minutes(1)))
    func nothingIsTakenWhenNotDrawn() {
        let landing = IdleReturnLaunchLanding(drewNewTabPage: false)
        #expect(!landing.takeDrawnNewTabPage())
    }

}
