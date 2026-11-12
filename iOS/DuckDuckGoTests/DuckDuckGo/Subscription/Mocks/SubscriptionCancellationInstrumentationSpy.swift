//
//  SubscriptionCancellationInstrumentationSpy.swift
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
import Networking
import Subscription
@testable import DuckDuckGo

final class SubscriptionCancellationInstrumentationSpy: SubscriptionCancellationInstrumenting {
    private(set) var cancelSubscriptionTappedCount = 0
    private(set) var manageSubscriptionTappedEntryPoints: [SubscriptionCancellationWideEventData.EntryPoint] = []
    private(set) var manageSubscriptionFailures: [Error] = []
    private(set) var manageSubscriptionClosedCount = 0
    private(set) var flowLoadFailures: [Error] = []
    private(set) var featureInfoFailures: [SubscriptionEntitlement] = []

    func cancelSubscriptionTapped(subscription: DuckDuckGoSubscription?) { cancelSubscriptionTappedCount += 1 }
    func manageSubscriptionTapped(entryPoint: SubscriptionCancellationWideEventData.EntryPoint, subscription: DuckDuckGoSubscription?) {
        manageSubscriptionTappedEntryPoints.append(entryPoint)
    }
    var onManageSubscriptionFailed: (() -> Void)?
    var onManageSubscriptionClosed: (() -> Void)?

    func manageSubscriptionFailed(_ error: Error) {
        manageSubscriptionFailures.append(error)
        onManageSubscriptionFailed?()
    }
    func manageSubscriptionClosed(entry: SubscriptionCancellationEntry, subscriptionBefore: DuckDuckGoSubscription, subscriptionAfter: DuckDuckGoSubscription?) {
        manageSubscriptionClosedCount += 1
        onManageSubscriptionClosed?()
    }
    func flowLoadFailed(_ error: Error) { flowLoadFailures.append(error) }
    func featureInfoFailed(entitlement: SubscriptionEntitlement) { featureInfoFailures.append(entitlement) }
}
