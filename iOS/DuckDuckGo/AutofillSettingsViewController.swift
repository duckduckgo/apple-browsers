//
//  AutofillSettingsViewController.swift
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

import UIKit
import Core
import BrowserServicesKit
import Common
import DDGSync
import SwiftUI
import Persistence
import Bookmarks

enum AutofillSettingsSource: String {
    case settings
    case overflow = "overflow_menu"
    case sync
    case appIconShortcut = "app_icon_shortcut"
    case homeScreenWidget = "home_screen_widget"
    case lockScreenWidget = "lock_screen_widget"
    case newTabPageShortcut = "new_tab_page_shortcut"
    case saveLoginDisablePrompt = "save_login_disable_prompt"
    case saveCreditCardDisablePrompt = "save_credit_card_disable_prompt"
    case viewSavedLoginPrompt = "view_saved_login_prompt"
    case newTabPageToolbar = "new_tab_page_toolbar"
    case viewSavedCreditCardPrompt = "view_saved_credit_card_prompt"
    case creditCardKeyboardShortcut = "credit_card_keyboard_shortcut"
}

protocol AutofillSettingsViewControllerDelegate: AnyObject {
    func autofillSettingsViewControllerDidFinish(_ controller: AutofillSettingsViewController)
}

final class AutofillSettingsViewController: UIViewController {
    
    weak var delegate: AutofillSettingsViewControllerDelegate?
    
    private var viewModel: AutofillSettingsViewModel
    private let appSettings: AppSettings
    private let syncService: DDGSyncing
    private let syncDataProviders: SyncDataProviders
    private let selectedAccount: SecureVaultModels.WebsiteAccount?
    private let selectedCard: SecureVaultModels.CreditCard?
    private let showPasswordManagement: Bool
    private let showCardManagement: Bool
    private let source: AutofillSettingsSource
    private let bookmarksDatabase: CoreDataDatabase
    private let favoritesDisplayMode: FavoritesDisplayMode
    private let keyValueStore: ThrowingKeyValueStoring

    init(appSettings: AppSettings,
         syncService: DDGSyncing,
         syncDataProviders: SyncDataProviders,
         selectedAccount: SecureVaultModels.WebsiteAccount?,
         selectedCard: SecureVaultModels.CreditCard?,
         showPasswordManagement: Bool,
         showCardManagement: Bool = false,
         source: AutofillSettingsSource,
         bookmarksDatabase: CoreDataDatabase,
         favoritesDisplayMode: FavoritesDisplayMode,
         keyValueStore: ThrowingKeyValueStoring
    ) {
        self.appSettings = appSettings
        self.syncService = syncService
        self.syncDataProviders = syncDataProviders
        self.selectedAccount = selectedAccount
        self.selectedCard = selectedCard
        self.showPasswordManagement = showPasswordManagement
        self.showCardManagement = showCardManagement
        self.source = source
        self.bookmarksDatabase = bookmarksDatabase
        self.favoritesDisplayMode = favoritesDisplayMode
        self.keyValueStore = keyValueStore
        self.viewModel = AutofillSettingsViewModel(appSettings: appSettings, source: source)
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupView()
        
        title = UserText.settingsLogins
        
        if selectedAccount != nil || showPasswordManagement {
            segueToPasswords()
        } else if selectedCard != nil || showCardManagement {
            segueToCreditCards()
        }
        
        Pixel.fire(pixel: .autofillSettingsOpened)
    }
    
    private func setupView() {
        viewModel.delegate = self
        
        let controller = UIHostingController(rootView: AutofillSettingsView(viewModel: viewModel))
        controller.view.backgroundColor = .clear
        installChildViewController(controller)
    }
    
    private func segueToPasswords() {
        let autofillLoginListViewController = AutofillLoginListViewController(
            appSettings: appSettings,
            currentTabUrl: nil,
            currentTabUid: nil,
            syncService: syncService,
            syncDataProviders: syncDataProviders,
            selectedAccount: selectedAccount,
            openSearch: false,
            source: source,
            bookmarksDatabase: bookmarksDatabase,
            favoritesDisplayMode: favoritesDisplayMode,
            keyValueStore: keyValueStore
        )
        navigationController?.pushViewController(autofillLoginListViewController, animated: true)
    }
    
    private func segueToCreditCards() {
        let autofillCreditCardsViewController = AutofillCreditCardListViewController(
            secureVault: viewModel.secureVault,
            selectedCard: selectedCard,
            source: source)
        navigationController?.pushViewController(autofillCreditCardsViewController, animated: true)
    }
    
    private func segueToFileImport() {
        let dataImportManager = DataImportManager(reporter: SecureVaultReporter(),
                                                  bookmarksDatabase: bookmarksDatabase,
                                                  favoritesDisplayMode: favoritesDisplayMode,
                                                  tld: AppDependencyProvider.shared.storageCache.tld)
        let dataImportViewController = DataImportViewController(importManager: dataImportManager,
                                                                importScreen: DataImportViewModel.ImportScreen.passwords,
                                                                syncService: syncService,
                                                                keyValueStore: keyValueStore)
        dataImportViewController.delegate = self
        navigationController?.pushViewController(dataImportViewController, animated: true)
        Pixel.fire(pixel: .autofillImportPasswordsImportButtonTapped, withAdditionalParameters: [PixelParameters.source: "settings"])
    }
    
    private func segueToImportViaSync() {
        let importController = ImportPasswordsViaSyncViewController(syncService: syncService)
        importController.delegate = self
        navigationController?.pushViewController(importController, animated: true)
        Pixel.fire(pixel: .autofillLoginsImportNoPasswords, withAdditionalParameters: [PixelParameters.source: "settings"])
    }
    
    private func segueToSync(source: String? = nil) {
        if let settingsVC = self.navigationController?.children.first as? SettingsHostingController {
            navigationController?.popToRootViewController(animated: true)
            if let source = source {
                settingsVC.viewModel.shouldPresentSyncViewWithSource(source)
            } else {
                settingsVC.viewModel.presentLegacyView(.sync(nil))
            }
        } else if let mainVC = self.presentingViewController as? MainViewController {
            dismiss(animated: true) {
                mainVC.segueToSettingsSync(with: source)
            }
        }
    }
}

// MARK: AutofillSettingsViewModelDelegate

extension AutofillSettingsViewController: AutofillSettingsViewModelDelegate {
    
    func navigateToFileImport(viewModel: AutofillSettingsViewModel) {
        segueToFileImport()
    }
    
    func navigateToImportViaSync(viewModel: AutofillSettingsViewModel) {
        segueToImportViaSync()
    }
    
    func navigateToPasswords(viewModel: AutofillSettingsViewModel) {
        segueToPasswords()
    }
    
    func navigateToCreditCards(viewModel: AutofillSettingsViewModel) {
        segueToCreditCards()
    }
    
}

// MARK: DataImportViewControllerDelegate

extension AutofillSettingsViewController: DataImportViewControllerDelegate {
    
    func dataImportViewControllerDidFinish(_ controller: DataImportViewController) {
        AppDependencyProvider.shared.autofillLoginSession.startSession()
        segueToPasswords()
    }
    
}

// MARK: ImportPasswordsViaSyncViewController

extension AutofillSettingsViewController: ImportPasswordsViaSyncViewControllerDelegate {
    
    func importPasswordsViaSyncViewControllerDidRequestOpenSync(_ viewController: ImportPasswordsViaSyncViewController) {
        segueToSync()
    }
    
}
