//
//  DefaultBrowserAndDockPromptUIProvider.swift
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

import SwiftUI
import Onboarding

protocol DefaultBrowserAndDockPromptUIProviding {

    /// Provides the browsers comparison chart used in the default browser and add to dock prompts.
    func makeBrowserComparisonChart() -> AnyView

}

struct DefaultBrowserAndDockPromptUIProvider: DefaultBrowserAndDockPromptUIProviding {

    func makeBrowserComparisonChart() -> AnyView {
        AnyView(BrowsersComparisonChart(privacyFeatures: BrowsersComparisonModel.privacyFeatures, configuration: .defaultBrowserAndDockPromptConfiguration))
    }

}

private extension BrowsersComparisonChart.Configuration {
    static let defaultBrowserAndDockPromptConfiguration = BrowsersComparisonChart.Configuration(fontSize: Metrics.fontSize,
                                                                                                fontWeight: Metrics.fontWeight,
                                                                                                showFeatureIcons: true,
                                                                                                showBottomDivider: false)

    enum Metrics {
        static let fontSize: CGFloat = 13
        static let fontWeight: Font.Weight = .medium
    }
}
