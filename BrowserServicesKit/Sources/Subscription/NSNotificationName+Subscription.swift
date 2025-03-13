//
//  NSNotificationName+Subscription.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public extension NSNotification.Name {

    static let openVPN = Notification.Name("com.duckduckgo.subscription.open.vpn")
    static let openPersonalInformationRemoval = Notification.Name("com.duckduckgo.subscription.open.personal-information-removal")
    static let openIdentityTheftRestoration = Notification.Name("com.duckduckgo.subscription.open.identity-theft-restoration")

    static let accountDidSignIn = Notification.Name("com.duckduckgo.subscription.AccountDidSignIn")
    static let accountDidSignOut = Notification.Name("com.duckduckgo.subscription.AccountDidSignOut")
    static let entitlementsDidChange = Notification.Name("com.duckduckgo.subscription.EntitlementsDidChange")
    static let subscriptionDidChange = Notification.Name("com.duckduckgo.subscription.SubscriptionDidChange")
    static let expiredRefreshTokenDetected = Notification.Name("com.duckduckgo.subscription.ExpiredRefreshTokenDetected")
}
