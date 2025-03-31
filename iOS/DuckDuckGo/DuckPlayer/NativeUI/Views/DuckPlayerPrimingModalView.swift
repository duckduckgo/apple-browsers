//
//  DuckPlayerPrimingModalView.swift
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

import DuckUI
import SwiftUI

struct DuckPlayerPrimingModalView: View {
    @ObservedObject var viewModel: DuckPlayerPrimingModalViewModel
    @Environment(\.colorScheme) var colorScheme

    @State private var isAnimating: Bool = true

    private enum Constants {
        static let cornerRadius: CGFloat = 12
        static let spacing: CGFloat = 16
        static let buttonHeight: CGFloat = 50
        static let closeButtonSize: CGFloat = 14
        static let maxWidth: CGFloat = 500
        static let imageWidth: CGFloat = 40
        static let imageHeight: CGFloat = 200
        static let contentHorizontalPadding: CGFloat = 32
        static let headerPadding: CGFloat = 16
        static let primingImageName: String = "DuckPlayer-PrimingAnimation"
        static let closeButtonImageName: String = "xmark"
    }

    var body: some View {
        VStack(spacing: Constants.spacing) {
            headerView

            VStack(spacing: Constants.spacing) {
                LottieView(
                    lottieFile: Constants.primingImageName,
                    loopMode: .mode(.loop),
                    isAnimating: $isAnimating
                )
                .frame(width: Constants.imageWidth, height: Constants.imageHeight)
                .aspectRatio(contentMode: .fit)

                Text(UserText.duckPlayerNativeModalTitle)
                    .daxTitle3()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                Text(UserText.duckPlayerNativeModalDescription)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Button(
                    action: { viewModel.tryDuckPlayer() },
                    label: {
                        Text(UserText.duckPlayerNativeModalCTA).daxButton()
                            .frame(maxWidth: .infinity)
                            .frame(height: Constants.buttonHeight)
                            .foregroundColor(Color(designSystemColor: .buttonsPrimaryText))
                            .background(Color(designSystemColor: .buttonsPrimaryDefault))
                            .cornerRadius(Constants.cornerRadius)

                    })
            }
            .padding(.horizontal, Constants.contentHorizontalPadding)
            Spacer()
        }
        .background(Color(designSystemColor: .backgroundSheets))
    }

    private var headerView: some View {
        HStack {
            Spacer()
            Button(
                action: { viewModel.dismiss() },
                label: {
                    Image(systemName: Constants.closeButtonImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: Constants.closeButtonSize, height: Constants.closeButtonSize)
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                }
            )
        }
        .padding(.horizontal, Constants.headerPadding)
        .padding(.top, Constants.headerPadding)
    }
}
