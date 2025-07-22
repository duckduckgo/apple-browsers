//
//  MainMenuActions.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Cocoa
import Common
import Configuration
import Crashes
import FeatureFlags
import History
import PixelKit
import Subscription
import WebKit
import os.log
import SwiftUI

// Actions are sent to objects of responder chain

// MARK: - Main Menu Actions

extension AppDelegate {

    // MARK: - DuckDuckGo

    @MainActor
    @objc func checkForUpdates(_ sender: Any?) {
#if SPARKLE
        if let warning = SupportedOSChecker().supportWarning,
           case .unsupported = warning {

            // Show not supported info
            if NSAlert.osNotSupported(warning).runModal() != .cancel {
                let url = Preferences.UnsupportedDeviceInfoBox.softwareUpdateURL
                NSWorkspace.shared.open(url)
            }
        }

        showAbout(sender)
#endif
    }

    // MARK: - File

    @objc func newWindow(_ sender: Any?) {
        DispatchQueue.main.async {
            WindowsManager.openNewWindow()
        }
    }

    @objc func newBurnerWindow(_ sender: Any?) {
        DispatchQueue.main.async {
            WindowsManager.openNewWindow(burnerMode: BurnerMode(isBurner: true))
        }
    }

    @objc func newAIChat(_ sender: Any?) {
        DispatchQueue.main.async {
            NSApp.delegateTyped.aiChatTabOpener.openAIChatTab(nil, with: .newTab(selected: true))
            PixelKit.fire(AIChatPixel.aichatApplicationMenuFileClicked, frequency: .dailyAndCount, includeAppVersionParameter: true)
        }
    }

    @objc func newTab(_ sender: Any?) {
        DispatchQueue.main.async {
            WindowsManager.openNewWindow()
        }
    }

    @objc func openLocation(_ sender: Any?) {
        DispatchQueue.main.async {
            WindowsManager.openNewWindow()
        }
    }

    @objc func closeAllWindows(_ sender: Any?) {
        DispatchQueue.main.async {
            WindowsManager.closeWindows()
        }
    }

    // MARK: - History

    @objc func reopenLastClosedTab(_ sender: Any?) {
        DispatchQueue.main.async {
            RecentlyClosedCoordinator.shared.reopenItem()
        }
    }

    @objc func recentlyClosedAction(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem,
              let cacheItem = menuItem.representedObject as? RecentlyClosedCacheItem else {
            assertionFailure("Wrong represented object for recentlyClosedAction()")
            return
        }
        DispatchQueue.main.async {
            RecentlyClosedCoordinator.shared.reopenItem(cacheItem)
        }
    }

    @objc func openHistoryEntryVisit(_ sender: NSMenuItem) {
        guard let visit = sender.representedObject as? Visit,
              let url = visit.historyEntry?.url else {
            assertionFailure("Wrong represented object")
            return
        }
        DispatchQueue.main.async {
            WindowsManager.openNewWindow(with: Tab(content: .contentFromURL(url, source: .historyEntry), shouldLoadInBackground: true))
        }
    }

    @objc func clearAllHistory(_ sender: NSMenuItem) {
        Task { @MainActor in
            let window: NSWindow? = windowControllersManager.lastKeyMainWindowController?.window ?? WindowsManager.openNewWindow(with: Tab(content: .newtab))
            guard let window else {
                assertionFailure("No reference to main window controller")
                return
            }

            if featureFlagger.isFeatureOn(.historyView) {
                let historyViewDataProvider = HistoryViewDataProvider(
                    historyDataSource: historyCoordinator,
                    historyBurner: FireHistoryBurner(fireproofDomains: fireproofDomains, fire: { @MainActor in self.fireCoordinator.fireViewModel.fire })
                )
                await historyViewDataProvider.refreshData()
                let visitsCount = await historyViewDataProvider.countVisibleVisits(matching: .rangeFilter(.all))

                let presenter = DefaultHistoryViewDialogPresenter()
                switch await presenter.showDeleteDialog(for: visitsCount, deleteMode: .all, in: window) {
                case .burn:
                    fireCoordinator.fireViewModel.fire.burnAll()
                case .delete:
                    historyCoordinator.burnAll {
                        // History View doesn't currently support having new data pushed to it
                        // so we need to instruct all open history tabs to reload themselves.
                        let historyTabs = self.windowControllersManager.mainWindowControllers
                            .flatMap(\.mainViewController.tabCollectionViewModel.tabCollection.tabs)
                            .filter { $0.content == .history }
                        historyTabs.forEach { $0.reload() }
                    }
                default:
                    break
                }
            } else {
                let alert = NSAlert.clearAllHistoryAndDataAlert()
                alert.beginSheetModal(for: window, completionHandler: { response in
                    guard case .alertFirstButtonReturn = response else {
                        return
                    }
                    self.fireCoordinator.fireViewModel.fire.burnAll()
                })
            }
        }
    }

    @objc func clearThisHistory(_ sender: ClearThisHistoryMenuItem) {
        DispatchQueue.main.async {
            guard let window = WindowsManager.openNewWindow(with: Tab(content: .newtab)),
                  let windowController = window.windowController as? MainWindowController else {
                assertionFailure("No reference to main window controller")
                return
            }

            windowController.mainViewController.clearThisHistory(sender)
        }
    }

    // MARK: - Window

    @objc func reopenAllWindowsFromLastSession(_ sender: Any?) {
        DispatchQueue.main.async {
            self.stateRestorationManager.restoreLastSessionState(interactive: true, includeRegularTabs: true)
        }
    }

    // MARK: - Help

    @MainActor
    @objc func showAbout(_ sender: Any?) {
        Application.appDelegate.windowControllersManager.showTab(with: .settings(pane: .about))
    }

    @MainActor
    @objc func addToDock(_ sender: Any?) {
        DockCustomizer().addToDock()
        PixelKit.fire(GeneralPixel.userAddedToDockFromMainMenu)
    }

    @MainActor
    @objc func setAsDefault(_ sender: Any?) {
        PixelKit.fire(GeneralPixel.defaultRequestedFromMainMenu)
        DefaultBrowserPreferences.shared.becomeDefault()
    }

    @MainActor
    @objc func showReleaseNotes(_ sender: Any?) {
        Application.appDelegate.windowControllersManager.showTab(with: .releaseNotes)
    }

    @MainActor
    @objc func showWhatIsNew(_ sender: Any?) {
        Application.appDelegate.windowControllersManager.showTab(with: .url(.updates, source: .ui))
    }

#if FEEDBACK

    @objc func openFeedback(_ sender: Any?) {
        DispatchQueue.main.async {
            if self.internalUserDecider.isInternalUser {
                Application.appDelegate.windowControllersManager.showTab(with: .url(.internalFeedbackForm, source: .ui))
            } else {
                FeedbackPresenter.presentFeedbackForm()
            }
        }
    }

