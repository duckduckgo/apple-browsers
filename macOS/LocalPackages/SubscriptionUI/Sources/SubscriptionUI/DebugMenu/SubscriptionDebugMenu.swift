//
//  SubscriptionDebugMenu.swift
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

import AppKit
import Subscription
import StoreKit

public final class SubscriptionDebugMenu: NSMenuItem {

    var currentEnvironment: SubscriptionEnvironment
    var updateServiceEnvironment: (SubscriptionEnvironment.ServiceEnvironment) -> Void
    var updatePurchasingPlatform: (SubscriptionEnvironment.PurchasePlatform) -> Void
    var updateCustomBaseSubscriptionURL: (URL?) -> Void
    var openSubscriptionTab: (URL) -> Void

    private var purchasePlatformItem: NSMenuItem?
    private var regionOverrideItem: NSMenuItem?

    var currentViewController: () -> NSViewController?

    let subscriptionAuthV1toV2Bridge: any SubscriptionAuthV1toV2Bridge
    let subscriptionManagerV1: (any SubscriptionManager)!
    let subscriptionManagerV2: (any SubscriptionManagerV2)!
    var accountManager: AccountManager {
        return subscriptionManagerV1.accountManager
    }

    let subscriptionUserDefaults: UserDefaults
    let isAuthV2Enabled: Bool

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    public init(currentEnvironment: SubscriptionEnvironment,
                updateServiceEnvironment: @escaping (SubscriptionEnvironment.ServiceEnvironment) -> Void,
                updatePurchasingPlatform: @escaping (SubscriptionEnvironment.PurchasePlatform) -> Void,
                updateCustomBaseSubscriptionURL: @escaping (URL?) -> Void,
                currentViewController: @escaping () -> NSViewController?,
                openSubscriptionTab: @escaping (URL) -> Void,
                subscriptionAuthV1toV2Bridge: any SubscriptionAuthV1toV2Bridge,
                subscriptionManagerV1: (any SubscriptionManager)?,
                subscriptionManagerV2: (any SubscriptionManagerV2)?,
                subscriptionUserDefaults: UserDefaults,
                isAuthV2Enabled: Bool) {
        self.currentEnvironment = currentEnvironment
        self.updateServiceEnvironment = updateServiceEnvironment
        self.updatePurchasingPlatform = updatePurchasingPlatform
        self.updateCustomBaseSubscriptionURL = updateCustomBaseSubscriptionURL
        self.currentViewController = currentViewController
        self.openSubscriptionTab = openSubscriptionTab
        self.subscriptionAuthV1toV2Bridge = subscriptionAuthV1toV2Bridge
        self.subscriptionManagerV1 = subscriptionManagerV1
        self.subscriptionManagerV2 = subscriptionManagerV2
        self.subscriptionUserDefaults = subscriptionUserDefaults
        self.isAuthV2Enabled = isAuthV2Enabled
        super.init(title: "Subscription", action: nil, keyEquivalent: "")
        self.submenu = makeSubmenu()
    }

