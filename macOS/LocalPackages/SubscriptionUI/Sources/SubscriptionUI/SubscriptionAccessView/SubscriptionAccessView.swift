//
//  SubscriptionAccessView.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public struct SubscriptionAccessView: View {

    private enum Constants {
        static let bodyWidth: CGFloat = 480
        static let verticalSpacing: CGFloat = 20
        static let horizontalOptionSpacing: CGFloat = 12
        static let contentPadding: CGFloat = 20
        static let cancelButtonVerticalPadding: CGFloat = 16
        static let titleImageSize = CGSize(width: 128, height: 96)
    }

    @Environment(\.presentationMode) private var presentationMode: Binding<PresentationMode>
    private let model: SubscriptionAccessViewModel

    private let dismissAction: (() -> Void)?

    public init(model: SubscriptionAccessViewModel, dismiss: (() -> Void)? = nil) {
        self.model = model
        self.dismissAction = dismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Constants.verticalSpacing) {
                Image("Privacy-Pro-128", bundle: .module)
                    .resizable()
                    .frame(width: Constants.titleImageSize.width, height: Constants.titleImageSize.height)

                Text(model.title)
                    .font(.title2)
                    .bold()
                    .foregroundColor(Color(.textPrimary))

                HStack(spacing: Constants.horizontalOptionSpacing) {
                    addViaEmailOption

                    if model.shouldShowRestorePurchase {
                        addViaAppleAccountOption
                    }
                }
            }
            .padding(Constants.contentPadding)

            Divider()

            footer
        }
        .frame(width: Constants.bodyWidth)
        .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    private var addViaEmailOption: some View {
        RoundedOptionView(title: model.emailLabel,
                          description: model.emailDescription,
                          imageName: "email-icon",
                          buttonTitle: model.emailButtonTitle,
                          buttonAction: {
            dismiss {
                model.handleEmailAction()
            }
        })
    }

    @ViewBuilder
    private var addViaAppleAccountOption: some View {
        RoundedOptionView(title: model.appleAccountLabel,
                          description: model.appleAccountDescription,
                          imageName: "apple-icon",
                          buttonTitle: model.appleAccountButtonTitle,
                          buttonAction: {
            dismiss {
                model.handleRestorePurchaseAction()
            }
        })
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()

            Button(UserText.cancelButtonTitle) {
                dismiss()
            }
            .buttonStyle(DismissActionButtonStyle())
        }
        .padding(.horizontal, Constants.contentPadding)
        .padding(.vertical, Constants.cancelButtonVerticalPadding)
    }

    private func dismiss(completion: (() -> Void)? = nil) {
        dismissAction?()
        presentationMode.wrappedValue.dismiss()

        if let completion = completion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                completion()
            }
        }
    }
}

private struct RoundedOptionView: View {

    private enum Constants {
        static let horizontalSpacing: CGFloat = 8
        static let verticalSpacing: CGFloat = 10

        static let titleTopOffset: CGFloat = -3
        static let buttonTopOffset: CGFloat = 6

        static let contentPadding: CGFloat = 20
    }

    let title: String
    let description: String
    let imageName: String
    let buttonTitle: String
    let buttonAction: () -> Void

    init(title: String,
         description: String,
         imageName: String,
         buttonTitle: String,
         buttonAction: @escaping () -> Void) {
        self.title = title
        self.description = description
        self.imageName = imageName
        self.buttonTitle = buttonTitle
        self.buttonAction = buttonAction
    }

    var body: some View {
        Group {
            HStack(alignment: .top, spacing: 0) {
                HStack(alignment: .top, spacing: Constants.horizontalSpacing) {
                    Image(imageName, bundle: .module)

                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: Constants.verticalSpacing) {
                            Text(title)
                                .font(.system(size: 14, weight: .regular, design: .default))

                            Text(description)
                                .font(.system(size: 13, weight: .regular, design: .default))
                                .foregroundColor(Color("TextSecondary", bundle: .module))
                                .fixMultilineScrollableText()

                            Button(buttonTitle) {
                                buttonAction()
                            }
                            .padding(.top, Constants.buttonTopOffset)
                        }
                        .padding(.top, Constants.titleTopOffset)

                        Spacer(minLength: 0)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(Constants.contentPadding)
        }
        .frame(maxWidth: .infinity)
        .roundedBorder()
    }
}
