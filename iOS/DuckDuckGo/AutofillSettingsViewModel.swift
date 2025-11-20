//
//  AutofillSettingsViewModel.swift
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

import Foundation
import Core
import PrivacyDashboard
import SwiftUI
import BrowserServicesKit
import DesignResourcesKit
import DesignResourcesKitIcons
import Combine
import DDGSync
import AuthenticationServices

protocol AutofillSettingsViewModelDelegate: AnyObject {
    func navigateToPasswords(viewModel: AutofillSettingsViewModel)
    func navigateToCreditCards(viewModel: AutofillSettingsViewModel)
    func navigateToFileImport(viewModel: AutofillSettingsViewModel)
    func navigateToImportViaSync(viewModel: AutofillSettingsViewModel)
    func navigateToExtensionManagement(viewModel: AutofillSettingsViewModel)
}

final class AutofillSettingsViewModel: ObservableObject {

    weak var delegate: AutofillSettingsViewModelDelegate?

    var secureVault: (any AutofillSecureVault)?
    private let autofillNeverPromptWebsitesManager: AutofillNeverPromptWebsitesManager
    private let appSettings: AppSettings
    private let keyValueStore: KeyValueStoringDictionaryRepresentable
    private let source: AutofillSettingsSource
    private let featureFlagger: FeatureFlagger
    private var syncCancellables = Set<AnyCancellable>()
    private var extensionEnableCoordinator: Any?

    private enum Constants {
        static let enableRetryThrottleDuration: TimeInterval = 10
    }

    enum AutofillType {
        case passwords
        case creditCards

        var icon: Image {
            switch self {
            case .passwords:
                return Image(uiImage: DesignSystemImages.Glyphs.Size24.key)
            case .creditCards:
                return Image(uiImage: DesignSystemImages.Glyphs.Size24.creditCard)
            }
        }

        var title: String {
            switch self {
            case .passwords:
                return UserText.autofillLoginListTitle
            case .creditCards:
                return UserText.autofillCreditCardListTitle
            }
        }
    }

    @Published var passwordsCount: Int?
    @Published var savePasswordsEnabled: Bool {
        didSet {
            appSettings.autofillCredentialsEnabled = savePasswordsEnabled
            keyValueStore.set(false, forKey: UserDefaultsWrapper<Bool>.Key.autofillFirstTimeUser.rawValue)
            NotificationCenter.default.post(name: AppUserDefaults.Notifications.autofillEnabledChange, object: self)
            
            if savePasswordsEnabled {
                Pixel.fire(pixel: .autofillLoginsSettingsEnabled)
            } else {
                Pixel.fire(pixel: .autofillLoginsSettingsDisabled, withAdditionalParameters: ["source": source.rawValue])
            }
        }
    }
    @Published var showingResetConfirmation = false
    @Published var showCreditCards = false
    @Published var creditCardsCount: Int?
    @Published var isShowingActivationView: Bool = false
    var saveCreditCardsEnabled: Binding<Bool> {
        Binding(
            get: { self.showCreditCards ? self.appSettings.autofillCreditCardsEnabled : false },
            set: { [weak self] newValue in
                guard let self = self, self.showCreditCards else { return }
                
                self.appSettings.autofillCreditCardsEnabled = newValue
                self.keyValueStore.set(false, forKey: UserDefaultsWrapper<Bool>.Key.autofillCreditCardsFirstTimeUser.rawValue)
                NotificationCenter.default.post(name: AppUserDefaults.Notifications.autofillEnabledChange, object: self)

                if newValue {
                    Pixel.fire(pixel: .autofillCardsSettingsEnabled)
                } else {
                    Pixel.fire(pixel: .autofillCardsSettingsDisabled, withAdditionalParameters: ["source": source.rawValue])
                }
            }
        )
    }
    @Published var showExtensionSettings = false
    @Published var isExtensionEnabled: Bool = false
    @Published var isEnableRequestThrottled: Bool = false

    init(appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         keyValueStore: KeyValueStoringDictionaryRepresentable = UserDefaults.standard,
         autofillNeverPromptWebsitesManager: AutofillNeverPromptWebsitesManager = AppDependencyProvider.shared.autofillNeverPromptWebsitesManager,
         secureVault: (any AutofillSecureVault)? = nil,
         source: AutofillSettingsSource,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         syncService: DDGSyncing,
         syncDataProviders: SyncDataProviders) {
        self.autofillNeverPromptWebsitesManager = autofillNeverPromptWebsitesManager
        self.appSettings = appSettings
        self.keyValueStore = keyValueStore
        self.secureVault = secureVault
        self.source = source
        self.featureFlagger = featureFlagger

        savePasswordsEnabled = appSettings.autofillCredentialsEnabled
        updatePasswordsCount()
        syncDataProviders.credentialsAdapter.syncDidCompletePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePasswordsCount()
            }
            .store(in: &syncCancellables)

