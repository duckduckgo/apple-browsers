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

protocol AutofillSettingsViewModelDelegate: AnyObject {
    func navigateToPasswords(viewModel: AutofillSettingsViewModel)
    func navigateToFileImport(viewModel: AutofillSettingsViewModel)
    func navigateToImportViaSync(viewModel: AutofillSettingsViewModel)
}

final class AutofillSettingsViewModel: ObservableObject {
    
    weak var delegate: AutofillSettingsViewModelDelegate?
    
    private let autofillNeverPromptWebsitesManager: AutofillNeverPromptWebsitesManager
    private let appSettings: AppSettings
    private let keyValueStore: KeyValueStoringDictionaryRepresentable
    private var secureVault: (any AutofillSecureVault)?
    private let source: AutofillSettingsSource
    
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
    
    init(appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         keyValueStore: KeyValueStoringDictionaryRepresentable = UserDefaults.standard,
         autofillNeverPromptWebsitesManager: AutofillNeverPromptWebsitesManager = AppDependencyProvider.shared.autofillNeverPromptWebsitesManager,
         secureVault: (any AutofillSecureVault)? = nil,
         source: AutofillSettingsSource) {
        self.autofillNeverPromptWebsitesManager = autofillNeverPromptWebsitesManager
        self.appSettings = appSettings
        self.keyValueStore = keyValueStore
        self.secureVault = secureVault
        self.source = source
        
        savePasswordsEnabled = appSettings.autofillCredentialsEnabled
        updatePasswordsCount()
    }
    
    func updatePasswordsCount() {
        if secureVault == nil {
            do {
                secureVault = try AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter())
            } catch {
                passwordsCount = nil
                return
            }
        }
        
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
    
    func navigateToFileImport() {
        delegate?.navigateToFileImport(viewModel: self)
    }
    
    func navigateToImportViaSync() {
        delegate?.navigateToImportViaSync(viewModel: self)
    }
    
    func shouldShowNeverPromptReset() -> Bool {
        !autofillNeverPromptWebsitesManager.neverPromptWebsites.isEmpty
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
