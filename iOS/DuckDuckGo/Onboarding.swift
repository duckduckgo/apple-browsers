//
//  Onboarding.swift
//  DuckDuckGo
//
//  Copyright © 2019 DuckDuckGo. All rights reserved.
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
import UserNotifications
import AIChat

protocol Onboarding: UIViewController {
    
    var delegate: OnboardingDelegate? { get set }
    
}

protocol OnboardingDelegate: NSObjectProtocol {

    func onboardingCompleted(controller: UIViewController)
    func openAIChatFromOnboarding(_ query: String?, autoSend: Bool, flowType: AIChatOnboardingFlowType)
    func searchFromOnboarding(for query: String)

}
