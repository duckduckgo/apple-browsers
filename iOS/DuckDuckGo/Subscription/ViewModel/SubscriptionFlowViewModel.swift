//
//  SubscriptionFlowViewModel.swift
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

import Foundation
import UserScript
import Combine
import Core
import Subscription
import BrowserServicesKit
import DataBrokerProtection_iOS
import PixelKit

final class SubscriptionFlowViewModel: ObservableObject {
    
    let userScript: SubscriptionPagesUserScript
    let userScriptsDependencies: DefaultScriptSourceProvider.Dependencies
    let subFeature: any SubscriptionPagesUseSubscriptionFeature
    var webViewModel: AsyncHeadlessWebViewViewModel
    let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    weak var dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?
    let purchaseURL: URL

    private let urlOpener: URLOpener
    private let featureFlagger: FeatureFlagger
    private let wideEvent: WideEventManaging
    private var cancellables = Set<AnyCancellable>()
    private var canGoBackCancellable: AnyCancellable?
    private var urlCancellable: AnyCancellable?
    private var transactionStatusTimer: Timer?
    
    enum Constants {
        static let navigationBarHideThreshold = 80.0
    }
    
    enum SelectedFeature {
        case netP, dbp, itr, none
    }
        
    struct State {
        var hasActiveSubscription = false
        var transactionStatus: SubscriptionTransactionStatus = .idle
        var userTappedRestoreButton = false
        var shouldActivateSubscription = false
        var canNavigateBack: Bool = false
        var transactionError: SubscriptionPurchaseError?
        var shouldHideBackButton = false
        var selectedFeature: SelectedFeature = .none
        var viewTitle: String = UserText.subscriptionTitle
        var shouldGoBackToSettings: Bool = false
    }
    
    // Read only View State - Should only be modified from the VM
    @Published private(set) var state = State()

    var isPIREnabled: Bool {
        featureFlagger.isFeatureOn(.personalInformationRemoval)
    }

    private let webViewSettings: AsyncHeadlessWebViewSettings

    init(purchaseURL: URL,
         isInternalUser: Bool = false,
         userScript: SubscriptionPagesUserScript,
         userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
         subFeature: any SubscriptionPagesUseSubscriptionFeature,
         subscriptionManager: SubscriptionAuthV1toV2Bridge,
         selectedFeature: SettingsViewModel.SettingsDeepLinkSection? = nil,
         urlOpener: URLOpener = UIApplication.shared,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         wideEvent: WideEventManaging = AppDependencyProvider.shared.wideEvent,
         dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?) {
        self.purchaseURL = purchaseURL
        self.userScript = userScript
        self.userScriptsDependencies = userScriptsDependencies
        self.subFeature = subFeature
        self.subscriptionManager = subscriptionManager
        self.urlOpener = urlOpener
        self.featureFlagger = featureFlagger
        self.wideEvent = wideEvent
        self.dataBrokerProtectionViewControllerProvider = dataBrokerProtectionViewControllerProvider
        let allowedDomains = AsyncHeadlessWebViewSettings.makeAllowedDomains(baseURL: subscriptionManager.url(for: .baseURL),
                                                                             isInternalUser: isInternalUser)

        self.webViewSettings = AsyncHeadlessWebViewSettings(bounces: false,
                                                            allowedDomains: allowedDomains,
                                                            userScriptsDependencies: nil)


        self.webViewModel = AsyncHeadlessWebViewViewModel(userScript: userScript,
                                                          subFeature: subFeature,
                                                          settings: webViewSettings)
    }

    // Observe transaction status
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
        
        
        subFeature.onBackToSettings = {
            DispatchQueue.main.async {
                self.state.shouldGoBackToSettings = true
            }
        }
        
        subFeature.onActivateSubscription = {
            DispatchQueue.main.async {
                self.state.shouldActivateSubscription = true
                self.setTransactionStatus(.idle)
            }
        }
        
