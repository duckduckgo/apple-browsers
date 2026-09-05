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
import PageRefreshMonitor

/// Events that can trigger a promo.
///
/// Triggers should map to e.g. an `NSNotification` or `@Published` property
/// that can be subscribed to by the PromoService.
enum PromoTrigger {
    case appLaunched
    case appBecameActive
    case windowBecameKey
    case newTabPageAppeared
    case autoplayDiscoverability
    case bookmarkAdded
    case bookmarksImported
    case missingBookmarkFaviconEncountered
    case pageRefreshPatternDetected
    case firstPasswordSaved
    case testTriggered

    /// Triggers for promotions, mapped to `PromoTrigger` values.
    static let triggerPublisher: AnyPublisher<PromoTrigger, Never> = {
        var triggers: [AnyPublisher<PromoTrigger, Never>] = [
            publisher(for: .promoServiceAppLaunched, trigger: .appLaunched),
            publisher(for: .newTabPageWebViewDidAppear, trigger: .newTabPageAppeared),
            publisher(for: NSWindow.didBecomeKeyNotification, trigger: .windowBecameKey),
            publisher(for: .autoplayPolicyDisplayed, trigger: .autoplayDiscoverability),
            publisher(for: .bookmarkAdded, trigger: .bookmarkAdded),
            publisher(for: .bookmarksImported, trigger: .bookmarksImported),
            publisher(for: .missingBookmarkFaviconEncountered, trigger: .missingBookmarkFaviconEncountered),
            publisher(for: .firstPasswordSaved, trigger: .firstPasswordSaved),
            publisher(for: NSApplication.didBecomeActiveNotification, trigger: .appBecameActive),
            publisher(for: .pageRefreshMonitorDidDetectRefreshPattern, trigger: .pageRefreshPatternDetected)
        ]

        if PromoServiceFactory.includeTestPromos {
            triggers.append(publisher(for: .promoDebugTestTrigger, trigger: .testTriggered))
        }

        return Publishers.MergeMany(triggers).eraseToAnyPublisher()
    }()

    private static func publisher(for name: Notification.Name,
                                  trigger: PromoTrigger) -> AnyPublisher<PromoTrigger, Never> {
        NotificationCenter.default.publisher(for: name)
            .map { _ in trigger }
            .eraseToAnyPublisher()
    }
}

extension Notification.Name {
    static let promoServiceAppLaunched = Notification.Name("com.duckduckgo.app.promoService.appLaunched")
    static let promoDebugTestTrigger = Notification.Name("com.duckduckgo.app.promoService.debugTestTrigger")
    static let autoplayPolicyDisplayed = Notification.Name("com.duckduckgo.app.autoplayPolicyDisplayed")
    static let bookmarkAdded = Notification.Name("com.duckduckgo.app.bookmarkAdded")
    static let bookmarksImported = Notification.Name("com.duckduckgo.app.bookmarksImported")
    static let missingBookmarkFaviconEncountered = Notification.Name("com.duckduckgo.app.missingBookmarkFaviconEncountered")
    static let firstPasswordSaved = Notification.Name("com.duckduckgo.app.firstPasswordSaved")
}
