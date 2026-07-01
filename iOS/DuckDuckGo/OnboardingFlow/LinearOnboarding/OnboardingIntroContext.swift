//
//  OnboardingIntroContext.swift
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

import UIKit

struct OnboardingIntroContext {
    /// A weakly retained instance of the onboarding intro to remove from the navigation stack when an interlude starts.
    weak var onboardingViewController: UIViewController?
    /// The view model to use to resume the onboarding after an interlude.
    var onboardingViewModel: OnboardingIntroViewModel
    /// Identifies which interlude experience the host is currently running.
    var activeInterlude: OnboardingIntroStep.Interlude?
}
