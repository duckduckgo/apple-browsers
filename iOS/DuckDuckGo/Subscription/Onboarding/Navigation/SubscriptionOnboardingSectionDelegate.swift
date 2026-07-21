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

/// Receives events from an onboarding section. The flow view model (next PR) conforms to this to advance the
/// flow when a section finishes — e.g. the VPN reaches `.connected`, or a Duck.ai model is chosen — and to
/// launch the Duck.ai chat when the Duck.ai section requests it.
protocol SubscriptionOnboardingSectionDelegate: AnyObject {
    func sectionDidComplete(_ section: SubscriptionOnboardingSection)
    func launchDuckAIChat(modelID: String?)
}
