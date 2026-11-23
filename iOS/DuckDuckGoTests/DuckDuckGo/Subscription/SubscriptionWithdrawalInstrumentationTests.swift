//
//  SubscriptionWithdrawalInstrumentationTests.swift
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
import Testing
@_spi(Testing) import PixelKit
@testable import DuckDuckGo

@Suite("Subscription withdrawal instrumentation")
struct SubscriptionWithdrawalInstrumentationTests {

    private struct TestError: Error {}

    @available(iOS 16, macOS 13, *)
    @Test("Funnel events fire their pixels once with standard frequency", .timeLimit(.minutes(1)))
    func funnelEventsFirePixels() {
        let pixelKit = PixelKitMock()
        let instrumentation = SubscriptionWithdrawalInstrumentation(pixelFiring: pixelKit)

        instrumentation.withdrawClicked()
        instrumentation.dialogShown()
        instrumentation.confirmClicked()
        instrumentation.keepClicked()

        #expect(pixelKit.actualFireCalls == [
            ExpectedFireCall(pixel: SubscriptionPixel.subscriptionWithdrawalWithdrawClick, frequency: .standard),
            ExpectedFireCall(pixel: SubscriptionPixel.subscriptionWithdrawalDialogShown, frequency: .standard),
            ExpectedFireCall(pixel: SubscriptionPixel.subscriptionWithdrawalConfirmClick, frequency: .standard),
            ExpectedFireCall(pixel: SubscriptionPixel.subscriptionWithdrawalKeepClick, frequency: .standard)
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A withdrawal failure fires the failure pixel daily and count", .timeLimit(.minutes(1)))
    func withdrawalFailedFiresPixel() {
        let pixelKit = PixelKitMock()
        let error = TestError()

        SubscriptionWithdrawalInstrumentation(pixelFiring: pixelKit).withdrawalFailed(error)

        #expect(pixelKit.actualFireCalls == [ExpectedFireCall(pixel: SubscriptionPixel.subscriptionWithdrawalFailure(error), frequency: .dailyAndCount)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("An eligibility failure fires the eligibility failure pixel daily and count", .timeLimit(.minutes(1)))
    func eligibilityFailedFiresPixel() {
        let pixelKit = PixelKitMock()
        let error = TestError()

        SubscriptionWithdrawalInstrumentation(pixelFiring: pixelKit).eligibilityFailed(error)

        #expect(pixelKit.actualFireCalls == [ExpectedFireCall(pixel: SubscriptionPixel.subscriptionWithdrawalEligibilityFailure(error), frequency: .dailyAndCount)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Pixel names match their definitions and use the standard platform suffix", .timeLimit(.minutes(1)))
    func pixelNamesAndSuffixPolicy() {
        let pixels: [(SubscriptionPixel, String)] = [
            (.subscriptionWithdrawalWithdrawClick, "subscription_withdrawal_withdraw_click"),
            (.subscriptionWithdrawalDialogShown, "subscription_withdrawal_dialog_shown"),
            (.subscriptionWithdrawalConfirmClick, "subscription_withdrawal_confirm_click"),
            (.subscriptionWithdrawalKeepClick, "subscription_withdrawal_keep_click"),
            (.subscriptionWithdrawalFailure(TestError()), "subscription_withdrawal_failure"),
            (.subscriptionWithdrawalEligibilityFailure(TestError()), "subscription_withdrawal_eligibility_failure")
        ]

        for (pixel, name) in pixels {
            #expect(pixel.name == name)
            #expect(pixel.platformSuffixPolicy == .standard)
            #expect(pixel.parameters == nil)
        }
    }
}
