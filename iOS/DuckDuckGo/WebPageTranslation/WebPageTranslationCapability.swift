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
/// Translation is only enabled when the `pageTranslation` feature flag is on AND its models could be set up at launch.
protocol WebPageTranslationCapable {
    /// Whether web page translation is enabled right now.
    var isWebPageTranslationEnabled: Bool { get }
}

enum WebPageTranslationCapability {

    static let modelsAvailableKey = "com.duckduckgo.webPageTranslation.session.modelsAvailable"

    /// Persists whether the models could be set up for this session.
    /// Must be called early in the app launch sequence, before any consumer
    /// reads `isWebPageTranslationEnabled`.
    static func resolve(translationModels: TranslationModels?) {
        UserDefaults.app.set(translationModels != nil, forKey: modelsAvailableKey)
    }

    static func create(featureFlagger: FeatureFlagger) -> WebPageTranslationCapable {
        WebPageTranslationDefaultCapability(featureFlagger: featureFlagger)
    }
}

struct WebPageTranslationDefaultCapability: WebPageTranslationCapable {

    let featureFlagger: FeatureFlagger

    /// The flag is read live, so turning it off remotely stops translation mid-session.
    /// Turning it on takes effect at the next launch, when the models are set up.
    var isWebPageTranslationEnabled: Bool {
        featureFlagger.isFeatureOn(.pageTranslation)
            && UserDefaults.app.bool(forKey: WebPageTranslationCapability.modelsAvailableKey)
    }
}
