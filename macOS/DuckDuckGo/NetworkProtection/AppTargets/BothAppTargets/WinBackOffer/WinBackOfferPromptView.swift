//
//  WinBackOfferPromptView.swift
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
import SwiftUIExtensions

@MainActor
struct WinBackOfferPromptView: ModalView {

    fileprivate enum Constants {
        static let viewWidth: CGFloat = 352
        static let imageHeight: CGFloat = 72
        static let imageWidth: CGFloat = 96
        static let buttonHeight: CGFloat = 28
        static let horizontalPadding: CGFloat = 16
        static let topPadding: CGFloat = 8
        static let bottomPadding: CGFloat = 16
        static let betweenButtonsSpacing: CGFloat = 8
        static let titleAndMessageSpacing: CGFloat = 12
        static let buttonTopPadding: CGFloat = 12
    }

    private let viewModel: WinBackOfferPromptViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: WinBackOfferPromptViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 8) {
            Image("subscription-clock")
                .resizable()
                .scaledToFit()
                .frame(width: Constants.imageWidth, height: Constants.imageHeight)

            titleAndMessage

            actionButtons
                .padding(.top, Constants.buttonTopPadding)
        }
        .frame(width: Constants.viewWidth)
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.topPadding)
        .padding(.bottom, Constants.bottomPadding)
    }

    private var titleAndMessage: some View {
        VStack(spacing: Constants.titleAndMessageSpacing) {
            Text(UserText.winBackCampaignModalTitle)
                .font(.title3)
                .multilineTextAlignment(.center)
                .fixMultilineScrollableText()

            Text(UserText.winBackCampaignModalMessage)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixMultilineScrollableText()
        }
    }

    private var actionButtons: some View {
        HStack(spacing: Constants.betweenButtonsSpacing) {
                Button {
                    dismiss()
                } label: {
                    Text(UserText.winBackCampaignModalDismiss)
                        .frame(maxWidth: .infinity)
                        .frame(height: Constants.buttonHeight)
                }
                .frame(height: 28)
                .buttonStyle(StandardButtonStyle())

                 Button {
                    viewModel.confirmAction()
                    dismiss()
                } label: {
                    Text(UserText.winBackCampaignModalCTA)
                        .frame(maxWidth: .infinity)
                        .frame(height: Constants.buttonHeight)
                }
                .frame(height: 28)
                .buttonStyle(DefaultActionButtonStyle(enabled: true, shouldBeFixedVertical: false))
            }
            .frame(height: Constants.buttonHeight)
        }
}
