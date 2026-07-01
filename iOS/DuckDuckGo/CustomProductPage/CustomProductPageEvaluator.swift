//
//  CustomProductPageEvaluator.swift
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

import Foundation
import Core

/// Represents the types of App Store Custom Product Pages supported by the app.
enum AppStoreCustomProductPage: String {
    /// The Duck.ai Custom Product Page
    case duckAI
}

/// A type for evaluating App Store Custom Product Page URLs  (e.g., `ddgCPP://<identifier>`).
protocol AppStoreCustomProductPageEvaluating {
    /// Evaluates a URL and returns the identified Custom Product Page type.
    /// - Parameter url: The URL to evaluate
    /// - Returns: The Custom Product Page type if recognised, otherwise `nil`
    func evaluateCustomProductPage(from url: URL) -> AppStoreCustomProductPage?
}

/// Parses App Store Custom Product Page URLs and identifies their type.
struct AppStoreCustomProductPageEvaluator: AppStoreCustomProductPageEvaluating {
    private let customProductPageScheme: String

    /// Creates a Custom Product Page URL evaluator.
    /// - Parameter customProductPageScheme: The URL scheme to recognise (default: `ddgCPP`)
    init(customProductPageScheme: String = AppDeepLinkSchemes.customProductPage.rawValue) {
        self.customProductPageScheme = customProductPageScheme
    }

    func evaluateCustomProductPage(from url: URL) -> AppStoreCustomProductPage? {
        Logger.customProductPage.debug("Evaluating Custom Product Page url: \(url.shortDescription)")

        guard
            url.scheme?.lowercased() == customProductPageScheme.lowercased(),
            let identifier = url.host
        else {
            Logger.customProductPage.debug("URL provided is not a Custom Product Page URL")
            return nil
        }

        guard let cpp = AppStoreCustomProductPage(rawValue: identifier) else {
            Logger.customProductPage.debug("Identifier \(identifier, privacy: .public) provided for Custom Product Page is not currently supported")
            return nil
        }

        Logger.customProductPage.debug("Evaluated Custom Product Page Type: \(cpp.rawValue, privacy: .public)")
        return cpp
    }
}