    private func makeSubmenu() -> NSMenu {
        let menu = NSMenu(title: "")

        menu.addItem(NSMenuItem(title: "I Have a Subscription", action: #selector(activateSubscription), target: self))
        menu.addItem(NSMenuItem(title: "Remove Subscription From This Device", action: #selector(signOut), target: self))
        menu.addItem(NSMenuItem(title: "Show Account Details", action: #selector(showAccountDetails), target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Validate Token", action: #selector(validateToken), target: self))
        menu.addItem(NSMenuItem(title: "Check Entitlements", action: #selector(checkEntitlements), target: self))
        menu.addItem(NSMenuItem(title: "Get Subscription Details", action: #selector(getSubscriptionDetails), target: self))

        if #available(macOS 12.0, *) {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Sync App Store AppleID Account (re- sign-in)", action: #selector(syncAppleIDAccount), target: self))
            menu.addItem(NSMenuItem(title: "Purchase Subscription from App Store", action: #selector(showPurchaseView), target: self))
            menu.addItem(NSMenuItem(title: "Restore Subscription from App Store transaction", action: #selector(restorePurchases), target: self))
        }

        menu.addItem(.separator())

        let purchasePlatformItem = NSMenuItem(title: "Purchase platform", action: nil, target: nil)
        menu.addItem(purchasePlatformItem)
        self.purchasePlatformItem = purchasePlatformItem

        let environmentItem = NSMenuItem(title: "Environment", action: nil, target: nil)
        environmentItem.submenu = makeEnvironmentSubmenu()
        menu.addItem(environmentItem)

        let customBaseSubscriptionURLItem = NSMenuItem(title: "Custom Base Subscription URL", action: nil, target: nil)
        customBaseSubscriptionURLItem.submenu = makeCustomBaseSubscriptionURLSubmenu()
        menu.addItem(customBaseSubscriptionURLItem)

        menu.addItem(.separator())
        let storefrontID = SKPaymentQueue.default().storefront?.identifier ?? "nil"
        menu.addItem(NSMenuItem(title: "Storefront ID: \(storefrontID)", action: nil, target: nil))
        let storefrontCountryCode = SKPaymentQueue.default().storefront?.countryCode ?? "nil"
        menu.addItem(NSMenuItem(title: "Storefront Country Code: \(storefrontCountryCode)", action: nil, target: nil))

        let regionOverrideItem = NSMenuItem(title: "Region override for App Store Sandbox", action: nil, target: nil)
        menu.addItem(regionOverrideItem)
        self.regionOverrideItem = regionOverrideItem

        menu.delegate = self

        return menu
    }

    private func makePurchasePlatformSubmenu() -> NSMenu {
        let menu = NSMenu(title: "Select purchase platform:")
        let appStoreItem = NSMenuItem(title: "App Store", action: #selector(setPlatformToAppStore), target: self)
        if currentEnvironment.purchasePlatform == .appStore {
            appStoreItem.state = .on
            appStoreItem.isEnabled = false
            appStoreItem.action = nil
            appStoreItem.target = nil
        }
        menu.addItem(appStoreItem)

        let stripeItem = NSMenuItem(title: "Stripe", action: #selector(setPlatformToStripe), target: self)
        if currentEnvironment.purchasePlatform == .stripe {
            stripeItem.state = .on
            stripeItem.isEnabled = false
            stripeItem.action = nil
            stripeItem.target = nil
        }
        menu.addItem(stripeItem)

        menu.addItem(.separator())

        let disclaimerItem = NSMenuItem(title: "⚠️ App restart required! The changes are persistent", action: nil, target: nil)
        menu.addItem(disclaimerItem)

        return menu
    }

    private func makeEnvironmentSubmenu() -> NSMenu {
        let menu = NSMenu(title: "Select environment:")

        let stagingItem = NSMenuItem(title: "Staging", action: #selector(setEnvironmentToStaging), target: self)
        let isStaging = currentEnvironment.serviceEnvironment == .staging
        stagingItem.state = isStaging ? .on : .off
        if isStaging {
            stagingItem.isEnabled = false
            stagingItem.action = nil
            stagingItem.target = nil
        }
        menu.addItem(stagingItem)

        let productionItem = NSMenuItem(title: "Production", action: #selector(setEnvironmentToProduction), target: self)
        let isProduction = currentEnvironment.serviceEnvironment == .production
        productionItem.state = isProduction ? .on : .off
        if isProduction {
            productionItem.isEnabled = false
            productionItem.action = nil
            productionItem.target = nil
        }
        menu.addItem(productionItem)

        let disclaimerItem = NSMenuItem(title: "⚠️ App restart required! The changes are persistent", action: nil, target: nil)
        menu.addItem(disclaimerItem)

        return menu
    }

    private func makeCustomBaseSubscriptionURLSubmenu() -> NSMenu {
        let menu = NSMenu(title: "Set custom base subscription URL:")

        let customURLString = currentEnvironment.customBaseSubscriptionURL?.absoluteString ?? " -"
        menu.addItem(withTitle: "Custom URL: \(customURLString)", action: nil, keyEquivalent: "")

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Update custom base subscription URL", action: #selector(setCustomBaseSubscriptionURL), target: self))
        menu.addItem(NSMenuItem(title: "Reset configuration to default", action: #selector(resetCustomBaseSubscriptionURL), target: self))

        let disclaimerItem = NSMenuItem(title: "⚠️ App restart required! The changes are persistent", action: nil, target: nil)
        menu.addItem(disclaimerItem)

        return menu
    }

    private func makeRegionOverrideItemSubmenu() -> NSMenu {
        let menu = NSMenu(title: "")

        let currentRegionOverride = subscriptionUserDefaults.storefrontRegionOverride

        let usaItem = NSMenuItem(title: "USA", action: #selector(setRegionOverrideToUSA), target: self)
        if currentRegionOverride == .usa {
            usaItem.state = .on
            usaItem.isEnabled = false
            usaItem.action = nil
            usaItem.target = nil
        }
        menu.addItem(usaItem)

        let rowItem = NSMenuItem(title: "Rest of World", action: #selector(setRegionOverrideToROW), target: self)
        if currentRegionOverride == .restOfWorld {
            rowItem.state = .on
            rowItem.isEnabled = false
            rowItem.action = nil
            rowItem.target = nil
        }
        menu.addItem(rowItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: "Clear storefront region override", action: #selector(clearRegionOverride), target: self)
        menu.addItem(clearItem)

        return menu
    }

    private func refreshSubmenu() {
        self.submenu = makeSubmenu()
    }

    @objc
    func activateSubscription() {
        let url = subscriptionAuthV1toV2Bridge.url(for: .activationFlow)
        openSubscriptionTab(url)
    }

    @objc
    func signOut() {
        Task {
            await subscriptionAuthV1toV2Bridge.signOut(notifyUI: true)
        }
    }

    @objc
    func showAccountDetails() {
        if !isAuthV2Enabled {
            showAccountDetailsV1()
        } else {
            showAccountDetailsV2()
        }
    }

    @objc
    func showAccountDetailsV1() {
        let title = accountManager.isUserAuthenticated ? "Authenticated" : "Not Authenticated"
        let message = accountManager.isUserAuthenticated ? ["AuthToken: \(accountManager.authToken ?? "")",
                                                                                  "AccessToken: \(accountManager.accessToken ?? "")",
                                                                                  "Email: \(accountManager.email ?? "")"].joined(separator: "\n") : nil
        showAlert(title: title, message: message)
    }

    @objc
    func showAccountDetailsV2() {
        Task {
            let title = subscriptionManagerV2.isUserAuthenticated ? "Authenticated" : "Not Authenticated"
            let tokenContainer = try? await subscriptionManagerV2.getTokenContainer(policy: .local)
            let message = subscriptionManagerV2.isUserAuthenticated ? ["External ID: \(tokenContainer?.decodedAccessToken.externalID ?? "")",
                                                                     "\(tokenContainer!.debugDescription)",
                                                                     "Email: \(subscriptionManagerV2.userEmail ?? "")"].joined(separator: "\n") : nil
            showAlert(title: title, message: message)
        }
    }

    @objc
    func validateToken() {
        if !isAuthV2Enabled {
            validateTokenV1()
        } else {
            validateTokenV2()
        }
    }

    @objc
    func validateTokenV1() {
        Task {
            guard let token = accountManager.accessToken else { return }
            switch await subscriptionManagerV1.authEndpointService.validateToken(accessToken: token) {
            case .success(let response):
                showAlert(title: "Validate token", message: "\(response)")
            case .failure(let error):
                showAlert(title: "Validate token", message: "\(error)")
            }
        }
    }

    @objc
    func validateTokenV2() {
        Task {
            do {
                let tokenContainer = try await subscriptionManagerV2.getTokenContainer(policy: .local)
                showAlert(title: "Valid token", message: tokenContainer.debugDescription)
            } catch {
                showAlert(title: "Validate token", message: "\(error)")
            }
        }
    }

    @objc
    func checkEntitlements() {
        if !isAuthV2Enabled {
            checkEntitlementsV1()
        } else {
            checkEntitlementsV2()
        }
    }

    @objc
    func checkEntitlementsV1() {
        Task {
            var results: [String] = []

            let entitlements: [Entitlement.ProductName] = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration]
            for entitlement in entitlements {
                if case let .success(result) = await accountManager.hasEntitlement(forProductName: entitlement, cachePolicy: .reloadIgnoringLocalCacheData) {
                    let resultSummary = "Entitlement check for \(entitlement.rawValue): \(result)"
                    results.append(resultSummary)
                    print(resultSummary)
                }
            }

            showAlert(title: "Check Entitlements", message: results.joined(separator: "\n"))
        }
    }

    @objc
    func checkEntitlementsV2() {
        Task {
            do {
                let productNames = Entitlement.ProductName.allCases
                let tokenContainer = try await subscriptionManagerV2.getTokenContainer(policy: .localValid)
                var descriptions: [String] = []

                for productName in productNames {
                    let featureEnabledDescription: String = await {
                        guard let isFeatureEnabled = try? await subscriptionManagerV2.isFeatureEnabled(productName) else {
                            return "error"
                        }

                        return String(describing: isFeatureEnabled)
                    }()

                    descriptions.append("\(productName.rawValue): \(featureEnabledDescription)")
                }

                showAlert(title: "Check Entitlements", message: descriptions.joined(separator: "\n"))
            } catch {
                showAlert(title: "Check Entitlements", message: "Error: \(error)")
            }
        }
    }

    @objc
    func getSubscriptionDetails() {
        if !isAuthV2Enabled {
            getSubscriptionDetailsV1()
        } else {
            getSubscriptionDetailsV2()
        }
    }

    @objc
    func getSubscriptionDetailsV1() {
        Task {
            guard let token = accountManager.accessToken else { return }
            switch await subscriptionManagerV1.subscriptionEndpointService.getSubscription(accessToken: token, cachePolicy: .reloadIgnoringLocalCacheData) {
            case .success(let response):
                showAlert(title: "Subscription info", message: "\(response)")
            case .failure(let error):
                showAlert(title: "Subscription info", message: "\(error)")
            }
        }
    }

    @objc
    func getSubscriptionDetailsV2() {
        Task {
            do {
                let subscription = try await subscriptionManagerV2.getSubscription(cachePolicy: .remoteFirst)
                showAlert(title: "Subscription info", message: subscription.debugDescription)
            } catch {
                showAlert(title: "Subscription info", message: "\(error)")
            }
        }
    }

    @available(macOS 12.0, *)
    @objc
    func syncAppleIDAccount() {
        if !isAuthV2Enabled {
            syncAppleIDAccountV1()
        } else {
            syncAppleIDAccountV2()
        }
    }

    @available(macOS 12.0, *)
    @objc
    func syncAppleIDAccountV1() {
        Task { @MainActor in
            try? await subscriptionManagerV1.storePurchaseManager().syncAppleIDAccount()
        }
    }

    @available(macOS 12.0, *)
    @objc
    func syncAppleIDAccountV2() {
        Task { @MainActor in
            try? await subscriptionManagerV2.storePurchaseManager().syncAppleIDAccount()
        }
    }

    @IBAction func showPurchaseView(_ sender: Any?) {
        if !isAuthV2Enabled {
            showPurchaseViewV1(sender)
        } else {
            showPurchaseViewV2(sender)
        }
    }

    @IBAction func showPurchaseViewV1(_ sender: Any?) {
        if #available(macOS 12.0, *) {
            let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: accountManager,
                                                                 storePurchaseManager: subscriptionManagerV1.storePurchaseManager(),
                                                                 subscriptionEndpointService: subscriptionManagerV1.subscriptionEndpointService,
                                                                 authEndpointService: subscriptionManagerV1.authEndpointService)
            let appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionEndpointService: subscriptionManagerV1.subscriptionEndpointService,
                                                                   storePurchaseManager: subscriptionManagerV1.storePurchaseManager(),
                                                                   accountManager: subscriptionManagerV1.accountManager,
                                                                   appStoreRestoreFlow: appStoreRestoreFlow,
                                                                   authEndpointService: subscriptionManagerV1.authEndpointService)
            // swiftlint:disable:next force_cast
            let vc = DebugPurchaseViewController(storePurchaseManager: subscriptionManagerV1.storePurchaseManager() as! DefaultStorePurchaseManager, appStorePurchaseFlow: appStorePurchaseFlow)
            currentViewController()?.presentAsSheet(vc)
        }
    }

    @IBAction func showPurchaseViewV2(_ sender: Any?) {
        if #available(macOS 12.0, *) {
            let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManagerV2,
                                                                 storePurchaseManager: subscriptionManagerV2.storePurchaseManager())
            let appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(subscriptionManager: subscriptionManagerV2,
                                                                   storePurchaseManager: subscriptionManagerV2.storePurchaseManager(),
                                                                   appStoreRestoreFlow: appStoreRestoreFlow)
            // swiftlint:disable:next force_cast
            let vc = DebugPurchaseViewControllerV2(storePurchaseManager: subscriptionManagerV2.storePurchaseManager() as! DefaultStorePurchaseManagerV2,
                                                   appStorePurchaseFlow: appStorePurchaseFlow)
            currentViewController()?.presentAsSheet(vc)
        }
    }

    // MARK: - Platform

    @IBAction func setPlatformToAppStore(_ sender: Any?) {
        askAndUpdatePlatform(to: .appStore)
    }

    @IBAction func setPlatformToStripe(_ sender: Any?) {
        askAndUpdatePlatform(to: .stripe)
    }

    private func askAndUpdatePlatform(to newPlatform: SubscriptionEnvironment.PurchasePlatform) {
        let alert = makeAlert(title: "Are you sure you want to change the purchase platform to \(newPlatform.rawValue.capitalized)",
                              message: "This setting IS persisted between app runs. This action will close the app, do you want to proceed?",
                              buttonNames: ["Yes", "No"])
        let response = alert.runModal()
        guard case .alertFirstButtonReturn = response else { return }
        updatePurchasingPlatform(newPlatform)
        closeTheApp()
    }

    // MARK: - Environment

    @IBAction func setEnvironmentToStaging(_ sender: Any?) {
        askAndUpdateServiceEnvironment(to: SubscriptionEnvironment.ServiceEnvironment.staging)
    }

    @IBAction func setEnvironmentToProduction(_ sender: Any?) {
        askAndUpdateServiceEnvironment(to: SubscriptionEnvironment.ServiceEnvironment.production)
    }

    private func askAndUpdateServiceEnvironment(to newServiceEnvironment: SubscriptionEnvironment.ServiceEnvironment) {
        let alert = makeAlert(title: "Are you sure you want to change the environment to \(newServiceEnvironment.description.capitalized)",
                              message: """
                              Please make sure you have manually removed your current active Subscription and reset all related features.
                              You may also need to change environment of related features.
                              This setting IS persisted between app runs. This action will close the app, do you want to proceed?
                              """,
                              buttonNames: ["Yes", "No"])
        let response = alert.runModal()
        guard case .alertFirstButtonReturn = response else { return }
        updateServiceEnvironment(newServiceEnvironment)
        closeTheApp()
    }

    // MARK: - Custom base subscription URL

    @IBAction func setCustomBaseSubscriptionURL(_ sender: Any?) {
        let currentCustomBaseSubscriptionURL = currentEnvironment.customBaseSubscriptionURL?.absoluteString ?? ""
        let defaultBaseSubscriptionURL = SubscriptionURL.baseURL.subscriptionURL(environment: .production).absoluteString

        let alert = makeAlert(title: "Are you sure you want to change the base subscription URL?",
                              message: """
                                                  This setting IS persisted between app runs. The custom base subscription URL is used for front-end URLs. Custom URL is only used when internal user mode is enabled.

                                                  This action will close the app, do you want to proceed?
                              """,
                              buttonNames: ["Yes", "No"])

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byTruncatingTail
        textField.stringValue = currentCustomBaseSubscriptionURL
        textField.placeholderString = defaultBaseSubscriptionURL
        alert.accessoryView = textField
        alert.window.initialFirstResponder = alert.accessoryView
        textField.currentEditor()?.selectAll(nil)

        if alert.runModal() != .cancel {
            guard let textField = alert.accessoryView as? NSTextField,
                  let newURL = URL(string: textField.stringValue),
                  newURL != self.currentEnvironment.customBaseSubscriptionURL
            else {
                return
            }

            guard newURL.scheme != nil else {
                self.showAlert(title: "URL is missing a scheme")
                return
            }

            self.updateCustomBaseSubscriptionURL(newURL)
            closeTheApp()
        }
    }

    @IBAction func resetCustomBaseSubscriptionURL(_ sender: Any?) {
        let alert = makeAlert(title: "Are you sure you want to reset the base subscription URL?",
                              message: """
                                                  This setting IS persisted between app runs. The custom base subscription URL is used for front-end URLs. Custom URL is only used when internal user mode is enabled.

                                                  This action will close the app, do you want to proceed?
                              """,
                              buttonNames: ["Yes", "No"])
        let response = alert.runModal()
        guard case .alertFirstButtonReturn = response else { return }

        self.updateCustomBaseSubscriptionURL(nil)
        closeTheApp()
    }

    func closeTheApp() {
      NSApp.terminate(self)
    }

    // MARK: - Region override

    @IBAction func clearRegionOverride(_ sender: Any?) {
        updateRegionOverride(to: nil)
    }

    @IBAction func setRegionOverrideToUSA(_ sender: Any?) {
        updateRegionOverride(to: .usa)
    }

    @IBAction func setRegionOverrideToROW(_ sender: Any?) {
        updateRegionOverride(to: .restOfWorld)
    }

    private func updateRegionOverride(to region: SubscriptionRegion?) {
        self.subscriptionUserDefaults.storefrontRegionOverride = region

        if #available(macOS 12.0, *) {
            Task {
                if !isAuthV2Enabled {
                    await subscriptionManagerV1.storePurchaseManager().updateAvailableProducts()
                } else {
                    await subscriptionManagerV2.storePurchaseManager().updateAvailableProducts()
                }
            }
        }
    }

    // MARK: -

    @objc
    func restorePurchases(_ sender: Any?) {
        if !isAuthV2Enabled {
            restorePurchasesV1(sender)
        } else {
            restorePurchasesV2(sender)
        }
    }

    @objc
    func restorePurchasesV1(_ sender: Any?) {
        if #available(macOS 12.0, *) {
            Task {
                let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: subscriptionManagerV1.accountManager,
                                                                     storePurchaseManager: subscriptionManagerV1.storePurchaseManager(),
                                                                     subscriptionEndpointService: subscriptionManagerV1.subscriptionEndpointService,
                                                                     authEndpointService: subscriptionManagerV1.authEndpointService)
                await appStoreRestoreFlow.restoreAccountFromPastPurchase()
            }
        }
    }

    @objc
    func restorePurchasesV2(_ sender: Any?) {
        if #available(macOS 12.0, *) {
            Task {
                let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManagerV2,
                                                                       storePurchaseManager: subscriptionManagerV2.storePurchaseManager())
                await appStoreRestoreFlow.restoreAccountFromPastPurchase()
            }
        }
    }

    private func showAlert(title: String, message: String? = nil) {
        Task { @MainActor in
            let alert = makeAlert(title: title, message: message)
            alert.runModal()
        }
    }

    private func makeAlert(title: String, message: String? = nil, buttonNames: [String] = ["Ok"]) -> NSAlert{
        let alert = NSAlert()
        alert.messageText = title
        if let message = message {
            alert.informativeText = message
        }

        for buttonName in buttonNames {
            alert.addButton(withTitle: buttonName)
        }
        alert.accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 0))
        return alert
    }
}

extension NSAlert {
    static func customURLAlert(value: String?, placeholder: String?) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Set custom URL:"
        alert.addButton(withTitle: "Ok")
        alert.addButton(withTitle: "Cancel")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byTruncatingTail
        textField.stringValue = value ?? ""
        textField.placeholderString = placeholder
        alert.accessoryView = textField
        alert.window.initialFirstResponder = alert.accessoryView
        textField.currentEditor()?.selectAll(nil)
        return alert
    }
}

extension NSMenuItem {

    convenience init(title string: String, action selector: Selector?, target: AnyObject?, keyEquivalent charCode: String = "", representedObject: Any? = nil) {
        self.init(title: string, action: selector, keyEquivalent: charCode)
        self.target = target
        self.representedObject = representedObject
    }
}

extension SubscriptionDebugMenu: NSMenuDelegate {

    public func menuWillOpen(_ menu: NSMenu) {
        purchasePlatformItem?.submenu = makePurchasePlatformSubmenu()
        regionOverrideItem?.submenu = makeRegionOverrideItemSubmenu()
    }
}