         subFeature.onFeatureSelected = { feature in
             DispatchQueue.main.async {
                 switch feature {
                 case .networkProtection:
                     UniquePixel.fire(pixel: .subscriptionWelcomeVPN)
                     self.state.selectedFeature = .netP
                 case .dataBrokerProtection:
                     UniquePixel.fire(pixel: .subscriptionWelcomePersonalInformationRemoval)
                     self.state.selectedFeature = .dbp
                 case .identityTheftRestoration, .identityTheftRestorationGlobal:
                     UniquePixel.fire(pixel: .subscriptionWelcomeIdentityRestoration)
                     self.state.selectedFeature = .itr
                 case .paidAIChat:
                     UniquePixel.fire(pixel: .subscriptionWelcomeAIChat)
                     self.urlOpener.open(AppDeepLinkSchemes.openAIChat.url)
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
                Task { await strongSelf.setTransactionStatus(.idle) }
                if let value {
                    Task { await strongSelf.handleTransactionError(error: value) }
                }
            }
        .store(in: &cancellables)
       
    }

    @MainActor
    private func handleTransactionError(error: UseSubscriptionError) {
        // Reset the transaction Status
        self.setTransactionStatus(.idle)
        
        switch error {
        case .purchaseFailed:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionPurchaseFailureStoreError,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
            state.transactionError = .purchaseFailed
        case .missingEntitlements:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionPurchaseFailureBackendError,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
            state.transactionError = .missingEntitlements
        case .failedToGetSubscriptionOptions:
            state.transactionError = .failedToGetSubscriptionOptions
        case .failedToSetSubscription:
            state.transactionError = .failedToSetSubscription
        case .cancelledByUser:
            state.transactionError = .cancelledByUser
        case .accountCreationFailed:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionPurchaseFailureAccountNotCreated,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
            state.transactionError = .generalError
        case .activeSubscriptionAlreadyPresent:
            state.transactionError = .hasActiveSubscription
        case .restoreFailedDueToNoSubscription:
            // Pixel handled in SubscriptionRestoreViewModel.handleRestoreError(error:)
            state.transactionError = .generalError
        case .restoreFailedDueToExpiredSubscription:
            // Pixel handled in SubscriptionRestoreViewModel.handleRestoreError(error:)
            state.transactionError = .subscriptionExpired
        case .otherRestoreError:
            // Pixel handled in SubscriptionRestoreViewModel.handleRestoreError(error:)
            state.transactionError = .failedToRestorePastPurchase
        case .generalError:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionPurchaseFailureOther,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
            state.transactionError = .generalError
        }
    }
    
    private func setupWebViewObservers() async {
        webViewModel.$navigationError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let strongSelf = self else { return }
                DispatchQueue.main.async {
                    strongSelf.state.transactionError = error != nil ? .generalError : nil
                    strongSelf.setTransactionStatus(.idle)
                }
                
            }
            .store(in: &cancellables)
        
        canGoBackCancellable = webViewModel.$canGoBack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let strongSelf = self else { return }
                strongSelf.state.canNavigateBack = false
                guard let currentURL = self?.webViewModel.url else { return }
                if strongSelf.shouldAllowWebViewBackNavigationForURL(currentURL: currentURL) {
                    DispatchQueue.main.async {
                        strongSelf.state.canNavigateBack = value
                    }
                }
            }
        
        urlCancellable = webViewModel.$url
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let strongSelf = self else { return }
                strongSelf.state.canNavigateBack = false
                Task { await strongSelf.setTransactionStatus(.idle) }

