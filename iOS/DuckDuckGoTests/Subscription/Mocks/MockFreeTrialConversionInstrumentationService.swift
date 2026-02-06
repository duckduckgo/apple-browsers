//
//  MockFreeTrialConversionInstrumentationService.swift
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
import Subscription

final class MockFreeTrialConversionInstrumentationService: FreeTrialConversionInstrumentationService {

    var startObservingSubscriptionChangesCalled = false
    var markVPNActivatedCalled = false
    var markPIRActivatedCalled = false
    var markDuckAIActivatedCalled = false

    var markVPNActivatedCallback: (() -> Void)?
    var markPIRActivatedCallback: (() -> Void)?
    var markDuckAIActivatedCallback: (() -> Void)?

    func startObservingSubscriptionChanges() {
        startObservingSubscriptionChangesCalled = true
    }

    func markVPNActivated() {
        markVPNActivatedCalled = true
        markVPNActivatedCallback?()
    }

    func markPIRActivated() {
        markPIRActivatedCalled = true
        markPIRActivatedCallback?()
    }

    func markDuckAIActivated() {
        markDuckAIActivatedCalled = true
        markDuckAIActivatedCallback?()
    }
}
