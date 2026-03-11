//
//  SubscriptionFlowView.swift
//  DuckDuckGo
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
import Foundation
import DesignResourcesKit
import Core
import DataBrokerProtection_iOS
import PrivacyConfig

struct SubscriptionFlowView: View {
        
    @Environment(\.dismiss) var dismiss
    @StateObject var viewModel: SubscriptionFlowViewModel
    
    @State private var isPurchaseInProgress = false
    @State private var isShowingITR = false
    @State private var isShowingDBP = false
    @State private var isShowingNetP = false
    @Binding var currentView: SubscriptionContainerView.CurrentViewType
    
    // Local View State
    @State private var errorMessageType: SubscriptionTransactionErrorAlert.MessageType = .general
    @State private var isPresentingError: Bool = false

    enum Constants {
        static let empty = ""
        static let navButtonPadding: CGFloat = 20.0
        static let backButtonImage = "chevron.left"
    }

    let featureFlagger: FeatureFlagger

    var body: some View {
        
        // Hidden Navigation Links for Onboarding sections
        NavigationLink(destination: LazyView(NetworkProtectionRootView().navigationViewStyle(.stack)),
                       isActive: $isShowingNetP,
                       label: { EmptyView() })
        
        NavigationLink(destination: LazyView(SubscriptionITPView(viewModel: SubscriptionITPViewModel(subscriptionManager: AppDependencyProvider.shared.subscriptionManager,
                                                                                                     userScriptsDependencies: viewModel.userScriptsDependencies,
                                                                                                     isInternalUser: AppDependencyProvider.shared.internalUserDecider.isInternalUser, featureFlagger: featureFlagger)).navigationViewStyle(.stack)),
                       isActive: $isShowingITR,
                       label: { EmptyView() })
        if viewModel.isPIREnabled, let vcProvider = viewModel.dataBrokerProtectionViewControllerProvider {
            NavigationLink(
                destination: LazyView(DataBrokerProtectionViewControllerRepresentation(dbpViewControllerProvider: vcProvider)
                    .edgesIgnoringSafeArea(.bottom)
                    .navigationViewStyle(.stack)),
                isActive: $isShowingDBP,
                label: { EmptyView() }
            )
        } else {
            NavigationLink(destination: LazyView(SubscriptionPIRMoveToDesktopView().navigationViewStyle(.stack)),
                           isActive: $isShowingDBP,
                           label: { EmptyView() })
        }

        baseView
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    backButton
                }
                ToolbarItem(placement: .principal) {
                    if viewModel.flowType.showsDaxLogo && viewModel.state.viewTitle == viewModel.flowType.navigationTitle {
                        DaxLogoNavbarTitle()
                    } else {
                        Text(viewModel.state.viewTitle).bold()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(viewModel.state.canNavigateBack || viewModel.subFeature.transactionStatus != .idle)
            .interactiveDismissDisabled(viewModel.subFeature.transactionStatus != .idle)
            .edgesIgnoringSafeArea(.bottom)
            .tint(Color(designSystemColor: .textPrimary))
    }
    
    @ViewBuilder
    private var backButton: some View {
        if viewModel.state.canNavigateBack {
            Button(action: {
                Task { await viewModel.navigateBack() }
            }, label: {
                HStack(spacing: 0) {
                    Image(systemName: Constants.backButtonImage)
                    Text(UserText.backButtonTitle)
                }
                
            })
        }
    }
    
    private func getTransactionStatus() -> String {
        switch viewModel.state.transactionStatus {
        case .polling:
            return UserText.subscriptionCompletingPurchaseTitle
        case .purchasing:
            return UserText.subscriptionPurchasingTitle
        case .restoring:
            return UserText.subscriptionRestoringTitle
        case .changingPlan:
            return UserText.subscriptionPlanChangeInProgressTitle
        case .planChangePolling:
            return UserText.subscriptionCompletePlanChangeTitle
        case .idle:
            return ""
        }
    }

    @ViewBuilder
    private var baseView: some View {
        ZStack(alignment: .top) {
            webView
        }
        
        .onChange(of: viewModel.state.selectedFeature) { feature in
            switch feature {
            case .dbp:
                self.isShowingDBP = true
            case .itr:
                self.isShowingITR = true
            case .netP:
                self.isShowingNetP = true
            default:
                break
            }
        }
        
        .onChange(of: viewModel.state.shouldActivateSubscription) { result in
            if result {
                withAnimation {
                    currentView = .restore
                }
            }
        }
        
        .onChange(of: viewModel.state.transactionError) { value in
            if !isPresentingError, let messageType = SubscriptionTransactionErrorAlert.displayContent(for: value) {
                errorMessageType = messageType
                isPresentingError = true
            }
        }
        
        .onChange(of: viewModel.state.shouldGoBackToSettings) { _ in
            dismiss()
        }
        
        .onFirstAppear {
            setUpAppearances()
            Task { await viewModel.onFirstAppear() }
        }
                
        .onAppear {
            viewModel.onAppear()
        }
                
        .alert(isPresented: $isPresentingError) {
            SubscriptionTransactionErrorAlert.alert(
                for: errorMessageType,
                onDismiss: {
                    viewModel.clearTransactionError()
                    dismiss()
                },
                onRestore: { viewModel.restoreAppstoreTransaction() }
            )
        }
    }

    @ViewBuilder
    private var webView: some View {
        ZStack(alignment: .top) {
            AsyncHeadlessWebView(viewModel: viewModel.webViewModel)
                .background()
            
            if viewModel.state.transactionStatus != .idle {
                PurchaseInProgressView(status: getTransactionStatus())
            }
        }
    }

    private func setUpAppearances() {
        let navAppearance = UINavigationBar.appearance()
        navAppearance.backgroundColor = UIColor(designSystemColor: .background)
        navAppearance.barTintColor = UIColor(designSystemColor: .controlsFillPrimary)
        navAppearance.shadowImage = UIImage()
        navAppearance.tintColor = UIColor(designSystemColor: .textPrimary)
    }

}

// Commented out because CI fails if a SwiftUI preview is enabled https://app.asana.com/0/414709148257752/1206774081310425/f
// struct SubscriptionFlowView_Previews: PreviewProvider {
//    static var previews: some View {
//        SubscriptionFlowView()
//    }
// }
