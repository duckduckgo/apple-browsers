//
//  SubscriptionAuthenticationStateProvider.swift
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

public protocol SubscriptionAuthenticationStateProvider {
    /// Whether the user is signed in. Set on sign-in and cleared only when the session is certainly over: an explicit sign-out,
    /// an unknown account, or a token nothing can recover. A missing or unreadable token alone doesn't change it.
    var isUserAuthenticated: Bool { get }
}