                if strongSelf.isCurrentURLMatchingPostPurchaseAddEmailFlow() {
                    strongSelf.state.viewTitle = UserText.subscriptionRestoreAddEmailTitle
                } else {
                    strongSelf.state.viewTitle = UserText.subscriptionTitle
                }
            }
    }

    private func shouldAllowWebViewBackNavigationForURL(currentURL: URL) -> Bool {
        return !currentURL.shouldPreventBackNavigation &&
        !isCurrentURL(matching: .purchase) &&
        !isCurrentURL(matching: .welcome) &&
        !isCurrentURL(matching: .activationFlowSuccess) &&
        !isCurrentURL(matching: subscriptionManager.url(for: .baseURL).appendingPathComponent("add-email/success"))
    }

    private func isCurrentURLMatchingPostPurchaseAddEmailFlow() -> Bool {
        // Not defined in SubscriptionURL as this flow is only triggered by FE as a part of post purchase flow. Only need for comparison.
        let baseURL = subscriptionManager.url(for: .baseURL)
        let addEmailURL = baseURL.appendingPathComponent("add-email")
        let addEmailSuccessURL = baseURL.appendingPathComponent("add-email/success")

        return isCurrentURL(matching: addEmailURL) || isCurrentURL(matching: addEmailSuccessURL)
    }

    private func isCurrentURL(matching subscriptionURL: SubscriptionURL) -> Bool {
        let urlToCheck = subscriptionManager.url(for: subscriptionURL)
        return isCurrentURL(matching: urlToCheck)
    }

    private func isCurrentURL(matching url: URL) -> Bool {
        guard let currentURL = webViewModel.url else { return false }
        return currentURL.forComparison() == url.forComparison()
    }

    private func cleanUp() {
        transactionStatusTimer?.invalidate()
        canGoBackCancellable?.cancel()
        urlCancellable?.cancel()
        cancellables.removeAll()
    }

    @MainActor
    func resetState() {
        self.setTransactionStatus(.idle)
        self.state = State()
    }
    
    deinit {
        cleanUp()
        transactionStatusTimer = nil
        canGoBackCancellable = nil
        urlCancellable = nil
    }
    
    @MainActor
    private func setTransactionStatus(_ status: SubscriptionTransactionStatus) {
        self.state.transactionStatus = status
        
        // Invalidate existing timer if any
        transactionStatusTimer?.invalidate()
        
        if status != .idle {
            // Schedule a new timer
            transactionStatusTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                guard let strongSelf = self else { return }
                strongSelf.transactionStatusTimer?.invalidate()
                strongSelf.transactionStatusTimer = nil
            }
        }
    }
        
    @MainActor
    private func backButtonEnabled(_ enabled: Bool) {
        state.canNavigateBack = enabled
    }

    // MARK: -
    
    func onAppear() {
        self.state.selectedFeature = .none
        self.state.shouldGoBackToSettings = false
    }
    
    func onFirstAppear() async {
        DispatchQueue.main.async {
            self.resetState()
        }
        if webViewModel.url != subscriptionManager.url(for: .purchase).forComparison() {
             self.webViewModel.navigationCoordinator.navigateTo(url: purchaseURL)
        }
        await self.setupTransactionObserver()
        await self.setupWebViewObservers()
        Pixel.fire(pixel: .subscriptionOfferScreenImpression)
    }

    @MainActor
    func restoreAppstoreTransaction() {
        let isSubscriptionRestoreWidePixelMeasurementEnabled = featureFlagger.isFeatureOn(.subscriptionRestoreWidePixelMeasurement)
        let data = SubscriptionRestoreWideEventData(
            restorePlatform: .purchaseBackgroundTask,
            contextData: WideEventContextData(name: SubscriptionRestoreFunnelOrigin.prePurchaseCheck.rawValue)
        )
        
        clearTransactionError()
        
        Task {
            if isSubscriptionRestoreWidePixelMeasurementEnabled {
                data.appleAccountRestoreDuration = WideEvent.MeasuredInterval.startingNow()
                wideEvent.startFlow(data)
            }
            
            do {
                try await subFeature.restoreAccountFromAppStorePurchase()
                
                if isSubscriptionRestoreWidePixelMeasurementEnabled {
                    data.appleAccountRestoreDuration?.complete()
                    wideEvent.completeFlow(data, status: .success, onComplete: { _, _ in })
                }
                
                backButtonEnabled(false)
                await webViewModel.navigationCoordinator.reload()
                backButtonEnabled(true)
            } catch let error {
                if let specificError = error as? UseSubscriptionError {
                    data.errorData = .init(error: specificError)
                    handleTransactionError(error: specificError)
                } else {
                    data.errorData = .init(error: error)
                }
                
                if isSubscriptionRestoreWidePixelMeasurementEnabled {
                    data.appleAccountRestoreDuration?.complete()
                    wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
                }
            }
        }
    }
    
    @MainActor
    func navigateBack() async {
        await webViewModel.navigationCoordinator.goBack()
    }
    
    @MainActor
    func clearTransactionError() {
        state.transactionError = nil
    }
    
}
