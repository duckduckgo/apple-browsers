//
//  WebPageTranslationCapability.swift
//  DuckDuckGo
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
import Core
import FeatureFlags_iOS
import Foundation
import PrivacyConfig
import WebPageTranslation

/// Protocol for resolving web page translation state.
///
/// Translation is only enabled when the `webPageTranslation` feature flag is on AND its models could be set up at launch.
protocol WebPageTranslationCapable {
    /// Whether web page translation is enabled for this session.
    var isWebPageTranslationEnabled: Bool { get }
}

enum WebPageTranslationCapability {

    static let isWebPageTranslationEnabledKey = "com.duckduckgo.webPageTranslation.session.enabled"

    /// Evaluate the checks once and persist the result for the session.
    /// Must be called early in the app launch sequence, before any consumer
    /// reads `isWebPageTranslationEnabled`, so that every component sees the same value.
    static func resolve(using featureFlagger: FeatureFlagger, translationModels: TranslationModels?) {
        let enabled = featureFlagger.isFeatureOn(.webPageTranslation) && translationModels != nil
        UserDefaults.app.set(enabled, forKey: isWebPageTranslationEnabledKey)
    }

    static func create() -> WebPageTranslationCapable {
        WebPageTranslationDefaultCapability()
    }
}

struct WebPageTranslationDefaultCapability: WebPageTranslationCapable {
    var isWebPageTranslationEnabled: Bool {
        UserDefaults.app.bool(forKey: WebPageTranslationCapability.isWebPageTranslationEnabledKey)
    }
}
