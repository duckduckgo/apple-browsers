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
import Subscription
@testable import DuckDuckGo

final class SubscriptionCancellationInstrumentationSpy: SubscriptionCancellationInstrumenting {
    private(set) var cancelClickedCount = 0
    private(set) var cancelledPlatforms: [DuckDuckGoSubscription.Platform] = []
    private(set) var flowLoadFailures: [Error] = []
    private(set) var featureInfoFailedCount = 0

    func cancelClicked() { cancelClickedCount += 1 }
    func subscriptionCancelled(platform: DuckDuckGoSubscription.Platform) { cancelledPlatforms.append(platform) }
    func flowLoadFailed(_ error: Error) { flowLoadFailures.append(error) }
    func featureInfoFailed() { featureInfoFailedCount += 1 }
}
