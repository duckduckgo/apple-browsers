//
//  PromoTrigger.swift
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

import AppKit
import Combine
import Foundation

/// Events that can trigger a promo.
///
/// Triggers should map to e.g. an `NSNotification` or `@Published` property
/// that can be subscribed to by the PromoService.
enum PromoTrigger {
    case appLaunched
    case windowBecameKey
    case newTabPageAppeared
    case testTriggered

    /// Triggers for promotions, mapped to `PromoTrigger` values.
    static let triggerPublisher: AnyPublisher<PromoTrigger, Never> = {
        let triggers = Publishers.Merge3(
            NotificationCenter.default.publisher(for: .promoServiceAppLaunched)
                .map { _ in PromoTrigger.appLaunched },
            NotificationCenter.default.publisher(for: .newTabPageWebViewDidAppear)
                .map { _ in PromoTrigger.newTabPageAppeared },
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
                .map { _ in PromoTrigger.windowBecameKey }
        ).eraseToAnyPublisher()

        if PromoServiceFactory.includeTestPromos{
            return Publishers.Merge(triggers,
                                    NotificationCenter.default.publisher(for: .promoDebugTestTrigger)
                .map { _ in PromoTrigger.testTriggered }
            ).eraseToAnyPublisher()
        } else {
            return triggers
        }
    }()
}

extension Notification.Name {
    static let promoServiceAppLaunched = Notification.Name("com.duckduckgo.app.promoService.appLaunched")
    static let promoDebugTestTrigger = Notification.Name("com.duckduckgo.app.promoService.debugTestTrigger")
}
