//
//  DataBrokerProtectionDebugMenu.swift
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

import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import Foundation
import AppKit
import Common
import LoginItems
import NetworkProtectionProxy
import os.log
import PixelKit
import Subscription
import Configuration

final class DataBrokerProtectionDebugMenu: NSMenu {

    enum EnvironmentTitle: String {
      case staging = "Staging"
      case production = "Production"
    }

    private let waitlistTokenItem = NSMenuItem(title: "Waitlist Token:")
    private let waitlistTimestampItem = NSMenuItem(title: "Waitlist Timestamp:")
    private let waitlistInviteCodeItem = NSMenuItem(title: "Waitlist Invite Code:")
    private let waitlistTermsAndConditionsAcceptedItem = NSMenuItem(title: "T&C Accepted:")

    private let productionURLMenuItem = NSMenuItem(title: "Use Production URL", action: #selector(DataBrokerProtectionDebugMenu.useWebUIProductionURL))

    private let customURLMenuItem = NSMenuItem(title: "Use Custom URL", action: #selector(DataBrokerProtectionDebugMenu.useWebUICustomURL))

    private var databaseBrowserWindowController: NSWindowController?
    private var dataBrokerForceOptOutWindowController: NSWindowController?
    private var logMonitorWindowController: NSWindowController?
    private let customURLLabelMenuItem = NSMenuItem(title: "")
    private let customServiceRootLabelMenuItem = NSMenuItem(title: "")

    private let environmentMenu = NSMenu()
    private let statusMenuIconMenu = NSMenuItem(title: "Show Status Menu Icon", action: #selector(DataBrokerProtectionDebugMenu.toggleShowStatusMenuItem))

    private let webUISettings = DataBrokerProtectionWebUIURLSettings(.dbp)
    private let settings = DataBrokerProtectionSettings(defaults: .dbp)

    private lazy var eventPixels: DataBrokerProtectionEventPixels = {
        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(
            directoryName: DatabaseConstants.directoryName,
            fileName: DatabaseConstants.fileName,
            appGroupIdentifier: Bundle.main.appGroupName
        )
        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(
            appGroupName: Bundle.main.appGroupName,
            databaseFileURL: databaseURL
        )
        guard let vault = try? vaultFactory.makeVault(reporter: nil) else {
            fatalError("Failed to make secure storage vault for event pixels")
        }
        let pixelHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: PixelKit.shared!, platform: .macOS)
        let database = DataBrokerProtectionDatabase(
            fakeBrokerFlag: DataBrokerDebugFlagFakeBroker(),
            pixelHandler: pixelHandler,
            vault: vault,
            localBrokerService: brokerUpdater
        )
        return DataBrokerProtectionEventPixels(database: database, handler: pixelHandler)
    }()

    private lazy var brokerUpdater: BrokerJSONServiceProvider = {
        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)
        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: Bundle.main.appGroupName, databaseFileURL: databaseURL)
        guard let vault = try? vaultFactory.makeVault(reporter: nil) else {
            fatalError("Failed to make secure storage vault")
        }
        let authenticationManager = DataBrokerAuthenticationManagerBuilder.buildAuthenticationManager(
            subscriptionManager: Application.appDelegate.subscriptionAuthV1toV2Bridge)
        let featureFlagger = DBPFeatureFlagger(featureFlagger: Application.appDelegate.featureFlagger)

        return RemoteBrokerJSONService(featureFlagger: featureFlagger,
                                       settings: DataBrokerProtectionSettings(defaults: .dbp),
                                       vault: vault,
                                       authenticationManager: authenticationManager,
                                       localBrokerProvider: nil)
    }()