    @objc func openReportBrokenSite(_ sender: Any?) {
        let privacyDashboardViewController = PrivacyDashboardViewController(
            privacyInfo: nil,
            entryPoint: .report,
            contentBlocking: privacyFeatures.contentBlocking,
            permissionManager: permissionManager
        )
        privacyDashboardViewController.sizeDelegate = self

        let window = NSWindow(contentViewController: privacyDashboardViewController)
        window.styleMask.remove(.resizable)
        window.setFrame(NSRect(x: 0, y: 0, width: PrivacyDashboardViewController.Constants.initialContentWidth,
                               height: PrivacyDashboardViewController.Constants.reportBrokenSiteInitialContentHeight),
                        display: true)
        privacyDashboardWindow = window

        DispatchQueue.main.async {
            guard let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController,
                  let tabModel = parentWindowController.mainViewController.tabCollectionViewModel.selectedTabViewModel else {
                assertionFailure("AppDelegate: Failed to present PrivacyDashboard")
                return
            }
            privacyDashboardViewController.updateTabViewModel(tabModel)
            parentWindowController.window?.beginSheet(window) { _ in }
        }
    }

    @objc func openReportABrowserProblem(_ sender: Any?) {

    }

    @objc func openRequestANewFeature(_ sender: Any?) {

    }

    @MainActor
    @objc func openPProFeedback(_ sender: Any?) {
        Application.appDelegate.windowControllersManager.showShareFeedbackModal(source: .settings)
    }

    @MainActor
    @objc func copyVersion(_ sender: Any?) {
        NSPasteboard.general.copy(AppVersionModel(appVersion: AppVersion(), internalUserDecider: nil).versionLabelShort)
    }

#endif

    @objc func navigateToBookmark(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else {
            Logger.general.error("AppDelegate: Casting to menu item failed")
            return
        }

        guard let bookmark = menuItem.representedObject as? Bookmark,
              let url = bookmark.urlObject else {
            assertionFailure("Unexpected type of menuItem.representedObject: \(type(of: menuItem.representedObject))")
            return
        }
        DispatchQueue.main.async {
            let tab = Tab(content: .url(url, source: .bookmark(isFavorite: bookmark.isFavorite)), shouldLoadInBackground: true)
            WindowsManager.openNewWindow(with: tab)
        }
    }

    @objc func showManageBookmarks(_ sender: Any?) {
        DispatchQueue.main.async {
            let tabCollection = TabCollection(tabs: [Tab(content: .bookmarks)])
            let tabCollectionViewModel = TabCollectionViewModel(tabCollection: tabCollection)

            WindowsManager.openNewWindow(with: tabCollectionViewModel)
        }
    }

    @objc func openPreferences(_ sender: Any?) {
        DispatchQueue.main.async {
            let tabCollection = TabCollection(tabs: [Tab(content: .anySettingsPane)])
            let tabCollectionViewModel = TabCollectionViewModel(tabCollection: tabCollection)
            WindowsManager.openNewWindow(with: tabCollectionViewModel)
        }
    }

    @MainActor
    @objc func openAbout(_ sender: Any?) {
        AboutPanelController.show(internalUserDecider: internalUserDecider)
    }

    @objc func openImportBookmarksWindow(_ sender: Any?) {
        DispatchQueue.main.async {
            DataImportView(isDataTypePickerExpanded: true).show()
        }
    }

    @objc func openImportPasswordsWindow(_ sender: Any?) {
        DispatchQueue.main.async {
            DataImportView(isDataTypePickerExpanded: true).show()
        }
    }

    @objc func openImportBrowserDataWindow(_ sender: Any?) {
        DispatchQueue.main.async {
            DataImportView(isDataTypePickerExpanded: false).show()
        }
    }

