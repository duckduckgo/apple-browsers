//
//  SubscriptionUserScriptDebugSettings.swift
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

/// Debug-only delays and failures for the `subscriptions` user script, so web pages' timeout and failure handling can be tested.
public enum SubscriptionUserScriptDebugSettings {

    public enum AuthAccessTokenResponse: String, CaseIterable {
        case normal
        case empty
        case error

        public var title: String {
            switch self {
            case .normal: return "Normal"
            case .empty: return "Empty Token"
            case .error: return "Error"
            }
        }
    }

    public static let delayPresets: [TimeInterval] = [0, 0.5, 1.5, 2.5, 4, 10]

    private static let handshakeDelayKey = "subscription.debug.handshakeDelay"
    private static let authAccessTokenDelayKey = "subscription.debug.authAccessTokenDelay"
    private static let authAccessTokenResponseKey = "subscription.debug.authAccessTokenResponse"

    public static var handshakeDelay: TimeInterval {
        get { UserDefaults.standard.double(forKey: handshakeDelayKey) }
        set { setOrRemove(newValue > 0 ? newValue : nil, forKey: handshakeDelayKey) }
    }

    public static var authAccessTokenDelay: TimeInterval {
        get { UserDefaults.standard.double(forKey: authAccessTokenDelayKey) }
        set { setOrRemove(newValue > 0 ? newValue : nil, forKey: authAccessTokenDelayKey) }
    }

    public static var authAccessTokenResponse: AuthAccessTokenResponse {
        get { UserDefaults.standard.string(forKey: authAccessTokenResponseKey).flatMap(AuthAccessTokenResponse.init(rawValue:)) ?? .normal }
        set { setOrRemove(newValue == .normal ? nil : newValue.rawValue, forKey: authAccessTokenResponseKey) }
    }

    public static func delayTitle(_ delay: TimeInterval) -> String {
        delay > 0 ? "\(delay.formatted())s" : "Off"
    }

    private static func setOrRemove(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
