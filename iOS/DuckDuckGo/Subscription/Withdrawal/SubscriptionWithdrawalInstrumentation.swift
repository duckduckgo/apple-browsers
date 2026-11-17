//
//  SubscriptionWithdrawalInstrumentation.swift
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
import PixelKit

protocol SubscriptionWithdrawalInstrumenting {
    func withdrawClicked()
    func dialogShown()
    func confirmClicked()
    func keepClicked()
    func withdrawalFailed(_ error: Error)
    func eligibilityFailed(_ error: Error)
}

struct SubscriptionWithdrawalInstrumentation: SubscriptionWithdrawalInstrumenting {

    private let pixelFiring: PixelFiring?

    init(pixelFiring: PixelFiring? = PixelKit.shared) {
        self.pixelFiring = pixelFiring
    }

    func withdrawClicked() {
        pixelFiring?.fire(SubscriptionPixel.subscriptionWithdrawalWithdrawClick)
    }

    func dialogShown() {
        pixelFiring?.fire(SubscriptionPixel.subscriptionWithdrawalDialogShown)
    }

    func confirmClicked() {
        pixelFiring?.fire(SubscriptionPixel.subscriptionWithdrawalConfirmClick)
    }

    func keepClicked() {
        pixelFiring?.fire(SubscriptionPixel.subscriptionWithdrawalKeepClick)
    }

    func withdrawalFailed(_ error: Error) {
        pixelFiring?.fire(SubscriptionPixel.subscriptionWithdrawalFailure(error), frequency: .dailyAndCount)
    }

    func eligibilityFailed(_ error: Error) {
        pixelFiring?.fire(SubscriptionPixel.subscriptionWithdrawalEligibilityFailure(error), frequency: .dailyAndCount)
    }
}
