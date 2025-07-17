//
//  SubscriptionRestoreView.swift
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

import Foundation
import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons
import Core

struct SubscriptionRestoreView: View {

    @Environment(\.dismiss) var dismiss
    
    @EnvironmentObject var subscriptionNavigationCoordinator: SubscriptionNavigationCoordinator
    @StateObject var viewModel: SubscriptionRestoreViewModel
    @StateObject var emailViewModel: SubscriptionEmailViewModel
    
    @State private var isAlertVisible = false
    @State private var isShowingWelcomePage = false
    @State private var isShowingActivationFlow = false
    @Binding var currentView: SubscriptionContainerView.CurrentViewType
    
    private enum Constants {
        static let heroImage = "Privacy-Pro-Add-Device-128"

        static let viewPadding = EdgeInsets(top: 10, leading: 30, bottom: 0, trailing: 30)
        static let sectionSpacing: CGFloat = 16
        static let maxWidth: CGFloat = 768
        static let boxMaxWidth: CGFloat = 500
        static let headerItemSpacing = 24.0
        static let headerBottomSpacing = 16.0
    }
    
    var body: some View {
        ZStack {
            baseView

            if viewModel.state.transactionStatus != .idle {
                PurchaseInProgressView(status: getTransactionStatus())
            }
        }
    }
    
    private var contentView: some View {
        Group {
            ScrollView {
                VStack(spacing: Constants.sectionSpacing) {
                    headerView
                    addViaEmailView
                    addViaAppleIDView

                    Spacer()
                    
                    // Hidden link to display Email Activation View
                    NavigationLink(destination: SubscriptionEmailView(viewModel: emailViewModel).environmentObject(subscriptionNavigationCoordinator),
                                   isActive: $isShowingActivationFlow) {
                          EmptyView()
                    }.isDetailLink(false)
                    
                }.frame(maxWidth: Constants.boxMaxWidth)
            }
            .frame(maxWidth: Constants.maxWidth, alignment: .center)
            .padding(Constants.viewPadding)
            .background(Color(designSystemColor: .background))
            .tint(Color(designSystemColor: .icons))
            
            .navigationTitle(viewModel.state.viewTitle)
            .navigationBarBackButtonHidden(viewModel.state.transactionStatus != .idle)
            .navigationBarTitleDisplayMode(.inline)
            .applyInsetGroupedListStyle()
            .interactiveDismissDisabled(viewModel.subFeature.transactionStatus != .idle)
            .tint(Color.init(designSystemColor: .textPrimary))
            .accentColor(Color.init(designSystemColor: .textPrimary))
        }
    }
    
    @ViewBuilder
    private var baseView: some View {
       
        contentView
            .alert(isPresented: $isAlertVisible) { getAlert() }
            
            .onChange(of: viewModel.state.activationResult) { result in
                if result != .unknown {
                    isAlertVisible = true
                }
            }
            
            // Navigation Flow Binding
            .onChange(of: viewModel.state.isShowingActivationFlow) { result in
                isShowingActivationFlow = result
            }
            .onChange(of: isShowingActivationFlow) { result in
                viewModel.showActivationFlow(result)
            }
            
            .onChange(of: viewModel.state.shouldDismissView) { result in
                if result {
                    dismiss()
                }
            }
            
            .onChange(of: viewModel.state.shouldShowPlans) { result in
                if result {
                    currentView = .subscribe
                }
            }
        
            .onFirstAppear {
                Task { await viewModel.onFirstAppear() }
                setUpAppearances()
            }
        
            .onAppear {
                viewModel.onAppear()
            }
    }

    // MARK: -

