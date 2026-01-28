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
import BrowserServicesKit
import Common
import LoginItems
import NetworkProtectionProxy
import os.log
import PixelKit
import SwiftUI
import SwiftUIExtensions
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

    private let currentURLMenuItem = NSMenuItem(title: "Current URL:")

    private let productionURLMenuItem = NSMenuItem(title: "Use Production URL", action: #selector(DataBrokerProtectionDebugMenu.useWebUIProductionURL))
    private let customURLMenuItem = NSMenuItem(title: "Use Custom URL...", action: #selector(DataBrokerProtectionDebugMenu.useWebUICustomURL))

    private var databaseBrowserWindowController: NSWindowController?
    private var dataBrokerForceOptOutWindowController: NSWindowController?
    private var logMonitorWindowController: NSWindowController?
    private let currentEndpointMenuItem = NSMenuItem(title: "Current Endpoint:")
    private let defaultEndpointMenuItem = NSMenuItem(title: "Use Default Endpoint", action: #selector(DataBrokerProtectionDebugMenu.useDBPDefaultEndpoint))
    private let customEndpointMenuItem = NSMenuItem(title: "Use Custom Endpoint...", action: #selector(DataBrokerProtectionDebugMenu.useDBPCustomEndpoint))

    private let subscriptionEnvironmentMenuItem = NSMenuItem(title: "Subscription Environment:")
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
            subscriptionManager: Application.appDelegate.subscriptionManager)
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
            subscriptionEnvironmentMenuItem

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

                    menuItem(withTitle: "Run email confirmation operations",
                             action: #selector(DataBrokerProtectionDebugMenu.runEmailConfirmationOperations(_:)),
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

                    menuItem(withTitle: "Run email confirmation operations",
                             action: #selector(DataBrokerProtectionDebugMenu.runEmailConfirmationOperations(_:)),
                             representedObject: true)
                }
            }

            NSMenuItem(title: "Web UI") {
                currentURLMenuItem.isEnabled = false
                currentURLMenuItem

                productionURLMenuItem.targetting(self)
                customURLMenuItem.targetting(self)
            }

            NSMenuItem(title: "DBP API") {
                currentEndpointMenuItem.isEnabled = false
                currentEndpointMenuItem

                defaultEndpointMenuItem.targetting(self)
                customEndpointMenuItem.targetting(self)
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

            subscriptionEnvironmentMenuItem.isEnabled = false
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Menu State Update

    override func update() {
        updateWebUIMenuItemsState()
        updateServiceRootMenuItemState()
        updateSubscriptionEnvironmentMenuItem()
        updateShowStatusMenuIconMenu()
    }

    // MARK: - Menu functions

    @objc private func useWebUIProductionURL() {
        webUISettings.setURLType(.production)
        webUISettings.setCustomURL(webUISettings.productionURL)
    }

    @objc private func useWebUICustomURL() {
        let sheet = CustomTextEntrySheet(
            title: "Custom Web UI URL",
            fieldLabel: "Web UI URL",
            placeholder: "https://example.com/dbp",
            content: { _, isValid in
                Text(verbatim: "Enter a full URL for the web UI")
                    .dbpSecondaryTextStyle()
                if !isValid.wrappedValue {
                    Text(verbatim: "Please enter a valid URL.")
                        .foregroundColor(.red)
                }
            },
            onApply: { [weak self] value in
                let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: trimmedValue), url.isValid else { return false }
                self?.webUISettings.setCustomURL(trimmedValue)
                self?.webUISettings.setURLType(.custom)
                return true
            }
        )

        Task { @MainActor in
            sheet.show()
        }
    }

    // swiftlint:disable force_try
    @objc private func useDBPDefaultEndpoint() {
        settings.serviceRoot = ""
        forceBrokerJSONFilesUpdate()
    }

    @objc private func useDBPCustomEndpoint() {
        let sheet = CustomDBPEndpointSheet(
            onApply: { [weak self] value, removeBrokers in
                guard let self else { return false }
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
        )

        Task { @MainActor in
            sheet.show()
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

    @objc private func runEmailConfirmationOperations(_ sender: NSMenuItem) {
        Task {
            Logger.dataBrokerProtection.log("Running email confirmation operations...")
            let showWebView = sender.representedObject as? Bool ?? false

            await DataBrokerProtectionManager.shared.loginItemInterface.runEmailConfirmationOperations(showWebView: showWebView)
        }
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
        let authenticationManager = DataBrokerAuthenticationManagerBuilder.buildAuthenticationManager(subscriptionManager: Application.appDelegate.subscriptionManager)
        let viewController = DataBrokerRunCustomJSONViewController(authenticationManager: authenticationManager,
                                                                   featureFlagger: DBPFeatureFlagger(featureFlagger: Application.appDelegate.featureFlagger))
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
            eventPixels.fireWeeklyReportPixels(isAuthenticated: true)
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

    private func updateWebUIMenuItemsState() {
        productionURLMenuItem.state = webUISettings.selectedURLType == .custom ? .off : .on
        customURLMenuItem.state = webUISettings.selectedURLType == .custom ? .on : .off

        currentURLMenuItem.title = "Current URL: \(webUISettings.selectedURL)"
    }

    private func updateServiceRootMenuItemState() {
        currentEndpointMenuItem.title = "Current Endpoint: \(settings.endpointURL.absoluteString)"
        switch settings.selectedEnvironment {
        case .production:
            defaultEndpointMenuItem.title = "Use Default Endpoint (env: production)"
            defaultEndpointMenuItem.state = .on
            customEndpointMenuItem.state = .off
            customEndpointMenuItem.isEnabled = false
        case .staging:
            defaultEndpointMenuItem.title = "Use Default Endpoint (env: staging)"
            customEndpointMenuItem.isEnabled = true

            if settings.serviceRoot.isEmpty {
                defaultEndpointMenuItem.state = .on
                customEndpointMenuItem.state = .off
            } else {
                defaultEndpointMenuItem.state = .off
                customEndpointMenuItem.state = .on
            }
        }
    }

    func menuItem(withTitle title: String, action: Selector, representedObject: Any?) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = representedObject
        return menuItem
    }

    private func updateSubscriptionEnvironmentMenuItem() {
        let environmentText = settings.selectedEnvironment == .production ? "production" : "staging"
        subscriptionEnvironmentMenuItem.title = "Subscription environment: \(environmentText)"
    }

    private func updateShowStatusMenuIconMenu() {
        statusMenuIconMenu.state = settings.showInMenuBar ? .on : .off
    }
}

private struct CustomTextEntrySheet<Content: View>: ModalView {
    @State private var text = ""
    @State private var isValid = true
    @Environment(\.dismiss) private var dismiss

    let title: String
    let fieldLabel: String
    let placeholder: String
    let content: (Binding<String>, Binding<Bool>) -> Content
    let onApply: (String) -> Bool

    init(title: String,
         fieldLabel: String,
         placeholder: String,
         @ViewBuilder content: @escaping (Binding<String>, Binding<Bool>) -> Content,
         onApply: @escaping (String) -> Bool) {
        self.title = title
        self.fieldLabel = fieldLabel
        self.placeholder = placeholder
        self.content = content
        self.onApply = onApply
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: title)
                .fontWeight(.bold)

            Divider()

            HStack {
                Text(verbatim: fieldLabel)
                    .padding(.trailing, 10)
                Spacer()
                TextField(placeholder, text: $text)
                    .frame(width: 250)
                    .onChange(of: text) { _ in
                        isValid = true
                    }
            }

            content($text, $isValid)

            Divider()

            HStack(alignment: .center) {
                Spacer()
                Button(UserText.cancel) {
                    dismiss()
                }
                Button {
                    if onApply(text) {
                        dismiss()
                    } else {
                        isValid = false
                    }
                } label: {
                    Text(verbatim: "Apply")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
        .frame(width: 400)
    }
}

private struct CustomDBPEndpointSheet: ModalView {
    @State private var removeBrokers = false

    let onApply: (String, Bool) -> Bool

    init(onApply: @escaping (String, Bool) -> Bool) {
        self.onApply = onApply
    }

    var body: some View {
        CustomTextEntrySheet(
            title: "Custom Service Root",
            fieldLabel: "Service Root",
            placeholder: "branches/some-branch",
            content: { serviceRoot, _ in
                let trimmedServiceRoot = serviceRoot.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let baseURL = "https://dbp-staging.duckduckgo.com"
                let previewURL = trimmedServiceRoot.isEmpty
                    ? baseURL
                    : URL(string: baseURL)!.appending(trimmedServiceRoot).absoluteString

                Text(verbatim: "Preview: \(previewURL)")
                    .dbpSecondaryTextStyle()

                Toggle(isOn: $removeBrokers) {
                    Text(verbatim: "Remove existing brokers")
                }
                    .toggleStyle(.checkbox)

                Text(verbatim: "Please reopen PIR and trigger a new scan for the changes to show up.")
                    .dbpSecondaryTextStyle()
            },
            onApply: { value in
                return onApply(value.trimmingCharacters(in: .whitespacesAndNewlines), removeBrokers)
            }
        )
    }
}

private extension View {
    func dbpSecondaryTextStyle() -> some View {
        multilineText()
            .multilineTextAlignment(.leading)
            .fixMultilineScrollableText()
            .foregroundColor(.secondary)
    }
}

extension DataBrokerProtectionDebugMenu: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        databaseBrowserWindowController = nil
        dataBrokerForceOptOutWindowController = nil
        logMonitorWindowController = nil
    }
}
