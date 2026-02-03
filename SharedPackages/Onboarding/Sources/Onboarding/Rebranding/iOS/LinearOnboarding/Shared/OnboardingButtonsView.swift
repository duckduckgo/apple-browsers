//
//  OnboardingButtonsView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

#if os(iOS)
import SwiftUI

extension OnboardingRebranding {

    struct OnboardingActions: View {
        @ObservedObject var viewModel: Model

        var primaryAction: (() -> Void)?
        var secondaryAction: (() -> Void)?

        var body: some View {
            VStack(spacing: 8) {
                PrimaryButton(
                    title: viewModel.primaryButtonTitle,
                    isEnabled: viewModel.isContinueEnabled
                ) {
                    primaryAction?()
                }
                .accessibilityIdentifier("Continue")

                SecondaryButton(title: viewModel.secondaryButtonTitle) {
                    secondaryAction?()
                }
                .accessibilityIdentifier("Skip")
            }
        }
    }
}

extension OnboardingRebranding.OnboardingActions {
    final class Model: ObservableObject {
        @Published var primaryButtonTitle: String
        @Published var secondaryButtonTitle: String
        @Published var isContinueEnabled: Bool

        init(primaryButtonTitle: String = "", secondaryButtonTitle: String = "", isContinueEnabled: Bool = true) {
            self.primaryButtonTitle = primaryButtonTitle
            self.secondaryButtonTitle = secondaryButtonTitle
            self.isContinueEnabled = isContinueEnabled
        }
    }
}
#endif
