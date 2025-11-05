//
//  DefaultBrowserAndDockPromptInactiveUserView.swift
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

final class DefaultBrowserAndDockPromptInactiveUserViewModel {
    let message: String
    let primaryButtonLabel: String
    let dismissButtonLabel: String
    let primaryButtonAction: () -> Void
    let dismissButtonAction: () -> Void

    init(message: String,
         primaryButtonLabel: String,
         dismissButtonLabel: String,
         primaryButtonAction: @escaping () -> Void,
         dismissButtonAction: @escaping () -> Void) {
        self.message = message
        self.primaryButtonLabel = primaryButtonLabel
        self.dismissButtonLabel = dismissButtonLabel
        self.primaryButtonAction = primaryButtonAction
        self.dismissButtonAction = dismissButtonAction
    }
}

struct DefaultBrowserAndDockPromptInactiveUserView: View {
    private let privacyFeatures = BrowsersComparisonModel.privacyFeatures
    private let configuration = BrowsersComparisonChart.Configuration(fontSize: Metrics.Chart.fontSize,
                                                                      fontWeight: Metrics.Chart.fontWeight,
                                                                      showFeatureIcons: true)

    let viewModel: DefaultBrowserAndDockPromptInactiveUserViewModel

    var body: some View {
        HStack(spacing: .zero) {
            VStack(alignment: .center) {
                Text(viewModel.message)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.top, Metrics.padding)
                    .padding(.horizontal, Metrics.Message.horizontalPadding)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Metrics.padding)

            VStack(spacing: Metrics.Chart.verticalSpacing) {
                Spacer()

                BrowsersComparisonChart(privacyFeatures: privacyFeatures, configuration: configuration)

                HStack {
                    Spacer()
                    OnboardingSecondaryCTAButton(title: viewModel.dismissButtonLabel, action: viewModel.dismissButtonAction)
                    OnboardingPrimaryCTAButton(title: viewModel.primaryButtonLabel, action: viewModel.primaryButtonAction)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Metrics.padding)
            .background(Color(.white))
        }
            .frame(width: 868, height: 508)
    }
}

private enum Metrics {
    static let padding: CGFloat = 24

    enum Message {
        static let horizontalPadding: CGFloat = 30
    }

    enum Chart {
        static let verticalSpacing: CGFloat = 44
        static let fontSize: CGFloat = 13
        static let fontWeight: Font.Weight = .medium
    }
}

#Preview("Set As Default") {
    let setAsDefault = DefaultBrowserAndDockPromptInactiveUserViewModel(message: "Make DuckDuckGo your default browser to protect more of what you do online.",
                                                                        primaryButtonLabel: "Set As Default",
                                                                        dismissButtonLabel: "No Thanks",
                                                                        primaryButtonAction: {},
                                                                        dismissButtonAction: {})
    return DefaultBrowserAndDockPromptInactiveUserView(viewModel: setAsDefault)
}
