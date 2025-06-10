//
//  SubscriptionEmailViewModel.swift
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
import UserScript
import Combine
import Core
import Subscription

final class SubscriptionEmailViewModel: ObservableObject {
    
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    let userScript: SubscriptionPagesUserScript
    let subFeature: any SubscriptionPagesUseSubscriptionFeature

    private var canGoBackCancellable: AnyCancellable?
    private var urlCancellable: AnyCancellable?

    var webViewModel: AsyncHeadlessWebViewViewModel


    enum SelectedFeature {
        case netP, dbp, itr, none
    }

    enum EmailViewFlow {
        case activationFlow, restoreFlow, manageEmailFlow
    }

    struct State {
        var currentFlow: EmailViewFlow = .activationFlow
        var subscriptionEmail: String?
        var transactionError: SubscriptionRestoreError?
        var shouldDisplaynavigationError: Bool = false
        var isPresentingInactiveError: Bool = false
        var canNavigateBack: Bool = false
        var shouldDismissView: Bool = false
        var subscriptionActive: Bool = false
        var backButtonTitle: String = UserText.backButtonTitle
        var selectedFeature: SelectedFeature = .none
        var shouldPopToSubscriptionSettings: Bool = false
        var shouldPopToAppSettings: Bool = false
        var viewTitle: String = ""
    }
    
    // Read only View State - Should only be modified from the VM
    @Published private(set) var state = State()

    enum SubscriptionRestoreError: Error {
        case subscriptionExpired,
             generalError
    }

    private var cancellables = Set<AnyCancellable>()

    private func isCurrentURL(matching subscriptionURL: SubscriptionURL) -> Bool {
        guard let currentURL = webViewModel.url else { return false }
        let checkedURL = subscriptionManager.url(for: subscriptionURL)
        return currentURL.forComparison() == checkedURL.forComparison()
    }

    init(isInternalUser: Bool = false,
         userScript: SubscriptionPagesUserScript,
         subFeature: any SubscriptionPagesUseSubscriptionFeature,
         subscriptionManager: any SubscriptionAuthV1toV2Bridge) {
        self.userScript = userScript
        self.subFeature = subFeature
        self.subscriptionManager = subscriptionManager
        let allowedDomains = AsyncHeadlessWebViewSettings.makeAllowedDomains(baseURL: subscriptionManager.url(for: .baseURL),
                                                                             isInternalUser: isInternalUser)

        self.webViewModel = AsyncHeadlessWebViewViewModel(userScript: userScript,
                                                          subFeature: subFeature,
                                                          settings: AsyncHeadlessWebViewSettings(bounces: false,
                                                                                                 allowedDomains: allowedDomains,
                                                                                                 contentBlocking: false))
    }

    func setEmailFlowMode(_ flow: EmailViewFlow) {
        state.currentFlow = flow
    }

    @MainActor
    func navigateBack() async {
        if state.canNavigateBack {
            await webViewModel.navigationCoordinator.goBack()
        } else {
            // If triggered from restoring subscription pop to main settings view
            if state.currentFlow == .restoreFlow {
                state.shouldPopToAppSettings = true
            } else {
                state.shouldDismissView = true
            }
        }
    }
    
    func resetDismissalState() {
        state.shouldDismissView = false
    }
    
    @MainActor
    func onFirstAppear() {
        setupWebObservers()
        setupFeatureObservers()
    }
    
    private func cleanUp() {
        canGoBackCancellable?.cancel()
        cancellables.removeAll()
    }
    
    func onAppear() {
        state.shouldDismissView = false

        let url: URL

        switch state.currentFlow {
        case .activationFlow, .restoreFlow:
            url = subscriptionManager.url(for: .activationFlow)
            state.viewTitle = ""
        case .manageEmailFlow:
            url = subscriptionManager.url(for: .manageEmail)
            state.viewTitle = UserText.subscriptionEditEmailTitle
        }

        // Load the URL unless the user has activated a subscription or is on the welcome page
        if !isCurrentURL(matching: .welcome) && !isCurrentURL(matching: .activationFlowSuccess){
            self.webViewModel.navigationCoordinator.navigateTo(url: url)
        }
    }
    
    private func setupFeatureObservers() {
        
        // Feature Callback
        subFeature.onSetSubscription = {
            DailyPixel.fireDailyAndCount(pixel: .privacyProRestorePurchaseEmailSuccess,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
            UniquePixel.fire(pixel: .privacyProSubscriptionActivated)
            DispatchQueue.main.async {
                self.state.subscriptionActive = true
            }
        }
        
        subFeature.onBackToSettings = {

            if self.state.currentFlow == .manageEmailFlow || self.state.currentFlow == .activationFlow {
                self.backToSubscriptionSettings()
            } else {
            // after adding email or restore we should go back to main settings
                self.backToAppSettings()
            }
        }
        
        subFeature.onFeatureSelected = { feature in
            DispatchQueue.main.async {
                switch feature {
                case .networkProtection:
                    UniquePixel.fire(pixel: .privacyProWelcomeVPN)
                    self.state.selectedFeature = .netP
                case .dataBrokerProtection:
                    UniquePixel.fire(pixel: .privacyProWelcomePersonalInformationRemoval)
                    self.state.selectedFeature = .dbp
                case .identityTheftRestoration, .identityTheftRestorationGlobal:
                    UniquePixel.fire(pixel: .privacyProWelcomeIdentityRestoration)
                    self.state.selectedFeature = .itr
                case .paidAIChat:
                    // Follow up: Implement paidAIChat selection
                    break
                case .unknown:
                    break
                }
            }
        }
          
        subFeature.transactionErrorPublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] value in
                guard let strongSelf = self else { return }
                if let value {
                    strongSelf.handleTransactionError(error: value)
                }
            }
        .store(in: &cancellables)
    }
        
    private func setupWebObservers() {
        
        // Webview navigation
        canGoBackCancellable = webViewModel.$canGoBack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.updateBackButton(canNavigateBack: value)
            }
        
        // Webview navigation
        urlCancellable = webViewModel.$url
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if self?.isCurrentURL(matching: .welcome) ?? false {
                    self?.state.viewTitle = UserText.subscriptionTitle
                }
            }
        
        webViewModel.$navigationError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let strongSelf = self else { return }
                DispatchQueue.main.async {
                    strongSelf.state.shouldDisplaynavigationError = error != nil ? true : false
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateBackButton(canNavigateBack: Bool) {
        // If the view is not Activation Success, or Welcome page, allow WebView Back Navigation
        if !isCurrentURL(matching: .welcome) && !isCurrentURL(matching: .activationFlowSuccess){
            self.state.canNavigateBack = canNavigateBack
            self.state.backButtonTitle = UserText.backButtonTitle
        } else {
            self.state.canNavigateBack = false
            self.state.backButtonTitle = UserText.settingsTitle
        }
    }
    
    // MARK: -
    
    private func handleTransactionError(error: UseSubscriptionError) {
        switch error {
        
        case .restoreFailedDueToExpiredSubscription:
            state.transactionError = .subscriptionExpired
        default:
            state.transactionError = .generalError
        }
        state.isPresentingInactiveError = true
    }
    
    func dismissView() {
        DispatchQueue.main.async {
            self.state.shouldDismissView = true
        }
    }
    
    func backToSubscriptionSettings() {
        DispatchQueue.main.async {
            self.state.shouldPopToSubscriptionSettings = true
        }
    }
    
    func backToAppSettings() {
        DispatchQueue.main.async {
            self.state.shouldPopToAppSettings = true
        }
    }
    
    deinit {
        cleanUp()
        canGoBackCancellable = nil
        
    }

}
