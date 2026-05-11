//
//  CustomProductPageDeepLinkHandler.swift
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

protocol AppStoreCustomProductPagePresenter: AIChatDeepLinkPresenting {}

/// Protocol for handling a specific Custom Product Page destination
protocol CustomProductPageDestinationHandling {
    /// Handles navigation to the CPP destination
    /// - Parameters:
    ///   - url: The original CPP URL
    ///   - presenter: The view controller to present on (e.g. MainViewController)
    func handle(url: URL, on presenter: AppStoreCustomProductPagePresenter)
}

/// Handles deep links from App Store Custom Product Pages after onboarding has been completed.
///
/// When a user opens the app via a Custom Product Page deep link (e.g., `ddgCPP://duckAI`)
struct AppStoreCustomProductPageDeepLinkHandler {
    private let handlers: [AppStoreCustomProductPage: CustomProductPageDestinationHandling]
    private let customProductPageEvaluator: AppStoreCustomProductPageEvaluating

    init(
        handlers: [AppStoreCustomProductPage: CustomProductPageDestinationHandling] = [.duckAI: DuckAIDestinationHandler()],
        customProductPageEvaluator: AppStoreCustomProductPageEvaluating = AppStoreCustomProductPageEvaluator()) {
            self.handlers = handlers
            self.customProductPageEvaluator = customProductPageEvaluator
        }

    /// Handles a Custom Product Page deep link by routing to the appropriate feature.
    /// - Parameters:
    ///   - url: The Custom Product Page URL (e.g., `ddgCPP://duckAI`)
    ///   - mainViewController: The main view controller to present the destination on
    func handleDeepLink(_ url: URL, on presenter: AppStoreCustomProductPagePresenter) {
        guard let cpp = customProductPageEvaluator.evaluateCustomProductPage(from: url) else {
            return
        }

        guard let handler = handlers[cpp] else {
            Logger.customProductPage.debug("No Registered Handler for Custom Product Page \(cpp.rawValue)")
            return
        }

        handler.handle(url: url, on: presenter)
    }
}

// MARK: - MainViewController + AppStoreCustomProductPagePresenter

extension MainViewController: AppStoreCustomProductPagePresenter {}