    @MainActor
    @objc func openExportLogins(_ sender: Any?) {
        guard let windowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController,
              let window = windowController.window else { return }

        DeviceAuthenticator.shared.authenticateUser(reason: .exportLogins) { authenticationResult in
            guard authenticationResult.authenticated else {

                return
            }

            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = "DuckDuckGo \(UserText.exportLoginsFileNameSuffix)"

            let accessory = NSTextField.label(titled: UserText.exportLoginsWarning)
            accessory.textColor = .red
            accessory.alignment = .center
            accessory.sizeToFit()

            let accessoryContainer = accessory.wrappedInContainer(padding: 10)
            accessoryContainer.frame.size = accessoryContainer.fittingSize

            savePanel.accessoryView = accessoryContainer
            savePanel.allowedContentTypes = [.commaSeparatedText]

            savePanel.beginSheetModal(for: window) { response in
                guard response == .OK, let selectedURL = savePanel.url else { return }

                let vault = try? AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter.shared)
                let exporter = CSVLoginExporter(secureVault: vault!)
                do {
                    try exporter.exportVaultLogins(to: selectedURL)
                } catch {
                    NSAlert.exportLoginsFailed()
                        .beginSheetModal(for: window, completionHandler: nil)
                }
            }
        }
    }

    @MainActor
    @objc func openExportBookmarks(_ sender: Any?) {
        guard let windowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController,
              let window = windowController.window,
              let list = bookmarkManager.list else { return }

        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "DuckDuckGo \(UserText.exportBookmarksFileNameSuffix)"
        savePanel.allowedContentTypes = [.html]

        savePanel.beginSheetModal(for: window) { response in
            guard response == .OK, let selectedURL = savePanel.url else { return }

            let exporter = BookmarksExporter(list: list)
            do {
                try exporter.exportBookmarksTo(url: selectedURL)
            } catch {
                NSAlert.exportBookmarksFailed()
                    .beginSheetModal(for: window, completionHandler: nil)
            }
        }
    }

    @objc func fireButtonAction(_ sender: NSButton) {
        DispatchQueue.main.async {
            self.fireCoordinator.fireButtonAction()
            let pixelReporter = OnboardingPixelReporter()
            pixelReporter.measureFireButtonPressed()
        }
    }

    @objc func navigateToPrivateEmail(_ sender: Any?) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.keyWindow,
                  let windowController = window.windowController as? MainWindowController else {
                assertionFailure("No reference to main window controller")
                return
            }
            windowController.mainViewController.browserTabViewController.openNewTab(with: .url(URL.duckDuckGoEmailLogin, source: .ui))
        }
    }

    // MARK: - Debug

    @MainActor
    @objc func skipOnboarding(_ sender: Any?) {
        UserDefaults.standard.set(true, forKey: UserDefaultsWrapper<Bool>.Key.onboardingFinished.rawValue)
        Application.appDelegate.onboardingContextualDialogsManager.state = .onboardingCompleted
        OnboardingActionsManager.isOnboardingFinished = true
        Application.appDelegate.windowControllersManager.updatePreventUserInteraction(prevent: false)
        Application.appDelegate.windowControllersManager.replaceTabWith(Tab(content: .newtab))
    }

    @objc func resetRemoteMessages(_ sender: Any?) {
        Task {
            await remoteMessagingClient.store?.resetRemoteMessages()
        }
    }

    @objc func resetNewTabPageCustomization(_ sender: Any?) {
        newTabPageCustomizationModel.resetAllCustomizations()
    }

    @objc func debugResetContinueSetup(_ sender: Any?) {
        let persistor = AppearancePreferencesUserDefaultsPersistor(keyValueStore: keyValueStore)
        persistor.continueSetUpCardsLastDemonstrated = nil
        persistor.continueSetUpCardsNumberOfDaysDemonstrated = 0
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        appearancePreferences.continueSetUpCardsClosed = false
        appearancePreferences.isContinueSetUpVisible = true
        HomePage.Models.ContinueSetUpModel.Settings().clear()
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
    }

    @objc func showContentScopeExperiments(_ sender: Any?) {
        let experiments = contentScopeExperimentsManager.allActiveContentScopeExperiments

        let alert = NSAlert()
        alert.messageText = "Content Scope Experiments"

        var infoText = "Active Experiments:\n"
        if experiments.isEmpty {
            infoText += "No active experiments\n"
        } else {
            for (key, data) in experiments {
                infoText += "\nExperiment: \(key)\n"
                infoText += "Parent ID: \(data.parentID)\n"
                infoText += "Cohort ID: \(data.cohortID)\n"
                infoText += "Enrollment Date: \(data.enrollmentDate)\n"
            }
        }

        alert.informativeText = infoText
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func resetDefaultBrowserPrompt(_ sender: Any?) {
        UserDefaultsWrapper.clear(.defaultBrowserDismissed)
    }

    @objc func resetDefaultGrammarChecks(_ sender: Any?) {
        UserDefaultsWrapper.clear(.spellingCheckEnabledOnce)
        UserDefaultsWrapper.clear(.grammarCheckEnabledOnce)
    }

    @objc func triggerFatalError(_ sender: Any?) {
        fatalError("Fatal error triggered from the Debug menu")
    }

    @objc func crashOnCxxException(_ sender: Any?) {
        throwTestCppException()
    }

    @objc func resetSecureVaultData(_ sender: Any?) {
        let vault = try? AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter.shared)

        let accounts = (try? vault?.accounts()) ?? []
        for accountID in accounts.compactMap(\.id) {
            if let accountID = Int64(accountID) {
                try? vault?.deleteWebsiteCredentialsFor(accountId: accountID)
            }
        }

        let cards = (try? vault?.creditCards()) ?? []
        for cardID in cards.compactMap(\.id) {
            try? vault?.deleteCreditCardFor(cardId: cardID)
        }

        let identities = (try? vault?.identities()) ?? []
        for identityID in identities.compactMap(\.id) {
            try? vault?.deleteIdentityFor(identityId: identityID)
        }

        let notes = (try? vault?.notes()) ?? []
        for noteID in notes.compactMap(\.id) {
            try? vault?.deleteNoteFor(noteId: noteID)
        }
        UserDefaults.standard.set(false, forKey: UserDefaultsWrapper<Bool>.Key.homePageContinueSetUpImport.rawValue)

        let autofillPixelReporter = AutofillPixelReporter(usageStore: AutofillUsageStore(standardUserDefaults: .standard, appGroupUserDefaults: nil),
                                                          autofillEnabled: AutofillPreferences().askToSaveUsernamesAndPasswords,
                                                          eventMapping: EventMapping<AutofillPixelEvent> { _, _, _, _ in },
                                                          installDate: nil)
        autofillPixelReporter.resetStoreDefaults()
        let loginImportState = AutofillLoginImportState()
        loginImportState.hasImportedLogins = false
        loginImportState.isCredentialsImportPromoInBrowserPermanentlyDismissed = false
    }

    @objc func resetBookmarks(_ sender: Any?) {
        bookmarkManager.resetBookmarks {
            self.bookmarkManager.sortMode = .manual
            UserDefaultsWrapper<Bool>(key: .homePageContinueSetUpImport, defaultValue: false).clear()
            UserDefaultsWrapper<Bool>(key: .showBookmarksBar, defaultValue: false).clear()
            UserDefaultsWrapper<Bool>(key: .bookmarksBarPromptShown, defaultValue: false).clear()
            UserDefaultsWrapper<Bool>(key: .centerAlignedBookmarksBar, defaultValue: false).clear()
            UserDefaultsWrapper<Bool>(key: .showTabsAndBookmarksBarOnFullScreen, defaultValue: false).clear()

            self.appearancePreferences.reload()
        }
    }

    @objc func resetPinnedTabs(_ sender: Any?) {
        for pinnedTabsManager in Application.appDelegate.pinnedTabsManagerProvider.currentPinnedTabManagers {
            pinnedTabsManager.tabCollection.removeAll()
        }
    }

    @objc func resetDuckPlayerOverlayInteractions(_ sender: Any?) {
        DuckPlayerPreferences.shared.youtubeOverlayAnyButtonPressed = false
        DuckPlayerPreferences.shared.youtubeOverlayInteracted = false
    }

    @objc func resetMakeDuckDuckGoYoursUserSettings(_ sender: Any?) {
        UserDefaults.standard.set(true, forKey: UserDefaultsWrapper<Bool>.Key.homePageShowAllFeatures.rawValue)
        UserDefaults.standard.set(true, forKey: UserDefaultsWrapper<Bool>.Key.homePageShowMakeDefault.rawValue)
        UserDefaults.standard.set(true, forKey: UserDefaultsWrapper<Bool>.Key.homePageShowImport.rawValue)
        UserDefaults.standard.set(true, forKey: UserDefaultsWrapper<Bool>.Key.homePageShowDuckPlayer.rawValue)
        UserDefaults.standard.set(true, forKey: UserDefaultsWrapper<Bool>.Key.homePageShowEmailProtection.rawValue)
    }

    @objc func resetOnboarding(_ sender: Any?) {
        UserDefaults.standard.set(false, forKey: UserDefaultsWrapper<Bool>.Key.onboardingFinished.rawValue)
    }

    @objc func resetHomePageSettingsOnboarding(_ sender: Any?) {
        UserDefaults.standard.set(false, forKey: UserDefaultsWrapper<Any>.Key.homePageDidShowSettingsOnboarding.rawValue)
    }

    @objc func resetContextualOnboarding(_ sender: Any?) {
        Application.appDelegate.onboardingContextualDialogsManager.state = .notStarted
    }

    @objc func resetDuckPlayerPreferences(_ sender: Any?) {
        DuckPlayerPreferences.shared.reset()
    }

    @objc func resetSyncPromoPrompts(_ sender: Any?) {
        SyncPromoManager().resetPromos()
    }

    @objc func resetAddToDockFeatureNotification(_ sender: Any?) {
#if SPARKLE
        guard let dockCustomizer = Application.appDelegate.dockCustomization else { return }
        dockCustomizer.resetData()
#endif
    }

    @objc func resetLaunchDateToToday(_ sender: Any?) {
        UserDefaults.standard.set(Date(), forKey: UserDefaultsWrapper<Any>.Key.firstLaunchDate.rawValue)
    }

    @objc func setLaunchDayAWeekInThePast(_ sender: Any?) {
        UserDefaults.standard.set(Date.weekAgo, forKey: UserDefaultsWrapper<Any>.Key.firstLaunchDate.rawValue)
    }

    @objc func resetTipKit(_ sender: Any?) {
        TipKitDebugOptionsUIActionHandler().resetTipKitTapped()
    }

    @objc func internalUserState(_ sender: Any?) {
        guard let internalUserDecider = NSApp.delegateTyped.internalUserDecider as? DefaultInternalUserDecider else { return }
        let state = internalUserDecider.isInternalUser
        internalUserDecider.debugSetInternalUserState(!state)
    }

    @objc func resetDailyPixels(_ sender: Any?) {
        PixelKit.shared?.clearFrequencyHistoryForAllPixels()
    }

    @objc func changePixelExperimentInstalledDateToLessMoreThan5DayAgo(_ sender: Any?) {
        let moreThanFiveDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: Date())
        UserDefaults.standard.set(moreThanFiveDaysAgo, forKey: UserDefaultsWrapper<Date>.Key.pixelExperimentEnrollmentDate.rawValue)
    }

    @objc func changeInstallDateToToday(_ sender: Any?) {
        UserDefaults.standard.set(Date(), forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)
    }

    @objc func changeInstallDateToLessThan5DayAgo(_ sender: Any?) {
        let lessThanFiveDaysAgo = Calendar.current.date(byAdding: .day, value: -4, to: Date())
        UserDefaults.standard.set(lessThanFiveDaysAgo, forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)
    }

    @objc func changeInstallDateToMoreThan5DayAgoButLessThan9(_ sender: Any?) {
        let between5And9DaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date())
        UserDefaults.standard.set(between5And9DaysAgo, forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)
    }

    @objc func changeInstallDateToMoreThan9DaysAgo(_ sender: Any?) {
        let nineDaysAgo = Calendar.current.date(byAdding: .day, value: -9, to: Date())
        UserDefaults.standard.set(nineDaysAgo, forKey: UserDefaultsWrapper<Date>.Key.firstLaunchDate.rawValue)
    }

    @objc func resetEmailProtectionInContextPrompt(_ sender: Any?) {
        EmailManager().resetEmailProtectionInContextPrompt()
    }

    @objc func reloadConfigurationNow(_ sender: Any?) {
        Application.appDelegate.configurationManager.forceRefresh(isDebug: true)
    }

    private func setConfigurationUrl(_ configurationUrl: URL?) {
        var configurationProvider = AppConfigurationURLProvider(
            privacyConfigurationManager: privacyFeatures.contentBlocking.privacyConfigurationManager,
            featureFlagger: featureFlagger,
            customPrivacyConfiguration: configurationUrl
        )
        if configurationUrl == nil {
            configurationProvider.resetToDefaultConfigurationUrl()
        }
        Configuration.setURLProvider(configurationProvider)
        Application.appDelegate.configurationManager.forceRefresh(isDebug: true)
        if let configurationUrl {
            Logger.config.debug("New configuration URL set to \(configurationUrl.absoluteString)")
        } else {
            Logger.config.log("New configuration URL reset to default")
        }
    }

    @objc func setCustomConfigurationURL(_ sender: Any?) {
        let currentConfigurationURL = AppConfigurationURLProvider(
            privacyConfigurationManager: privacyFeatures.contentBlocking.privacyConfigurationManager,
            featureFlagger: featureFlagger
        ).url(for: .privacyConfiguration).absoluteString
        let alert = NSAlert.customConfigurationAlert(configurationUrl: currentConfigurationURL)
        if alert.runModal() != .cancel {
            guard let textField = alert.accessoryView as? NSTextField,
                  let newConfigurationUrl = URL(string: textField.stringValue) else {
                Logger.config.error("Failed to set custom configuration URL")
                return
            }

            setConfigurationUrl(newConfigurationUrl)
        }
    }

    @objc func resetConfigurationToDefault(_ sender: Any?) {
        setConfigurationUrl(nil)
    }

}