    private var addViaEmailView: some View {
        RoundedCardView(title: UserText.subscriptionActivateViaEmailTitle,
                        description: UserText.subscriptionActivateViaEmailDescription,
                        image: Image(uiImage: DesignSystemImages.Glyphs.Size16.email),
                        buttonTitle: UserText.subscriptionActivateViaEmailButton,
                        buttonAction: {
            DailyPixel.fireDailyAndCount(pixel: .privacyProRestorePurchaseEmailStart,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
            viewModel.showActivationFlow(true)
        })
    }

    private var addViaAppleIDView: some View {
        RoundedCardView(title: UserText.subscriptionActivateViaAppleAccountTitle,
                        description: UserText.subscriptionActivateViaAppleAccountDescription,
                        image: Image(uiImage: DesignSystemImages.Glyphs.Size16.platformApple),
                        buttonTitle: UserText.subscriptionActivateViaAppleAccountButton,
                        buttonAction: {
            viewModel.restoreAppstoreTransaction()
        })
    }

    private func getTransactionStatus() -> String {
        switch viewModel.state.transactionStatus {
        case .polling:
            return UserText.subscriptionCompletingPurchaseTitle
        case .purchasing:
            return UserText.subscriptionPurchasingTitle
        case .restoring:
            return UserText.subscriptionRestoringTitle
        case .idle:
            return ""
        }
    }
    
    private var headerView: some View {
        VStack(spacing: Constants.headerItemSpacing) {
            Image(Constants.heroImage)
            Text(UserText.subscriptionActivateHeaderTitle)
                .daxTitle1()
                .multilineTextAlignment(.center)
                .foregroundColor(Color(designSystemColor: .textPrimary))
        }
        .padding(.bottom, Constants.headerBottomSpacing)
    }

    private func getAlert() -> Alert {
        switch viewModel.state.activationResult {
        case .activated:
            return Alert(title: Text(UserText.subscriptionRestoreSuccessfulTitle),
                         message: Text(UserText.subscriptionRestoreSuccessfulMessage),
                         dismissButton: .default(Text(UserText.subscriptionRestoreSuccessfulButton)) {
                            viewModel.dismissView()
                         }
            )
        case .notFound:
            return Alert(title: Text(UserText.subscriptionRestoreNotFoundTitle),
                         message: Text(UserText.subscriptionRestoreNotFoundMessage),
                         primaryButton: .default(Text(UserText.subscriptionRestoreNotFoundPlans),
                                                 action: { viewModel.showPlans() }),
                         secondaryButton: .cancel())
            
        case .expired:
            return Alert(title: Text(UserText.subscriptionRestoreNotFoundTitle),
                         message: Text(UserText.subscriptionRestoreNotFoundMessage),
                         primaryButton: .default(Text(UserText.subscriptionRestoreNotFoundPlans),
                                                 action: { viewModel.showPlans() }),
                         secondaryButton: .cancel())
        default:
            return Alert(
                title: Text(UserText.subscriptionBackendErrorTitle),
                message: Text(UserText.subscriptionBackendErrorMessage),
                dismissButton: .cancel(Text(UserText.subscriptionBackendErrorButton)) {
                    viewModel.dismissView()
                }
            )
        }
    }
    
    private func setUpAppearances() {
        let navAppearance = UINavigationBar.appearance()
        navAppearance.backgroundColor = UIColor(designSystemColor: .background)
        navAppearance.barTintColor = UIColor(designSystemColor: .surface)
        navAppearance.shadowImage = UIImage()
        navAppearance.tintColor = UIColor(designSystemColor: .textPrimary)
    }
}

private struct RoundedCardView: View {

    private enum Constants {
        static let cornerRadius = 12.0
        static let cardPadding = EdgeInsets(top: 16,
                                            leading: 16,
                                            bottom: 16,
                                            trailing: 16)
        static let cardHorizontalItemSpacing: CGFloat = 16
        static let cardVerticalItemSpacing: CGFloat = 8
        static let imageWidth: CGFloat = 32
        static let imageHeight: CGFloat = 32
        static let titleTopOffset: CGFloat = 4

        static let separatorPadding: EdgeInsets = .init(top: 8, leading: 0, bottom: 8, trailing: -Constants.cardPadding.trailing)
    }

    let title: String
    let description: String
    let image: Image
    let buttonTitle: String
    let buttonAction: () -> Void

    init(title: String,
         description: String,
         image: Image,
         buttonTitle: String,
         buttonAction: @escaping () -> Void) {
        self.title = title
        self.description = description
        self.image = image
        self.buttonTitle = buttonTitle
        self.buttonAction = buttonAction
    }

    var body: some View {
        HStack(alignment: .top, spacing: Constants.cardHorizontalItemSpacing) {
            image
                .frame(width: Constants.imageWidth, height: Constants.imageHeight)
                .background(Color(designSystemColor: .lines))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: Constants.cardVerticalItemSpacing) {
                Text(title)
                    .daxHeadline()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .padding(.top, Constants.titleTopOffset)
                Text(description)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))

                Rectangle()
                    .fill(Color(designSystemColor: .lines))
                    .frame(height: 1)
                    .padding(Constants.separatorPadding)

                Button(action: {
                    self.buttonAction()
                }, label: {
                    Text(buttonTitle)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .accent))
                })
            }
        }
        .padding(Constants.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(designSystemColor: .surface))
        .cornerRadius(Constants.cornerRadius)
    }
}
