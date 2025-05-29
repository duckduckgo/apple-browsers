//
//  ContextualOnboardingPresenterMock.swift
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

import XCTest
import Foundation
@testable import DuckDuckGo

final class ContextualOnboardingPresenterMock: ContextualOnboardingPresenting {
    private(set) var didCallPresentContextualOnboarding = false
    private(set) var capturedBrowsingSpec: DaxDialogs.BrowsingSpec?
    private(set) var didCallDismissContextualOnboardingIfNeeded = false

    func presentContextualOnboarding(for spec: DaxDialogs.BrowsingSpec, in vc: TabViewOnboardingDelegate) {
        didCallPresentContextualOnboarding = true
        capturedBrowsingSpec = spec
    }
    
    func dismissContextualOnboardingIfNeeded(from vc: TabViewOnboardingDelegate) {
        didCallDismissContextualOnboardingIfNeeded = true
    }
}

final class ContextualOnboardingLogicMock: ContextualOnboardingLogic, PrivacyProPromotionCoordinating, ContextualDaxDialogDisabling {
    var expectation: XCTestExpectation?
    private(set) var didCallSetTryAnonymousSearchMessageSeen = false
    private(set) var didCallSetTryVisitSiteMessageSeen = false
    private(set) var didCallSetFireEducationMessageSeen = false
    private(set) var didCallSetFinalOnboardingDialogSeen = false
    private(set) var didCallSetSearchMessageSeen = false
    private(set) var didCallEnableAddFavoriteFlow = false
    private(set) var didCallSetDaxDialogDismiss = false
    private(set) var didCallClearedBrowserData = false
    private(set) var didCallDisableDaxDialogs = false

    var canStartFavoriteFlow = false

    var isShowingFireDialog: Bool = false
    var shouldShowPrivacyButtonPulse: Bool = false
    var isShowingSearchSuggestions: Bool = false
    var isShowingSitesSuggestions: Bool = false
    var isShowingPrivacyProPromotion: Bool = false

    func setTryAnonymousSearchMessageSeen() {
        didCallSetTryAnonymousSearchMessageSeen = true
    }

    func setTryVisitSiteMessageSeen() {
        didCallSetTryVisitSiteMessageSeen = true
    }

    func setFireEducationMessageSeen() {
        didCallSetFireEducationMessageSeen = true
    }

    func setFinalOnboardingDialogSeen() {
        didCallSetFinalOnboardingDialogSeen = true
        expectation?.fulfill()
    }

    func setSearchMessageSeen() {
        didCallSetSearchMessageSeen = true
    }

    func setPrivacyButtonPulseSeen() {

    }

    func enableAddFavoriteFlow() {
        didCallEnableAddFavoriteFlow = true
    }

    func setDaxDialogDismiss() {
        didCallSetDaxDialogDismiss = true
    }

    func clearedBrowserData() {
        didCallClearedBrowserData = true
    }

    var privacyProPromotionDialogSeen: Bool = false

    func disableContextualDaxDialogs() {
        didCallDisableDaxDialogs = true
    }
}
