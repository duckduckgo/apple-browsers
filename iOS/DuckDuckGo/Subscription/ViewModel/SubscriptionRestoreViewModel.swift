//
//  SubscriptionRestoreViewModel.swift
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
import BrowserServicesKit

final class SubscriptionRestoreViewModel: ObservableObject {
    
    let userScript: SubscriptionPagesUserScript
    let subFeature: any SubscriptionPagesUseSubscriptionFeature

    private var cancellables = Set<AnyCancellable>()
    
    enum SubscriptionActivationResult {
        case unknown, activated, expired, notFound, error
    }
    
    struct State {
        var transactionStatus: SubscriptionTransactionStatus = .idle
        var activationResult: SubscriptionActivationResult = .unknown
        var subscriptionEmail: String?
        var isShowingWelcomePage = false
        var isShowingActivationFlow = false
        var shouldShowPlans = false
        var shouldDismissView = false
        var isLoading = false
        var viewTitle: String = UserText.subscriptionActivateViewTitle
    }
    
    // Publish the currently selected feature    
    @Published var selectedFeature: SettingsViewModel.SettingsDeepLinkSection?
    
    // Read only View State - Should only be modified from the VM
    @Published private(set) var state = State()

    private let featureFlagger: FeatureFlagger

    init(userScript: SubscriptionPagesUserScript,
         subFeature: any SubscriptionPagesUseSubscriptionFeature,
         isAddingDevice: Bool = false,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.userScript = userScript
        self.subFeature = subFeature
        self.featureFlagger = featureFlagger
    }
    
    func onAppear() {
        DispatchQueue.main.async {
            self.resetState()
        }
    }
    
    func onFirstAppear() async {
        await setupTransactionObserver()
    }
    
    private func cleanUp() {
        cancellables.removeAll()
    }

    @MainActor
    private func resetState() {
        state.isShowingActivationFlow = false
        state.shouldShowPlans = false
        state.isShowingWelcomePage = false
        state.shouldDismissView = false
    }
    
    private func setupTransactionObserver() async {
        
        subFeature.transactionStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let strongSelf = self else { return }
                Task {
                    await strongSelf.setTransactionStatus(status)
                }
            }
            .store(in: &cancellables)
        
    }
    
    @MainActor
    private func handleRestoreError(error: UseSubscriptionError) {
        switch error {
        case .restoreFailedDueToExpiredSubscription:
            state.activationResult = .expired
        case .restoreFailedDueToNoSubscription:
            state.activationResult = .notFound
        case .otherRestoreError:
            state.activationResult = .error
        default:
            state.activationResult = .error
        }

        switch state.activationResult {
        case .expired,
             .notFound:
            DailyPixel.fireDailyAndCount(pixel: .privacyProRestorePurchaseStoreFailureNotFound,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
        case .error:
            DailyPixel.fireDailyAndCount(pixel: .privacyProRestorePurchaseStoreFailureOther,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
        default:
            break
        }
    }
    
    @MainActor
    private func setTransactionStatus(_ status: SubscriptionTransactionStatus) {
        self.state.transactionStatus = status
    }
    
    @MainActor
    func restoreAppstoreTransaction() {
        DailyPixel.fireDailyAndCount(pixel: .privacyProRestorePurchaseStoreStart,
                                     pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
        Task {
            state.transactionStatus = .restoring
            state.activationResult = .unknown
            do {
                try await subFeature.restoreAccountFromAppStorePurchase()
                DailyPixel.fireDailyAndCount(pixel: .privacyProRestorePurchaseStoreSuccess,
                                             pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
                state.activationResult = .activated
                state.transactionStatus = .idle
            } catch let error {
                if let specificError = error as? UseSubscriptionError {
                    handleRestoreError(error: specificError)
                }
                state.transactionStatus = .idle
            }
        }
    }
    
    @MainActor
    func showActivationFlow(_ visible: Bool) {
        if visible != state.shouldDismissView {
            self.state.isShowingActivationFlow = visible
        }
    }
    
    @MainActor
    func showPlans() {
        state.shouldShowPlans = true
    }
    
    @MainActor
    func dismissView() {
        state.shouldDismissView = true
    }
    
    deinit {
        cleanUp()
    }
    
    
}