extension MainViewController {

    /// Finds currently active Tab even if it‘s playing a Full Screen video
    private func getActiveTabAndIndex() -> (tab: Tab, index: TabIndex)? {
        var tab: Tab? {
            // popup windows don‘t get to lastKeyMainWindowController so try getting their WindowController directly fron a key window
            if let window = self.view.window,
               let mainWindowController = window.nextResponder as? MainWindowController,
               let tab = mainWindowController.activeTab {
                return tab
            }
            return Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.activeTab
        }
        guard let tab else {
            assertionFailure("Could not get currently active Tab")
            return nil
        }
        guard let index = tabCollectionViewModel.indexInAllTabs(of: tab) else {
            assertionFailure("Could not get Tab index")
            return nil
        }
        return (tab, index)
    }

    var activeTabViewModel: TabViewModel? {
        getActiveTabAndIndex().flatMap { tabCollectionViewModel.tabViewModel(at: $0.index) }
    }

    func makeKeyIfNeeded() {
        if view.window?.isKeyWindow != true {
            view.window?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Main Menu

    @objc func openPreferences(_ sender: Any?) {
        makeKeyIfNeeded()
        browserTabViewController.openNewTab(with: .anySettingsPane)
    }

    // MARK: - File

    @objc func newTab(_ sender: Any?) {
        makeKeyIfNeeded()
        browserTabViewController.openNewTab(with: .newtab)
    }

    @objc func openLocation(_ sender: Any?) {
        makeKeyIfNeeded()
        guard let addressBarTextField = navigationBarViewController.addressBarViewController?.addressBarTextField else {
            Logger.general.error("MainViewController: Cannot reference address bar text field")
            return
        }

        // If the address bar is already the first responder it means that the user is editing the URL and wants to select the whole url.
        if addressBarTextField.isFirstResponder {
            addressBarTextField.selectText(nil)
        } else {
            addressBarTextField.makeMeFirstResponder()
        }
    }

    @objc func closeTab(_ sender: Any?) {
        guard let (tab, index) = getActiveTabAndIndex() else { return }
        makeKeyIfNeeded()

        // when close is triggered by a keyboard shortcut,
        // instead of closing a pinned tab we select the first regular tab
        // (this is in line with Safari behavior)
        // If there are no regular tabs, we close the window.
        var isHandlingKeyDownEvent: Bool {
            guard sender is NSMenuItem,
                  let currentEvent = NSApp.currentEvent,
                  case .keyDown = currentEvent.type,
                  currentEvent.modifierFlags.contains(.command) else { return false }
             return true
        }
        if isHandlingKeyDownEvent, tab.isPinned {
            if tabCollectionViewModel.tabCollection.tabs.isEmpty {
                view.window?.performClose(sender)
            } else {
                tab.stopAllMediaAndLoading()
                tabCollectionViewModel.select(at: .unpinned(0))
            }
            return
        }

        tabCollectionViewModel.remove(at: index)
    }

    // MARK: - View

    @objc func reloadPage(_ sender: Any) {
        makeKeyIfNeeded()
        activeTabViewModel?.reload()
    }

    @objc func stopLoadingPage(_ sender: Any) {
        getActiveTabAndIndex()?.tab.stopLoading()
    }

    @objc func zoomIn(_ sender: Any) {
        getActiveTabAndIndex()?.tab.webView.zoomIn()
        navigationBarViewController.addressBarViewController?.addressBarButtonsViewController?.openZoomPopover(source: .menu)
    }

    @objc func zoomOut(_ sender: Any) {
        getActiveTabAndIndex()?.tab.webView.zoomOut()
        navigationBarViewController.addressBarViewController?.addressBarButtonsViewController?.openZoomPopover(source: .menu)
    }

    @objc func actualSize(_ sender: Any) {
        getActiveTabAndIndex()?.tab.webView.resetZoomLevel()
    }

    @objc func summarize(_ sender: Any) {
        guard featureFlagger.isFeatureOn(.aiChatTextSummarization), featureFlagger.isFeatureOn(.aiChatSidebar) else {
            return
        }
        Logger.aiChat.debug("Summarize action to be implemented")

        Task {
            do {
                let selectedText = try await getActiveTabAndIndex()?.tab.webView.evaluateJavaScript("window.getSelection().toString()") as? String
                guard let selectedText, !selectedText.isEmpty else {
                    return
                }
                let request = AIChatTextSummarizationRequest(
                    text: selectedText,
                    websiteURL: browserTabViewController.webView?.url,
                    websiteTitle: browserTabViewController.webView?.title,
                    source: .keyboardShortcut
                )
                aiChatSummarizer.summarize(request)
            } catch {
                Logger.aiChat.error("Failed to get selected text from the webView")
            }
        }
    }

    @objc func toggleDownloads(_ sender: Any) {
        var navigationBarViewController = self.navigationBarViewController
        if view.window?.isPopUpWindow == true {
            if let vc = Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.mainViewController.navigationBarViewController {
                navigationBarViewController = vc
            } else {
                WindowsManager.openNewWindow(with: Tab(content: .newtab))
                guard let wc = Application.appDelegate.windowControllersManager.mainWindowControllers.first(where: { $0.window?.isPopUpWindow == false }) else {
                    return
                }
                navigationBarViewController = wc.mainViewController.navigationBarViewController
            }
            navigationBarViewController.view.window?.makeKeyAndOrderFront(nil)
        }
        navigationBarViewController.toggleDownloadsPopover(keepButtonVisible: sender is NSMenuItem /* keep button visible for some time on Cmd+J */)
    }

    @objc func toggleBookmarksBarFromMenu(_ sender: Any) {
        // Leaving this keyboard shortcut in place.  When toggled on it will use the previously set appearence which defaults to "always".
        //  If the user sets it to "new tabs only" somewhere (e.g. preferences), then it'll be that.
        guard let mainVC = Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.mainViewController else { return }

        let prefs = NSApp.delegateTyped.appearancePreferences
        if prefs.showBookmarksBar && prefs.bookmarksBarAppearance == .newTabOnly {
            // show bookmarks bar but don't change the setting
            mainVC.toggleBookmarksBarVisibility()
        } else {
            prefs.showBookmarksBar.toggle()
        }
    }

    @objc func toggleAutofillShortcut(_ sender: Any) {
        LocalPinningManager.shared.togglePinning(for: .autofill)
    }

    @objc func toggleBookmarksShortcut(_ sender: Any) {
        LocalPinningManager.shared.togglePinning(for: .bookmarks)
    }

    @objc func toggleDownloadsShortcut(_ sender: Any) {
        LocalPinningManager.shared.togglePinning(for: .downloads)
    }

    @objc func toggleNetworkProtectionShortcut(_ sender: Any) {
        LocalPinningManager.shared.togglePinning(for: .networkProtection)
    }

    // MARK: - History

    @objc func back(_ sender: Any?) {
        makeKeyIfNeeded()
        getActiveTabAndIndex()?.tab.goBack()
    }

    @objc func forward(_ sender: Any?) {
        makeKeyIfNeeded()
        getActiveTabAndIndex()?.tab.goForward()
    }

    @objc func home(_ sender: Any?) {
        guard view.window?.isPopUpWindow == false,
            let (tab, _) = getActiveTabAndIndex(), tab === tabCollectionViewModel.selectedTab else {

            browserTabViewController.openNewTab(with: .newtab)
            return
        }
        makeKeyIfNeeded()
        tab.openHomePage()
    }

    @objc func openHistoryEntryVisit(_ sender: NSMenuItem) {
        guard let visit = sender.representedObject as? Visit,
              let historyEntry = visit.historyEntry else {
            assertionFailure("Wrong represented object")
            return
        }

        makeKeyIfNeeded()

        Application.appDelegate.windowControllersManager.open(historyEntry, with: NSApp.currentEvent)
    }

    @objc func clearThisHistory(_ sender: ClearThisHistoryMenuItem) {
        let isToday = sender.isToday
        let visits = sender.getVisits(featureFlagger: featureFlagger)

        if featureFlagger.isFeatureOn(.historyView) {
            let deleteMode: HistoryViewDeleteDialogModel.DeleteMode = {
                guard let dateString = sender.dateString else {
                    return sender.isToday ? .today : .unspecified
                }
                return .formattedDate(dateString)
            }()

            Task {
                let presenter = DefaultHistoryViewDialogPresenter()
                switch await presenter.showDeleteDialog(for: visits.count, deleteMode: deleteMode, in: nil) {
                case .burn:
                    self.fireCoordinator.fireViewModel.fire.burnVisits(visits, except: fireproofDomains, isToday: isToday)
                case .delete:
                    historyCoordinator.burnVisits(visits) {}
                default:
                    break
                }
            }
        } else {
            guard let window = view.window else {
                assertionFailure("No window")
                return
            }

            let dateString = sender.dateString
            let alert = NSAlert.clearHistoryAndDataAlert(dateString: dateString)
            alert.beginSheetModal(for: window, completionHandler: { response in
                guard case .alertFirstButtonReturn = response else {
                    return
                }
                self.fireCoordinator.fireViewModel.fire.burnVisits(visits, except: self.fireproofDomains, isToday: isToday)
            })
        }
    }

    // MARK: - Bookmarks

    @objc func bookmarkThisPage(_ sender: Any) {
        guard let tabIndex = getActiveTabAndIndex()?.index else { return }
        if tabCollectionViewModel.selectedTabIndex != tabIndex {
            tabCollectionViewModel.select(at: tabIndex)
        }
        makeKeyIfNeeded()

        navigationBarViewController
            .addressBarViewController?
            .addressBarButtonsViewController?
            .openBookmarkPopover(setFavorite: false, accessPoint: .init(sender: sender, default: .moreMenu))
    }

    @objc func bookmarkAllOpenTabs(_ sender: Any) {
        let websitesInfo = tabCollectionViewModel.tabs.compactMap(WebsiteInfo.init)
        BookmarksDialogViewFactory.makeBookmarkAllOpenTabsView(websitesInfo: websitesInfo, bookmarkManager: bookmarkManager).show()
    }

    @objc func favoriteThisPage(_ sender: Any) {
        guard let tabIndex = getActiveTabAndIndex()?.index else { return }
        if tabCollectionViewModel.selectedTabIndex != tabIndex {
            tabCollectionViewModel.select(at: tabIndex)
        }
        makeKeyIfNeeded()

        navigationBarViewController
            .addressBarViewController?
            .addressBarButtonsViewController?
            .openBookmarkPopover(setFavorite: true, accessPoint: .init(sender: sender, default: .moreMenu))
    }

    @objc func openBookmark(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else {
            Logger.general.error("MainViewController: Casting to menu item failed")
            return
        }

        guard let bookmark = menuItem.representedObject as? Bookmark else { return }

        PixelKit.fire(NavigationEngagementPixel.navigateToBookmark(source: .menu, isFavorite: bookmark.isFavorite))

        makeKeyIfNeeded()

        Application.appDelegate.windowControllersManager.open(bookmark, with: NSApp.currentEvent)
    }

    @objc func openAllInTabs(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else {
            Logger.general.error("MainViewController: Casting to menu item failed")
            return
        }

        guard let models = menuItem.representedObject as? [BookmarkViewModel] else {
            return
        }

        let tabs = models.compactMap { model -> Tab? in
            guard let bookmark = model.entity as? Bookmark,
                  let url = bookmark.urlObject else {
                return nil
            }

            return Tab(content: .url(url, source: .bookmark(isFavorite: bookmark.isFavorite)),
                       shouldLoadInBackground: true,
                       burnerMode: tabCollectionViewModel.burnerMode)
        }
        tabCollectionViewModel.append(tabs: tabs, andSelect: true)
    }

    @objc func showManageBookmarks(_ sender: Any?) {
        makeKeyIfNeeded()
        browserTabViewController.openNewTab(with: .bookmarks)
    }

    @objc func showHistory(_ sender: Any?) {
        makeKeyIfNeeded()
        browserTabViewController.openNewTab(with: .history)
        if let menuItem = sender as? NSMenuItem {
            if menuItem.representedObject as? HistoryMenu.Location == .moreOptionsMenu {
                PixelKit.fire(HistoryViewPixel.historyPageShown(.sideMenu), frequency: .dailyAndStandard)
            } else {
                PixelKit.fire(HistoryViewPixel.historyPageShown(.topMenu), frequency: .dailyAndStandard)
            }
        }
    }

    // MARK: - Window

    @objc func showPreviousTab(_ sender: Any?) {
        makeKeyIfNeeded()
        guard let (tab, index) = getActiveTabAndIndex() else { return }
        if tabCollectionViewModel.selectedTab !== tab {
            tabCollectionViewModel.select(at: index)
        }
        tabCollectionViewModel.selectPrevious()
    }

    @objc func showNextTab(_ sender: Any?) {
        guard let (tab, index) = getActiveTabAndIndex() else { return }
        makeKeyIfNeeded()

        if tabCollectionViewModel.selectedTab !== tab {
            tabCollectionViewModel.select(at: index)
        }
        tabCollectionViewModel.selectNext()
    }

    @objc func showTab(_ sender: Any?) {
        makeKeyIfNeeded()
        guard let sender = sender as? NSMenuItem else {
            Logger.general.error("MainViewController: Casting to NSMenuItem failed")
            return
        }
        guard let keyEquivalent = Int(sender.keyEquivalent), keyEquivalent >= 0 && keyEquivalent <= 9 else {
            Logger.general.error("MainViewController: Key equivalent is not correct for tab selection")
            return
        }
        let index = keyEquivalent - 1
        if keyEquivalent == 9 {
            tabCollectionViewModel.select(at: .last(in: tabCollectionViewModel))
        } else if index < tabCollectionViewModel.allTabsCount {
            tabCollectionViewModel.select(at: .at(index, in: tabCollectionViewModel))
        }
    }

    @objc func moveTabToNewWindow(_ sender: Any?) {
        guard let (tab, index) = getActiveTabAndIndex() else { return }

        tabCollectionViewModel.remove(at: index)
        WindowsManager.openNewWindow(with: tab)
    }

    @objc func duplicateTab(_ sender: Any?) {
        guard let (_, index) = getActiveTabAndIndex() else { return }

        tabCollectionViewModel.duplicateTab(at: index)
    }

    @objc func pinOrUnpinTab(_ sender: Any?) {
        guard let (_, selectedTabIndex) = getActiveTabAndIndex() else { return }

        switch selectedTabIndex {
        case .pinned(let index):
            tabCollectionViewModel.unpinTab(at: index)
        case .unpinned(let index):
            tabCollectionViewModel.pinTab(at: index)

            tabBarViewController.presentPinnedTabsDiscoveryPopoverIfNecessary()
        }
    }

    @objc func mergeAllWindows(_ sender: Any?) {
        guard let mainWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController else { return }
        assert(!self.isBurner)

        let otherWindowControllers = Application.appDelegate.windowControllersManager.mainWindowControllers.filter {
            $0 !== mainWindowController && $0.mainViewController.isBurner == false
        }
        let excludedWindowControllers = Application.appDelegate.windowControllersManager.mainWindowControllers.filter {
            $0 === mainWindowController || $0.mainViewController.isBurner == true
        }

        let otherMainViewControllers = otherWindowControllers.compactMap { $0.mainViewController }
        let otherTabCollectionViewModels = otherMainViewControllers.map { $0.tabCollectionViewModel }
        let otherTabs = otherTabCollectionViewModels.flatMap { $0.tabCollection.tabs }
        let otherLocalHistoryOfRemovedTabs = Set(otherTabCollectionViewModels.flatMap { $0.tabCollection.localHistoryOfRemovedTabs })

        WindowsManager.closeWindows(except: excludedWindowControllers.compactMap(\.window))

        tabCollectionViewModel.append(tabs: otherTabs, andSelect: false)
        tabCollectionViewModel.tabCollection.localHistoryOfRemovedTabs += otherLocalHistoryOfRemovedTabs
    }

    // MARK: - Printing

    @objc func printWebView(_ sender: Any?) {
        let pdfHUD = (sender as? NSMenuItem)?.pdfHudRepresentedObject // if printing a PDF (may be from a frame context menu)
        getActiveTabAndIndex()?.tab.print(pdfHUD: pdfHUD)
    }

    // MARK: - Saving

    @objc func saveAs(_ sender: Any) {
        let pdfHUD = (sender as? NSMenuItem)?.pdfHudRepresentedObject // if saving a PDF (may be from a frame context menu)
        getActiveTabAndIndex()?.tab.saveWebContent(pdfHUD: pdfHUD, location: .prompt)
    }

    // MARK: - Debug

    @objc func addDebugTabs(_ sender: AnyObject) {
        let numberOfTabs = sender.representedObject as? Int ?? 1
        (1...numberOfTabs).forEach { _ in
            let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .ui))
            tabCollectionViewModel.append(tab: tab)
        }
    }

