//
//  DuckDuckGoDBPBackgroundAgentAppDelegate.swift
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

import Cocoa
import Combine
import Common
import ServiceManagement
import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import BrowserServicesKit
import PixelKit
import Networking
import Subscription
import os.log
import Configuration

@objc(Application)
final class DuckDuckGoDBPBackgroundAgentApplication: NSApplication {
    private let _delegate: DuckDuckGoDBPBackgroundAgentAppDelegate // swiftlint:disable:this weak_delegate

    override init() {
        Logger.dbpBackgroundAgent.log("🟢 Starting: \(NSRunningApplication.current.processIdentifier, privacy: .public)")

        let dryRun: Bool
#if DEBUG
        dryRun = true
#else
        dryRun = false
#endif

        PixelKit.setUp(dryRun: dryRun,
                       appVersion: AppVersion.shared.versionNumber,
                       source: "dbpBackgroundAgent",
                       defaultHeaders: [:],
                       defaults: .standard) { (pixelName: String, headers: [String: String], parameters: [String: String], _, _, onComplete: @escaping (Bool, Error?) -> Void) in

            let url = URL.pixelUrl(forPixelNamed: pixelName)
            let apiHeaders = APIRequest.Headers(additionalHeaders: headers) // workaround - Pixel class should really handle APIRequest.Headers by itself
            let configuration = APIRequest.Configuration(url: url, method: .get, queryParameters: parameters, headers: apiHeaders)
            let request = APIRequest(configuration: configuration)

            request.fetch { _, error in
                onComplete(true, error)
            }
        }

        let pixelHandler = DataBrokerProtectionMacOSPixelsHandler()
        pixelHandler.fire(.backgroundAgentStarted)

        // prevent agent from running twice
        if let anotherInstance = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!).first(where: { $0 != .current }) {
            Logger.dbpBackgroundAgent.error("Stopping: another instance is running: \(anotherInstance.processIdentifier, privacy: .public).")
            pixelHandler.fire(.backgroundAgentStartedStoppingDueToAnotherInstanceRunning)
            exit(0)
        }

        _delegate = DuckDuckGoDBPBackgroundAgentAppDelegate()
        super.init()
        self.delegate = _delegate
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}

@main
final class DuckDuckGoDBPBackgroundAgentAppDelegate: NSObject, NSApplicationDelegate {
    private let settings = DataBrokerProtectionSettings(defaults: .dbp)
    private var cancellables = Set<AnyCancellable>()
    private var statusBarMenu: StatusBarMenu?
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private var manager: DataBrokerProtectionAgentManager?

    override init() {

        // Configure Subscription
        if !settings.isAuthV2Enabled {
            Logger.dbpBackgroundAgent.log("Configuring subscription V1")
            subscriptionManager = DefaultSubscriptionManager()
        } else {
            Logger.dbpBackgroundAgent.log("Configuring subscription V2")
            let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)
            let subscriptionUserDefaults = UserDefaults(suiteName: subscriptionAppGroup)!
            let subscriptionEnvironment = DefaultSubscriptionManager.getSavedOrDefaultEnvironment(userDefaults: subscriptionUserDefaults)
            subscriptionManager = DefaultSubscriptionManagerV2(keychainType: .dataProtection(.named(subscriptionAppGroup)),
                                                               environment: subscriptionEnvironment,
                                                               userDefaults: subscriptionUserDefaults,
                                                               pixelHandlingSource: .dbp)
        }
    }

    @MainActor
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Logger.dbpBackgroundAgent.log("DuckDuckGoAgent started")

        Configuration.setURLProvider(DBPAgentConfigurationURLProvider())
        let configStore = ConfigurationStore()
        let privacyConfigurationManager = DBPPrivacyConfigurationManager()
        let configurationManager = ConfigurationManager(privacyConfigManager: privacyConfigurationManager, store: configStore)
        configurationManager.start()
        // Load cached config (if any)
        privacyConfigurationManager.reload(etag: configStore.loadEtag(for: .privacyConfiguration), data: configStore.loadData(for: .privacyConfiguration))

        let authenticationManager = DataBrokerAuthenticationManagerBuilder.buildAuthenticationManager(subscriptionManager: subscriptionManager)

        manager = DataBrokerProtectionAgentManagerProvider.agentManager(
            authenticationManager: authenticationManager,
            configurationManager: configurationManager,
            privacyConfigurationManager: privacyConfigurationManager,
            remoteBrokerDeliveryFeatureFlagger: DBPFeatureFlagger(configurationManager: configurationManager,
                                                                  privacyConfigurationManager: privacyConfigurationManager),
            vpnBypassService: VPNBypassService()
        )
        manager?.agentFinishedLaunching()

        setupStatusBarMenu()

        // Aligning the environment with the Subscription one
        settings.alignTo(subscriptionEnvironment: subscriptionManager.currentEnvironment)
    }

    @MainActor
    private func setupStatusBarMenu() {
        statusBarMenu = StatusBarMenu()

        if settings.showInMenuBar {
            statusBarMenu?.show()
        } else {
            statusBarMenu?.hide()
        }

        settings.showInMenuBarPublisher.sink { [weak self] showInMenuBar in
            Task { @MainActor in
                if showInMenuBar {
                    self?.statusBarMenu?.show()
                } else {
                    self?.statusBarMenu?.hide()
                }
            }
        }.store(in: &cancellables)
    }
}
