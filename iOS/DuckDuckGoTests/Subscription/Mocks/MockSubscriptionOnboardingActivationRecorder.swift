//
//  MockSubscriptionOnboardingActivationRecorder.swift
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

import Foundation
@testable import DuckDuckGo

final class MockSubscriptionOnboardingActivationRecorder: SubscriptionOnboardingActivationRecording {

    var recordDuckAIActivatedCalled = false
    var recordPIRActivatedCalled = false
    var recordVPNActivatedCalled = false
    var recordDuckAIActivatedCallCount = 0
    var recordPIRActivatedCallCount = 0
    var recordVPNActivatedCallCount = 0
    var isDuckAIActivated = false
    var isPIRActivated = false
    var isVPNActivated = false

    func recordDuckAIActivated() {
        recordDuckAIActivatedCalled = true
        recordDuckAIActivatedCallCount += 1
    }

    func recordPIRActivated() {
        recordPIRActivatedCalled = true
        recordPIRActivatedCallCount += 1
    }

    func recordVPNActivated() {
        recordVPNActivatedCalled = true
        recordVPNActivatedCallCount += 1
    }
}