    @objc func debugResetContinueSetup(_ sender: Any?) {
        let persistor = AppearancePreferencesUserDefaultsPersistor(keyValueStore: NSApp.delegateTyped.keyValueStore)
        persistor.continueSetUpCardsLastDemonstrated = nil
        persistor.continueSetUpCardsNumberOfDaysDemonstrated = 0
        NSApp.delegateTyped.appearancePreferences.isContinueSetUpCardsViewOutdated = false
        NSApp.delegateTyped.appearancePreferences.continueSetUpCardsClosed = false
        NSApp.delegateTyped.appearancePreferences.isContinueSetUpVisible = true
        HomePage.Models.ContinueSetUpModel.Settings().clear()
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
    }

    @objc func debugShiftNewTabOpeningDate(_ sender: Any?) {
        let persistor = AppearancePreferencesUserDefaultsPersistor(keyValueStore: NSApp.delegateTyped.keyValueStore)
        persistor.continueSetUpCardsLastDemonstrated = (persistor.continueSetUpCardsLastDemonstrated ?? Date()).addingTimeInterval(-.day)
        NSApp.delegateTyped.appearancePreferences.continueSetUpCardsViewDidAppear()
    }

    @objc func debugShiftNewTabOpeningDateNtimes(_ sender: Any?) {
        for _ in 0..<AppearancePreferences.Constants.dismissNextStepsCardsAfterDays {
            debugShiftNewTabOpeningDate(sender)
        }
    }

