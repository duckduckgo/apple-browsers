//
//  OnboardingManagerMock.swift
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

import Foundation
import Core
import Onboarding
@testable import DuckDuckGo

final class OnboardingManagerMock: OnboardingStepsProvider, OnboardingDownloadReasonHandling, OnboardingAddToDockVisibilityManager, OnboardingFlowManaging {

    private(set) var didCallSettingsURLPath = false
    private(set) var didCallConfigureOnboardingFlow = false
    private(set) var capturedURL: URL?
    private(set) var didCallEvaluateOnboardingFlow = false

    var onboardingSteps: [DuckDuckGo.OnboardingIntroStep] = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)

    private(set) var didCallSelectDownloadReason = false
    private(set) var capturedDownloadReason: OnboardingDownloadReason?
    var currentDownloadReason: OnboardingDownloadReason?
    var stubbedRemainingSteps: [DuckDuckGo.OnboardingIntroStep] = []

    var userHasSeenAddToDockPromoDuringOnboarding: Bool = false

    var currentOnboardingFlow: OnboardingFlowType = .default

    func configureOnboardingFlow(from url: URL?) {
        didCallConfigureOnboardingFlow = true
        capturedURL = url
    }

    func selectDownloadReason(_ reason: OnboardingDownloadReason) -> [DuckDuckGo.OnboardingIntroStep] {
        didCallSelectDownloadReason = true
        capturedDownloadReason = reason
        currentDownloadReason = reason
        return stubbedRemainingSteps
    }
}
