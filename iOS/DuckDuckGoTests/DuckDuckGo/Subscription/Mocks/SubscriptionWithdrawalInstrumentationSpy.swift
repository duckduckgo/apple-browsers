//
//  SubscriptionWithdrawalInstrumentationSpy.swift
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

final class SubscriptionWithdrawalInstrumentationSpy: SubscriptionWithdrawalInstrumenting {
    private(set) var withdrawClickedCount = 0
    private(set) var dialogShownCount = 0
    private(set) var confirmClickedCount = 0
    private(set) var keepClickedCount = 0
    private(set) var withdrawalFailures: [Error] = []
    private(set) var eligibilityFailures: [Error] = []

    func withdrawClicked() { withdrawClickedCount += 1 }
    func dialogShown() { dialogShownCount += 1 }
    func confirmClicked() { confirmClickedCount += 1 }
    func keepClicked() { keepClickedCount += 1 }
    func withdrawalFailed(_ error: Error) { withdrawalFailures.append(error) }
    func eligibilityFailed(_ error: Error) { eligibilityFailures.append(error) }
}
