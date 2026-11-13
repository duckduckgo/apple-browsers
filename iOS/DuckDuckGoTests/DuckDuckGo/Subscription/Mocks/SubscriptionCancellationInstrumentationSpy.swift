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
    private(set) var cancelSubscriptionFailures: [Error] = []
    private(set) var appStoreSubscriptionCancelledCount = 0
    private(set) var manageSubscriptionSheetShownCount = 0
    private(set) var flowLoadFailures: [Error] = []
    private(set) var featureInfoFailures: [SubscriptionEntitlement] = []

    func cancelSubscriptionTapped(subscription: DuckDuckGoSubscription?) { cancelSubscriptionTappedCount += 1 }
    func manageSubscriptionTapped(entryPoint: SubscriptionCancellationWideEventData.EntryPoint, subscription: DuckDuckGoSubscription?) {
        manageSubscriptionTappedEntryPoints.append(entryPoint)
    }
    var onCancelSubscriptionFailed: (() -> Void)?
    var onManageSubscriptionSheetShown: (() -> Void)?

    func cancelSubscriptionFailed(_ error: Error) {
        cancelSubscriptionFailures.append(error)
        onCancelSubscriptionFailed?()
    }
    func manageSubscriptionSheetShown() {
        manageSubscriptionSheetShownCount += 1
        onManageSubscriptionSheetShown?()
    }
    func appStoreSubscriptionCancelled(entry: SubscriptionCancellationEntry, subscription: DuckDuckGoSubscription) { appStoreSubscriptionCancelledCount += 1 }
    func flowLoadFailed(_ error: Error) { flowLoadFailures.append(error) }
    func featureInfoFailed(entitlement: SubscriptionEntitlement) { featureInfoFailures.append(entitlement) }
}
