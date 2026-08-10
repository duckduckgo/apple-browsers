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

/// Receives events from an onboarding section. Implemented by ``SubscriptionOnboardingFlowViewModel``, which
/// turns a completion into a store write and an advance into a cursor move.
///
/// Sections never hold this. They expose closures instead, which the view factory wires to these methods: a
/// weak delegate that had been released would swallow a tap with no crash and no log, where a closure cannot.
///
/// There is no "go back" here: back is a native pop everywhere, and the flow view model's navigation binding
/// walks its cursor back to match.
protocol SubscriptionOnboardingSectionDelegate: AnyObject {
    func sectionDidComplete(_ section: SubscriptionOnboardingSection)
    func sectionDidRequestDuckAIChat(modelID: String?)
    func sectionDidRequestAdvance()
}