    @objc func crashOnException(_ sender: Any?) {
        DispatchQueue.main.async {
            self.navigationBarViewController.addressBarViewController?.addressBarTextField.suggestionViewController.tableView.view(atColumn: 1, row: .max, makeIfNecessary: false)
        }
    }

    @objc func toggleWatchdog(_ sender: Any?) {
        if Self.watchdog.isRunning {
            Self.watchdog.stop()
        } else {
            Self.watchdog.start()
        }
    }

    @objc func simulate15SecondHang() {
        DispatchQueue.main.async {
            print("Simulating main thread hang...")
            sleep(15)
            print("Main thread is unblocked")
        }
    }

    @objc func resetPinnedTabs(_ sender: Any?) {
        if tabCollectionViewModel.selectedTabIndex?.isPinnedTab == true, tabCollectionViewModel.tabCollection.tabs.count > 0 {
            tabCollectionViewModel.select(at: .unpinned(0))
        }
        Application.appDelegate.resetPinnedTabs(sender)
    }

    @objc func showSaveCredentialsPopover(_ sender: Any?) {
#if DEBUG || REVIEW
        NotificationCenter.default.post(name: .ShowSaveCredentialsPopover, object: nil)
#endif
    }

    @objc func showCredentialsSavedPopover(_ sender: Any?) {
#if DEBUG || REVIEW
        NotificationCenter.default.post(name: .ShowCredentialsSavedPopover, object: nil)
#endif
    }

