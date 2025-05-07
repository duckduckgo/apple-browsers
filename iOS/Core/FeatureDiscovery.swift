//
//  FeatureDiscovery.swift
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

import DDGSync
import BrowserServicesKit
import Persistence

/// These features don't have a way to see if have been used before so storage is provided here.
///  Don't change these unless you intend to reset the feature discovery flag.
public enum WasUsedBeforeFeature: String {

    case aiChat
    case duckPlayer
    case vpn
    case privacyDashboard

    var storageKey: String {
        "featureUsedBefore_\(rawValue)"
    }

}

/// Allows easy querying of feature usage, primarily for use with feature discovery pixels.
/// See <a href="https://app.asana.com/1/137249556945/project/715106103902962/task/1210059260849216">feature discovery for iOS list</a>.
///
public protocol FeatureDiscovery {

    /// Some features don't have clear state for their previous usage, so let it be set explicitly.
    func setWasUsedBefore(_ feature: WasUsedBeforeFeature)

    /// Retrieve the stored state for a given feature.
    func wasUsedBefore(_ feature: WasUsedBeforeFeature) -> Bool

    func addToParams(_ params: [String: String], forFeature feature: WasUsedBeforeFeature) -> [String: String]

}

final public class DefaultFeatureDiscovery: FeatureDiscovery {

    private let wasUsedBeforeStorage: KeyValueStoring

    public init(wasUsedBeforeStorage: KeyValueStoring = UserDefaults.standard) {
        self.wasUsedBeforeStorage = wasUsedBeforeStorage
    }

    public func setWasUsedBefore(_ feature: WasUsedBeforeFeature) {
        wasUsedBeforeStorage.set(true, forKey: feature.storageKey)
    }
    
    public func wasUsedBefore(_ feature: WasUsedBeforeFeature) -> Bool {
        return wasUsedBeforeStorage.object(forKey: feature.storageKey) as? Bool ?? false
    }

    public func addToParams(_ params: [String: String], forFeature feature: WasUsedBeforeFeature) -> [String: String] {
        var params = params
        params["was_used_before"] = wasUsedBefore(feature) ? "1" : "0"
        return params
    }

}
