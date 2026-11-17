//
//  SubscriptionProcess.swift
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

/// The process a subscription manager runs in.
public enum SubscriptionProcess {
    /// The iOS or macOS browser app, including PIR when it runs inside the iOS app. Signs the user out automatically when the
    /// session is certainly over.
    case browser
    /// A VPN process: the iOS packet tunnel, the macOS packet tunnel or the macOS VPN agent. Never signs the user out automatically.
    case vpn
    /// The macOS PIR background agent. Never signs the user out automatically.
    case pir
}
