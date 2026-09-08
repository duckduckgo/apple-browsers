//
//  SubscriptionOnboardingSessionState.swift
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

/// Whether the checklist reached 100% during *this* run of the app.
///
/// Held at app scope and injected. `SettingsViewModel` is rebuilt on every Settings presentation, so a flag
/// owned any lower would reset mid-session and take the card with it.
protocol SubscriptionOnboardingSessionStateManaging: AnyObject {
    var didCompleteDuringThisSession: Bool { get }
    func recordCompletedDuringThisSession()
}

final class SubscriptionOnboardingSessionState: SubscriptionOnboardingSessionStateManaging {

    private(set) var didCompleteDuringThisSession = false

    func recordCompletedDuringThisSession() {
        didCompleteDuringThisSession = true
    }
}