    init() {
        super.init(title: "Personal Information Removal")

        buildItems {
            NSMenuItem(title: "Environment")
                .submenu(environmentMenu)

            NSMenuItem(title: "Background Agent") {
                NSMenuItem(title: "Enable", action: #selector(DataBrokerProtectionDebugMenu.backgroundAgentEnable))
                    .targetting(self)

                NSMenuItem(title: "Disable", action: #selector(DataBrokerProtectionDebugMenu.backgroundAgentDisable))
                    .targetting(self)

                NSMenuItem(title: "Restart", action: #selector(DataBrokerProtectionDebugMenu.backgroundAgentRestart))
                    .targetting(self)

                NSMenuItem.separator()

                NSMenuItem(title: "Show agent IP address", action: #selector(DataBrokerProtectionDebugMenu.showAgentIPAddress))
                    .targetting(self)
            }

            NSMenuItem(title: "Operations") {
                NSMenuItem(title: "Hidden WebView") {
                    menuItem(withTitle: "Run queued operations",
                             action: #selector(DataBrokerProtectionDebugMenu.startScheduledOperations(_:)),
                             representedObject: false)

                    menuItem(withTitle: "Run scan operations",
                             action: #selector(DataBrokerProtectionDebugMenu.runScanOperations(_:)),
                             representedObject: false)

                    menuItem(withTitle: "Run opt-out operations",
                             action: #selector(DataBrokerProtectionDebugMenu.runOptoutOperations(_:)),
                             representedObject: false)
                }

                NSMenuItem(title: "Visible WebView") {
                    menuItem(withTitle: "Run queued operations",
                             action: #selector(DataBrokerProtectionDebugMenu.startScheduledOperations(_:)),
                             representedObject: true)

                    menuItem(withTitle: "Run scan operations",
                             action: #selector(DataBrokerProtectionDebugMenu.runScanOperations(_:)),
                             representedObject: true)

                    menuItem(withTitle: "Run opt-out operations",
                             action: #selector(DataBrokerProtectionDebugMenu.runOptoutOperations(_:)),
                             representedObject: true)
                }
            }

            NSMenuItem(title: "Web UI") {
                productionURLMenuItem.targetting(self)
                customURLMenuItem.targetting(self)

                NSMenuItem.separator()

                NSMenuItem(title: "Set Custom URL", action: #selector(DataBrokerProtectionDebugMenu.setWebUICustomURL))
                    .targetting(self)
                NSMenuItem(title: "Reset Custom URL", action: #selector(DataBrokerProtectionDebugMenu.resetCustomURL))
                    .targetting(self)

                customURLLabelMenuItem
            }

            NSMenuItem(title: "DBP API") {
                NSMenuItem(title: "Set Service Root", action: #selector(DataBrokerProtectionDebugMenu.setCustomServiceRoot))
                    .targetting(self)

                customServiceRootLabelMenuItem

                NSMenuItem(title: "⚠️ Please reopen PIR and trigger a new scan for the changes to show up", action: nil, target: nil)
            }

            NSMenuItem.separator()

            NSMenuItem(title: "Toggle VPN Bypass", action: #selector(DataBrokerProtectionDebugMenu.toggleVPNBypass))
                .targetting(self)
            NSMenuItem(title: "Reset VPN Bypass Onboarding", action: #selector(DataBrokerProtectionDebugMenu.resetVPNBypassOnboarding))
                .targetting(self)

            NSMenuItem.separator()

            statusMenuIconMenu.targetting(self)

            NSMenuItem(title: "Show DB Browser", action: #selector(DataBrokerProtectionDebugMenu.showDatabaseBrowser))
                .targetting(self)
            NSMenuItem(title: "Log Monitor", action: #selector(DataBrokerProtectionDebugMenu.openLogMonitor))
                .targetting(self)
            NSMenuItem(title: "Force Profile Removal", action: #selector(DataBrokerProtectionDebugMenu.showForceOptOutWindow))
                .targetting(self)
            NSMenuItem(title: "Force broker JSON files update", action: #selector(DataBrokerProtectionDebugMenu.forceBrokerJSONFilesUpdate))
                .targetting(self)
            NSMenuItem(title: "Test Firing Weekly Pixels", action: #selector(DataBrokerProtectionDebugMenu.testFireWeeklyPixels))
                .targetting(self)
            NSMenuItem(title: "Run Personal Information Removal Debug Mode", action: #selector(DataBrokerProtectionDebugMenu.runCustomJSON))
                .targetting(self)
            NSMenuItem(title: "Reset All State and Delete All Data", action: #selector(DataBrokerProtectionDebugMenu.deleteAllDataAndStopAgent))
                .targetting(self)

            populateDataBrokerProtectionEnvironmentListMenuItems()
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Menu State Update

    override func update() {
        updateWebUIMenuItemsState()
        updateServiceRootMenuItemState()
        updateEnvironmentMenu()
        updateShowStatusMenuIconMenu()
    }

    // MARK: - Menu functions

    @objc private func useWebUIProductionURL() {
        webUISettings.setURLType(.production)
    }

    @objc private func useWebUICustomURL() {
        webUISettings.setURLType(.custom)
        webUISettings.setCustomURL(webUISettings.productionURL)
    }

    @objc private func resetCustomURL() {
        webUISettings.setURLType(.production)
        webUISettings.setCustomURL(webUISettings.productionURL)
    }

    @objc private func setWebUICustomURL() {
        showCustomURLAlert { [weak self] value in

            guard let value = value, let url = URL(string: value), url.isValid else { return false }

            self?.webUISettings.setCustomURL(value)
            return true
        }
    }

    // swiftlint:disable force_try
    @objc private func setCustomServiceRoot() {
        showCustomServiceRootAlert { [weak self] value, removeBrokers in
            guard let value, let self else { return false }

            self.settings.serviceRoot = value

            if removeBrokers {
                let pixelHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: PixelKit.shared!, platform: .macOS)
                let privacyConfigManager = DBPPrivacyConfigurationManager()
                let reporter = DataBrokerProtectionSecureVaultErrorReporter(pixelHandler: pixelHandler, privacyConfigManager: privacyConfigManager)
                let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)
                let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: Bundle.main.appGroupName, databaseFileURL: databaseURL)
                let vault = try! vaultFactory.makeVault(reporter: reporter)
                let database = DataBrokerProtectionDatabase(fakeBrokerFlag: DataBrokerDebugFlagFakeBroker(),
                                                            pixelHandler: pixelHandler,
                                                            vault: vault,
                                                            localBrokerService: self.brokerUpdater)
                let dataManager = DataBrokerProtectionDataManager(database: database)
                try! dataManager.removeAllData()
            }

            self.forceBrokerJSONFilesUpdate()

            return true
        }
    }
    // swiftlint:enable force_try

    @objc private func startScheduledOperations(_ sender: NSMenuItem) {
        Logger.dataBrokerProtection.log("Running queued operations...")
        let showWebView = sender.representedObject as? Bool ?? false

        DataBrokerProtectionManager.shared.loginItemInterface.startScheduledOperations(showWebView: showWebView)
    }

    @objc private func runScanOperations(_ sender: NSMenuItem) {
        Logger.dataBrokerProtection.log("Running scan operations...")
        let showWebView = sender.representedObject as? Bool ?? false

        DataBrokerProtectionManager.shared.loginItemInterface.startImmediateOperations(showWebView: showWebView)
    }

    @objc private func runOptoutOperations(_ sender: NSMenuItem) {
        Logger.dataBrokerProtection.log("Running Optout operations...")
        let showWebView = sender.representedObject as? Bool ?? false

        DataBrokerProtectionManager.shared.loginItemInterface.runAllOptOuts(showWebView: showWebView)
    }

    @objc private func backgroundAgentRestart() {
        LoginItemsManager().restartLoginItems([LoginItem.dbpBackgroundAgent])
    }

    @objc private func backgroundAgentDisable() {
        LoginItemsManager().disableLoginItems([LoginItem.dbpBackgroundAgent])
        NotificationCenter.default.post(name: .dbpLoginItemDisabled, object: nil)
    }

    @objc private func backgroundAgentEnable() {
        LoginItemsManager().enableLoginItems([LoginItem.dbpBackgroundAgent])
        NotificationCenter.default.post(name: .dbpLoginItemEnabled, object: nil)
    }

    @objc private func deleteAllDataAndStopAgent() {
        Task { @MainActor in
            guard case .alertFirstButtonReturn = await NSAlert.removeAllDBPStateAndDataAlert().runModal() else { return }
            DataBrokerProtectionFeatureDisabler().disableAndDelete()
        }
    }

    @objc private func showDatabaseBrowser() {
        let viewController = DataBrokerDatabaseBrowserViewController(localBrokerService: brokerUpdater)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1300, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)

        window.contentViewController = viewController
        window.minSize = NSSize(width: 1300, height: 800)
        databaseBrowserWindowController = NSWindowController(window: window)
        databaseBrowserWindowController?.showWindow(nil)

        window.delegate = self
        window.center()
    }

    @objc private func showAgentIPAddress() {
        DataBrokerProtectionManager.shared.showAgentIPAddress()
    }

    @objc private func showForceOptOutWindow() {
        let viewController = DataBrokerForceOptOutViewController(localBrokerService: brokerUpdater)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)

        window.contentViewController = viewController
        window.minSize = NSSize(width: 500, height: 400)
        window.center()
        dataBrokerForceOptOutWindowController = NSWindowController(window: window)
        dataBrokerForceOptOutWindowController?.showWindow(nil)
        window.delegate = self
    }

    @objc private func openLogMonitor() {
        if logMonitorWindowController == nil {
            let viewController = DataBrokerLogMonitorViewController()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered,
                                  defer: false)

            window.contentViewController = viewController
            window.title = "DataBrokerProtection Log Monitor"
            window.minSize = NSSize(width: 1000, height: 650)
            logMonitorWindowController = NSWindowController(window: window)
            window.delegate = self

            // Center after setting up the controller to ensure proper sizing
            window.center()
        }

        logMonitorWindowController?.showWindow(self)
        logMonitorWindowController?.window?.makeKeyAndOrderFront(self)
    }

    @objc private func runCustomJSON() {
        let authenticationManager = DataBrokerAuthenticationManagerBuilder.buildAuthenticationManager(subscriptionManager: Application.appDelegate.subscriptionAuthV1toV2Bridge)
        let viewController = DataBrokerRunCustomJSONViewController(authenticationManager: authenticationManager)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)

        window.contentViewController = viewController
        window.minSize = NSSize(width: 500, height: 400)
        window.center()
        databaseBrowserWindowController = NSWindowController(window: window)
        databaseBrowserWindowController?.showWindow(nil)
        window.delegate = self
    }

    @objc private func forceBrokerJSONFilesUpdate() {
        Task {
            settings.resetBrokerDeliveryData()
            try await brokerUpdater.checkForUpdates(skipsLimiter: true)
        }
    }

    @objc private func testFireWeeklyPixels() {
        Task { @MainActor in
            eventPixels.fireWeeklyReportPixels()
        }
    }

    @objc private func toggleVPNBypass() {
        Task {
            await DataBrokerProtectionManager.shared.dataBrokerProtectionDataManagerWillApplyVPNBypassSetting(!VPNBypassService().isEnabled)
        }
    }

    @objc private func resetVPNBypassOnboarding() {
        DataBrokerProtectionSettings(defaults: .dbp).vpnBypassOnboardingShown = false
    }

    @objc private func toggleShowStatusMenuItem() {
        settings.showInMenuBar.toggle()
    }

    // MARK: - Utility Functions

    private func populateDataBrokerProtectionEnvironmentListMenuItems() {
        environmentMenu.items = [
            NSMenuItem(title: "⚠️ The environment can be set in the Subscription > Environment menu", action: nil, target: nil),
            NSMenuItem(title: EnvironmentTitle.production.rawValue, action: nil, target: nil, keyEquivalent: ""),
            NSMenuItem(title: EnvironmentTitle.staging.rawValue, action: nil, target: nil, keyEquivalent: ""),
        ]
    }

    func showCustomURLAlert(callback: @escaping (String?) -> Bool) {
        let alert = NSAlert()
        alert.messageText = "Enter URL"
        alert.addButton(withTitle: "Accept")
        alert.addButton(withTitle: "Cancel")

        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = inputTextField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if !callback(inputTextField.stringValue) {
                let invalidAlert = NSAlert()
                invalidAlert.messageText = "Invalid URL"
                invalidAlert.informativeText = "Please enter a valid URL."
                invalidAlert.addButton(withTitle: "OK")
                invalidAlert.runModal()
            }
        } else {
            _ = callback(nil)
        }
    }

    func showCustomServiceRootAlert(callback: @escaping (String?, Bool) -> Bool) {
        let alert = NSAlert()
        alert.messageText = "Enter custom service root (staging environment only)"
        alert.informativeText = "Leave blank for default"
        alert.addButton(withTitle: "Accept")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Remove existing brokers"

        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputTextField.placeholderString = "branches/some-branch"
        alert.accessoryView = inputTextField

        let shouldRemoveBrokers = alert.suppressionButton?.state == .on

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if !callback(inputTextField.stringValue, shouldRemoveBrokers) {
                let invalidAlert = NSAlert()
                invalidAlert.messageText = "Invalid service root"
                invalidAlert.informativeText = "Please enter a valid service root."
                invalidAlert.addButton(withTitle: "OK")
                invalidAlert.runModal()
            }
        } else {
            _ = callback(nil, shouldRemoveBrokers)
        }
    }

    private func updateWebUIMenuItemsState() {
        productionURLMenuItem.state = webUISettings.selectedURLType == .custom ? .off : .on
        customURLMenuItem.state = webUISettings.selectedURLType == .custom ? .on : .off

        customURLLabelMenuItem.title = "Custom URL: [\(webUISettings.customURL ?? "")]"
    }

    private func updateServiceRootMenuItemState() {
        switch settings.selectedEnvironment {
        case .production:
            customServiceRootLabelMenuItem.title = "Production environment currently in used. Please change it to Staging to use a custom service root"
        case .staging:
            customServiceRootLabelMenuItem.title = "Endpoint URL: [\(settings.endpointURL)]"
        }
    }

    func menuItem(withTitle title: String, action: Selector, representedObject: Any?) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = representedObject
        return menuItem
    }

    private func updateEnvironmentMenu() {
        let selectedEnvironment = settings.selectedEnvironment
        guard environmentMenu.items.count == 3 else { return }

        environmentMenu.items[1].state = selectedEnvironment == .production ? .on: .off
        environmentMenu.items[2].state = selectedEnvironment == .staging ? .on: .off
    }

    private func updateShowStatusMenuIconMenu() {
        statusMenuIconMenu.state = settings.showInMenuBar ? .on : .off
    }
}

extension DataBrokerProtectionDebugMenu: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        databaseBrowserWindowController = nil
        dataBrokerForceOptOutWindowController = nil
        logMonitorWindowController = nil
    }
}
