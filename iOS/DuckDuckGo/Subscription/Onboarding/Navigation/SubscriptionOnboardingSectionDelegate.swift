//
//  SubscriptionOnboardingSectionDelegate.swift
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

/// Receives events from an onboarding section. The flow view model conforms to this to track progress when a
/// section finishes — e.g. the VPN reaches `.connected`, or a Duck.ai model is chosen — to launch the Duck.ai
/// chat when the Duck.ai section requests it, to move to the next section when a section's terminal screen
/// (e.g. the VPN tips carousel's "Done") signals it's done, and to move to the previous section when a
/// section's root screen's back button is tapped.
protocol SubscriptionOnboardingSectionDelegate: AnyObject {
    func sectionDidComplete(_ section: SubscriptionOnboardingSection)
    func sectionDidRequestDuckAIChat(modelID: String?)
    func sectionDidRequestAdvance()
    func sectionDidRequestGoBack()
}
