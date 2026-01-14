//
//  SubscriptionDebugViewController.swift
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

import UIKit
import SwiftUI
import WebKit
import BrowserServicesKit
import Subscription
import Core
import VPN
import StoreKit
import PrivacyConfig
import Networking

final class SubscriptionDebugViewController: UITableViewController {

    private let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)
    private lazy var subscriptionUserDefaults = UserDefaults(suiteName: subscriptionAppGroup)!
    private let reporter: SubscriptionDataReporting

    private var subscriptionManagerV2: SubscriptionManagerV2 {
        AppDependencyProvider.shared.subscriptionManagerV2!
    }
    private var featureFlagger: FeatureFlagger {
        AppDependencyProvider.shared.featureFlagger
    }
    var currentEnvironment: SubscriptionEnvironment {
        AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge.currentEnvironment
    }

    init?(coder: NSCoder, subscriptionDataReporter: SubscriptionDataReporting) {
        self.reporter = subscriptionDataReporter
        super.init(coder: coder)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Use init(coder:subscriptionDataReporter:) instead")
    }

    private let titles = [
        Sections.authorization: "Authentication",
        Sections.api: "Make API Call",
        Sections.appstore: "App Store",
        Sections.environment: "Environment",
        Sections.customBaseSubscriptionURL: "Custom Base Subscription URL",
        Sections.pixels: "Promo Pixel Parameters",
        Sections.metadata: "StoreKit Metadata",
        Sections.regionOverride: "Region override for App Store Sandbox",
    ]

    enum Sections: Int, CaseIterable {
        case authorization
        case api
        case appstore
        case environment
        case customBaseSubscriptionURL
        case pixels
        case metadata
        case regionOverride
    }

    enum AuthorizationRows: Int, CaseIterable {
        case restoreSubscription
        case clearAuthData
        case showAccountDetails
    }

    enum SubscriptionRows: Int, CaseIterable {
        case validateToken
        case checkEntitlements
        case getSubscription
    }

    enum AppStoreRows: Int, CaseIterable {
        case syncAppStoreAccount
        case buyProductionSubscriptions
    }

    enum EnvironmentRows: Int, CaseIterable {
        case staging
        case production
    }

    enum CustomBaseSubscriptionURLRows: Int, CaseIterable {
        case current
        case reset
    }

    enum PixelsRows: Int, CaseIterable {
        case randomize
    }

    enum MetadataRows: Int, CaseIterable {
        case storefrontID
        case countryCode
    }

    enum RegionOverrideRows: Int, CaseIterable {
        case currentRegionOverride
    }

    private var storefrontID = "Loading"
    private var storefrontCountryCode = "Loading"

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Sections.allCases.count
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadStoreKitMetadata()
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Sections(rawValue: section) else { return nil }
        return titles[section]
    }

    var serviceEnvironment: SubscriptionEnvironment.ServiceEnvironment {
        return subscriptionManagerV2.currentEnvironment.serviceEnvironment
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        cell.textLabel?.textColor = UIColor.label
        cell.detailTextLabel?.text = nil
        cell.accessoryView = nil
        cell.accessoryType = .none

        switch Sections(rawValue: indexPath.section) {

        case .authorization:
            switch AuthorizationRows(rawValue: indexPath.row) {
            case .restoreSubscription:
                cell.textLabel?.text = "I Have a Subscription"
            case .clearAuthData:
                cell.textLabel?.text = "Remove Subscription From This Device"
            case .showAccountDetails:
                cell.textLabel?.text = "Show Account Details"
            case .none:
                break
            }

        case .api:
            switch SubscriptionRows(rawValue: indexPath.row) {
            case .validateToken:
                cell.textLabel?.text = "Validate Token"
            case .checkEntitlements:
                cell.textLabel?.text = "Check Entitlements"
            case .getSubscription:
                cell.textLabel?.text = "Get Subscription Details"

            case .none:
                break
            }


        case .appstore:
            switch AppStoreRows(rawValue: indexPath.row) {
            case .syncAppStoreAccount:
                cell.textLabel?.text = "Sync App Store Account"
            case .buyProductionSubscriptions:
                cell.textLabel?.text = "Change Tier"
                cell.accessoryType = .disclosureIndicator
            case .none:
                break
            }

        case .environment:
            let currentEnv = serviceEnvironment
            switch EnvironmentRows(rawValue: indexPath.row) {
            case .staging:
                cell.textLabel?.text = "Staging"
                cell.accessoryType = currentEnv == .staging ? .checkmark : .none
            case .production:
                cell.textLabel?.text = "Production"
                cell.accessoryType = currentEnv == .production ? .checkmark : .none
            case .none:
                break
            }

        case .customBaseSubscriptionURL:
            switch CustomBaseSubscriptionURLRows(rawValue: indexPath.row) {
            case .current:
                if let currentURL = currentEnvironment.customBaseSubscriptionURL {
                    cell.textLabel?.text = currentURL.absoluteString
                } else {
                    cell.textLabel?.text = " - "
                }

                cell.textLabel?.sizeToFit()
                cell.detailTextLabel?.sizeToFit()
                cell.textLabel?.numberOfLines = 0
            case .reset:
                cell.textLabel?.text = "Edit Custom URL"
                cell.textLabel?.textColor = UIColor(designSystemColor: .accent)
            case .none:
                break
            }


        case .pixels:
            switch PixelsRows(rawValue: indexPath.row) {
            case .randomize:
                cell.textLabel?.text = "Show Randomized Parameters"
            case .none:
                break
            }

        case .metadata:
            switch MetadataRows(rawValue: indexPath.row) {
            case .storefrontID:
                cell.textLabel?.text = "Storefront ID"
                cell.detailTextLabel?.text = storefrontID
            case .countryCode:
                cell.textLabel?.text = "Country Code"
                cell.detailTextLabel?.text = storefrontCountryCode
            case .none:
                break
            }

        case .regionOverride:
            switch RegionOverrideRows(rawValue: indexPath.row) {
            case .currentRegionOverride:
                cell.textLabel?.text = "Current override"

                let buttonConfiguration = UIButton.Configuration.plain()
                let button = UIButton(configuration: buttonConfiguration)

                let adjustMenuButtonWidth = {
                    button.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
                    button.sizeToFit()
                }

                let currentRegionOverride = subscriptionUserDefaults.storefrontRegionOverride

                button.menu = UIMenu(options: [.singleSelection], children: [
                    UIAction(title: "None", state: currentRegionOverride == nil ? .on : .off, handler: { [weak self] _ in
                        self?.subscriptionUserDefaults.storefrontRegionOverride = nil
                        adjustMenuButtonWidth()
                    }),
                    UIAction(title: "USA", state: currentRegionOverride == .usa ? .on : .off, handler: { [weak self] _ in
                        self?.subscriptionUserDefaults.storefrontRegionOverride = .usa
                        adjustMenuButtonWidth()
                    }),
                    UIAction(title: "Rest of World", state: currentRegionOverride == .restOfWorld ? .on : .off, handler: { [weak self] _ in
                        self?.subscriptionUserDefaults.storefrontRegionOverride = .restOfWorld
                        adjustMenuButtonWidth()
                    }),
                ])

                button.showsMenuAsPrimaryAction = true
                button.changesSelectionAsPrimaryAction = true

                cell.accessoryView = button
                adjustMenuButtonWidth()
            case .none:
                break
            }

        case .none:
            break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Sections(rawValue: section) {
        case .authorization: return AuthorizationRows.allCases.count
        case .api: return SubscriptionRows.allCases.count
        case .appstore: return AppStoreRows.allCases.count
        case .environment: return EnvironmentRows.allCases.count
        case .customBaseSubscriptionURL: return CustomBaseSubscriptionURLRows.allCases.count
        case .pixels: return PixelsRows.allCases.count
        case .metadata: return MetadataRows.allCases.count
        case .regionOverride: return RegionOverrideRows.allCases.count
        case .none: return 0
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Sections(rawValue: indexPath.section) {
        case .authorization:
            switch AuthorizationRows(rawValue: indexPath.row) {
            case .restoreSubscription: openSubscriptionRestoreFlow()
            case .clearAuthData: clearAuthData()
            case .showAccountDetails: showAccountDetails()
            default: break
            }
        case .appstore:
            switch AppStoreRows(rawValue: indexPath.row) {
            case .syncAppStoreAccount: syncAppleIDAccount()
            case .buyProductionSubscriptions: showBuyProductionSubscriptions()
            default: break
            }
        case .api:
            switch SubscriptionRows(rawValue: indexPath.row) {
            case .validateToken: validateToken()
            case .checkEntitlements: checkEntitlements()
            case .getSubscription: getSubscriptionDetails()
            default: break
            }
        case .environment:
            guard let subEnv: EnvironmentRows = EnvironmentRows(rawValue: indexPath.row) else { return }
            changeSubscriptionEnvironment(envRows: subEnv)
        case .customBaseSubscriptionURL:
            switch CustomBaseSubscriptionURLRows(rawValue: indexPath.row) {
            case .reset: presentCustomBaseSubscriptionURLAlert(at: indexPath)
            default: break
            }
        case .pixels:
            switch PixelsRows(rawValue: indexPath.row) {
            case .randomize: showRandomizedParamters()
            default: break
            }
        case .metadata:
            break
        case .regionOverride:
            break
        case .none:
            break
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    private func changeSubscriptionEnvironment(envRows: EnvironmentRows) {
        var subEnvDesc: String
        switch envRows {
        case .staging:
            subEnvDesc = "STAGING"
        case .production:
            subEnvDesc = "PRODUCTION"
        }
        let message = """
                    Are you sure you want to change the environment to \(subEnvDesc)?
                    This setting IS persisted between app runs. This action will close the app, do you want to proceed?
                    """
        let alertController = UIAlertController(title: "⚠️ App restart required! The changes are persistent",
                                                message: message,
                                                preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet)
        alertController.addAction(UIAlertAction(title: "Yes", style: .destructive) { [weak self] _ in
            Task {
                switch envRows {
                case .staging:
                    await self?.setEnvironment(.staging)
                case .production:
                    await self?.setEnvironment(.production)
                }
                // Close the app
                exit(0)
            }
        })
        let okAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(okAction)
        DispatchQueue.main.async {
            self.present(alertController, animated: true, completion: nil)
        }
    }

    private func showAlert(title: String, message: String? = nil) {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
            alertController.addAction(okAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }

    // MARK: Account Status Actions

    private func openSubscriptionRestoreFlow() {
        guard let mainVC = view.window?.rootViewController as? MainViewController else { return }


        if let navigationController = mainVC.presentedViewController as? UINavigationController {

            navigationController.popToRootViewController {
                if navigationController.viewControllers.first is SettingsHostingController {
                    mainVC.segueToSubscriptionRestoreFlow()
                } else {
                    navigationController.dismiss(animated: true, completion: {
                        mainVC.segueToSubscriptionRestoreFlow()
                    })
                }
            }
        }
    }

    private func clearAuthData() {
        Task {
            await subscriptionManagerV2.signOut(notifyUI: true)
            showAlert(title: "Data cleared!")
        }
    }

    private func showAccountDetails() {
        Task {
            let tokenContainer = try? await subscriptionManagerV2.getTokenContainer(policy: .local)
            let authenticated = tokenContainer != nil
            let title = authenticated ? "Authenticated" : "Not Authenticated"
            let message = authenticated ?
            ["Service Environment: \(subscriptionManagerV2.currentEnvironment.serviceEnvironment)",
             "AuthToken: \(tokenContainer?.accessToken ?? "")",
             "Email: \(tokenContainer?.decodedAccessToken.email ?? "")"].joined(separator: "\n") : nil
            DispatchQueue.main.async {
                self.showAlert(title: title, message: message)
            }
        }
    }

    private func showRandomizedParamters() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        let reportedParameters = reporter.randomizedParameters(for: .debug).map { "\($0.key)=\($0.value)" }
        
        // Cast to concrete type to access debug properties
        guard let reporter = reporter as? SubscriptionDataReporter else { return }
        
        let message = """
                isReinstall=\(reporter.isReinstall().toString) (variant=\(reporter._variantName ?? "unknown"))
                fireButtonUsed=\(reporter.isFireButtonUser().toString) (count=\(reporter._fireCount))
                syncUsed=\(reporter.isSyncUsed().toString) (state=\(reporter._syncAuthState.rawValue))
                fireproofingUsed=\(reporter.isFireproofingUsed().toString) (count=\(reporter._fireproofedDomainsCount))
                appOnboardingCompleted=\(reporter.isAppOnboardingCompleted().toString)
                emailEnabled=\(reporter.isEmailEnabled().toString)
                widgetAdded=\(reporter.isWidgetAdded().toString)
                frequentUser=\(reporter.isFrequentUser().toString) (lastSession=\(dateFormatter.string(from: reporter._lastSessionEnded ?? .distantPast)))
                longTermUser=\(reporter.isLongTermUser().toString) (installDate=\(dateFormatter.string(from: reporter._installDate ?? .distantPast)))
                autofillUser=\(reporter.isAutofillUser().toString) (count=\(reporter._accountsCount))
                validOpenTabsCount=\(reporter.isValidOpenTabsCount().toString) (count=\(reporter._tabsCount))
                searchUser=\(reporter.isSearchUser().toString) (count=\(reporter._searchCount))
                
                Randomized: \(reportedParameters.joined(separator: ", "))
                """
        showAlert(title: "", message: message)
    }

    private func syncAppleIDAccount() {
        Task {
            do {
                try await subscriptionManagerV2.storePurchaseManager().syncAppleIDAccount()
            } catch {
                showAlert(title: "Error syncing!", message: error.localizedDescription)
                return
            }

            showAlert(title: "Account synced!", message: "")
        }
    }

    private func validateToken() {
        Task {
            do {
                let tokenContainer = try await subscriptionManagerV2.getTokenContainer(policy: .localValid)
                showAlert(title: "Token details", message: "\(tokenContainer.debugDescription)")
            } catch OAuthClientError.missingTokenContainer {
                showAlert(title: "Not authenticated", message: "No authenticated user found! - Token not available")
            } catch {
                showAlert(title: "Error Validating Token", message: "\(error)")
            }
        }
    }

    private func getSubscriptionDetails() {
        Task {
            do {
                let subscription = try await subscriptionManagerV2.getSubscription(cachePolicy: .remoteFirst)
                showAlert(title: "Subscription info", message: subscription.debugDescription)
            } catch {
                showAlert(title: "Subscription info", message: "\(error)")
            }
        }
    }

    private func checkEntitlements() {
        Task {
            do {
                let tokenContainer = try await subscriptionManagerV2.getTokenContainer(policy: .localValid)
                let entitlementsDescription = tokenContainer.decodedAccessToken.subscriptionEntitlements.map { entitlement in
                    return entitlement.rawValue
                }.joined(separator: "\n")
                showAlert(title: "Available Entitlements", message: entitlementsDescription)
            } catch OAuthClientError.missingTokenContainer {
                showAlert(title: "Not authenticated", message: "No authenticated user found! - Token not available")
            } catch {
                showAlert(title: "Error retrieving entitlements", message: "\(error)")
            }
        }
    }

    private func setEnvironment(_ environment: SubscriptionEnvironment.ServiceEnvironment) async {

        let currentSubscriptionEnvironment = DefaultSubscriptionManagerV2.getSavedOrDefaultEnvironment(userDefaults: subscriptionUserDefaults)
        var newSubscriptionEnvironment = SubscriptionEnvironment.default
        newSubscriptionEnvironment.serviceEnvironment = environment

        if newSubscriptionEnvironment.serviceEnvironment != currentSubscriptionEnvironment.serviceEnvironment {
            await AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge.signOut(notifyUI: true)

            // Save Subscription environment
            DefaultSubscriptionManagerV2.save(subscriptionEnvironment: newSubscriptionEnvironment, userDefaults: subscriptionUserDefaults)

            // The VPN environment is forced to match the subscription environment
            let settings = AppDependencyProvider.shared.vpnSettings
            switch newSubscriptionEnvironment.serviceEnvironment {
            case .production:
                settings.selectedEnvironment = .production
            case .staging:
                settings.selectedEnvironment = .staging
            }
            NetworkProtectionLocationListCompositeRepository.clearCache()
        }
    }

    private func setCustomBaseSubscriptionURL(_ url: URL?) {

        let currentSubscriptionEnvironment = DefaultSubscriptionManagerV2.getSavedOrDefaultEnvironment(userDefaults: subscriptionUserDefaults)

        if currentSubscriptionEnvironment.customBaseSubscriptionURL != url {
            var newSubscriptionEnvironment = currentSubscriptionEnvironment
            newSubscriptionEnvironment.customBaseSubscriptionURL = url

            // Save Subscription environment
            DefaultSubscriptionManagerV2.save(subscriptionEnvironment: newSubscriptionEnvironment, userDefaults: subscriptionUserDefaults)
        }
    }

    private func presentCustomBaseSubscriptionURLAlert(at indexPath: IndexPath) {
        let alert = UIAlertController(title: "Set a custom base subscription URL", message: nil, preferredStyle: .alert)

        alert.addTextField { textField in
            textField.placeholder = SubscriptionURL.baseURL.subscriptionURL(environment: .production).absoluteString
            textField.text = self.currentEnvironment.customBaseSubscriptionURL?.absoluteString
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            self.tableView.reloadData()
        }
        alert.addAction(cancelAction)

        let resetAction = UIAlertAction(title: "Clear and reset to default", style: .destructive) { _ in
            self.presentConfirmationForCustomBaseSubscriptionURLAlert(url: nil)
        }
        alert.addAction(resetAction)

        let submitAction = UIAlertAction(title: "Update custom URL", style: .default) { _ in
            guard let inputString = alert.textFields?.first?.text,
                  let newURL = URL(string: inputString),
                  newURL != self.currentEnvironment.customBaseSubscriptionURL
            else {
                return
            }

            guard newURL.scheme != nil else {
                self.showAlert(title: "URL is missing a scheme")
                return
            }

            self.presentConfirmationForCustomBaseSubscriptionURLAlert(url: newURL)
        }
        alert.addAction(submitAction)

        let cell = self.tableView.cellForRow(at: indexPath)!
        present(controller: alert, fromView: cell)
    }

    private func presentConfirmationForCustomBaseSubscriptionURLAlert(url: URL?) {
        let messageFirstLine = {
            if let url {
                "Are you sure you want to change the base subscription URL to `\(url.absoluteString)` ?"
            } else {
                "Are you sure you want to reset the base subscription URL?"
            }
        }()

        let message = """
                    \(messageFirstLine)
                    
                    This setting IS persisted between app runs. The custom base subscription URL is used for front-end URLs. Custom URL is only used when internal user mode is enabled.
                    
                    This action will close the app, do you want to proceed?
                    """
        let alertController = UIAlertController(title: "⚠️ App restart required! The changes are persistent",
                                                message: message,
                                                preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet)
        alertController.addAction(UIAlertAction(title: "Yes", style: .destructive) { [weak self] _ in
            self?.setCustomBaseSubscriptionURL(url)
            // Close the app
            exit(0)
        })
        let okAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(okAction)
        DispatchQueue.main.async {
            self.present(alertController, animated: true, completion: nil)
        }
    }

    private func loadStoreKitMetadata() {
        Task { @MainActor in
            let storefront = await Storefront.current
            self.storefrontID = storefront?.id ?? "nil"
            self.storefrontCountryCode = storefront?.countryCode ?? "nil"
            self.tableView.reloadData()
        }
    }

    private func showBuyProductionSubscriptions() {
        // Create the subscription selection handler that routes to the appropriate feature method
        let handler: SubscriptionSelectionHandler = { productId, changeType in
            guard let subscriptionManager = AppDependencyProvider.shared.subscriptionManagerV2 else {
                Logger.subscription.error("[ProductionSubscriptionDebug] Subscription manager not available")
                return
            }

            // Create the flows and feature
            let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(
                subscriptionManager: subscriptionManager,
                storePurchaseManager: subscriptionManager.storePurchaseManager()
            )
            let appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(
                subscriptionManager: subscriptionManager,
                storePurchaseManager: subscriptionManager.storePurchaseManager(),
                appStoreRestoreFlow: appStoreRestoreFlow,
                wideEvent: AppDependencyProvider.shared.wideEvent
            )

            let subscriptionFeatureAvailability = BrowserServicesKit.DefaultSubscriptionFeatureAvailability(
                privacyConfigurationManager: ContentBlocking.shared.privacyConfigurationManager,
                purchasePlatform: SubscriptionEnvironment.PurchasePlatform.appStore,
                featureFlagProvider: SubscriptionPageFeatureFlagAdapter(featureFlagger: AppDependencyProvider.shared.featureFlagger)
            )

            let feature = DefaultSubscriptionPagesUseSubscriptionFeatureV2(
                subscriptionManager: subscriptionManager,
                subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                subscriptionAttributionOrigin: nil,
                appStorePurchaseFlow: appStorePurchaseFlow,
                appStoreRestoreFlow: appStoreRestoreFlow,
                internalUserDecider: AppDependencyProvider.shared.internalUserDecider,
                wideEvent: AppDependencyProvider.shared.wideEvent
            )

            // Create params matching what the web would send
            var params: [String: Any] = ["id": productId]
            if let changeType = changeType {
                params["change"] = changeType
            }

            // Call the appropriate handler based on whether it's a tier change or new purchase
            if changeType != nil {
                _ = await feature.subscriptionChangeSelected(params: params, original: WKScriptMessage())
            } else {
                _ = await feature.subscriptionSelected(params: params, original: WKScriptMessage())
            }
        }

        let hostingController = UIHostingController(rootView: ProductionSubscriptionPurchaseDebugView(subscriptionSelectionHandler: handler))
        navigationController?.pushViewController(hostingController, animated: true)
    }
}

extension Bool {
    fileprivate var toString: String {
        String(self)
    }
}
