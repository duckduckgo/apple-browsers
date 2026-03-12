//
//  AccessibilityIdentifiers+PromoQueue.swift
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

public extension AccessibilityIdentifiers {
    enum PromoQueue {
        public static let promoQueueDebugMenu = "DebugMenu.promoQueue"
        public static let fireTestTriggerMenuItem = "PromoDebugMenu.fireTestTrigger"
        public static let resetAllPromoState = "PromoDebugMenu.resetAllPromoState"
        public static let resetSimulatedDate = "PromoDebugMenu.resetSimulatedDate"
        public static let advanceSimulatedDate1Hour = "PromoDebugMenu.advanceSimulatedDate1Hour"
        public static let advanceSimulatedDate1Day = "PromoDebugMenu.advanceSimulatedDate1Day"
        public static func testPromoAlert(_ id: String) -> String {
            "PromoQueue.testPromoAlert.\(id)"
        }
        public static let actionButton = "PromoQueue.testPromoAlert.actionButton"
        public static let dismissPermanentlyButton = "PromoQueue.testPromoAlert.dismissPermanentlyButton"
        public static let dismissWithCooldownButton = "PromoQueue.testPromoAlert.dismissWithCooldownButton"
        public static let noneButton = "PromoQueue.testPromoAlert.noneButton"
        public static let setIneligibleButton = "PromoQueue.testPromoAlert.setIneligibleButton"
    }
}