    /// debug menu popup window test
    @objc func showPopUpWindow(_ sender: Any?) {
        let tab = Tab(content: .url(.duckDuckGo, source: .ui),
                      webViewConfiguration: WKWebViewConfiguration(),
                      parentTab: nil,
                      canBeClosedWithBack: false,
                      webViewSize: .zero)

        WindowsManager.openPopUpWindow(with: tab, origin: nil, contentSize: nil)
    }

    @objc func removeUserScripts(_ sender: Any?) {
        tabCollectionViewModel.selectedTab?.userContentController?.cleanUpBeforeClosing()
        tabCollectionViewModel.selectedTab?.reload()
        Logger.general.info("User scripts removed from the current tab")
    }

    @available(macOS 13.5, *)
    @objc func showAllCredentials(_ sender: Any?) {
        let hostingView = NSHostingView(rootView: AutofillCredentialsDebugView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.frame.size = hostingView.intrinsicContentSize

        let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1400, height: 700),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)

        window.center()
        window.title = "Credentials"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Developer Tools

    @objc func toggleDeveloperTools(_ sender: Any?) {
        guard let webView = browserTabViewController.webView else {
            return
        }

        if webView.isInspectorShown == true {
            webView.closeDeveloperTools()
        } else {
            webView.openDeveloperTools()
        }
    }

    @objc func openJavaScriptConsole(_ sender: Any?) {
        browserTabViewController.webView?.openJavaScriptConsole()
    }

    @objc func showPageSource(_ sender: Any?) {
        browserTabViewController.webView?.showPageSource()
    }

    @objc func showPageResources(_ sender: Any?) {
        browserTabViewController.webView?.showPageSource()
    }
}

