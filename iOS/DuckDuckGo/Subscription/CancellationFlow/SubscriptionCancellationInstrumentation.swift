//
//  SubscriptionCancellationInstrumentation.swift
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
import PixelKit

protocol SubscriptionCancellationInstrumenting {
    func cancelClicked()
    func appStoreSubscriptionCancelled()
    func flowLoadFailed(_ error: Error)
    func featureInfoFailed(entitlement: SubscriptionEntitlement)
}

struct SubscriptionCancellationInstrumentation: SubscriptionCancellationInstrumenting {

    private let pixelFiring: PixelFiring?

    init(pixelFiring: PixelFiring? = PixelKit.shared) {
        self.pixelFiring = pixelFiring
    }

    func cancelClicked() {
        pixelFiring?.fire(SubscriptionPixel.subscriptionCancellationCancelClick)
    }

    func appStoreSubscriptionCancelled() {
        pixelFiring?.fire(SubscriptionPixel.subscriptionCancellationAppStoreCancelled)
    }

    func flowLoadFailed(_ error: Error) {
        pixelFiring?.fire(SubscriptionPixel.subscriptionCancellationFlowLoadFailure(error), frequency: .dailyAndCount)
    }

    func featureInfoFailed(entitlement: SubscriptionEntitlement) {
        pixelFiring?.fire(SubscriptionPixel.subscriptionCancellationFeatureInfoFailure(entitlement: entitlement), frequency: .dailyAndCount)
    }
}