        showCreditCards = featureFlagger.isFeatureOn(.autofillCreditCards)
        if showCreditCards {
            updateCreditCardsCount()
            syncDataProviders.creditCardsAdapter?.syncDidCompletePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updateCreditCardsCount()
                }
                .store(in: &syncCancellables)
        }
        if #available(iOS 18, *) {
            showExtensionSettings = featureFlagger.isFeatureOn(.autofillExtensionSettings)
            Task { @MainActor in
                extensionEnableCoordinator = AutofillExtensionEnableCoordinator(source: "settings")
                await updateExtensionStatus()
            }
        }
        syncService.scheduler.requestSyncImmediately()
    }

    func initSecureVaultIfRequired() {
        if secureVault == nil {
            do {
                secureVault = try AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter())
            } catch {
                return
            }
        }
    }

    func refreshData() {
        updatePasswordsCount()
        if showCreditCards {
            updateCreditCardsCount()
        }
        if showExtensionSettings {
            Task {
                await updateExtensionStatus()
            }
        }
    }

    func updatePasswordsCount() {
        initSecureVaultIfRequired()

        guard let vault = secureVault else {
            passwordsCount = nil
            return
        }
        
        do {
            passwordsCount = try vault.accountsCount()
        } catch {
            passwordsCount = nil
        }
    }
    
    func updateCreditCardsCount() {
        initSecureVaultIfRequired()

        guard let vault = secureVault else {
            creditCardsCount = nil
            return
        }

        do {
            creditCardsCount = try vault.creditCardsCount()
        } catch {
            creditCardsCount = nil
        }
    }

    @MainActor
    func updateExtensionStatus() async {
        guard showExtensionSettings else {
            return
        }

        if #available(iOS 18, *), let coordinator = extensionEnableCoordinator as? AutofillExtensionEnableCoordinator {
            isExtensionEnabled = await coordinator.updateExtensionStatus()
        }
    }

    func footerAttributedString() -> AttributedString {
        let markdownString = UserText.autofillLearnMoreLinkTitle
        
        do {
            var attributedString = try AttributedString(markdown: markdownString)
            attributedString.foregroundColor = Color(designSystemColor: .accent)
            
            return attributedString
        } catch {
            return ""
        }
    }
    
    // MARK: - Navigation
    
    func navigateToPasswords() {
        delegate?.navigateToPasswords(viewModel: self)
    }

    func navigateToCreditCards() {
        delegate?.navigateToCreditCards(viewModel: self)
    }

    func navigateToFileImport() {
        delegate?.navigateToFileImport(viewModel: self)
    }
    
    func navigateToImportViaSync() {
        delegate?.navigateToImportViaSync(viewModel: self)
    }
    
    func shouldShowNeverPromptReset() -> Bool {
        !autofillNeverPromptWebsitesManager.neverPromptWebsites.isEmpty
    }

    func navigateToExtensionManagement() {
        Task { @MainActor in
            if #available(iOS 18.0, *), let coordinator = extensionEnableCoordinator as? AutofillExtensionEnableCoordinator {
                let currentlyEnabled = await coordinator.updateExtensionStatus()

                if !currentlyEnabled {
                    let result = await coordinator.enableExtension()

                    switch result {
                    case .success:
                        isExtensionEnabled = true
                        isShowingActivationView = true
                    case .throttled:
                        isEnableRequestThrottled = coordinator.isEnableRequestThrottled
                        isShowingActivationView = false
                    case .cancelled, .failed:
                        isShowingActivationView = false
                    }
                } else {
                    delegate?.navigateToExtensionManagement(viewModel: self)
                }
            }
        }
    }

    // MARK: - Reset Excluded Sites
    
    func resetExcludedSites() {
        showingResetConfirmation = true
        Pixel.fire(pixel: .autofillLoginsSettingsResetExcludedDisplayed)
    }
    
    func confirmResetExcludedSites() {
        _ = autofillNeverPromptWebsitesManager.deleteAllNeverPromptWebsites()
        showingResetConfirmation = false
        Pixel.fire(pixel: .autofillLoginsSettingsResetExcludedConfirmed)
    }
    
    func cancelResetExcludedSites() {
        showingResetConfirmation = false
        Pixel.fire(pixel: .autofillLoginsSettingsResetExcludedDismissed)
    }

}
