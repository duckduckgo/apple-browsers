//
//  SubscriptionWidePixelEventMapping.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import PixelKit
import BrowserServicesKit
import Common

// MARK: - App Store Purchase Flow Events

final class SubscriptionAppStoreWidePixelEventMapping: EventMapping<AppStorePurchaseFlowV2Event> {
    private let widePixelManager: WidePixelManaging
    private let originProvider: () -> String?
    private let internalUserDecider: InternalUserDecider
    private var widePixelData: SubscriptionPurchaseWidePixelData?
    private var lastFailingStep: SubscriptionPurchaseWidePixelData.FailingStep = .flowStart

    init(widePixelManager: WidePixelManaging, originProvider: @escaping () -> String?, internalUserDecider: InternalUserDecider) {
        self.widePixelManager = widePixelManager
        self.originProvider = originProvider
        self.internalUserDecider = internalUserDecider

        super.init { _, _, _, _ in }

        // Assign the real mapper after initialization to safely capture self
        self.eventMapper = { [weak self] event, error, _, _ in
            guard let self else { return }
            switch event {
            case let .started(subscriptionIdentifier, freeTrialEligible):
                var data = SubscriptionPurchaseWidePixelData(
                    purchasePlatform: .appStore,
                    subscriptionIdentifier: subscriptionIdentifier,
                    freeTrialEligible: freeTrialEligible,
                    contextData: WidePixelContextData(name: "subscription-purchase")
                )

                if let origin = self.originProvider() {
                    data.contextData.name = origin
                } else {
                    data.contextData.name = subscriptionIdentifier
                }

                data.appData.internalUser = self.internalUserDecider.isInternalUser
                self.widePixelData = data
                self.widePixelManager.startFlow(data)
                self.lastFailingStep = .flowStart

            case .accountCreationStarted:
                self.lastFailingStep = .accountCreate
                self.widePixelData?.createAccountDuration = WidePixel.MeasuredInterval(start: Date())

            case .accountCreationEnded:
                self.widePixelData?.createAccountDuration?.end = Date()
                if let data = self.widePixelData { self.widePixelManager.updateFlow(data) }

            case .paymentStarted:
                self.lastFailingStep = .accountPayment
                self.widePixelData?.completePurchaseDuration = WidePixel.MeasuredInterval(start: Date())

            case .paymentEnded:
                self.widePixelData?.completePurchaseDuration?.end = Date()
                if let data = self.widePixelData { self.widePixelManager.updateFlow(data) }

            case .activationStarted:
                self.lastFailingStep = .accountActivation
                self.widePixelData?.activateAccountDuration = WidePixel.MeasuredInterval(start: Date())

            case .activationEnded:
                self.widePixelData?.activateAccountDuration?.end = Date()
                if let data = self.widePixelData { self.widePixelManager.updateFlow(data) }

            case .succeeded:
                if let data = self.widePixelData {
                    self.widePixelManager.completeFlow(data, status: .success) { _, _ in }
                }
                self.widePixelData = nil
                self.lastFailingStep = .flowStart

            case .cancelled:
                if let data = self.widePixelData {
                    self.widePixelManager.completeFlow(data, status: .cancelled) { _, _ in }
                }
                self.widePixelData = nil
                self.lastFailingStep = .flowStart

            case let .failed(errorDescription):
                guard var data = self.widePixelData else { break }

                data.failingStep = self.lastFailingStep

                if let error {
                    data.errorData = WidePixelErrorData(error: error)
                }

                self.widePixelManager.completeFlow(data, status: .failure) { _, _ in }
                self.widePixelData = nil
                self.lastFailingStep = .flowStart
            }
        }
    }
}

// MARK: - Stripe Purchase Flow Events

final class SubscriptionStripeWidePixelEventMapping: EventMapping<StripePurchaseFlowV2Event> {
    private let widePixelManager: WidePixelManaging
    private let originProvider: () -> String?
    private let internalUserDecider: InternalUserDecider
    private var widePixelData: SubscriptionPurchaseWidePixelData?
    private var lastFailingStep: SubscriptionPurchaseWidePixelData.FailingStep = .flowStart

    init(widePixelManager: WidePixelManaging, originProvider: @escaping () -> String?, internalUserDecider: InternalUserDecider) {
        self.widePixelManager = widePixelManager
        self.originProvider = originProvider
        self.internalUserDecider = internalUserDecider

        super.init { _, _, _, _ in }

        self.eventMapper = { [weak self] event, error, _, _ in
            guard let self else { return }
            switch event {
            case let .started(subscriptionIdentifier):
                var data = SubscriptionPurchaseWidePixelData(
                    purchasePlatform: .stripe,
                    subscriptionIdentifier: subscriptionIdentifier,
                    freeTrialEligible: true,
                    contextData: WidePixelContextData(name: "subscription-purchase")
                )

                if let origin = self.originProvider() {
                    data.contextData.name = origin
                } else {
                    data.contextData.name = subscriptionIdentifier
                }

                data.appData.internalUser = self.internalUserDecider.isInternalUser
                self.widePixelData = data
                self.widePixelManager.startFlow(data)
                self.lastFailingStep = .flowStart

            case .accountCreationStarted:
                self.lastFailingStep = .accountCreate
                self.widePixelData?.createAccountDuration = WidePixel.MeasuredInterval(start: Date())

            case .accountCreationEnded:
                self.widePixelData?.createAccountDuration?.end = Date()
                if let data = self.widePixelData { self.widePixelManager.updateFlow(data) }

            case .paymentStarted:
                self.lastFailingStep = .accountPayment
                self.widePixelData?.completePurchaseDuration = WidePixel.MeasuredInterval(start: Date())

            case .paymentEnded:
                self.widePixelData?.completePurchaseDuration?.end = Date()
                if let data = self.widePixelData { self.widePixelManager.updateFlow(data) }

            case .activationStarted:
                self.lastFailingStep = .accountActivation
                self.widePixelData?.activateAccountDuration = WidePixel.MeasuredInterval(start: Date())

            case .activationEnded:
                self.widePixelData?.activateAccountDuration?.end = Date()
                if let data = self.widePixelData { self.widePixelManager.updateFlow(data) }

            case .succeeded:
                if let data = self.widePixelData {
                    self.widePixelManager.completeFlow(data, status: .success) { _, _ in }
                }
                self.widePixelData = nil
                self.lastFailingStep = .flowStart

            case .cancelled:
                if let data = self.widePixelData {
                    self.widePixelManager.completeFlow(data, status: .cancelled) { _, _ in }
                }
                self.widePixelData = nil
                self.lastFailingStep = .flowStart

            case let .failed(errorDescription):
                guard var data = self.widePixelData else { break }

                data.failingStep = self.lastFailingStep

                if let error {
                    data.errorData = WidePixelErrorData(error: error)
                }

                self.widePixelManager.completeFlow(data, status: .failure) { _, _ in }
                self.widePixelData = nil
                self.lastFailingStep = .flowStart
            }
        }
    }
}
