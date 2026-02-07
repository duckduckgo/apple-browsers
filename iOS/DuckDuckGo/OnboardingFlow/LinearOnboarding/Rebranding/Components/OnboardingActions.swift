//
//  OnboardingActions.swift
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

import SwiftUI
import DuckUI
import Onboarding

extension OnboardingRebranding.OnboardingView {

    struct OnboardingActions: View {

        @ObservedObject var viewModel: Model

        var primaryAction: (() -> Void)?
        var secondaryAction: (() -> Void)?

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

        var body: some View {
            VStack(spacing: 8) {
                Button(action: {
                    self.primaryAction?()
                }, label: {
                    Text(viewModel.primaryButtonTitle)
                })
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.isContinueEnabled)
                .accessibilityIdentifier("Continue")

                Button(action: {
                    self.secondaryAction?()
                }, label: {
                    Text(viewModel.secondaryButtonTitle)
                })
                .buttonStyle(GhostButtonStyle())
                .accessibilityIdentifier("Skip")
            }
        }
    }

}
