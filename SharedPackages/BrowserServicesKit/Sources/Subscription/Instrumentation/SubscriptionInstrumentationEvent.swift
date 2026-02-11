//
//  SubscriptionInstrumentationEvent.swift
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

/// Events fired by the subscription instrumentation facade.
/// Platform-specific pixel handlers map these events to actual pixel firing calls.
public enum SubscriptionInstrumentationEvent {

    // MARK: - Purchase Events

    case purchaseAttempt
    case purchaseSuccess(origin: String?)
    case purchaseSuccessStripe(origin: String?)
    case purchaseFailure(step: SubscriptionPurchaseWideEventData.FailingStep, error: Error)
    case purchasePendingTransaction
    case existingSubscriptionFound

    // MARK: - Restore Events

    case restoreStoreStart
    case restoreStoreSuccess
    case restoreStoreFailureNotFound
    case restoreStoreFailureOther
    case restoreEmailStart
    case restoreEmailSuccess
}
