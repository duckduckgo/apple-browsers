//
//  SERPSettingsConstants.swift
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

/// Constants used for SERP settings communication and storage.
///
/// These constants define the contract between the SERP web page and native
/// application for settings synchronization and navigation requests.
public enum SERPSettingsConstants {

    /// Parameter key for return navigation requests.
    ///
    /// Used in `openNativeSettings` messages to specify where the user should
    /// be navigated after leaving the SERP settings page.
    ///
    /// Example: `["return": "privateSearch"]`
    public static let returnParameterKey = "return"

    /// Parameter key for direct screen navigation requests.
    ///
    /// Used in `openNativeSettings` messages to specify which settings screen
    /// should be opened directly.
    ///
    /// Example: `["screen": "aiFeatures"]`
    public static let screenParameterKey = "screen"

    /// Parameter value indicating private search settings navigation.
    ///
    /// When used with `returnParameterKey`, signals the app should navigate
    /// to the privacy search settings screen.
    public static let privateSearch = "privateSearch"

    /// Parameter value indicating AI features settings navigation.
    ///
    /// When used with `returnParameterKey` or `screenParameterKey`, signals
    /// the app should navigate to the AI features settings screen.
    public static let aiFeatures = "aiFeatures"

    /// Key-value store key for SERP settings persistence.
    ///
    /// This key identifies the JSON blob containing all SERP settings in
    /// the native storage. The blob contains only non-default setting values.
    public static let serpSettingsStorage = "serp.settings.native.storage"
}