extension MainViewController: NSMenuItemValidation {

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard fireViewController.fireViewModel.fire.burningData == nil else {
            return true
        }
        switch menuItem.action {
        // Back/Forward
        case #selector(MainViewController.back(_:)):
            return activeTabViewModel?.canGoBack == true
        case #selector(MainViewController.forward(_:)):
            return activeTabViewModel?.canGoForward == true

        case #selector(MainViewController.stopLoadingPage(_:)):
            return activeTabViewModel?.isLoading == true

        case #selector(MainViewController.reloadPage(_:)):
            return activeTabViewModel?.canReload == true

        // Find In Page
        case #selector(findInPage),
             #selector(findInPageNext),
             #selector(findInPagePrevious):
            return activeTabViewModel?.canFindInPage == true // must have content loaded
                && view.window?.isKeyWindow == true // disable in video full screen

        case #selector(findInPageDone):
            return getActiveTabAndIndex()?.tab.findInPage?.isActive == true

        // Zoom
        case #selector(MainViewController.zoomIn(_:)):
            return getActiveTabAndIndex()?.tab.webView.canZoomIn == true
        case #selector(MainViewController.zoomOut(_:)):
            return getActiveTabAndIndex()?.tab.webView.canZoomOut == true
        case #selector(MainViewController.actualSize(_:)):
            return getActiveTabAndIndex()?.tab.webView.canZoomToActualSize == true ||
            getActiveTabAndIndex()?.tab.webView.canResetMagnification == true

        // Bookmarks
        case #selector(MainViewController.bookmarkThisPage(_:)),
             #selector(MainViewController.favoriteThisPage(_:)):
            return activeTabViewModel?.canBeBookmarked == true
        case #selector(MainViewController.bookmarkAllOpenTabs(_:)):
            return tabCollectionViewModel.canBookmarkAllOpenTabs()
        case #selector(MainViewController.openBookmark(_:)),
             #selector(MainViewController.showManageBookmarks(_:)):
            return true

        // Pin Tab
        case #selector(MainViewController.pinOrUnpinTab(_:)):
            guard getActiveTabAndIndex()?.tab.isUrl == true,
                  tabCollectionViewModel.pinnedTabsManager != nil,
                  !isBurner
            else {
                return false
            }
            if tabCollectionViewModel.selectionIndex?.isUnpinnedTab == true {
                menuItem.title = UserText.pinTab
                return true
            }
            if tabCollectionViewModel.selectionIndex?.isPinnedTab == true {
                menuItem.title = UserText.unpinTab
                return true
            }
            return false

        // Save Content
        case #selector(MainViewController.saveAs(_:)):
            return activeTabViewModel?.canSaveContent == true

        // Printing
        case #selector(MainViewController.printWebView(_:)):
            return activeTabViewModel?.canPrint == true

        // Merge all windows
        case #selector(MainViewController.mergeAllWindows(_:)):
            return Application.appDelegate.windowControllersManager.mainWindowControllers.filter({ !$0.mainViewController.isBurner }).count > 1 && !self.isBurner

        // Move Tab to New Window, Select Next/Prev Tab
        case #selector(MainViewController.moveTabToNewWindow(_:)):
            return tabCollectionViewModel.tabCollection.tabs.count > 1 && tabCollectionViewModel.selectionIndex?.isUnpinnedTab == true

        case #selector(MainViewController.showNextTab(_:)),
             #selector(MainViewController.showPreviousTab(_:)):
            return tabCollectionViewModel.allTabsCount > 1

        // Developer Tools
        case #selector(MainViewController.toggleDeveloperTools(_:)):
            let isInspectorShown = getActiveTabAndIndex()?.tab.webView.isInspectorShown ?? false
            menuItem.title = isInspectorShown ? UserText.closeDeveloperTools : UserText.openDeveloperTools
            fallthrough
        case #selector(MainViewController.openJavaScriptConsole(_:)),
             #selector(MainViewController.showPageSource(_:)),
             #selector(MainViewController.showPageResources(_:)):
            let canReload = activeTabViewModel?.canReload == true
            let isHTMLNewTabPage = activeTabViewModel?.tab.content == .newtab && !isBurner
            let isHistoryView = featureFlagger.isFeatureOn(.historyView) && activeTabViewModel?.tab.content == .history
            return canReload || isHTMLNewTabPage || isHistoryView

        case #selector(MainViewController.toggleDownloads(_:)):
            let isDownloadsPopoverShown = self.navigationBarViewController.isDownloadsPopoverShown
            menuItem.title = isDownloadsPopoverShown ? UserText.closeDownloads : UserText.openDownloads

            return true

        default:
            return true
        }
    }
}

extension AppDelegate: NSMenuItemValidation {

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(AppDelegate.closeAllWindows(_:)):
            return !Application.appDelegate.windowControllersManager.mainWindowControllers.isEmpty

        // Reopen Last Removed Tab
        case #selector(AppDelegate.reopenLastClosedTab(_:)):
            return RecentlyClosedCoordinator.shared.canReopenRecentlyClosedTab == true

        // Reopen All Windows From Last Session
        case #selector(AppDelegate.reopenAllWindowsFromLastSession(_:)):
            return stateRestorationManager.canRestoreLastSessionState

        // Enables and disables export bookmarks items
        case #selector(AppDelegate.openExportBookmarks(_:)):
            return bookmarkManager.list?.totalBookmarks != 0

        // Enables and disables export passwords items
        case #selector(AppDelegate.openExportLogins(_:)):
            return areTherePasswords

#if FEEDBACK
        case #selector(AppDelegate.openReportBrokenSite(_:)):
            return Application.appDelegate.windowControllersManager.selectedTab?.canReload ?? false
#endif
        default:
            return true
        }
    }

    private var areTherePasswords: Bool {
        let vault = try? AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter.shared)
        guard let vault else {
            return false
        }
        let accounts = (try? vault.accounts()) ?? []
        if !accounts.isEmpty {
            return true
        }
        let cards = (try? vault.creditCards()) ?? []
        if !cards.isEmpty {
            return true
        }
        let notes = (try? vault.notes()) ?? []
        if !notes.isEmpty {
            return true
        }
        let identities = (try? vault.identities()) ?? []
        if !identities.isEmpty {
            return true
        }
        return false
    }

}

extension MainViewController: FindInPageDelegate {

    @objc func findInPage(_ sender: Any) {
        activeTabViewModel?.showFindInPage()
    }

    @objc func findInPageNext(_ sender: Any) {
        activeTabViewModel?.findInPageNext()
    }

    @objc func findInPagePrevious(_ sender: Any) {
        activeTabViewModel?.findInPagePrevious()
    }

    @objc func findInPageDone(_ sender: Any) {
        activeTabViewModel?.closeFindInPage()
    }

}

extension AppDelegate: PrivacyDashboardViewControllerSizeDelegate {

    func privacyDashboardViewControllerDidChange(size: NSSize) {
        privacyDashboardWindow?.setFrame(NSRect(origin: .zero, size: size), display: true, animate: false)
    }
}

extension NSMenuItem {

    var pdfHudRepresentedObject: WKPDFHUDViewWrapper? {
        guard let representedObject = representedObject else { return nil }

        return representedObject as? WKPDFHUDViewWrapper ?? {
            assertionFailure("Unexpected SaveAs/Print menu item represented object: \(representedObject)")
            return nil
        }()
    }

}
